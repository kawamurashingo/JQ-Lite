use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;
use File::Temp qw(tempfile);
use JSON::PP ();
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my $tool = File::Spec->catfile($FindBin::Bin, '..', 'ci',
    'inventory-cpantesters-jq-lite-uploads.pl');
ok(-f $tool, 'offline CPAN Testers upload extractor is shipped');

sub saved {
    my ($blob) = @_;
    my ($fh, $path) = tempfile(UNLINK => 1);
    binmode $fh;
    print {$fh} $blob or die "write: $!";
    close $fh or die "close: $!";
    return $path;
}
sub invoke {
    my ($path) = @_;
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $^X, $tool, '--input', $path);
    close $in;
    my $stdout = do { local $/; <$out> } || '';
    my $stderr = do { local $/; <$err> } || '';
    close $out; close $err; waitpid($pid, 0);
    return { rc => $? >> 8, stdout => $stdout, stderr => $stderr };
}
sub row {
    my ($v, $date) = @_;
    return { dist => 'JQ-Lite', version => $v, author => 'SHINGO',
        filename => "JQ-Lite-$v.tar.gz", released => $date };
}
sub file {
    return saved(JSON::PP->new->canonical->encode(shift));
}
my $normal = [
    row('2.59', '2026-09-20T10:59:07Z'),
    row('0.100', '2025-10-13T03:50:00Z'),
    row('0.99', '2025-10-13T01:26:00Z'),
];
my $good = invoke(file($normal));
is($good->{rc}, 0, 'valid full array is accepted');
like($good->{stdout}, qr/\Areleased_observed\tversion\tauthor\tfilename\ttype\tclassification\n/,
    'TSV header includes observation timestamp and classification');
like($good->{stdout}, qr/0\.99.*\n.*0\.100.*\n.*2\.59/s,
    'release dates determine observation order');
like($good->{stdout}, qr/\tunreported\tobserved-upload\n/,
    'missing optional upload type stays explicitly unreported');
unlike($good->{stdout}, qr/ATTESTED|APPROVED/, 'no fabricated release approval');

my $types = [row('0.05','2025-03-29T03:37:09Z')];
$types->[0]{type} = 'backpan';
is(invoke(file($types))->{rc}, 0, 'known backpan type retained');

my $dup = [row('1.31','2025-10-26T09:05:26Z'),
           row('1.31','2025-10-26T09:06:26Z')];
my $dupr = invoke(file($dup));
is($dupr->{rc}, 2, 'multiple uploads are data anomalies, not parser errors');
is(scalar(() = $dupr->{stdout} =~ /JQ-Lite-1\.31\.tar\.gz/g),
    2, 'duplicate original observations are both preserved');
like($dupr->{stdout}, qr/DUPLICATE-VERSION-REVIEW/, 'duplicate marked');

my $incomplete = [row('0.81','1970-01-01T00:00:00Z')];
$incomplete->[0]{author} = '';
$incomplete->[0]{filename} = '';
my $bad_record = invoke(file($incomplete));
is($bad_record->{rc}, 2, 'historic missing metadata and epoch sentinel block audit');
like($bad_record->{stdout}, qr/\t0\.81\t\t\tunreported\t/,
    'unknown uploader and filename not invented');
like($bad_record->{stdout}, qr/MISSING-FILENAME-REVIEW,MISSING-AUTHOR-REVIEW,EPOCH-SENTINEL-REVIEW/,
    'all historical irregularities explicitly retained');
like($bad_record->{stderr}, qr/REVIEW_ONLY_UPLOAD_RECORD_ANOMALIES/,
    'audit anomaly classified separately from malformed JSON');

my $internal = invoke(file([row('3.00_03','2026-10-25T01:00:00Z')]));
ok($internal->{rc} != 0, 'internal developer archive never accepted silently');
like($internal->{stdout}, qr/INTERNAL-DEVELOPER-ARTIFACT-ALERT/,
    'developer archive retained in review TSV');
my $vdev = invoke(file([row('v3.00_02','2026-10-25T01:00:00Z')]));
ok($vdev->{rc} != 0, 'v-prefixed internal developer archive also blocked');
my $other = [row('1.31','2025-10-26T09:05:26Z')];
$other->[0]{author} = 'OTHER';
my $o = invoke(file($other));
ok($o->{rc} != 0, 'other upload author triggers investigation');
like($o->{stdout}, qr/NON-SHINGO-UPLOADER-REVIEW/, 'other author visible');

my $foreign = [row('2.59','2026-09-20T10:59:07Z')];
$foreign->[0]{dist} = 'Other';
ok(invoke(file($foreign))->{rc} != 0, 'foreign distribution rejected');
my $mismatch = [row('2.59','2026-09-20T10:59:07Z')];
$mismatch->[0]{version} = '2.58';
ok(invoke(file($mismatch))->{rc} != 0, 'version/filename mismatch rejected');
my $bad_type = [row('2.59','2026-09-20T10:59:07Z')];
$bad_type->[0]{type} = 'approved';
ok(invoke(file($bad_type))->{rc} != 0, 'untrusted status cannot masquerade as approval');
ok(invoke(file([row('2.59','not-a-date')]))->{rc} != 0,
    'invalid release date rejected');
ok(invoke(file([row('2.59','2026-99-99T99:99:99Z')]))->{rc} != 0,
    'impossible clock and calendar values rejected');
ok(invoke(file([row('2.59','2026-02-30T12:00:00Z')]))->{rc} != 0,
    'nonexistent calendar day rejected');
ok(invoke(file([row('2.59','2025-02-29T12:00:00Z')]))->{rc} != 0,
    'non-leap-year February 29 rejected');
is(invoke(file([row('2.59','2024-02-29T12:00:00Z')]))->{rc}, 0,
    'genuine leap day accepted');
ok(invoke(file([row('2.59','2026-01-01T00:30:00+01:00')]))->{rc} != 0,
    'offset date disallowed so lexicographic observation order is safe');
ok(invoke(file([row('2.59','2026-01-01T00:30:00.5Z')]))->{rc} != 0,
    'fractional date disallowed rather than mis-sorted');

ok(invoke(file({error=>'upstream failure'}))->{rc} != 0,
    'API error response rather than a JSON array rejected');
ok(invoke(file([]))->{rc} != 0, 'empty response not a complete history');
ok(invoke(saved('invalid JSON'))->{rc} != 0, 'corrupt JSON rejected');
ok(invoke(saved(''))->{rc} != 0, 'empty response rejected');
ok(invoke('missing-upload-feed.json')->{rc} != 0, 'missing file rejected');
my $help = do {
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $^X, $tool, '--help');
    close $in;
    my $s = do { local $/; <$out> } || '';
    close $out; close $err; waitpid($pid, 0);
    { rc => $? >> 8, stdout => $s };
};
is($help->{rc}, 0, 'help succeeds without network');
like($help->{stdout}, qr/No network access or release approval/,
    'help text never promises release approval');
done_testing;
