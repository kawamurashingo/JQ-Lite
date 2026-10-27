use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Archive::Tar ();
use IO::Compress::Gzip qw(gzip $GzipError);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);
use Cwd qw(getcwd);

my $installer = File::Spec->rel2abs(
    File::Spec->catfile($FindBin::Bin, '..', 'install.sh'));
ok(-f $installer, 'standalone public install.sh exists');
is(system('bash', '-n', $installer), 0, 'installer has valid Bash syntax');
open my $sf, '<', $installer or die $!;
my $source = do { local $/; <$sf> };
close $sf;
like($source, qr/perl -MArchive::Tar - "\$TARBALL_ABS" "\$DIST_DIR" <<'PERL'/,
    'installer uses core Archive::Tar to validate the target archive');
like($source, qr/IO::Uncompress::Gunzip->new/,
    'gzip checked by core decompressor before archive parsing');
like($source, qr/Strict => 1/, 'gzip CRC and trailer checked');
like($source, qr/\$plain_size > 8_000_000/,
    'decompressed tar stream bounded before Archive::Tar parsing');
like($source, qr/\$entry_count > 2000/,
    'raw header count limited before directory objects are buffered');
like($source, qr/\$size > 4_000_000/, 'raw tar member sizes limited');
like($source, qr/Tar header checksum mismatch/, 'raw tar checksums checked');
like($source, qr/\$tar->extract or die/,
    'validated Archive::Tar extracts safe members');
unlike($source, qr/(?:tar\s+(?:-\S*x\S*|--extract)|tar\s+-xzf)/,
    'installer never re-parses archive using external tar');
like($source, qr/Unsafe link or special member/,
    'links and special archive members are rejected');
like($source, qr/Entry outside distribution root/,
    'foreign root / traversal paths are rejected');

my $root = tempdir(CLEANUP => 1);
my $mock = File::Spec->catdir($root, 'bin');
mkdir $mock or die $!;
my $make = File::Spec->catfile($mock, 'make');
open my $mk, '>', $make or die $!;
print {$mk} <<'MAKE';
#!/bin/sh
printf '%s\n' "$*" >> "$INSTALL_MAKE_CALLS"
exit 0
MAKE
close $mk;
chmod 0755, $make or die $!;
my $calls = File::Spec->catfile($root, 'make.log');
my $case_num = 0;

sub fixture {
    my ($name, @entries) = @_;
    my $directory = File::Spec->catdir($root, 'fixture-' . ++$case_num);
    make_path($directory);
    my $tar = Archive::Tar->new;
    for my $entry (@entries) {
        my ($filename, $payload, $opts) = @$entry;
        if (defined $opts) {
            $tar->add_data($filename, $payload, $opts);
        } else {
            $tar->add_data($filename, $payload);
        }
    }
    my $archive = File::Spec->catfile($directory, $name);
    $tar->write($archive, 1) or die "Cannot write test tarball";
    return $archive;
}
sub ordinary {
    return (
        ['JQ-Lite-2.59/Makefile.PL', "print qq(dummy Makefile.PL\\n); 1;\n"],
        ['JQ-Lite-2.59/lib/JQ/Lite.pm', "1;\n"],
    );
}
sub invoke {
    my ($archive, @extra) = @_;
    unlink $calls if -e $calls;
    local $ENV{PATH} = "$mock:$ENV{PATH}";
    local $ENV{INSTALL_MAKE_CALLS} = $calls;
    my $err = gensym;
    my $prefix = File::Spec->catdir($root, 'install-prefix');
    my $pid = open3(my $in, my $out, $err,
        'bash', $installer, '--skip-tests', '-p', $prefix, @extra, $archive);
    close $in;
    my $stdout = do { local $/; <$out> };
    my $stderr = do { local $/; <$err> };
    close $out; close $err;
    waitpid($pid, 0);
    my $make_calls = '';
    if (-e $calls) {
        open my $cf, '<', $calls or die $!;
        $make_calls = do { local $/; <$cf> };
        close $cf;
    }
    return {
        rc => $? >> 8, stdout => $stdout || '', stderr => $stderr || '',
        make_calls => $make_calls,
    };
}
my $ok_archive = fixture('JQ-Lite-2.59.tar.gz', ordinary());
my $good = invoke($ok_archive);
is($good->{rc}, 0, 'minimal valid stable tarball installs via mocked make');
is($good->{make_calls}, "\ninstall\n",
    'valid archive reaches build and install steps');

