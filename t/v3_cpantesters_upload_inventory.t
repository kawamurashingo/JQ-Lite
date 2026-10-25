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
ok($dupr->{rc} != 0, 'multiple uploads of same version require review');
is(scalar(() = $dupr->{stdout} =~ /JQ-Lite-1\.31\.tar\.gz/g),
    2, 'duplicate original observations are both preserved');
like($dupr->{stdout}, qr/DUPLICATE-UPLOAD-NEEDS-REVIEW/, 'duplicate marked');

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
like($help->{stdout}, qr/No network, PAUSE completeness attestation or release/,
    'help text never promises release approval');
done_testing;
