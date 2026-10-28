use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;
use File::Temp qw(tempfile);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);
use MIME::Base64 qw(encode_base64);

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
    my ($a, $b, $pause, $mbox, $count) = @_;
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $^X, $tool,
        '--backpan-author', $a, '--metacpan', $b,
        (defined($pause) ? ('--pause-receipts', $pause) : ()),
        (defined($mbox) ? ('--pause-mbox', $mbox) : ()),
        (defined($count) ? ('--expected-pause-events', $count) : ()));
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


# Gmail Takeout-style local MBOX import; ALL fixtures are synthetic.
# The real mailbox and its headers must never be checked into GitHub.
sub mbox_mail {
    my ($version, $utc, $entered) = @_;
    my $archive = "JQ-Lite-$version.tar.gz";
    my $header = "From synthetic\@example.invalid Tue Oct 28 00:00:00 2025\n"
        . "Subject: CPAN Upload: S/SH/SHINGO/$archive\n"
        . "Content-Type: text/plain; charset=UTF-8\n";
    my $body = "The uploaded file\n\n$archive\n\nhas entered CPAN as\n\n"
        . 'file: $CPAN/authors/id/S/SH/SHINGO/' . "$archive\n"
        . "size: 1234 bytes\n"
        . "sha256: " . ('a' x 64) . "\n\n"
        . "Request entered on: $entered\n"
        . "Request completed: $utc\n";
    return ($header, $body);
}
my @raw = (
    mbox_mail('0.05', 'Sat, 29 Mar 2025 03:37:10 GMT',
        'Sat, 29 Mar 2025 03:36:06 GMT'),
    mbox_mail('1.31', 'Sun, 26 Oct 2025 09:05:27 GMT',
        'Sun, 26 Oct 2025 09:04:12 GMT'),
    mbox_mail('1.32', 'Sun, 26 Oct 2025 11:09:49 GMT',
        'Sun, 26 Oct 2025 11:09:39 GMT'),
);
my $mbox_text = '';
for my $i (0 .. 2) {
    $mbox_text .= $raw[$i * 2] . "\n" . $raw[$i * 2 + 1];
}
my $mbox_file = saved($mbox_text);
my $mbox_ok = run_tool($archive, $meta, undef, $mbox_file, 3);
is($mbox_ok->{exit}, 0, 'local mbox import agrees with source observations');
like($mbox_ok->{out}, qr/PAUSE original receipt events: 3/,
    'mbox imported three original receipt bodies');
like($mbox_ok->{out}, qr/REVIEW ONLY/,
    'a successful mbox observation never approves publication');

my $wrong_count = run_tool($archive, $meta, undef, $mbox_file, 4);
ok($wrong_count->{exit} != 0,
    'missing expected mbox upload event fails closed');
like($wrong_count->{err}, qr/Unexpected PAUSE receipt event count/,
    'expected-event error is explicit without leaking mail headers');

my $mbox_missing = run_tool($archive, $meta, undef,
    saved($raw[0] . "\n" . $raw[1] . $raw[2] . "\n" . $raw[3]));
ok($mbox_missing->{exit} != 0, 'incomplete mbox version-set fails');
like($mbox_missing->{out}, qr/PAUSE-MISSING VERSION: 1\.32/,
    'archive missing from partial original mbox is reported');

my $mbox_duplicate = run_tool($archive, $meta, undef,
    saved($mbox_text . $raw[2] . "\n" . $raw[3]));
ok($mbox_duplicate->{exit} != 0,
    'duplicate exact original upload completion event rejected');

my $qprint = $mbox_text;
$qprint =~ s/Content-Type: text\/plain; charset=UTF-8\n/Content-Type: text\/plain; charset=UTF-8\nContent-Transfer-Encoding: quoted-printable\n/g;
$qprint =~ s/The uploaded file/The=20uploaded file/g;
is(run_tool($archive, $meta, undef, saved($qprint))->{exit}, 0,
    'quoted-printable single-part PAUSE body supported');

my $encoded = '';
for my $i (0 .. 2) {
    my $head = $raw[$i * 2];
    $head .= "Content-Transfer-Encoding: base64\n";
    $encoded .= $head . "\n" . encode_base64($raw[$i * 2 + 1]);
}
is(run_tool($archive, $meta, undef, saved($encoded))->{exit}, 0,
    'base64 single-part PAUSE body supported');

my $unsupported = $mbox_text;
$unsupported =~ s/Content-Type: text\/plain; charset=UTF-8/Content-Type: multipart\/mixed; boundary="unsafe"/;
my $bad_mime = run_tool($archive, $meta, undef, saved($unsupported));
ok($bad_mime->{exit} != 0, 'unparsed multipart target mail is not silently omitted');
like($bad_mime->{err}, qr/Unsupported non-plain-text PAUSE receipt MIME/,
    'unsupported MIME format fails closed without outputting mail data');