my %bad = (
    traversal => ['JQ-Lite-2.59/../outside', 'bad'],
    absolute  => ['/tmp/outside', 'bad'],
    wrongroot => ['Another-Package/Makefile.PL', 'print 1;'],
    symlink   => ['JQ-Lite-2.59/escape', '', {type=>2,linkname=>'../../outside'}],
    hardlink  => ['JQ-Lite-2.59/escape', '', {type=>1,linkname=>'../../outside'}],
    fifo      => ['JQ-Lite-2.59/fifo', '', {type=>6}],
    newline   => ["JQ-Lite-2.59/bad\nname", 'bad'],
);
for my $kind (sort keys %bad) {
    my $archive = fixture('JQ-Lite-2.59.tar.gz', ordinary(), $bad{$kind});
    my $result = invoke($archive);
    ok($result->{rc} != 0, "$kind archive rejected before install");
    is($result->{make_calls}, '', "$kind archive cannot execute build");
}
my $missing = fixture('JQ-Lite-2.59.tar.gz',
    ['JQ-Lite-2.59/lib/JQ/Lite.pm', '1;']);
my $missing_result = invoke($missing);
ok($missing_result->{rc} != 0, 'missing Makefile.PL rejected');
is($missing_result->{make_calls}, '', 'missing Makefile.PL never runs make');

my $internal = fixture('JQ-Lite-3.00_03.tar.gz', ordinary());
my $internal_result = invoke($internal);
ok($internal_result->{rc} != 0, 'explicit internal 3.00_03 tarball rejected');
is($internal_result->{make_calls}, '', 'internal developer archive never runs make');

# Archive::Tar can return a *positive parsed-entry count* and still
# report an error after a later member is truncated. A valid Makefile
# header before the broken member must never reach make/install.
my $raw_tar = File::Spec->catfile($root, 'partial-raw.tar');
my $partial_tar = Archive::Tar->new;
$partial_tar->add_data('JQ-Lite-2.59/Makefile.PL',
    "print qq(dummy Makefile.PL\\n); 1;\n");
$partial_tar->add_data('JQ-Lite-2.59/lib/JQ/Lite.pm', 'x' x 20000);
$partial_tar->write($raw_tar, 0) or die "Cannot generate partial-tar test source";
open my $raw_fh, '<', $raw_tar or die $!;
binmode $raw_fh;
my $raw_data = do { local $/; <$raw_fh> };
close $raw_fh;
my $short_tar = substr($raw_data, 0, 1800);
my $partial_dir = File::Spec->catdir($root, 'partial-member');
make_path($partial_dir);
my $partial_file = File::Spec->catfile($partial_dir, 'JQ-Lite-2.59.tar.gz');
gzip \$short_tar => $partial_file or die "Cannot gzip partial-tar fixture: $GzipError";
my $partial_check = Archive::Tar->new;
my $parsed_count = $partial_check->read($partial_file, 1);
ok($parsed_count > 0, 'fixture yields positive parsed-member count despite later truncation');
ok($partial_check->error, 'fixture also reports a real Archive::Tar read error');
# A tiny gzip can expand to a huge regular member. The iterator's
# filter callback must reject the member from its header BEFORE it
# allocates the decompressed payload; a mere member-count check fails.
my $large_file = fixture('JQ-Lite-2.59.tar.gz', ordinary(),
    ['JQ-Lite-2.59/huge.bin', 'Z' x 17_000_000]);
