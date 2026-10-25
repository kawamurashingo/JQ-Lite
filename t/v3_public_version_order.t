use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;
use IPC::Open3 qw(open3);
use Symbol qw(gensym);
use File::Temp qw(tempfile);

my $gate = File::Spec->catfile(
    $FindBin::Bin, '..', 'ci', 'check-public-version-order.pl'
);
ok(-f $gate, 'public version-order preflight is in the source distribution');

sub invoke {
    my (@args) = @_;
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $^X, $gate, @args);
    close $in;
    my $stdout = do { local $/; <$out> };
    my $stderr = do { local $/; <$err> };
    close $out;
    close $err;
    waitpid($pid, 0);
    return {
        rc => $? >> 8,
        stdout => defined($stdout) ? $stdout : '',
        stderr => defined($stderr) ? $stderr : '',
    };
}

my $no_audit = invoke('--planned', '3.00');
ok($no_audit->{rc} != 0,
    'cannot check a proposed public version without audited history');
like($no_audit->{stderr}, qr/Publication history must be independently audited/,
    'uncorroborated release-history omission is explained');

my $no_plan = invoke('--history-reviewed');
ok($no_plan->{rc} != 0, 'candidate public sequence is required');

my $stable_only = invoke('--history-reviewed', '--planned', '3.00');
is($stable_only->{rc}, 0, 'stable-only scenario works after a manual no-public-history audit');
like($stable_only->{stdout}, qr/No publication authorized/,
    'success never implies publication permission');

my $v2_to_stable = invoke('--history-reviewed', '--published', '2.59',
    '--planned', '3.00');
is($v2_to_stable->{rc}, 0, 'published 2.59 precedes hypothetical stable 3.00');

my $bad_downgrade = invoke('--history-reviewed',
    '--published', '2.59', '--published', '3.00_03',
    '--planned', '3.00');
ok($bad_downgrade->{rc} != 0,
    'hypothetically publicly distributed 3.00_03 cannot downgrade to 3.00');
like($bad_downgrade->{stderr}, qr/must strictly increase/,
    'Perl numeric ordering blocks underscored development-to-stable downgrade');

my $higher_stable = invoke('--history-reviewed',
    '--published', '3.00_03', '--planned', '3.01');
is($higher_stable->{rc}, 0,
    'a hypothetical higher stable version is ordered numerically, not approved');
my $internal_dev = invoke('--history-reviewed',
    '--planned', '3.00_03', '--planned', '3.01');
ok($internal_dev->{rc} != 0,
    'the permanently internal 3.00_0x train cannot be a public prerelease');
like($internal_dev->{stderr}, qr/Internal-only 3.00_0x/,
    'internal candidate rejection is explicit');

my $prefixed_internal_dev = invoke('--history-reviewed',
    '--planned', 'v3.00_03', '--planned', '3.01');
ok($prefixed_internal_dev->{rc} != 0,
    'v-prefixed internal developer version cannot bypass public-version gate');
like($prefixed_internal_dev->{stderr}, qr/Internal-only 3.00_0x/,
    'v-prefixed developer version is rejected before public publication');

my $prerelease_downgrade = invoke('--history-reviewed',
    '--planned', '3.01_01', '--planned', '3.01');
ok($prerelease_downgrade->{rc} != 0,
    'a generic underscore prerelease is not blindly considered older than stable');

# Hypothetical future public train only. These test literals are not
# suggested or authorized production release numbers.
my $increasing_train = invoke('--history-reviewed',
    '--published', '2.59', '--planned', '3.01_01',
    '--planned', '3.02');
is($increasing_train->{rc}, 0,
    'monotonic illustrative public prerelease-to-stable series passes');

my $out_of_order_plan = invoke('--history-reviewed',
    '--published', '2.59', '--planned', '3.02',
    '--planned', '3.01');
ok($out_of_order_plan->{rc} != 0,
    'a decreasing proposed public sequence is rejected even with valid history');

my $unsorted_history = invoke('--history-reviewed', '--published', '2.59',
    '--published', '2.58', '--planned', '3.00');
ok($unsorted_history->{rc} != 0,
    'historical non-increase cannot be silently ignored');
like($unsorted_history->{stderr}, qr/acknowledge-historical-regressions/,
    'actual historical regressions require separate human acknowledgement');

# Both 0.99 and the later 0.100 appear in the CPAN author index dated
# 2025-10-13. Perl treats 0.100 as LOWER than 0.99. These examples are
# regression fixtures, not a complete audited publication ledger.
my @old_public_history = (
    '--history-reviewed', '--published', '0.99', '--published', '0.100'
);
my $actual_old_inversion = invoke(@old_public_history, '--planned', '1.00');
ok($actual_old_inversion->{rc} != 0,
    'observed old CPAN inversion must be acknowledged explicitly');
like($actual_old_inversion->{stderr}, qr/0\.99 is not below 0\.100/,
    'diagnostic identifies the actual numeric reversal');

my $acknowledged_old_history = invoke(
    @old_public_history, '--acknowledge-historical-regressions',
    '--planned', '1.00'
);
is($acknowledged_old_history->{rc}, 0,
    'historical inversion can be acknowledged for an illustrative safe future');
like($acknowledged_old_history->{stdout}, qr/Historical public version regressions: 1 acknowledged/,
    'passing result makes historical irregularity visible');
