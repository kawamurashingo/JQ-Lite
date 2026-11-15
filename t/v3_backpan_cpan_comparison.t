use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;
use File::Temp qw(tempfile);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my $tool = File::Spec->catfile($FindBin::Bin, '..', 'ci',
    'compare-backpan-cpan-inventory.pl');
ok(-f $tool, 'offline BackPAN comparison script exists');
sub fixture {
    my ($text) = @_;
    my ($fh, $path) = tempfile(UNLINK => 1);
    print {$fh} $text or die "Cannot write fixture: $!";
    close $fh or die "Cannot close fixture: $!";
    return $path;
}
sub run_tool {
    my (@args) = @_;
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $^X, $tool, @args);
    close $in;
    my $stdout = do { local $/; <$out> };
    my $stderr = do { local $/; <$err> };
    close $out;
    close $err;
    waitpid($pid, 0);
    return { code => $? >> 8, out => $stdout || '', err => $stderr || '' };
}
my $bh = "path\tepoch\tsize\n";
my $ch = "archive\tversion\tindex_last_modified\tclassification\n";
sub br {
    my ($version, $epoch, $path) = @_;
    $path ||= "S/SH/SHINGO/JQ-Lite-$version.tar.gz";
    return "$path\t$epoch\t8192\n";
}
sub cr {
    my ($version, $mtime, $class) = @_;
    return "JQ-Lite-$version.tar.gz\t$version\t$mtime\t" .
        ($class || 'observed-archive') . "\n";
}
my $backpan = fixture($bh . br('0.99', 1760318760) .
    br('0.100', 1760327400) . br('2.59', 1789901940));
my $cpan = fixture($ch . cr('0.99', '2025-10-13 01:26') .
    cr('0.100', '2025-10-13 03:50') . cr('2.59', '2026-09-20 10:59'));
my $same = run_tool('--backpan-file', $backpan, '--inventory', $cpan);
is($same->{code}, 0, 'matching observations return zero, without audit attestation');
like($same->{out}, qr/BackPAN observed versions: 3/, 'BackPAN count reported');
like($same->{out}, qr/HISTORICAL PERL ORDER NON-INCREASE: 0\.100 <= 0\.99/,
    'historical numeric version inversion is explicitly reported');
like($same->{out}, qr/NOT a complete PAUSE\/publication audit/, 'no release sign-off');
like($same->{out}, qr/BACKPAN ORDER OBSERVATION: 1760318760\t0\.99/, 'epoch recorded as observation');

my $older = fixture($bh . br('0.98', 1760100000) . br('0.99', 1760318760) .
    br('0.100', 1760327400) . br('2.59', 1789901940));
my $only_backpan = run_tool('--backpan-file', $older, '--inventory', $cpan);
ok($only_backpan->{code} != 0, 'BackPAN-only archival release requires follow-up');
like($only_backpan->{out}, qr/BACKPAN ONLY.*JQ-Lite-0\.98/, 'BackPAN-only artifact named');
my $partial_backpan = fixture($bh . br('0.99', 1760318760) . br('0.100', 1760327400));
my $only_cpan = run_tool('--backpan-file', $partial_backpan, '--inventory', $cpan);
ok($only_cpan->{code} != 0, 'CPAN-only version requires follow-up');
like($only_cpan->{out}, qr/CPAN ONLY.*JQ-Lite-2\.59/, 'CPAN-only artifact named');

my $tie = fixture($bh . br('0.99', 1760318760) . br('0.100', 1760318760));
my $tie_cpan = fixture($ch . cr('0.99', '2025-10-13 01:26') .
    cr('0.100', '2025-10-13 03:50'));
my $ambiguous = run_tool('--backpan-file', $tie, '--inventory', $tie_cpan);
ok($ambiguous->{code} != 0, 'equal BackPAN epochs fail ambiguous chronology');
like($ambiguous->{out}, qr/AMBIGUOUS ORDER/, 'ties are prominently flagged');

my $internal_backpan = fixture($bh . br('v3.00_03', 1792900000));
my $internal_cpan = fixture($ch . cr('v3.00_03', '2026-10-25 01:00'));
my $developer = run_tool('--backpan-file', $internal_backpan, '--inventory', $internal_cpan);
ok($developer->{code} != 0, 'v-prefixed internal-only archive cannot reconcile successfully');
like($developer->{out}, qr/INTERNAL-DEVELOPER-ARTIFACT-ALERT/, 'developer exposure flagged');
my $wrong_class = fixture($ch . cr('2.59', '2026-09-20 10:59',
    'INTERNAL-DEVELOPER-ARTIFACT-ALERT'));
my $alert_class = run_tool('--backpan-file', fixture($bh . br('2.59', 1789901940)),
    '--inventory', $wrong_class);
ok($alert_class->{code} != 0, 'upstream internal-alert classification also fails closed');

my $dupe = fixture($bh . br('2.59', 1789901940) . br('2.59', 1789901941));
ok(run_tool('--backpan-file', $dupe, '--inventory', $cpan)->{code} != 0,
    'duplicate BackPAN record rejected');
my $dupe_version = fixture($bh . br('2.59', 1789901940) .
    br('2.59', 1789901941, 'A/AB/OTHER/JQ-Lite-2.59.tar.gz'));
ok(run_tool('--backpan-file', $dupe_version, '--inventory', $cpan)->{code} != 0,
    'same version under different author cannot be silently merged');
my $other_author = fixture($bh . br('2.59', 1789901940,
    'A/AB/OTHER/JQ-Lite-2.59.tar.gz'));
my $just_259 = fixture($ch . cr('2.59', '2026-09-20 10:59'));
my $wrong_author = run_tool('--backpan-file', $other_author, '--inventory', $just_259);
ok($wrong_author->{code} != 0, 'same filename but different uploader path fails closed');
like($wrong_author->{out}, qr/AUTHOR\/PATH MISMATCH/, 'provenance conflict explicitly reported');
my $bad_path = fixture($bh . "S/SH/SHINGO/JQ-Lite-2.59.zip\t1789901940\t123\n");
ok(run_tool('--backpan-file', $bad_path, '--inventory', $cpan)->{code} != 0,
    'unexpected archive suffix rejected');
my $bad_epoch = fixture($bh . br('2.59', '2026-09-20'));
ok(run_tool('--backpan-file', $bad_epoch, '--inventory', $cpan)->{code} != 0,
    'non-numeric epoch rejected');
my $bad_header = fixture("filename,epoch,size\n" . br('2.59', 1789901940));
ok(run_tool('--backpan-file', $bad_header, '--inventory', $cpan)->{code} != 0,
    'wrong BackPAN header rejected');
my $bad_cpan_header = fixture("version\n2.59\n");
ok(run_tool('--backpan-file', $backpan, '--inventory', $bad_cpan_header)->{code} != 0,
    'wrong CPAN header rejected');
my $bad_cpan_name = fixture($ch .
    "JQ-Lite-2.59.tar.gz\t2.58\t2026-09-20 10:59\tobserved-archive\n");
ok(run_tool('--backpan-file', $backpan, '--inventory', $bad_cpan_name)->{code} != 0,
    'mismatched CPAN archive and version rejected');
my $empty = fixture($bh);
ok(run_tool('--backpan-file', $empty, '--inventory', $cpan)->{code} != 0,
    'empty BackPAN observation set rejected');
my $no_args = run_tool();
ok($no_args->{code} != 0, 'both file arguments required');
my $help = run_tool('--help');
is($help->{code}, 0, 'help option works');
like($help->{out}, qr/REVIEW ONLY/, 'help prohibits treating this as release approval');
done_testing;
