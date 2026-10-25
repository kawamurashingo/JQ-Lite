use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

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

my $prerelease_downgrade = invoke('--history-reviewed',
    '--planned', '3.01_01', '--planned', '3.01');
ok($prerelease_downgrade->{rc} != 0,
    'a generic underscore prerelease is not blindly considered older than stable');

my $unsorted_history = invoke('--history-reviewed', '--published', '2.59',
    '--published', '2.58', '--planned', '3.00');
ok($unsorted_history->{rc} != 0,
    'chronologically supplied public history must itself increase');

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
