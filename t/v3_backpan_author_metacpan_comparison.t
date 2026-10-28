use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;
use File::Temp qw(tempfile);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my $tool = File::Spec->catfile($FindBin::Bin, '..', 'ci',
    'compare-backpan-author-metacpan-inventory.pl');
ok(-f $tool, 'offline BackPAN author/MetaCPAN comparison tool is shipped');
sub saved {
    my ($text) = @_;
    my ($fh, $path) = tempfile(UNLINK => 1);
    print {$fh} $text or die "write: $!";
    close $fh or die "close: $!";
    return $path;
}
sub run_tool {
    my ($a, $b, $pause) = @_;
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $^X, $tool,
        '--backpan-author', $a, '--metacpan', $b,
        (defined($pause) ? ('--pause-receipts', $pause) : ()));
    close $in;
    my $stdout = do { local $/; <$out> } || '';
    my $stderr = do { local $/; <$err> } || '';
    close $out; close $err; waitpid($pid, 0);
    return { exit => $? >> 8, out => $stdout, err => $stderr };
}
my $ahead = "archive\tversion\tindex_last_modified\tclassification\n";
my $mhead = "release\tversion\tmetacpan_date\tauthor\tstatus\tclassification\n";
sub ba {
    my ($ver) = @_;
    return "JQ-Lite-$ver.tar.gz\t$ver\t2025-10-26 11:09\tobserved-archive\n";
}
sub ma {
    my ($ver, $author) = @_;
    $author ||= 'SHINGO';
    return "JQ-Lite-$ver\t$ver\t2025-10-26T11:09:00Z\t$author\tbackpan\tobserved-metacpan-release\n";
}
my $archive = saved($ahead . ba('0.05') . ba('1.31') . ba('1.32'));
my $meta = saved($mhead . ma('0.05') . ma('1.31') . ma('1.32'));
my $good = run_tool($archive, $meta);
is($good->{exit}, 0, 'identical observational sets match');
like($good->{out}, qr/BackPAN SHINGO author archive versions: 3/, 'BackPAN total printed');
like($good->{out}, qr/MetaCPAN JQ-Lite release versions: 3/, 'MetaCPAN total printed');
like($good->{out}, qr/REVIEW ONLY/, 'successful match is not publication signoff');

my $missing_archive = run_tool(saved($ahead . ba('0.05') . ba('1.31')), $meta);
ok($missing_archive->{exit} != 0, 'MetaCPAN-only release is a discrepancy');
like($missing_archive->{out}, qr/METACPAN ONLY: 1\.32/, 'missing historical archive shown');
my $missing_meta = run_tool($archive, saved($mhead . ma('0.05') . ma('1.31')));
ok($missing_meta->{exit} != 0, 'BackPAN-only release is a discrepancy');
like($missing_meta->{out}, qr/BACKPAN AUTHOR ONLY: 1\.32/, 'BackPAN-only archive shown');
my $off_author = run_tool($archive, saved($mhead . ma('0.05') . ma('1.31') . ma('1.32', 'OTHER')));
ok($off_author->{exit} != 0, 'foreign author requires investigation');
like($off_author->{out}, qr/NON-SHINGO RELEASE AUTHOR: 1\.32/, 'foreign author surfaced');

my $dev = run_tool(saved($ahead . ba('3.00_03')),
    saved($mhead . ma('3.00_03')));
ok($dev->{exit} != 0, 'internal developer build fails even if sources agree');
like($dev->{out}, qr/INTERNAL-DEVELOPER-ARTIFACT-ALERT/, 'internal alert preserved');
my $vdev = run_tool(saved($ahead . ba('v3.00_01')),
    saved($mhead . ma('v3.00_01')));
ok($vdev->{exit} != 0, 'v-prefixed internal build cannot evade guard');

my $duplicate = run_tool(saved($ahead . ba('1.31') . ba('1.31')), saved($mhead . ma('1.31')));
ok($duplicate->{exit} != 0, 'duplicate source archive version rejected');
like($duplicate->{err}, qr/Duplicate BackPAN/, 'duplicate diagnostic');
my $dup_meta = run_tool(saved($ahead . ba('1.31')), saved($mhead . ma('1.31') . ma('1.31')));
ok($dup_meta->{exit} != 0, 'duplicate MetaCPAN release rejected');
my $bad_a = run_tool(saved("wrong\n" . ba('1.31')), saved($mhead . ma('1.31')));
ok($bad_a->{exit} != 0, 'wrong author-index TSV schema rejected');
my $bad_m = run_tool(saved($ahead . ba('1.31')), saved("wrong\n" . ma('1.31')));
ok($bad_m->{exit} != 0, 'wrong MetaCPAN TSV schema rejected');
my $bad_class = run_tool(saved($ahead . "JQ-Lite-1.31.tar.gz\t1.31\t2025-10-26 11:09\tapproved\n"),
    saved($mhead . ma('1.31')));
ok($bad_class->{exit} != 0, 'fabricated release approval field rejected');
my $empty = run_tool(saved($ahead), $meta);
ok($empty->{exit} != 0, 'empty author index rejected');
my $empty_meta = run_tool($archive, saved($mhead));
ok($empty_meta->{exit} != 0, 'empty MetaCPAN search rejected');
my $bad_time = run_tool(saved($ahead . ba('1.31')), saved($mhead . "JQ-Lite-1.31\t1.31\ttomorrow\tSHINGO\tbackpan\tobserved-metacpan-release\n"));
ok($bad_time->{exit} != 0, 'invalid MetaCPAN timestamps rejected');

