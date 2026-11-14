use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;
use File::Temp qw(tempfile);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my $tool = File::Spec->catfile($FindBin::Bin, '..', 'ci',
    'reconcile-cpan-public-history.pl');
ok(-f $tool, 'offline CPAN history reconciliation tool is shipped');
sub sample_file {
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
my $header = "archive\tversion\tindex_last_modified\tclassification\n";
sub item {
    my ($version, $mtime, $classification) = @_;
    return "JQ-Lite-$version.tar.gz\t$version\t$mtime\t" .
        ($classification || 'observed-archive') . "\n";
}
my $index = sample_file($header .
    item('0.99', '2025-10-13 01:26') .
    item('0.100', '2025-10-13 03:50') .
    item('2.59', '2026-09-20 10:59'));
my $ledger = sample_file("# Independently reviewed source required in real use\n" .
    "0.99\n0.100\n2.59\n");
my $same = invoke('--inventory', $index, '--published-file', $ledger);
is($same->{rc}, 0, 'identical version sets reconcile even with historical inversion');
like($same->{stdout}, qr/Observed CPAN archive versions: 3/, 'inventory record count reported');
like($same->{stdout}, qr/NOT publication-history approval/, 'even exact agreement cannot certify completeness');

my $incomplete = sample_file("0.99\n2.59\n");
my $missing = invoke('--inventory', $index, '--published-file', $incomplete);
ok($missing->{rc} != 0, 'missing CPAN-observed version is flagged');
like($missing->{stdout}, qr/UNRECONCILED CPAN archive: JQ-Lite-0\.100\.tar\.gz/,
    'unreconciled archive is named');
my $extended = sample_file("0.99\n0.100\n2.58\n2.59\n");
my $extra = invoke('--inventory', $index, '--published-file', $extended);
ok($extra->{rc} != 0, 'history-only versions require independent provenance');
like($extra->{stdout}, qr/NEEDS EXTERNAL EVIDENCE: history version 2\.58/,
    'partial CPAN index cannot silently invalidate extra history');

my $internal = sample_file($header . item('3.00_03', '2026-10-25 01:00',
    'INTERNAL-DEVELOPER-ARTIFACT-ALERT'));
my $dev = invoke('--inventory', $internal,
    '--published-file', sample_file("3.00_03\n"));
ok($dev->{rc} != 0, 'matching sets still fail for an internal-only developer archive');
like($dev->{stdout}, qr/INTERNAL-DEVELOPER-ARTIFACT-ALERT/, 'developer artifact needs investigation');

my $prefixed_internal = sample_file($header .
    item('v3.00_03', '2026-10-25 01:01', 'observed-archive'));
my $prefixed_result = invoke('--inventory', $prefixed_internal,
    '--published-file', sample_file("v3.00_03\n"));
ok($prefixed_result->{rc} != 0,
    'v-prefixed internal developer archive cannot pass even with normal classification');
like($prefixed_result->{stdout}, qr/INTERNAL-DEVELOPER-ARTIFACT-ALERT/,
    'reconciler detects internal-only v-prefixed archive independently of TSV tag');

my $dupe = sample_file($header .
    item('2.59', '2026-09-20 10:59') . item('2.59', '2026-09-20 10:59'));
ok(invoke('--inventory', $dupe, '--published-file', $ledger)->{rc} != 0,
    'duplicate observed version rejected');
my $bad_header = sample_file("version\n2.59\n");
ok(invoke('--inventory', $bad_header, '--published-file', $ledger)->{rc} != 0,
    'unexpected TSV format rejected');
my $bad_name = sample_file($header .
    "JQ-Lite-2.59.tar.gz\t2.58\t2026-09-20 10:59\tobserved-archive\n");
ok(invoke('--inventory', $bad_name, '--published-file', $ledger)->{rc} != 0,
    'mismatched archive/version rejected');
my $dupe_history = sample_file("2.59\n2.59\n");
ok(invoke('--inventory', $index, '--published-file', $dupe_history)->{rc} != 0,
    'duplicate public-history version rejected');
my $empty_history = sample_file("# empty\n");
ok(invoke('--inventory', $index, '--published-file', $empty_history)->{rc} != 0,
    'empty history cannot mean no public predecessors');
my $unreadable = invoke('--inventory', $index,
    '--published-file', 'not-a-real-history.txt');
ok($unreadable->{rc} != 0, 'missing input file rejected');
my $no_args = invoke();
ok($no_args->{rc} != 0, 'required inputs enforced');
my $help = invoke('--help');
is($help->{rc}, 0, 'help is available');
like($help->{stdout}, qr/NOT a --history-reviewed attestation/,
    'documentation distinguishes comparison from human history review');
done_testing;
