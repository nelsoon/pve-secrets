#!/usr/bin/perl
# Integration patcher for stock pve-manager files
# (INTEGRATION.md) for pve-secrets. Run from postinst (mode "apply", also on
# a dpkg trigger after pve-manager changes those files)
# and from postrm (mode "remove"). Idempotent, atomic
# writes, never fails the install.
#
# Degrade rule (spec R9): the UI (script tag + nav) is
# only present when BOTH API registrations are present and
# the shipped JS exists; otherwise the UI is removed so the
# panel is hidden, not broken. The outcome of every point is
# recorded in <prefix>/var/lib/pve-secrets/integration.status.
# <prefix>/var/lib/pve-secrets/changed is touched when anything
# was modified (the caller restarts the PVE daemons).
use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use File::Path qw(make_path);

my ($mode, $prefix) = @ARGV;
$prefix //= '';
if (!defined $mode || ($mode ne 'apply' && $mode ne 'remove')) {
    print STDERR "usage: integrate.pl apply|remove [prefix]\n";
    exit 0;
}

my $pm = "$prefix/usr/share/perl5";
my $js = "$prefix/usr/share/pve-manager/js";
my $tpl = "$prefix/usr/share/pve-manager/index.html.tpl";
my $state = "$prefix/var/lib/pve-secrets";
my $changed = 0;
my %status;

my sub slurp {
    my ($file) = @_;
    open(my $fh, '<', $file) or return undef;
    local $/;
    my $data = <$fh>;
    close($fh);
    return $data;
}

my sub write_atomic {
    my ($file, $data) = @_;
    my $tmp = "$file.pve-secrets.tmp";
    open(my $fh, '>', $tmp) or return 0;
    print {$fh} $data;
    close($fh) or return 0;
    return rename($tmp, $file);
}

# Apply $code to the file; returns 'ok', 'changed', or 'fail: why'.
my sub edit {
    my ($file, $code) = @_;
    return 'fail: not found' if !-f $file;
    my $src = slurp($file);
    return 'fail: unreadable' if !defined $src;
    my ($new, $why) = $code->($src);
    return "fail: $why" if !defined $new;
    return 'ok' if $new eq $src;
    write_atomic($file, $new) or return 'fail: cannot write';
    $changed = 1;
    return 'changed';
}

# --- API registration (Cluster.pm) --------------------------
my $module = 'PVE::API2::Cluster::Secrets';
my $use_anchor = "use PVE::API2::Cluster::Ceph;\n";
my $use = "use $module;\n";
my $reg_anchor = "    path => 'ceph',\n});\n";
my $block = "\n__PACKAGE__->register_method ({\n"
    . "    subclass => \"$module\",\n"
    . "    path => 'secrets',\n});\n";
$status{api_cluster} = edit("$pm/PVE/API2/Cluster.pm", sub {
    my ($src) = @_;
    if ($mode eq 'remove') {
        $src =~ s/\Q$use\E//;
        $src =~ s/\Q$block\E//;
        return $src;
    }
    return $src if index($src, $module) >= 0;
    return (undef, 'anchor not found')
        if index($src, $use_anchor) < 0 || index($src, $reg_anchor) < 0;
    $src =~ s/\Q$use_anchor\E/$use_anchor$use/;
    $src =~ s/\Q$reg_anchor\E/$reg_anchor$block/;
    return $src;
});

# --- UI: script tag + Datacenter nav, only with the API -------
my $js_file = "$js/PVESecrets.js";
my $jsdata = slurp($js_file);
my $want_ui = $mode eq 'apply' && $status{api_cluster} !~ /^fail/
    && defined $jsdata && length $jsdata;
my $jsver = $want_ui ? substr(md5_hex($jsdata), 0, 8) : 'none';
my $tag_re = qr{ *<script type="text/javascript" src="/pve2/js/PVESecrets\.js\?ver=[^"]*"></script>\n};
my $tag = '    <script type="text/javascript" '
    . 'src="/pve2/js/PVESecrets.js?ver=[% version %]'
    . "-pvesec-$jsver\"></script>\n";
$status{script_tag} = edit($tpl, sub {
    my ($src) = @_;
    if (!$want_ui) {
        $src =~ s/$tag_re//;
        return $src;
    }
    return $src if index($src, "-pvesec-$jsver") >= 0;
    return $src if $src =~ s/$tag_re/$tag/;
    my $pos = index($src, '/pve2/js/pvemanagerlib.js');
    return (undef, 'anchor not found') if $pos < 0;
    my $eol = index($src, "\n", $pos);
    return (undef, 'anchor not found') if $eol < 0;
    substr($src, $eol + 1, 0) = $tag;
    return $src;
});

my $nav_begin = "// pve-secrets:begin\n";
my $nav_end = "// pve-secrets:end\n";
my $anchor = "if (caps.storage['Datastore.Allocate'] || caps.dc['Sys.Audit']) {";
$status{nav} = edit("$js/pvemanagerlib.js", sub {
    my ($src) = @_;
    $src =~ s/[ \t]*\Q$nav_begin\E.*?[ \t]*\Q$nav_end\E//s;
    return $src if !$want_ui;
    my $at = index($src, $anchor);
    return (undef, 'anchor not found') if $at < 0;
    my $ls = rindex($src, "\n", $at) + 1;
    my ($ind) = substr($src, $ls, $at - $ls) =~ /^([ \t]*)$/;
    return (undef, 'anchor not found') if !defined $ind;
    my $in = "$ind    ";
    my $f = "$in    ";
    my $nav = "$ind$nav_begin${ind}if (caps.dc['Sys.Audit']) {\n"
        . "${in}me.items.push({\n${f}xtype: 'pveSecretsView',\n"
        . "${f}title: gettext('Secrets'),\n${f}iconCls: 'fa fa-key',\n"
        . "${f}itemId: 'secrets',\n${in}});\n$ind}\n$ind$nav_end";
    substr($src, $ls, 0) = $nav;
    return $src;
});

# --- record the outcome --------------------------------------
$status{ui} = $want_ui ? 'visible' : $mode eq 'remove' ? 'removed' : 'hidden';
if ($mode eq 'apply' || -d $state) {
    if (-d $state || eval { make_path($state); 1 }) {
        my $out = "# pve-secrets integration status (" . time() . ")\n";
        $out .= "$_: $status{$_}\n" for qw(api_cluster script_tag nav ui);
        write_atomic("$state/integration.status", $out);
        if ($changed && open(my $fh, '>', "$state/changed")) {
            close($fh);
        }
    }
}
for my $k (sort keys %status) {
    print STDERR "pve-secrets: integration $k: $status{$k}"
        . " (see INTEGRATION.md)\n" if $status{$k} =~ /^fail/;
}
print "pve-secrets: integration " . ($changed ? "updated" : "unchanged")
    . ", ui $status{ui}\n";
exit 0;