# Optional PRIVATE PAUSE receipt schema: use non-sensitive synthetic data.
my $phead = "archive\tversion\tcompleted_utc\tbytes\tsha256\n";
sub pa {
    my ($version, $when, $hash, $bytes) = @_;
    $hash = 'a' x 64 unless defined $hash;
    $bytes = 1234 unless defined $bytes;
    return "JQ-Lite-$version.tar.gz\t$version\t$when\t$bytes\t$hash\n";
}
my $pause = saved($phead
    . pa('0.05', '2025-03-29T03:37:10Z')
    . pa('1.31', '2025-10-26T09:05:27Z')
    . pa('1.32', '2025-10-26T11:09:49Z'));
my $all_match = run_tool($archive, $meta, $pause);
is($all_match->{exit}, 0,
    'private PAUSE receipt version set matches independently saved observations');
like($all_match->{out}, qr/PAUSE original receipt events: 3/,
    'private receipt event count displayed without raw mail');
like($all_match->{out}, qr/PAUSE distinct versions: 3/,
    'distinct PAUSE version count shown');
like($all_match->{out}, qr/REVIEW ONLY/,
    'even three-way exact match does not certify original PAUSE ledger');

my $repeat_pause = saved($phead
    . pa('0.05', '2025-03-29T03:37:10Z')
    . pa('1.31', '2025-10-26T09:05:27Z')
    . pa('1.31', '2025-10-26T09:06:59Z')
    . pa('1.32', '2025-10-26T11:09:49Z'));
my $with_repeat = run_tool($archive, $meta, $repeat_pause);
is($with_repeat->{exit}, 0, 'same-byte repeat with distinct completion time is retained');
like($with_repeat->{out}, qr/PAUSE same-byte repeated uploads: 1/,
    'repeat is counted instead of silently removed');

my $conflict = run_tool($archive, $meta, saved($phead
    . pa('0.05', '2025-03-29T03:37:10Z')
    . pa('1.31', '2025-10-26T09:05:27Z')
    . pa('1.31', '2025-10-26T09:06:59Z', 'b' x 64)
    . pa('1.32', '2025-10-26T11:09:49Z')));
ok($conflict->{exit} != 0, 'same version with different tarball SHA-256 fails closed');
like($conflict->{err}, qr/Conflicting PAUSE archive size or SHA-256/,
    'hash inconsistency is a review blocker');

my $no_distinct = run_tool($archive, $meta, saved($phead
    . pa('0.05', '2025-03-29T03:37:10Z')
    . pa('1.31', '2025-10-26T09:05:27Z')));
ok($no_distinct->{exit} != 0, 'missing PAUSE receipt version fails despite matching public indexes');
like($no_distinct->{out}, qr/PAUSE-MISSING VERSION: 1\.32/,
    'missing private-receipt evidence identified');

my $pause_extra = run_tool($archive, $meta, saved($phead
    . pa('0.05', '2025-03-29T03:37:10Z')
    . pa('1.31', '2025-10-26T09:05:27Z')
    . pa('1.32', '2025-10-26T11:09:49Z')
    . pa('2.59', '2026-09-20T10:59:08Z')));
ok($pause_extra->{exit} != 0, 'PAUSE-only version fails closed');
like($pause_extra->{out}, qr/PAUSE-ONLY VERSION: 2\.59/,
    'extra PAUSE version requires external corroboration');

my $dupe_event = run_tool($archive, $meta, saved($phead
    . pa('1.31', '2025-10-26T09:05:27Z')
    . pa('1.31', '2025-10-26T09:05:27Z')));
ok($dupe_event->{exit} != 0, 'same version and completion time cannot masquerade as two uploads');

my $bad_receipt = run_tool($archive, $meta,
    saved($phead . "JQ-Lite-1.31.tar.gz\t1.31\tnot-a-time\t1234\t" . ('a' x 64) . "\n"));
ok($bad_receipt->{exit} != 0, 'missing original UTC completion time rejected');

my $internal_receipt = run_tool($archive, $meta,
    saved($phead . pa('3.00_03', '2026-10-25T00:00:00Z')));
ok($internal_receipt->{exit} != 0,
    'internal developer artifact cannot be laundered through PAUSE receipt input');

my $historic_archive = saved($ahead . ba('0.99') . ba('0.100') . ba('1.00'));
my $historic_meta = saved($mhead . ma('0.99') . ma('0.100') . ma('1.00'));
my $historic_pause = saved($phead
    . pa('0.99', '2025-10-13T01:26:30Z')
    . pa('0.100', '2025-10-13T03:50:59Z')
    . pa('1.00', '2025-10-14T21:14:59Z'));
my $historic_result = run_tool($historic_archive, $historic_meta, $historic_pause);
is($historic_result->{exit}, 0,
    'historical non-increase is reported without rewriting real publication history');
like($historic_result->{out}, qr/HISTORICAL NON-INCREASE: 0\.100 after 0\.99/,
    'Perl version semantics identify original 0.99 to 0.100 regression');
like($historic_result->{out}, qr/REVIEW ONLY/,
    'historic regression observation does not imply approval');
my $ambiguous = run_tool($historic_archive, $historic_meta,
    saved($phead
        . pa('0.99', '2025-10-13T01:26:30Z')
        . pa('0.100', '2025-10-13T01:26:30Z')
        . pa('1.00', '2025-10-14T21:14:59Z')));
ok($ambiguous->{exit} != 0,
    'identical UTC completion times across different versions require review');
like($ambiguous->{out}, qr/AMBIGUOUS PAUSE COMPLETION TIME/,
    'ambiguous original order is explicitly diagnosed');

done_testing;
