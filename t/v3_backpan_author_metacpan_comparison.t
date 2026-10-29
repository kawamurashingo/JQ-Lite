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

# Developer releases are identified by an underscore suffix regardless
# of the major/minor version, including v-prefixed names. Even when both
# independent public observations agree, they must not certify a release.
for my $developer_version ('1.31_01', '3.01_01', 'v3.01_02') {
    my $result = run_tool(
        saved($ahead . ba($developer_version)),
        saved($mhead . ma($developer_version)));
    ok($result->{exit} != 0,
        'synthetic non-3.00 underscore developer version fails closed');
    like($result->{out}, qr/INTERNAL-DEVELOPER-ARTIFACT-ALERT:/,
        'matching observations of developer release still emit an alert');
}
my $backpan_other_developer = run_tool(
    saved($ahead . ba('0.05') . ba('1.31_01')),
    saved($mhead . ma('0.05')));
ok($backpan_other_developer->{exit} != 0,
    'developer release in BackPAN-only evidence is blocked');
like($backpan_other_developer->{out},
    qr/INTERNAL-DEVELOPER-ARTIFACT-ALERT:/,
    'BackPAN-only developer release emits the explicit alert');
my $metacpan_other_developer = run_tool(
    saved($ahead . ba('0.05')),
    saved($mhead . ma('0.05') . ma('3.01_01')));
ok($metacpan_other_developer->{exit} != 0,
    'developer release in MetaCPAN-only evidence is blocked');
like($metacpan_other_developer->{out},
    qr/INTERNAL-DEVELOPER-ARTIFACT-ALERT:/,
    'MetaCPAN-only developer release emits the explicit alert');


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


# Public BackPAN Last-Modified timestamps must be real calendar dates
# and UTC clock values, not merely strings matching the shape.
for my $bad_modified (
    '2025-02-31 11:09',
    '2025-02-29 11:09',
    '2025-04-31 11:09',
    '2025-10-26 24:00',
    '2025-10-26 11:60',
) {
    my $row = ba('0.05');
    is(($row =~ s/2025-10-26 11:09/$bad_modified/), 1,
        'synthetic invalid BackPAN timestamp prepared');
    my $result = run_tool(
        saved($ahead . $row . ba('1.31') . ba('1.32')), $meta);
    ok($result->{exit} != 0,
        'impossible BackPAN observation calendar/clock is rejected');
    like($result->{err}, qr/Invalid BackPAN listing modification time/,
        'invalid BackPAN timestamp gets a specific diagnostic');
}
my $leap_modified_row = ba('0.05');
is(($leap_modified_row =~
    s/2025-10-26 11:09/2024-02-29 12:34/), 1,
    'synthetic valid BackPAN leap-day timestamp prepared');
my $leap_modified = run_tool(
    saved($ahead . $leap_modified_row . ba('1.31') . ba('1.32')), $meta);
is($leap_modified->{exit}, 0,
    'real BackPAN leap day with minute precision is accepted');


# MetaCPAN dates may be zoned, fractional, or unzoned, but even a
# syntactically plausible observation must represent an actual calendar
# date, clock time, and bounded numeric timezone offset.
for my $invalid_date (
    '2025-02-31T11:09:00Z',
    '2025-02-29T11:09:00Z',
    '2025-04-31T11:09:00.123+09:00',
    '2025-10-26T24:00:00Z',
    '2025-10-26T11:60:00Z',
    '2025-10-26T11:09:60Z',
    '2025-10-26T11:09:00+24:00',
    '2025-10-26T11:09:00-03:60',
) {
    my $row = ma('0.05');
    is(($row =~ s/2025-10-26T11:09:00Z/$invalid_date/), 1,
        'synthetic invalid MetaCPAN timestamp prepared');
    my $result = run_tool($archive,
        saved($mhead . $row . ma('1.31') . ma('1.32')));
    ok($result->{exit} != 0,
        'invalid MetaCPAN observation calendar, clock or offset is rejected');
    like($result->{err}, qr/Invalid MetaCPAN date/,
        'invalid MetaCPAN observation gets a source-safe diagnostic');
}
for my $valid_date (
    '2024-02-29T23:59:59.123+14:00',
    '2025-10-26T11:09:00-05:30',
    '2025-10-26T11:09:00',
    '2025-10-26T11:09:00Z',
) {
    my $row = ma('0.05');
    is(($row =~ s/2025-10-26T11:09:00Z/$valid_date/), 1,
        'synthetic valid MetaCPAN timestamp prepared');
    my $result = run_tool($archive,
        saved($mhead . $row . ma('1.31') . ma('1.32')));
    is($result->{exit}, 0,
        'valid MetaCPAN leap date, offset or optional zone is accepted');
}

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

