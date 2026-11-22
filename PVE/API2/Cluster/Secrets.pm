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
    code => sub { return [{ name => 'status' }, { name => 'init' }] },
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

1;