my $large_result = invoke($large_file);
ok($large_result->{rc} != 0, 'highly compressed oversized member refused');
is($large_result->{make_calls}, '', 'oversized member cannot reach make/install');
like($large_result->{stderr}, qr/Uncompressed source tar exceeds 8 MB size budget/,
    'oversized archive has a bounded-memory diagnostic');

my $partial_result = invoke($partial_file);
ok($partial_result->{rc} != 0, 'partially parsed, corrupted archive rejected');
is($partial_result->{make_calls}, '', 'partially corrupt archive never runs Makefile/make');
like($partial_result->{stderr}, qr/Invalid tar framing or missing end markers/,
    'partial archive failure is explicitly diagnosed');

# Gzip CRC corruption and missing trailers must fail before make.
open my $gzip_fh, '<', $ok_archive or die $!;
binmode $gzip_fh;
my $gz_bytes = do { local $/; <$gzip_fh> };
close $gzip_fh;
sub archive_bytes {
    my ($bytes) = @_;
    my $dir = File::Spec->catdir($root, 'raw-variant-' . ++$case_num);
    make_path($dir);
    my $path = File::Spec->catfile($dir, 'JQ-Lite-2.59.tar.gz');
    open my $fh, '>', $path or die $!;
    binmode $fh;
    print {$fh} $bytes or die $!;
    close $fh;
    return $path;
}
my $bad_crc = $gz_bytes;
substr($bad_crc, -8, 1) = chr(ord(substr($bad_crc, -8, 1)) ^ 1);
for my $case (
    ['bad gzip CRC', archive_bytes($bad_crc)],
    ['missing gzip trailer', archive_bytes(substr($gz_bytes, 0, -8))],
) {
    my ($name, $path) = @$case;
    my $result = invoke($path);
    ok($result->{rc} != 0, "$name rejected");
    is($result->{make_calls}, '', "$name never executes make");
    like($result->{stderr}, qr/(?:Corrupt gzip|Invalid gzip|Gzip trailer validation failed)/,
        "$name reports gzip integrity failure");
}

# Valid gzip containing a partial second header must be refused.
my $short_header = substr($raw_data, 0, 1024 + 100);
my $short_header_dir = File::Spec->catdir($root, 'short-header');
make_path($short_header_dir);
my $short_header_path = File::Spec->catfile($short_header_dir, 'JQ-Lite-2.59.tar.gz');
gzip \$short_header => $short_header_path
    or die "Cannot create short-header fixture: $GzipError";
my $bad_header = invoke($short_header_path);
ok($bad_header->{rc} != 0, 'valid-gzip tar with partial last header rejected');
is($bad_header->{make_calls}, '', 'partial header cannot execute make');
like($bad_header->{stderr}, qr/Invalid tar framing/,
    'incomplete header yields framing diagnostic');

# A fully framed entry followed immediately by EOF is not a valid
# tar archive: the required two zero blocks must be present.
my $no_end = substr($raw_data, 0, -1024);
my $no_end_dir = File::Spec->catdir($root, 'missing-end-markers');
make_path($no_end_dir);
my $no_end_path = File::Spec->catfile($no_end_dir, 'JQ-Lite-2.59.tar.gz');
gzip \$no_end => $no_end_path or die "Cannot create no-end fixture: $GzipError";
my $no_end_result = invoke($no_end_path);
ok($no_end_result->{rc} != 0, 'valid gzip without tar end markers rejected');
is($no_end_result->{make_calls}, '', 'missing tar end marker never reaches make');
like($no_end_result->{stderr}, qr/Missing tar end markers/,
    'missing end-marker diagnostic recorded');