# The private TSV path must never be echoed when the offline importer
# cannot open it. Only a non-sensitive synthetic temporary file is used.
my $private_missing_path = saved('synthetic only');
unlink $private_missing_path or die "cannot remove synthetic fixture: $!";
my $private_missing = run_tool($archive, $meta, $private_missing_path);
ok($private_missing->{exit} != 0, 'unreadable private TSV fails closed');
like($private_missing->{err}, qr/Cannot open private PAUSE receipts TSV/,
    'private TSV open failure has a path-free diagnostic');
unlike($private_missing->{out} . $private_missing->{err},
    qr/\Q$private_missing_path\E/,
    'private input path is not written to diagnostic output');

my $bad_receipt = run_tool($archive, $meta,
    saved($phead . "JQ-Lite-1.31.tar.gz\t1.31\tnot-a-time\t1234\t" . ('a' x 64) . "\n"));
ok($bad_receipt->{exit} != 0, 'missing original UTC completion time rejected');

# The manual PRIVATE_RECEIPTS.tsv format check must also validate the
# real calendar, not only numeric fields. Synthetic dates only.
for my $impossible (
    '2025-02-31T03:37:10Z',
    '2025-02-29T03:37:10Z',
    '2025-04-31T03:37:10Z',
) {
    my $bad_date = run_tool($archive, $meta, saved($phead
        . pa('0.05', $impossible)
        . pa('1.31', '2025-10-26T09:05:27Z')
        . pa('1.32', '2025-10-26T11:09:49Z')));
    ok($bad_date->{exit} != 0,
        'impossible Gregorian PAUSE TSV completion date is rejected');
    like($bad_date->{err}, qr/Malformed PAUSE receipt/,
        'impossible TSV calendar date has a safe diagnostic');
}

my $leap_date = run_tool($archive, $meta, saved($phead
    . pa('0.05', '2024-02-29T03:37:10Z')
    . pa('1.31', '2025-10-26T09:05:27Z')
    . pa('1.32', '2025-10-26T11:09:49Z')));
is($leap_date->{exit}, 0,
    'real February 29 leap-day PAUSE TSV timestamp is accepted');

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

# An incomplete "From ... weekday ..." line in an original mail BODY
# is not a Takeout envelope. Never split and lose part of a PAUSE
# receipt just because quoted text starts with an mbox-like prefix.
my $body_from = $mbox_text;
my $quoted_from = "From quoted\@example.invalid Tue Oct 28 not-a-time 2025\n";
is(($body_from =~ s/(Request completed: Sat, 29 Mar 2025 03:37:10 GMT\n)/
    $quoted_from . $1/e), 1,
    'synthetic incomplete From line inserted into a receipt body');
my $body_from_result = run_tool($archive, $meta, undef,
    saved($body_from), 3);
is($body_from_result->{exit}, 0,
    'body From prefix without a full envelope does not truncate receipt');
like($body_from_result->{out}, qr/PAUSE original receipt events: 3/,
    'all three receipts survive embedded non-envelope From line');
unlike($body_from_result->{out} . $body_from_result->{err},
    qr/quoted\@example\.invalid|not-a-time/,
    'private-style quoted From line is never echoed to diagnostics');

# Conversely, a malformed first line must not be promoted to a real
# mbox envelope or used to manufacture an apparently valid archive.
my $malformed_first_envelope = $mbox_text;
is(($malformed_first_envelope =~
    s/\AFrom [^\n]+/From synthetic\@example.invalid Tue Oct 28 bad-clock 2025/),
    1, 'synthetic malformed first envelope prepared');
