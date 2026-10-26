use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my $script = File::Spec->catfile($FindBin::Bin, '..', 'download.sh');
ok(-f $script, 'public download script exists');
is(system('bash', '-n', $script), 0, 'public download script has valid Bash syntax');
open my $source, '<', $script or die $!;
my $script_text = do { local $/; <$source> };
close $source;
like($script_text, qr/sysopen my \$out, \$dest, O_WRONLY\|O_CREAT\|O_EXCL/, 'all existing output types rejected atomically');
like($script_text, qr/my \@present = lstat \$dest/, 'failed-copy cleanup checks path identity');
unlike($script_text, qr/\b(?:mv|ln) -n -- /, 'no implicit destination-directory behavior');
my $root = tempdir(CLEANUP => 1);
my $mock_dir = File::Spec->catdir($root, 'mock-bin');
mkdir $mock_dir or die $!;
my $curl = File::Spec->catfile($mock_dir, 'curl');
open my $mock, '>', $curl or die $!;
print {$mock} <<'MOCK';
#!/bin/sh
# Offline only: accept just the pinned HTTPS paths.
kind=''
output=''
prev=''
for arg in "$@"; do
  if [ "$prev" = '-o' ]; then output="$arg"; fi
  prev="$arg"
  case "$arg" in
    https://fastapi.metacpan.org/v1/release/JQ-Lite) kind='metadata' ;;
    https://cpan.metacpan.org/authors/id/S/SH/SHINGO/JQ-Lite-*.tar.gz) kind='archive' ;;
    http://*|file://*|ftp://*) exit 72 ;;
  esac
done
printf '%s\n' "$kind" >> "$MOCK_CALLS"
case "$kind" in
  metadata)
    if [ "$MOCK_MODE" = 'metadata-fail' ]; then exit 22; fi
    printf '%s\n' "$MOCK_RELEASE"
    ;;
  archive)
    if [ "$MOCK_MODE" = 'dir-race' ]; then
      mkdir -p -- "$MOCK_RACE_TARGET"
    fi
    if [ "$MOCK_MODE" = 'symlink-race' ]; then
      ln -s -- "$MOCK_SYMLINK_TARGET" "$MOCK_RACE_TARGET"
    fi
    if [ "$MOCK_MODE" = 'null-link-race' ]; then
      ln -s -- /dev/null "$MOCK_RACE_TARGET"
    fi
    if [ "$MOCK_MODE" = 'fifo-race' ]; then
      mkfifo "$MOCK_RACE_TARGET"
    fi
    if [ "$MOCK_MODE" = 'archive-fail' ]; then
      printf 'partial' > "$output"
      exit 22
    fi
    printf 'fake-archive-bytes' > "$output"
    ;;
  *) exit 73 ;;
esac
MOCK
close $mock or die $!;
chmod 0755, $curl or die $!;
my $calls = File::Spec->catfile($root, 'calls.log');
my $out = File::Spec->catdir($root, 'out path');
sub run {
    my ($json, $mode, @args) = @_;
    unlink $calls if -e $calls;
    local $ENV{PATH} = "$mock_dir:$ENV{PATH}";
    local $ENV{MOCK_RELEASE} = defined($json) ? $json : '';
    local $ENV{MOCK_MODE} = $mode || '';
    local $ENV{MOCK_CALLS} = $calls;
    local $ENV{MOCK_RACE_TARGET} = File::Spec->catfile($out, ($mode || '') eq 'symlink-race' ? 'JQ-Lite-2.65.tar.gz' : ($mode || '') eq 'null-link-race' ? 'JQ-Lite-2.66.tar.gz' : ($mode || '') eq 'fifo-race' ? 'JQ-Lite-2.67.tar.gz' : 'JQ-Lite-2.63.tar.gz');
    local $ENV{MOCK_SYMLINK_TARGET} = File::Spec->catfile($out, 'JQ-Lite-2.59.tar.gz');
    my $err = gensym;
    my $pid = open3(my $in, my $stdout, $err, 'bash', ($ENV{TEST_SCRIPT_OVERRIDE} || $script), @args);
    close $in;
    my $output = do { local $/; <$stdout> };
    my $stderr = do { local $/; <$err> };
    close $stdout; close $err;
    waitpid($pid, 0);
    my $calls_text = '';
    if (-e $calls) {
        open my $fh, '<', $calls or die $!;
        $calls_text = do { local $/; <$fh> };
        close $fh;
    }
    return {rc => $? >> 8, out => $output || '', err => $stderr || '', calls => $calls_text};
}

my $good = run('{"version":"2.59","distribution":"JQ-Lite","author":"SHINGO","name":"JQ-Lite-2.59"}', '', '-o', $out);
is($good->{rc}, 0, 'latest signed-shape stable release downloaded');
is($good->{calls}, "metadata\narchive\n", 'latest downloads only metadata and pinned-author archive');
my $tarball = File::Spec->catfile($out, 'JQ-Lite-2.59.tar.gz');
ok(-f $tarball, 'download stored under explicit stable version and spaced destination');
open my $in, '<', $tarball or die $!;
my $body = do { local $/; <$in> };
close $in;
is($body, 'fake-archive-bytes', 'exclusive output copy preserves archive bytes');

my $existing = run('{"version":"2.59"}', '', '-v', '2.59', '-o', $out);
ok($existing->{rc} != 0, 'existing target cannot be overwritten');
is($existing->{calls}, '', 'existing explicit-version target causes no network access');
open $in, '<', $tarball or die $!;
$body = do { local $/; <$in> };
close $in;
is($body, 'fake-archive-bytes', 'existing bytes preserved');