my $bad_body = $mbox_text;
$bad_body =~ s/Request completed on:/Request completed on:/;
$bad_body =~ s/Request completed: Sat, 29 Mar 2025 03:37:10 GMT/Request completed: invalid date/;
ok(run_tool($archive, $meta, undef, saved($bad_body))->{exit} != 0,
    'malformed original completion timestamp rejected');

my $private_unrelated =
    "From private\@example.invalid Tue Oct 28 00:00:00 2025\n"
    . "Subject: Private unrelated mail\n\n"
    . "SECRETS_DO_NOT_LOG\n";
my $unrelated = run_tool($archive, $meta, undef,
    saved($private_unrelated . $mbox_text));
is($unrelated->{exit}, 0, 'unrelated local mbox messages are skipped');
unlike($unrelated->{out} . $unrelated->{err}, qr/SECRETS_DO_NOT_LOG|example\.invalid/,
    'tool stdout/stderr never display unrelated private mail fields');

my ($dev_h, $dev_b) = mbox_mail('3.00_03',
    'Sun, 26 Oct 2025 11:09:49 GMT', 'Sun, 26 Oct 2025 11:09:39 GMT');
my $devmail = run_tool($archive, $meta, undef, saved($dev_h . "\n" . $dev_b));
ok($devmail->{exit} != 0,
    'internal developer mbox receipt triggers manual audit instead of being ignored');

my $conflict_mbox = $mbox_text . $raw[2] . "\n" . $raw[3];
$conflict_mbox =~ s/sha256: a{64}\nRequest entered on: Sun, 26 Oct 2025 09:04:12 GMT/sha256: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\nRequest entered on: Sun, 26 Oct 2025 09:04:12 GMT/;
# The repeated event is the same UTC instant and is invalid regardless.
ok(run_tool($archive, $meta, undef, saved($conflict_mbox))->{exit} != 0,
    'same-version non-unique event cannot hide a competing body digest');


# PAUSE's actual file-hash summary may indent fields with spaces.
my $aligned = $mbox_text;
$aligned =~ s/^file:/  file:/mg;
$aligned =~ s/^size:/  size:/mg;
$aligned =~ s/^sha256:/  sha256:/mg;
$aligned =~ s/^Request completed:/  Request completed:/mg;
is(run_tool($archive, $meta, undef, saved($aligned), 3)->{exit}, 0,
    'aligned PAUSE producer fields are recognized without loosening their values');

# RFC 2047 subjects must be decoded BEFORE target/developer detection.
my $q_subject = $mbox_text;
$q_subject =~ s{^Subject: CPAN Upload: S/SH/SHINGO/JQ-Lite-0\.05}{
    'Subject: =?UTF-8?Q?CPAN_Upload:?= S/SH/SHINGO/JQ-Lite-0.05'}em;
is(run_tool($archive, $meta, undef, saved($q_subject), 3)->{exit}, 0,
    'quoted-printable MIME subject identifies intended PAUSE upload');
my $b_subject = $mbox_text;
my $encoded_title = encode_base64('CPAN Upload:', '');
$b_subject =~ s{^Subject: CPAN Upload: S/SH/SHINGO/JQ-Lite-0\.05}{
    'Subject: =?UTF-8?B?' . $encoded_title . '?= S/SH/SHINGO/JQ-Lite-0.05'}em;
is(run_tool($archive, $meta, undef, saved($b_subject), 3)->{exit}, 0,
    'base64 MIME subject identifies intended PAUSE upload');
my $encoded_dev = $dev_h . "\n" . $dev_b;
$encoded_dev =~ s/^Subject: CPAN Upload: /
    'Subject: =?UTF-8?Q?CPAN_Upload:?= '/em;
my $with_encoded_dev = run_tool($archive, $meta, undef,
    saved($mbox_text . $encoded_dev), 3);
ok($with_encoded_dev->{exit} != 0,
    'MIME-encoded developer receipt cannot bypass the release audit alert');

for my $field ('file', 'size', 'sha256', 'Request completed') {
    my $two = $mbox_text;
    $two =~ s/^(\Q$field\E:[^\n]*\n)/$1$1/m;
    my $result = run_tool($archive, $meta, undef, saved($two), 3);
    ok($result->{exit} != 0,
        "duplicate $field receipt evidence fails closed");
    like($result->{err}, qr/Missing or duplicate PAUSE receipt field/,
        "duplicate $field explanation never exposes raw mail");
}

done_testing;