my $invalid_envelope_result = run_tool($archive, $meta, undef,
    saved($malformed_first_envelope), 3);
ok($invalid_envelope_result->{exit} != 0,
    'malformed first envelope fails closed');
like($invalid_envelope_result->{err}, qr/Invalid mbox envelope separator/,
    'invalid first envelope yields a source-safe diagnostic');

# Conventional mbox separators may use a leading zero for day 1..9.
# Preserve both one-digit and space-padded variants without accepting 00.
my $original_mbox_envelope =
    "From synthetic\@example.invalid Tue Oct 28 00:00:00 2025\n";
for my $example (
    ['Wed', '01'],
    ['Wed', '08'],
    ['Thu', '09'],
    ['Wed', '8'],
    ['Wed', ' 8'],
) {
    my ($weekday, $day) = @$example;
    my $variant = $mbox_text;
    my $new_envelope =
        "From synthetic\@example.invalid $weekday Oct $day 00:00:00 2025\n";
    is(($variant =~ s/\A\Q$original_mbox_envelope\E/$new_envelope/),
        1, 'synthetic mbox envelope day form prepared');
    my $result = run_tool($archive, $meta, undef, saved($variant), 3);
    is($result->{exit}, 0,
        'valid single-digit, zero-padded or space-padded mbox day accepted');
    like($result->{out}, qr/PAUSE original receipt events: 3/,
        'valid mbox day keeps all three PAUSE receipt events');
}
for my $day ('00', '32') {
    my $variant = $mbox_text;
    my $new_envelope =
        "From synthetic\@example.invalid Wed Oct $day 00:00:00 2025\n";
    is(($variant =~ s/\A\Q$original_mbox_envelope\E/$new_envelope/),
        1, 'synthetic invalid mbox day prepared');
    my $result = run_tool($archive, $meta, undef, saved($variant), 3);
    ok($result->{exit} != 0, 'invalid zero-padded mbox day is rejected');
    like($result->{err}, qr/Invalid mbox envelope separator/,
        'invalid first-envelope date has a source-safe diagnostic');
}

# A complete-looking From line with an impossible Gregorian date is
# ordinary body text, not a trustworthy mbox envelope separator.
# Place it before a required PAUSE field so accidental splitting fails.
for my $fake_date ('Feb 31', 'Feb 29', 'Apr 31') {
    my $body_with_fake = $mbox_text;
    my $fake_line =
        "From quoted\@example.invalid Tue $fake_date 00:00:00 2025\n";
    is(($body_with_fake =~
        s/(Request completed: Sat, 29 Mar 2025 03:37:10 GMT\n)/
            $fake_line . $1/e), 1,
        'synthetic impossible-date From line inserted in receipt body');
    my $result = run_tool($archive, $meta, undef,
        saved($body_with_fake), 3);
    is($result->{exit}, 0,
        'impossible-date From body line does not split target receipt');
    like($result->{out}, qr/PAUSE original receipt events: 3/,
        'all PAUSE events survive the impossible-date From body line');
    unlike($result->{out} . $result->{err},
        qr/quoted\@example\.invalid/,
        'synthetic private-style From sender not logged');
}
my $invalid_calendar_envelope = $mbox_text;
my $invalid_calendar_line =
    "From synthetic\@example.invalid Tue Feb 31 00:00:00 2025";
is(($invalid_calendar_envelope =~
    s/\AFrom [^\n]+/$invalid_calendar_line/), 1,
    'synthetic invalid first envelope date prepared');
my $bad_calendar_result = run_tool($archive, $meta, undef,
    saved($invalid_calendar_envelope), 3);
ok($bad_calendar_result->{exit} != 0,
    'invalid Gregorian date in first envelope fails closed');
like($bad_calendar_result->{err}, qr/Invalid mbox envelope separator/,
    'invalid first envelope calendar gets source-safe diagnostic');

my $valid_leap_envelope = $mbox_text;
my $valid_leap_line =
    "From synthetic\@example.invalid Thu Feb 29 00:00:00 2024";
