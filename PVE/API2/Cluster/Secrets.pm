package PVE::API2::Cluster::Secrets;

# /cluster/secrets: store status and first-time setup. The work is done by
# /usr/sbin/pve-secrets; this API runs it as root (protected) and returns its
# JSON. Setup is synchronous on purpose: the recovery keys are returned to the
# caller once and never written to a task log or a file.
#
# SPDX-License-Identifier: AGPL-3.0-or-later

use strict;
use warnings;

use JSON;
use PVE::Exception qw(raise);
use PVE::RPCEnvironment;
use PVE::Tools qw(run_command);

use base qw(PVE::RESTHandler);

my $CLI = '/usr/sbin/pve-secrets';

my sub cli_json {
    my (@args) = @_;
    my ($out, $err) = ('', '');
    eval {
        run_command([$CLI, @args], outfunc => sub { $out .= "$_[0]\n" },
            errfunc => sub { $err .= "$_[0]\n" }, timeout => 120);
    };
    if (my $e = $@) {
        $err =~ s/^pve-secrets: //mg;
        raise((($err || $e) =~ s/\s+$//r) . "\n", code => 500);
    }
    return decode_json($out);
}

__PACKAGE__->register_method({
    name => 'index',
    path => '',
    method => 'GET',
    description => "Directory index.",
    permissions => { user => 'all' },
    parameters => { additionalProperties => 0, properties => {} },
    returns => { type => 'array', items => { type => 'object', properties => {} },
        links => [{ rel => 'child', href => '{name}' }] },
    code => sub { return [{ name => 'status' }, { name => 'init' }, { name => 'backup' }, { name => 'k8s' }] },
});

__PACKAGE__->register_method({
    name => 'status',
    path => 'status',
    method => 'GET',
    protected => 1,
    description => "Store health: seal state, Raft members, failure tolerance.",
    permissions => { check => ['perm', '/', ['Sys.Audit']] },
    parameters => { additionalProperties => 0, properties => {} },
    returns => { type => 'object' },
    code => sub { return cli_json('status', '--json') },
});

__PACKAGE__->register_method({
    name => 'init',
    path => 'init',
    method => 'POST',
    protected => 1,
    description => "First-time setup of the cluster store. Returns the recovery"
        . " keys once; they are not stored anywhere.",
    permissions => { check => ['perm', '/', ['Sys.Modify']] },
    parameters => {
        additionalProperties => 0,
        properties => {
            vip => { type => 'string', format => 'CIDRv4',
                description => "Client address (VRRP), e.g. 192.0.2.10/24." },
            name => { type => 'string', format => 'dns-name', optional => 1,
                description => "DNS name added to the TLS certificates." },
            interface => { type => 'string', pattern => '[A-Za-z0-9_.-]+', optional => 1,
                default => 'vmbr0', description => "Interface carrying the address." },
            vrid => { type => 'integer', minimum => 1, maximum => 255, optional => 1,
                default => 90, description => "VRRP router id (must be unused on the LAN)." },
        },
    },
    returns => {
        type => 'object',
        properties => {
            recovery_keys => { type => 'array', items => { type => 'string' } },
            threshold => { type => 'integer' },
        },
    },
    code => sub {
        my ($param) = @_;
        my @a = ('init', '--json', '--vip', $param->{vip});
        for my $k (qw(name interface vrid)) {
            push @a, "--$k", $param->{$k} if defined $param->{$k};
        }
        return cli_json(@a);
    },
});

__PACKAGE__->register_method({
    name => 'backup_config',
    path => 'backup',
    method => 'PUT',
    protected => 1,
    description => "Set where and how often Raft snapshots are taken.",
    permissions => { check => ['perm', '/', ['Sys.Modify']] },
    parameters => {
        additionalProperties => 0,
        properties => {
            storage => { type => 'string', format => 'pve-storage-id',
                description => "PVE storage with 'backup' content." },
            keep => { type => 'integer', minimum => 1, maximum => 1000, optional => 1,
                default => 14, description => "Snapshots to keep." },
            interval => { type => 'integer', minimum => 1, maximum => 720, optional => 1,
                default => 24, description => "Hours between snapshots." },
        },
    },
    returns => { type => 'null' },
    code => sub {
        my ($param) = @_;
        my @a = ('backup-config', '--storage', $param->{storage});
        push @a, '--keep', $param->{keep} if defined $param->{keep};
        push @a, '--interval', $param->{interval} if defined $param->{interval};
        my $err = '';
        eval { run_command([$CLI, @a], errfunc => sub { $err .= "$_[0]\n" }, timeout => 60) };
        if ($@) {
            $err =~ s/^pve-secrets: //mg;
            raise((($err || $@) =~ s/\s+$//r) . "\n", code => 400);
        }
        return undef;
    },
});

__PACKAGE__->register_method({
    name => 'backup_now',
    path => 'backup',
    method => 'POST',
    protected => 1,
    description => "Take a Raft snapshot now (task).",
    permissions => { check => ['perm', '/', ['Sys.Modify']] },
    parameters => { additionalProperties => 0, properties => {} },
    returns => { type => 'string', description => 'Task UPID.' },
    code => sub {
        my $rpcenv = PVE::RPCEnvironment::get();
        my $user = $rpcenv->get_user();
        return $rpcenv->fork_worker('pvesecretsbackup', undef, $user, sub {
            run_command([$CLI, 'backup', '--force'], timeout => 600);
        });
    },
});

my sub cli_run {
    my ($input, @args) = @_;
    my $err = '';
    eval { run_command([$CLI, @args], input => $input, errfunc => sub { $err .= "$_[0]\n" },
        timeout => 120) };
    if ($@) {
        $err =~ s/^pve-secrets: //mg;
        raise((($err || $@) =~ s/\s+$//r) . "\n", code => 400);
    }
}

__PACKAGE__->register_method({
    name => 'k8s_list',
    path => 'k8s',
    method => 'GET',
    protected => 1,
    description => "Registered Kubernetes clusters (service-account issuers).",
    permissions => { check => ['perm', '/', ['Sys.Audit']] },
    parameters => { additionalProperties => 0, properties => {} },
    returns => { type => 'array', items => { type => 'object' },
        links => [{ rel => 'child', href => '{cluster}' }] },
    code => sub { return cli_json('k8s-list', '--json') },
});

__PACKAGE__->register_method({
    name => 'k8s_register',
    path => 'k8s/{cluster}',
    method => 'PUT',
    protected => 1,
    description => "Register or update a Kubernetes cluster: its service-account"
        . " issuer and public keys. Pods then read secret/k8s/{cluster}/<namespace>/*.",
    permissions => { check => ['perm', '/', ['Sys.Modify']] },
    parameters => {
        additionalProperties => 0,
        properties => {
            cluster => { type => 'string', pattern => '[a-z0-9][a-z0-9-]{0,39}' },
            issuer => { type => 'string', maxLength => 512,
                description => "Service-account issuer URL (the 'iss' claim)." },
            jwks => { type => 'string', maxLength => 65536,
                description => "JWKS JSON (/openid/v1/jwks) or PEM public keys." },
        },
    },
    returns => { type => 'null' },
    code => sub {
        my ($p) = @_;
        cli_run($p->{jwks}, 'k8s-register', '--cluster', $p->{cluster},
            '--issuer', $p->{issuer}, '--jwks', '-');
        return undef;
    },
});

__PACKAGE__->register_method({
    name => 'k8s_unregister',
    path => 'k8s/{cluster}',
    method => 'DELETE',
    protected => 1,
    description => "Unregister a Kubernetes cluster (removes its login; secrets stay).",
    permissions => { check => ['perm', '/', ['Sys.Modify']] },
    parameters => { additionalProperties => 0,
        properties => { cluster => { type => 'string', pattern => '[a-z0-9][a-z0-9-]{0,39}' } } },
    returns => { type => 'null' },
    code => sub {
        my ($p) = @_;
        cli_run(undef, 'k8s-unregister', '--cluster', $p->{cluster});
        return undef;
    },
});

1;