for my $version ('3.00_03', '../bad', 'v2.59', '2.59;touch', '3.00\n') {
    my $bad = run('', '', '-v', $version, '-o', $out);
    ok($bad->{rc} != 0, "untrusted explicit version rejected: $version");
    is($bad->{calls}, '', 'explicit invalid version never contacts network');
}

for my $json (
    '{"version":"3.00_03"}',
    '{"version":"../../bad"}',
    '{"version":{"number":"2.59"}}',
    '{"version":"2.60","author":"ATTACKER"}',
    '{"version":"2.60","distribution":"Other"}',
    '{"version":"2.60","name":"JQ-Lite-2.59"}',
    '{}', 'not-json',
) {
    my $bad = run($json, '', '-o', $out);
    ok($bad->{rc} != 0, "bad release JSON rejected: $json");
    is($bad->{calls}, "metadata\n", 'bad metadata cannot trigger archive download');
}
my $broken = run('', 'metadata-fail', '-o', $out);
ok($broken->{rc} != 0, 'failed metadata request causes exit');
is($broken->{calls}, "metadata\n", 'failed metadata request prevents archive download');

my $partial = run('{"version":"2.60"}', 'archive-fail', '-o', $out);
ok($partial->{rc} != 0, 'partial download is rejected');
is($partial->{calls}, "metadata\narchive\n", 'failed download makes exactly one archive request');
ok(!-e File::Spec->catfile($out, 'JQ-Lite-2.60.tar.gz'), 'partial download never published as target');
opendir my $dh, $out or die $!;
my @tmp = grep { /^\.JQ-Lite-2\.60\./ } readdir $dh;
closedir $dh;
is_deeply(\@tmp, [], 'partial temporary file cleaned up on failure');

my $dir_race = run('', 'dir-race', '-v', '2.63', '-o', $out);
ok($dir_race->{rc} != 0, 'directory appearing during download is rejected');
my $directory = File::Spec->catfile($out, 'JQ-Lite-2.63.tar.gz');
ok(-d $directory, 'existing competing directory not removed');
opendir my $race_dir, $directory or die $!;
my @files = grep { $_ ne '.' && $_ ne '..' } readdir $race_dir;
closedir $race_dir;
is_deeply(\@files, [], 'no temporary tarball is moved inside competing directory');

my $symlink_target = File::Spec->catfile($out, 'JQ-Lite-2.59.tar.gz');
my $link_race = run('', 'symlink-race', '-v', '2.65', '-o', $out);
ok($link_race->{rc} != 0, 'competing destination symlink refused');
open $in, '<', $symlink_target or die $!;
$body = do { local $/; <$in> };
close $in;
is($body, 'fake-archive-bytes', 'symlink target bytes unchanged');

my $null_link = run('', 'null-link-race', '-v', '2.66', '-o', $out);
ok($null_link->{rc} != 0, 'symlink to /dev/null is refused');
ok(-l File::Spec->catfile($out, 'JQ-Lite-2.66.tar.gz'), 'competing device symlink preserved');

my $fifo_race = run('', 'fifo-race', '-v', '2.67', '-o', $out);
ok($fifo_race->{rc} != 0, 'competing FIFO is refused without blocking');
ok(-p File::Spec->catfile($out, 'JQ-Lite-2.67.tar.gz'), 'competing FIFO preserved');

# Deterministically inject an I/O failure after the exclusive open in a
# temporary copy of the exact production shell script. No test hooks in
# the deployed downloader and no network connections.
sub modified_script {
    my ($statement) = @_;
    my $copy = $script_text;
    my $original = '  my $ok = eval {';
    my $injected = $original . "\n" . $statement;
    my $changed = ($copy =~ s/\Q$original\E/$injected/);
    die 'Missing copy-loop injection point' unless $changed == 1;
    my $path = File::Spec->catfile($root, 'test-download.sh');
    open my $fh, '>', $path or die $!;
    print {$fh} $copy or die $!;
    close $fh;
    return $path;
}
my $failure_script = modified_script('    die "injected write failure\n";');
{
    local $ENV{TEST_SCRIPT_OVERRIDE} = $failure_script;
    my $write_fail = run('', '', '-v', '2.64', '-o', $out);
    ok($write_fail->{rc} != 0, 'simulated failed output copy is rejected');
    ok(!-e File::Spec->catfile($out, 'JQ-Lite-2.64.tar.gz'), 'partial output cleaned on failure');
}
my $replace_script = modified_script(q{    unlink $dest or die "unlink failed";
    open my $foreign, ">", $dest or die "replacement creation failed";
    print {$foreign} "foreign-owned";
    close $foreign;
    die "injected replacement race";});
{
    local $ENV{TEST_SCRIPT_OVERRIDE} = $replace_script;
    my $replaced = run('', '', '-v', '2.68', '-o', $out);
    ok($replaced->{rc} != 0, 'replacing output during failed copy is rejected');
    my $other = File::Spec->catfile($out, 'JQ-Lite-2.68.tar.gz');
    open my $fh, '<', $other or die $!;
    my $bytes = do { local $/; <$fh> };
    close $fh;
    is($bytes, 'foreign-owned', 'cleanup never deletes a competing replacement');
}

my $pinned = run('', '', '-v', '2.61', '-o', $out);
is($pinned->{rc}, 0, 'explicit stable release fetched without API lookup');
is($pinned->{calls}, "archive\n", 'pinned version uses only constructed CPAN archive URL');
ok(-f File::Spec->catfile($out, 'JQ-Lite-2.61.tar.gz'), 'pinned archive stored safely');

my $extra = run('', '', '-v', '2.62', '-o', $out, 'unexpected');
ok($extra->{rc} != 0, 'extra positional input is rejected');
is($extra->{calls}, '', 'unexpected argument never contacts network');

done_testing;