is(($valid_leap_envelope =~
    s/\AFrom [^\n]+/$valid_leap_line/), 1,
    'synthetic leap-year envelope prepared');
my $valid_leap_result = run_tool($archive, $meta, undef,
    saved($valid_leap_envelope), 3);
is($valid_leap_result->{exit}, 0,
    'real February 29 mbox envelope remains supported');
like($valid_leap_result->{out}, qr/PAUSE original receipt events: 3/,
    'valid leap-day envelope preserves receipt event count');

# Even a real Gregorian date should not split a receipt when the
# envelope's weekday disagrees with its written local calendar date.
# Optional timezones affect the instant, not that local weekday.
for my $bad_envelope (
    "From quoted\@example.invalid Mon Oct 28 00:00:00 2025\n",
    "From quoted\@example.invalid Sun Oct 08 00:00:00 +0900 2025\n",
) {
    my $variant = $mbox_text;
    is(($variant =~
        s/(Request completed: Sat, 29 Mar 2025 03:37:10 GMT\n)/
            $bad_envelope . $1/e), 1,
        'synthetic wrong-weekday From line inserted into receipt body');
    my $result = run_tool($archive, $meta, undef, saved($variant), 3);
    is($result->{exit}, 0,
        'mismatched-weekday From body text does not split receipt');
    like($result->{out}, qr/PAUSE original receipt events: 3/,
        'all PAUSE receipts survive incorrect-weekday body text');
    unlike($result->{out} . $result->{err},
        qr/quoted\@example\.invalid/,
        'synthetic private-style sender is absent from audit diagnostics');
}
my $wrong_first_weekday = $mbox_text;
my $wrong_first_line =
    "From synthetic\@example.invalid Mon Oct 28 00:00:00 2025";
is(($wrong_first_weekday =~
    s/\AFrom [^\n]+/$wrong_first_line/), 1,
    'synthetic wrong-weekday first envelope prepared');
my $wrong_first_result = run_tool($archive, $meta, undef,
    saved($wrong_first_weekday), 3);
ok($wrong_first_result->{exit} != 0,
    'first mbox envelope with mismatched weekday fails closed');
like($wrong_first_result->{err}, qr/Invalid mbox envelope separator/,
    'wrong-weekday first envelope has a path-free diagnostic');

my $zoned_weekday = $mbox_text;
my $zoned_line =
    "From synthetic\@example.invalid Wed Oct 08 12:34:56 +0900 2025";
is(($zoned_weekday =~ s/\AFrom [^\n]+/$zoned_line/), 1,
    'synthetic matching-weekday zoned envelope prepared');
my $zoned_result = run_tool($archive, $meta, undef,
    saved($zoned_weekday), 3);
is($zoned_result->{exit}, 0,
    'matching local weekday with numeric zone remains accepted');
like($zoned_result->{out}, qr/PAUSE original receipt events: 3/,
    'matching zoned envelope preserves original receipt count');

# Numerically malformed zone offsets are not credible mbox separators.
# When quoted within a receipt, these complete-looking From lines must
# remain body text rather than discarding its following PAUSE evidence.
for my $bad_zone ('+2400', '+2360', '-0060', '-2500') {
    my $variant = $mbox_text;
    my $quoted_zone =
        "From quoted\@example.invalid Tue Oct 28 00:00:00 $bad_zone 2025\n";
    is(($variant =~
        s/(Request completed: Sat, 29 Mar 2025 03:37:10 GMT\n)/
            $quoted_zone . $1/e), 1,
        'synthetic impossible-zone From body line prepared');
    my $result = run_tool($archive, $meta, undef, saved($variant), 3);
    is($result->{exit}, 0,
        'impossible numeric zone in body does not split original receipt');
    like($result->{out}, qr/PAUSE original receipt events: 3/,
        'all PAUSE receipts survive impossible-zone From body text');
    unlike($result->{out} . $result->{err},
        qr/quoted\@example\.invalid/,
        'private-style quoted sender is not printed in diagnostics');
}
my $invalid_zone_first = $mbox_text;
my $invalid_zone_line =
    "From synthetic\@example.invalid Tue Oct 28 00:00:00 +2400 2025";
