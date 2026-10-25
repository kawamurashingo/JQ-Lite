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
    my ($a, $b) = @_;
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $^X, $tool,
        '--backpan-author', $a, '--metacpan', $b);
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
done_testing;
