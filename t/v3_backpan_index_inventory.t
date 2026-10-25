use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;
use File::Temp qw(tempfile);
use IO::Compress::Gzip qw(gzip $GzipError);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my $tool = File::Spec->catfile($FindBin::Bin, '..', 'ci',
    'inventory-backpan-jq-lite-index.pl');
ok(-f $tool, 'pure-core BackPAN source-index extractor is shipped');

sub fixture {
    my ($text, $compressed) = @_;
    my ($fh, $path) = tempfile(UNLINK => 1);
    binmode $fh;
    if ($compressed) {
        my $blob;
        gzip(\$text => \$blob) or die "Cannot gzip fixture: $GzipError";
        print {$fh} $blob or die "Cannot write gzip fixture: $!";
    } else {
        print {$fh} $text or die "Cannot write plain fixture: $!";
    }
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
my $sample = "#FORMAT 1\n" .
    "Z/ZZ/ZED/Unrelated-9.00.tar.gz 1760100000 900\n" .
    "S/SH/SHINGO/JQ-Lite-0.100.tar.gz 1760327400 57000\n" .
    "S/SH/SHINGO/JQ-Lite-0.99.tar.gz 1760318760 56000\n" .
    "S/SH/SHINGO/JQ-Lite-2.59.tar.gz 1789901940 132000\n";
my $plain = fixture($sample, 0);
my $gz = fixture($sample, 1);
my $a = invoke('--input', $plain);
my $b = invoke('--input', $gz);
is($a->{rc}, 0, 'plain #FORMAT 1 input accepted');
is($b->{rc}, 0, 'gzip #FORMAT 1 input accepted');
is($b->{stdout}, $a->{stdout}, 'gzip and plain inventories are identical');
like($a->{stdout}, qr/\Apath\tepoch\tsize\n/, 'exact TSV schema emitted');
like($a->{stdout}, qr/JQ-Lite-0\.99.*\n.*JQ-Lite-0\.100/s,
    'records sorted by observed epoch not by Perl numeric order');
unlike($a->{stdout}, qr/Unrelated/, 'unrelated archives ignored');
is(scalar(() = $a->{stdout} =~ /JQ-Lite-/g), 3, 'three JQ-Lite archive observations');
like($a->{stdout}, qr/1789901940\t132000/, 'original epochs and byte sizes preserved');

my $full = fixture("#FORMAT 1\n" .
    "authors/id/S/SH/SHINGO/JQ-Lite-2.59.tar.gz 1789901940 132000\n", 1);
my $norm = invoke('--input', $full);
is($norm->{rc}, 0, 'full-index authors/id/ prefix accepted');
like($norm->{stdout}, qr/\nS\/SH\/SHINGO\/JQ-Lite-2\.59/, 'full path normalized to releases-only form');

my $crlf = fixture("#FORMAT 1\r\nS/SH/SHINGO/JQ-Lite-2.59.tar.gz\t1789901940\t132000\r\n", 0);
is(invoke('--input', $crlf)->{rc}, 0, 'CRLF and whitespace delimiters handled');
my $internal = fixture("#FORMAT 1\nS/SH/SHINGO/JQ-Lite-v3.00_03.tar.gz 1792900000 10000\n", 1);
my $dev = invoke('--input', $internal);
ok($dev->{rc} != 0, 'v-prefixed 3.00_0x archive fails closed');
like($dev->{stderr}, qr/INTERNAL-DEVELOPER-ARTIFACT-ALERT/,
    'internal candidate generates explicit alert');
my $nonprefixed = fixture("#FORMAT 1\nS/SH/SHINGO/JQ-Lite-3.00_01.tar.gz 1792900000 10000\n", 0);
ok(invoke('--input', $nonprefixed)->{rc} != 0, 'nonprefixed developer archive also fails closed');

my $dupe = fixture("#FORMAT 1\n" .
    "S/SH/SHINGO/JQ-Lite-2.59.tar.gz 1789901940 132000\n" .
    "S/SH/SHINGO/JQ-Lite-2.59.tar.gz 1789901940 132000\n", 0);
ok(invoke('--input', $dupe)->{rc} != 0, 'duplicate path rejected');
my $dupe_ver = fixture("#FORMAT 1\n" .
    "S/SH/SHINGO/JQ-Lite-2.59.tar.gz 1789901940 132000\n" .
    "A/AB/OTHER/JQ-Lite-2.59.tar.gz 1789901940 132000\n", 0);
ok(invoke('--input', $dupe_ver)->{rc} != 0,
    'multiple author paths for the same version rejected');
my $bad_format = fixture("#FORMAT 2\nS/SH/SHINGO/JQ-Lite-2.59.tar.gz 1789901940 132000\n", 0);
ok(invoke('--input', $bad_format)->{rc} != 0, 'unsupported index format rejected');
my $bad_epoch = fixture("#FORMAT 1\nS/SH/SHINGO/JQ-Lite-2.59.tar.gz yesterday 132000\n", 0);
ok(invoke('--input', $bad_epoch)->{rc} != 0, 'invalid timestamp rejected');
my $zero_size = fixture("#FORMAT 1\nS/SH/SHINGO/JQ-Lite-2.59.tar.gz 1789901940 0\n", 0);
ok(invoke('--input', $zero_size)->{rc} != 0, 'zero-size archive rejected');
my $bad_name = fixture("#FORMAT 1\nS/SH/SHINGO/JQ-Lite-2.59.zip 1789901940 132000\n", 0);
ok(invoke('--input', $bad_name)->{rc} != 0,
    'unexpected JQ-Lite archive extension cannot be silently omitted');
my $bad_path = fixture("#FORMAT 1\nJQ-Lite-2.59.tar.gz 1789901940 132000\n", 0);
ok(invoke('--input', $bad_path)->{rc} != 0, 'missing author provenance rejected');
my $empty = fixture("#FORMAT 1\n", 0);
ok(invoke('--input', $empty)->{rc} != 0, 'empty observation set rejected');
my $zero = fixture("", 0);
ok(invoke('--input', $zero)->{rc} != 0, 'empty input rejected');
my $not_gzip = fixture("\x1f\x8bnot-really-gzip", 0);
ok(invoke('--input', $not_gzip)->{rc} != 0, 'corrupt gzip cannot be accepted');
# Regression: a valid first record must not conceal a truncated gzip tail.
my $gzip_bytes = '';
gzip(\$sample => \$gzip_bytes) or die "Cannot gzip integrity fixture: $GzipError";
my $cut_gzip = fixture(substr($gzip_bytes, 0, length($gzip_bytes) - 7), 0);
my $cut = invoke('--input', $cut_gzip);
ok($cut->{rc} != 0, 'truncated gzip with valid leading archives is rejected');
is($cut->{stdout}, '', 'truncated gzip produces no misleading partial TSV');
like($cut->{stderr}, qr/Corrupt or incomplete BackPAN gzip index/,
    'gzip trailer failure is reported');

my $bad_crc = $gzip_bytes;
substr($bad_crc, -8, 1, chr(ord(substr($bad_crc, -8, 1)) ^ 1));
my $crc = invoke('--input', fixture($bad_crc, 0));
ok($crc->{rc} != 0, 'corrupt CRC32 is rejected in strict mode');
is($crc->{stdout}, '', 'corrupt checksum produces no TSV');

my ($first_gzip, $second_gzip) = ('', '');
my $first = "#FORMAT 1\nS/SH/SHINGO/JQ-Lite-2.59.tar.gz 1789901940 132000\n";
my $second = "S/SH/SHINGO/JQ-Lite-3.00_01.tar.gz 1792900000 10000\n";
gzip(\$first => \$first_gzip) or die "Cannot gzip first fixture: $GzipError";
gzip(\$second => \$second_gzip) or die "Cannot gzip second fixture: $GzipError";
my $joined = invoke('--input', fixture($first_gzip . $second_gzip, 0));
ok($joined->{rc} != 0, 'concatenated member with internal artifact cannot be ignored');
like($joined->{stderr}, qr/INTERNAL-DEVELOPER-ARTIFACT-ALERT/,
    'second gzip member developer archive is detected');

my $missing = invoke('--input', 'no-such-backpan-index.txt.gz');
ok($missing->{rc} != 0, 'missing input rejected');
ok(invoke()->{rc} != 0, 'input argument required');
my $help = invoke('--help');
is($help->{rc}, 0, 'help succeeds');
like($help->{stdout}, qr/NOT a chronological --published-file ledger/,
    'help distinguishes source inventory from public-history attestation');
done_testing;