is(($invalid_zone_first =~
    s/\AFrom [^\n]+/$invalid_zone_line/), 1,
    'synthetic invalid first-envelope timezone prepared');
my $invalid_zone_result = run_tool($archive, $meta, undef,
    saved($invalid_zone_first), 3);
ok($invalid_zone_result->{exit} != 0,
    'first envelope with impossible timezone fails closed');
like($invalid_zone_result->{err}, qr/Invalid mbox envelope separator/,
    'impossible envelope timezone has a source-safe diagnostic');

for my $good_zone ('+1400', '-0530', 'GMT') {
    my $variant = $mbox_text;
    my $valid_zone_line =
        "From synthetic\@example.invalid Tue Oct 28 00:00:00 $good_zone 2025";
    is(($variant =~ s/\AFrom [^\n]+/$valid_zone_line/), 1,
        'synthetic valid numeric or named envelope zone prepared');
    my $result = run_tool($archive, $meta, undef, saved($variant), 3);
    is($result->{exit}, 0,
        'valid numeric or named mbox envelope timezone remains supported');
    like($result->{out}, qr/PAUSE original receipt events: 3/,
        'valid timezone keeps all three PAUSE receipts');
}

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

# Strict transfer decoding: Perl's MIME decoders otherwise accept malformed
# source material, allowing a receipt with trailing corrupt bytes to pass.
my $bad_base64_padding = run_tool($archive, $meta, undef,
    saved($encoded . "=ZGVm\n"), 3);
ok($bad_base64_padding->{exit} != 0,
    'base64 receipt with trailing invalid padding is rejected');
like($bad_base64_padding->{err}, qr/Malformed PAUSE base64 transfer encoding/,
    'invalid base64 transfer content is diagnosed without logging mail');

my $qp_soft = $qprint;
$qp_soft =~ s/The=20uploaded file/The=20uploaded=\n file/g;
is(run_tool($archive, $meta, undef, saved($qp_soft), 3)->{exit}, 0,
    'valid quoted-printable soft line breaks remain supported');

# RFC 2045 permits spaces/tabs as transport padding after a soft break.
# Both formats must decode to the same receipt while invalid escapes fail.
for my $padding (' ', "\t", " \t") {
    my $padded = $qp_soft;
    $padded =~ s/The=20uploaded=\n file/"The=20uploaded=" . $padding . "\n file"/e;
    is(run_tool($archive, $meta, undef, saved($padded), 3)->{exit}, 0,
        'quoted-printable soft break accepts RFC 2045 transport padding');
}
my $bad_soft_break = $qp_soft;
$bad_soft_break =~ s/The=20uploaded=\n file/The=20uploaded= X\n file/;
my $bad_soft_result = run_tool($archive, $meta, undef,
    saved($bad_soft_break), 3);
ok($bad_soft_result->{exit} != 0,
    'quoted-printable equals followed by padding and non-newline remains invalid');
like($bad_soft_result->{err},
    qr/Malformed PAUSE quoted-printable transfer encoding/,
    'malformed padded soft-break is diagnosed without private data');


my $bad_quoted_printable = run_tool($archive, $meta, undef,
    saved($qprint . "=GG\n"), 3);
ok($bad_quoted_printable->{exit} != 0,
    'invalid quoted-printable escape is rejected');
like($bad_quoted_printable->{err},
    qr/Malformed PAUSE quoted-printable transfer encoding/,
    'invalid quoted-printable transfer content is diagnosed without logging mail');

my $unsupported = $mbox_text;
$unsupported =~ s/Content-Type: text\/plain; charset=UTF-8/Content-Type: multipart\/mixed; boundary="unsafe"/;
my $bad_mime = run_tool($archive, $meta, undef, saved($unsupported));
ok($bad_mime->{exit} != 0, 'unparsed multipart target mail is not silently omitted');
like($bad_mime->{err}, qr/Unsupported non-plain-text PAUSE receipt MIME/,
    'unsupported MIME format fails closed without outputting mail data');