like($acknowledged_old_history->{stdout}, qr/No publication authorized/,
    'historical acknowledgement is never release permission');

my $below_historical_peak = invoke(
    @old_public_history, '--acknowledge-historical-regressions',
    '--planned', '0.50'
);
ok($below_historical_peak->{rc} != 0,
    'planned version newer than latest 0.100 but below old peak 0.99 fails');
like($below_historical_peak->{stderr}, qr/historical maximum 0\.99/,
    'future candidate is compared against historical peak, not last release');

my $equal_historical_peak = invoke(
    @old_public_history, '--acknowledge-historical-regressions',
    '--planned', '0.99'
);
ok($equal_historical_peak->{rc} != 0,
    'a candidate equal to an older public maximum is rejected');

my $future_drop_with_ack = invoke(
    @old_public_history, '--acknowledge-historical-regressions',
    '--planned', '1.00', '--planned', '0.99'
);
ok($future_drop_with_ack->{rc} != 0,
    'acknowledging the past cannot waive strict order among future releases');

my $unreviewed_ack = invoke(
    '--published', '0.99', '--published', '0.100',
    '--acknowledge-historical-regressions', '--planned', '1.00'
);
ok($unreviewed_ack->{rc} != 0,
    'historical acknowledgement cannot bypass the full-history attestation');

# A file is the practical, reviewable input for hundreds of historical
# CPAN releases; contents are illustrative, never an attested full ledger.
sub history_file {
    my ($content) = @_;
    my ($fh, $path) = tempfile(UNLINK => 1);
    print {$fh} $content or die "Cannot write test ledger: $!";
    close $fh or die "Cannot close test ledger: $!";
    return $path;
}

my $file_source = history_file(
    "# Sample chronology: not a complete release history\r\n" .
    "2.58\r\n\r\n 2.59 # human-provided note\r\n"
);
my $file_pass = invoke('--history-reviewed', '--published-file', $file_source,
    '--planned', '3.00');
is($file_pass->{rc}, 0,
    'line-oriented history file accepts CRLF, comments and chronological records');
like($file_pass->{stdout}, qr/2 audited public predecessors/,
    'file input is counted in the audited predecessor total');

my $mixed_source = invoke('--history-reviewed', '--published', '2.57',
    '--published-file', $file_source, '--planned', '3.00');
ok($mixed_source->{rc} != 0, 'mixing CLI and file predecessors is rejected');
like($mixed_source->{stderr}, qr/Cannot combine --published/,
    'mixed-source diagnostic is explicit');

my $inverted_file = history_file("0.99\n0.100\n");
my $file_requires_ack = invoke('--history-reviewed',
    '--published-file', $inverted_file, '--planned', '1.00');
ok($file_requires_ack->{rc} != 0,
    'file history with numeric inversion cannot silently pass');
my $file_with_ack = invoke('--history-reviewed',
    '--published-file', $inverted_file,
    '--acknowledge-historical-regressions', '--planned', '1.00');
is($file_with_ack->{rc}, 0,
    'explicitly acknowledged file history uses the same historical-peak gate');
my $file_below_peak = invoke('--history-reviewed',
    '--published-file', $inverted_file,
    '--acknowledge-historical-regressions', '--planned', '0.50');
ok($file_below_peak->{rc} != 0,
    'file source still rejects candidates below the historic maximum');

my $file_without_review = invoke('--published-file', $file_source,
    '--planned', '3.00');
ok($file_without_review->{rc} != 0,
    'file input cannot bypass mandatory human-history attestation');

my $empty_file = history_file("# no historical public entries\n");
my $empty_history = invoke('--history-reviewed',
    '--published-file', $empty_file, '--planned', '3.00');
ok($empty_history->{rc} != 0,
    'empty version file is rejected instead of silently implying no predecessors');

my $bad_file = history_file("2.58\nnot-a-version\n");
my $bad_history = invoke('--history-reviewed',
    '--published-file', $bad_file, '--planned', '3.00');
ok($bad_history->{rc} != 0, 'malformed ledger row fails closed');
like($bad_history->{stderr}, qr/line 2/,
    'malformed ledger row includes its line number');

my $missing_history = invoke('--history-reviewed',
    '--published-file', File::Spec->catfile(
        $FindBin::Bin, 'absent-v3-version-ledger.txt'
    ), '--planned', '3.00');
ok($missing_history->{rc} != 0, 'missing history file fails closed');

my $same_number = invoke('--history-reviewed',
    '--published', '2.59', '--planned', '2.59');
ok($same_number->{rc} != 0, 'a repeated public version is not monotonic');

my $dev_as_stable = invoke('--history-reviewed', '--planned', '3.01_01');
ok($dev_as_stable->{rc} != 0,
    'last future release must have non-underscored stable version');
like($dev_as_stable->{stderr}, qr/final --planned version must be stable/,
    'missing stable endpoint is explained');

my $invalid = invoke('--history-reviewed', '--planned', 'not-a-version');
ok($invalid->{rc} != 0, 'invalid Perl version string is rejected');
like($invalid->{stderr}, qr/Invalid Perl version string/,
    'invalid-version diagnostics are explicit');

my $help = invoke('--help');
is($help->{rc}, 0, 'offline version gate help is available');
like($help->{stdout}, qr/not publication history/i,
    'help explicitly says the tool cannot audit CPAN history');

done_testing;