# Valid gzip wrapping corrupt tar header checksum must be refused.
my $corrupt_header = $raw_data;
substr($corrupt_header, 1024, 1) = 'X';
my $checksum_dir = File::Spec->catdir($root, 'bad-tar-checksum');
make_path($checksum_dir);
my $checksum_path = File::Spec->catfile($checksum_dir, 'JQ-Lite-2.59.tar.gz');
gzip \$corrupt_header => $checksum_path
    or die "Cannot create corrupt-header fixture: $GzipError";
my $bad_checksum = invoke($checksum_path);
ok($bad_checksum->{rc} != 0, 'invalid tar header checksum rejected');
is($bad_checksum->{make_calls}, '', 'invalid tar header cannot execute make');
like($bad_checksum->{stderr}, qr/Tar header checksum mismatch/,
    'tar checksum error specifically reported');

# Valid checksum but empty raw member name: Archive::Tar can silently
# stop parsing here without setting an error. Header count must match.
my $empty_name_tar = $raw_data;
my $second_header = substr($empty_name_tar, 1024, 512);
substr($second_header, 0, 100) = "\0" x 100;
substr($second_header, 148, 8) = " " x 8;
my $checksum = unpack("%32C*", $second_header);
substr($second_header, 148, 8) = sprintf("%06o\0 ", $checksum);
substr($empty_name_tar, 1024, 512) = $second_header;
my $empty_name_dir = File::Spec->catdir($root, 'empty-member-name');
make_path($empty_name_dir);
my $empty_name_path = File::Spec->catfile($empty_name_dir, 'JQ-Lite-2.59.tar.gz');
gzip \$empty_name_tar => $empty_name_path or die "Cannot gzip empty-name fixture: $GzipError";
my $empty_name_result = invoke($empty_name_path);
ok($empty_name_result->{rc} != 0, 'valid-checksum empty tar header name rejected');
is($empty_name_result->{make_calls}, '', 'empty-name header never reaches make');
like($empty_name_result->{stderr}, qr/(?:Empty raw tar member name|Tar parser skipped)/,
    'raw name and count reconciliation rejects parser-skipped entries');

# A huge directory train must be rejected before Archive::Tar buffers
# many directory objects. The tar payload itself is small enough.
my $many = Archive::Tar->new;
$many->add_data('JQ-Lite-2.59/Makefile.PL', "print qq(dummy\\n); 1;\n");
for my $i (1 .. 2100) {
    $many->add_data(sprintf('JQ-Lite-2.59/d%05d/', $i), '', {type=>5});
}
my $many_dir = File::Spec->catdir($root, 'many-directories');
make_path($many_dir);
my $many_path = File::Spec->catfile($many_dir, 'JQ-Lite-2.59.tar.gz');
$many->write($many_path, 1) or die "Cannot write directory flood";
my $many_result = invoke($many_path);
ok($many_result->{rc} != 0, 'directory flood refused by raw header count');
is($many_result->{make_calls}, '', 'directory flood cannot reach build');
like($many_result->{stderr}, qr/Too many tar entries/,
    'raw entry count guard diagnosed');

my $corrupt_dir = File::Spec->catdir($root, 'corrupt');
make_path($corrupt_dir);
my $corrupt = File::Spec->catfile($corrupt_dir, 'JQ-Lite-2.59.tar.gz');
open my $bad_fh, '>', $corrupt or die $!;
print {$bad_fh} 'not a gzip archive';
close $bad_fh;
my $invalid_result = invoke($corrupt);
ok($invalid_result->{rc} != 0, 'corrupted archive rejected');
is($invalid_result->{make_calls}, '', 'corrupt archive never reaches build');

my $link_archive = File::Spec->catfile($root, 'JQ-Lite-2.59.tar.gz');
symlink $ok_archive, $link_archive or die "Cannot symlink fixture: $!";
my $linked = invoke($link_archive);
is($linked->{rc}, 0, 'legitimate already-downloaded archive symlink is validated');

done_testing;