# The PAUSE producer supplies a weekday as well as a GMT calendar date.
# A valid-looking numeric date with a contradictory weekday is not
# trustworthy original chronology evidence.
my $wrong_completed_weekday = $mbox_text;
is(($wrong_completed_weekday =~
    s/Request completed: Sat, 29 Mar 2025/Request completed: Sun, 29 Mar 2025/),
    1, 'synthetic completed-weekday corruption applied once');
my $wrong_completed = run_tool($archive, $meta, undef,
    saved($wrong_completed_weekday), 3);
ok($wrong_completed->{exit} != 0,
    'valid numeric completion date with wrong weekday is rejected');
like($wrong_completed->{err}, qr/Invalid PAUSE UTC weekday\/date mismatch/,
    'completion weekday mismatch gets a source-safe diagnostic');

my $wrong_entered_weekday = $mbox_text;
is(($wrong_entered_weekday =~
    s/Request entered on: Sat, 29 Mar 2025/Request entered on: Sun, 29 Mar 2025/),
    1, 'synthetic entered-weekday corruption applied once');
my $wrong_entered = run_tool($archive, $meta, undef,
    saved($wrong_entered_weekday), 3);
ok($wrong_entered->{exit} != 0,
    'valid numeric request-entry date with wrong weekday is rejected');
like($wrong_entered->{err}, qr/Invalid PAUSE UTC weekday\/date mismatch/,
    'entry weekday mismatch gets a source-safe diagnostic');

my $bad_body = $mbox_text;
$bad_body =~ s/Request completed on:/Request completed on:/;
$bad_body =~ s/Request completed: Sat, 29 Mar 2025 03:37:10 GMT/Request completed: invalid date/;
ok(run_tool($archive, $meta, undef, saved($bad_body))->{exit} != 0,
    'malformed original completion timestamp rejected');

# A JQ-Lite upload notice from another PAUSE author is not unrelated
# mailbox traffic. Do not silently omit that independent evidence even
# if all expected SHINGO receipt events were otherwise present.
my $foreign_header = $raw[0];
is(($foreign_header =~
    s{^Subject: CPAN Upload: S/SH/SHINGO/JQ-Lite-0\.05}{Subject: CPAN Upload: O/OT/OTHER/JQ-Lite-0.05}m),
    1, 'synthetic other-author JQ-Lite notice prepared');
my $foreign_mail = $foreign_header . "\n" . $raw[1];
for my $foreign_case (
    $foreign_mail . $mbox_text,
    $mbox_text . $foreign_mail,
) {
    my $result = run_tool($archive, $meta, undef,
        saved($foreign_case), 3);
    ok($result->{exit} != 0,
        'other-author JQ-Lite notice fails closed before or after originals');
    like($result->{err}, qr/Non-SHINGO JQ-Lite PAUSE receipt/,
        'other-author upload has an explicit source-safe audit diagnostic');
    unlike($result->{out} . $result->{err},
        qr/O\/OT\/OTHER|OTHER\@example\.invalid/,
        'alternative PAUSE author metadata is not printed');
}
my $encoded_foreign_header = $foreign_header;
is(($encoded_foreign_header =~
    s/^Subject: CPAN Upload: /Subject: =?UTF-8?Q?CPAN_Upload:?= /m),
    1, 'synthetic encoded other-author subject prepared');
my $encoded_foreign = run_tool($archive, $meta, undef,
    saved($mbox_text . $encoded_foreign_header . "\n" . $raw[1]), 3);
ok($encoded_foreign->{exit} != 0,
    'encoded other-author JQ-Lite notice cannot evade the audit');
like($encoded_foreign->{err}, qr/Non-SHINGO JQ-Lite PAUSE receipt/,
    'encoded alternative-author notice is explicitly diagnosed');

