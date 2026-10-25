use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;
use File::Temp qw(tempfile);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my $tool = File::Spec->catfile($FindBin::Bin, '..', 'ci',
    'inventory-cpan-jq-lite-index.pl');
ok(-f $tool, 'offline CPAN index inventory tool is distributed');

sub saved_index {
    my ($content) = @_;
    my ($fh, $path) = tempfile(UNLINK => 1);
    print {$fh} $content or die "Cannot write fixture: $!";
    close $fh or die "Cannot close fixture: $!";
    return $path;
}
sub invoke {
    my (@args) = @_;
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $^X, $tool, @args);
    close $in;
    my $stdout = do { local $/; <$out> };
    my $stderr = do { local $/; <$err> };
    close $out;
    close $err;
    waitpid($pid, 0);
    return { rc => $? >> 8, stdout => $stdout || '', stderr => $stderr || '' };
}

my $sample = saved_index(<<'HTML');
<html><table>
<tr><td><a href="Another-9.00.tar.gz">Another-9.00.tar.gz</a></td><td>2026-01-01 00:00</td></tr>
<tr><td><a href="JQ-Lite-2.59.tar.gz">JQ-Lite-2.59.tar.gz</a></td><td align="right">2026-09-20 10:59</td></tr>
<tr><td><a href="JQ-Lite-0.100.tar.gz">JQ-Lite-0.100.tar.gz</a></td><td>2025-10-13 03:50</td></tr>
<tr><td><a href="JQ-Lite-0.99.readme">JQ-Lite-0.99.readme</a></td><td>2025-10-13 01:25</td></tr>
<tr><td><a href="JQ-Lite-0.99.tar.gz">JQ-Lite-0.99.tar.gz</a></td><td>2025-10-13 01:26</td></tr>
</table></html>
HTML
my $result = invoke('--input', $sample);
is($result->{rc}, 0, 'offline inventory succeeds for saved author HTML');
is($result->{stdout}, join("\n",
    "archive\tversion\tindex_last_modified\tclassification",
    "JQ-Lite-0.99.tar.gz\t0.99\t2025-10-13 01:26\tobserved-archive",
    "JQ-Lite-0.100.tar.gz\t0.100\t2025-10-13 03:50\tobserved-archive",
    "JQ-Lite-2.59.tar.gz\t2.59\t2026-09-20 10:59\tobserved-archive",
    ''), 'only JQ-Lite tarballs appear, ordered by observed index modification time');

my $dup = saved_index(<<'HTML');
<table><tr><td><a href="JQ-Lite-2.59.tar.gz">2.59</a></td><td>2026-09-20 10:59</td></tr>
<tr><td><a href="JQ-Lite-2.59.tar.gz">2.59</a></td><td>2026-09-20 10:59</td></tr></table>
HTML
my $duplicated = invoke('--input', $dup);
ok($duplicated->{rc} != 0, 'duplicate archive rows fail');
like($duplicated->{stderr}, qr/Duplicate archive/, 'duplicate diagnostic');

my $missing_date = saved_index('<tr><td><a href="JQ-Lite-2.59.tar.gz">2.59</a></td></tr>');
my $missing = invoke('--input', $missing_date);
ok($missing->{rc} != 0, 'missing listing date fails');
like($missing->{stderr}, qr/Missing directory modification time/, 'missing-date diagnostic');

my $unexpected = saved_index('<tr><td><a href="JQ-Lite-special.tar.gz">special</a></td><td>2026-10-25 01:00</td></tr>');
my $unknown = invoke('--input', $unexpected);
ok($unknown->{rc} != 0, 'unexpected archive names fail instead of silently dropping');

my $developer = saved_index('<tr><td><a href="JQ-Lite-3.00_03.tar.gz">3.00_03</a></td><td>2026-10-25 01:00</td></tr>');
my $dev = invoke('--input', $developer);
ok($dev->{rc} != 0, 'public index containing internal developer version returns failure');
like($dev->{stdout}, qr/INTERNAL-DEVELOPER-ARTIFACT-ALERT/, 'developer artifact remains visible in inventory');
like($dev->{stderr}, qr/investigate public distribution/, 'developer artifact requires investigation');

my $empty = saved_index('<html><table><tr><td>nothing</td></tr></table></html>');
ok(invoke('--input', $empty)->{rc} != 0, 'empty snapshot fails instead of passing with zero entries');
ok(invoke('--input', 'missing-cpan-index.html')->{rc} != 0, 'missing input file fails');
ok(invoke()->{rc} != 0, 'input file must be supplied');
my $help = invoke('--help');
is($help->{rc}, 0, 'help does not require a saved source');
like($help->{stdout}, qr/NOT an audited publication ledger/, 'help explicitly limits provenance claim');

done_testing;