# An altered JQ-Lite CPAN Upload subject is still possible original
# evidence, even if it cannot be parsed as the known PAUSE tar.gz form.
# Reject without printing subject text or alternative-author details.
for my $altered_path (
    'S/SH/SHINGO/JQ-Lite-0.05.zip',
    'S/SH/SHINGO/JQ-Lite-0.05.tar.gz EXTRA_PRIVATE_TOKEN',
    'S/SH/SHINGO/JQ-Lite-3.00_03-extra.tar.gz',
    'O/OT/OTHER/JQ-Lite-0.05.tar.bz2',
) {
    my $altered_header = $raw[0];
    is(($altered_header =~
        s/^Subject: CPAN Upload: [^\n]+/Subject: CPAN Upload: $altered_path/m),
        1, 'synthetic malformed JQ-Lite upload notice prepared');
    my $result = run_tool($archive, $meta, undef,
        saved($mbox_text . $altered_header . "\n" . $raw[1]), 3);
    ok($result->{exit} != 0,
        'malformed JQ-Lite upload notice blocks apparent complete history');
    like($result->{err}, qr/Malformed JQ-Lite PAUSE upload subject/,
        'altered JQ-Lite notification is diagnosed without subject details');
    unlike($result->{out} . $result->{err},
        qr/EXTRA_PRIVATE_TOKEN|O\/OT\/OTHER/,
        'subject-specific private metadata is absent from diagnostics');
}

my $encoded_altered_header = $raw[0];
my $encoded_altered_subject =
    'Subject: =?UTF-8?Q?CPAN_Upload:?= S/SH/SHINGO/JQ-Lite-0.05.zip';
is(($encoded_altered_header =~
    s/^Subject: CPAN Upload: [^\n]+/$encoded_altered_subject/m),
    1, 'synthetic MIME-encoded malformed upload notice prepared');
my $encoded_altered_result = run_tool($archive, $meta, undef,
    saved($mbox_text . $encoded_altered_header . "\n" . $raw[1]), 3);
ok($encoded_altered_result->{exit} != 0,
    'encoded malformed JQ-Lite subject cannot evade strict classification');
like($encoded_altered_result->{err},
    qr/Malformed JQ-Lite PAUSE upload subject/,
    'encoded malformed notification gets the same source-safe diagnostic');

# A discussion reply containing the exact upload title is not itself
# a PAUSE CPAN Upload producer notification.
my $reply_header = $raw[0];
is(($reply_header =~ s/^Subject: CPAN Upload:/Subject: Re: CPAN Upload:/m),
    1, 'synthetic unrelated reply subject prepared');
my $reply_result = run_tool($archive, $meta, undef,
    saved($reply_header . "\n" . $raw[1] . $mbox_text), 3);
is($reply_result->{exit}, 0,
    'unrelated reply about a JQ-Lite upload is still ignored');

# Other distributions should still be ignored; an unrelated CPAN
# upload notification does not constitute JQ-Lite original evidence.
my $unrelated_upload_header = $foreign_header;
is(($unrelated_upload_header =~ s/JQ-Lite-0\.05/Another-Dist-0.05/),
    1, 'synthetic unrelated distribution notice prepared');
my $unrelated_upload = run_tool($archive, $meta, undef,
    saved($unrelated_upload_header . "\n" . $raw[1] . $mbox_text), 3);
is($unrelated_upload->{exit}, 0,
    'unrelated distribution upload notices remain safely ignored');

my $private_unrelated =
    "From private\@example.invalid Tue Oct 28 00:00:00 2025\n"
    . "Subject: Private unrelated mail\n\n"
    . "SECRETS_DO_NOT_LOG\n";
my $unrelated = run_tool($archive, $meta, undef,
    saved($private_unrelated . $mbox_text));
is($unrelated->{exit}, 0, 'unrelated local mbox messages are skipped');
unlike($unrelated->{out} . $unrelated->{err}, qr/SECRETS_DO_NOT_LOG|example\.invalid/,
    'tool stdout/stderr never display unrelated private mail fields');

# A large private Takeout can include unrelated mail with duplicate MIME
# headers. These are not PAUSE receipts and must not block an otherwise
# valid offline comparison or expose private body/header contents.
my $unrelated_duplicates =
    "From private\@example.invalid Tue Oct 28 00:00:00 2025\n"
    . "Subject: Unrelated message A\n"
    . "Subject: Unrelated message B\n"
    . "Content-Type: text/plain\n"
    . "Content-Type: multipart/mixed\n"
    . "Content-Transfer-Encoding: 7bit\n"
    . "Content-Transfer-Encoding: base64\n\n"
    . "UNRELATED_PRIVATE_BODY_DO_NOT_LOG\n";
my $with_unrelated_duplicates = run_tool($archive, $meta, undef,
    saved($unrelated_duplicates . $mbox_text), 3);
is($with_unrelated_duplicates->{exit}, 0,
    'duplicate classification headers in unrelated Takeout mail are ignored');
unlike($with_unrelated_duplicates->{out} . $with_unrelated_duplicates->{err},
    qr/UNRELATED_PRIVATE_BODY_DO_NOT_LOG|example\.invalid/,
    'unrelated duplicated MIME data never appears in stdout or stderr');

# A duplicate Subject containing one PAUSE target and one unrelated
# value must still fail closed; otherwise an injected first Subject
# could hide a valid upload or internal developer artifact.
my $mixed_subject = $mbox_text;
$mixed_subject =~ s{^(Subject: CPAN Upload: S/SH/SHINGO/JQ-Lite-0\.05\.tar\.gz\n)}{
    "Subject: Unrelated message\n" . $1
}em;
my $mixed_subject_result = run_tool($archive, $meta, undef,
    saved($mixed_subject), 3);
ok($mixed_subject_result->{exit} != 0,
    'mixed unrelated/PAUSE duplicate Subject cannot hide target evidence');
like($mixed_subject_result->{err},
    qr/Duplicate MIME classification header/,
    'matching PAUSE receipt still rejects contradictory Subject headers');

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


for my $header (qw(Subject Content-Type Content-Transfer-Encoding)) {
    my $two_header = $mbox_text;
    if ($header eq 'Subject') {
        $two_header =~ s{^(Subject: [^\n]+\n)}{
            $1 . "Subject: CPAN Upload: S/SH/SHINGO/JQ-Lite-3.00_03.tar.gz\n"}em;
    } elsif ($header eq 'Content-Type') {
        $two_header =~ s{^(Content-Type: [^\n]+\n)}{
            $1 . "Content-Type: multipart/mixed\n"}em;
    } else {
        $two_header =~ s{^(Content-Type: [^\n]+\n)}{
            $1 . "Content-Transfer-Encoding: 8bit\n"
               . "Content-Transfer-Encoding: base64\n"}em;
    }
    my $duplicate = run_tool($archive, $meta, undef,
        saved($two_header), 3);
    ok($duplicate->{exit} != 0,
        "duplicate $header cannot conceal contradictory private MIME evidence");
    like($duplicate->{err}, qr/Duplicate MIME classification header/,
        "duplicate $header refusal never logs private message contents");
}


# Mailbox classifier must not silently drop public developer archive
# receipts with a v-prefix, nor incomplete subject-only target messages.
my $prefixed_dev_mail = $dev_h . "\n" . $dev_b;
$prefixed_dev_mail =~ s/JQ-Lite-3\.00_03/JQ-Lite-v3.00_03/g;
my $prefixed_dev_result = run_tool($archive, $meta, undef,
    saved($mbox_text . $prefixed_dev_mail), 3);
ok($prefixed_dev_result->{exit} != 0,
    'v-prefixed developer PAUSE subject is explicitly rejected');
like($prefixed_dev_result->{err},
    qr/Internal\/developer PAUSE receipt/,
    'v-prefixed developer archive is not silently skipped');

my $truncated_target = $mbox_text
    . "From synthetic\@example.invalid Tue Oct 28 00:00:00 2025\n"
    . "Subject: CPAN Upload: S/SH/SHINGO/JQ-Lite-3.00_03.tar.gz\n";
my $truncated_result = run_tool($archive, $meta, undef,
    saved($truncated_target), 3);
ok($truncated_result->{exit} != 0,
    'incomplete developer receipt header cannot pass event-count gate');
like($truncated_result->{err},
    qr/Truncated PAUSE target receipt/,
    'truncated target is rejected before it can be skipped');

done_testing;
