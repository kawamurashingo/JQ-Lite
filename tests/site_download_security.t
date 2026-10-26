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
    my $err = gensym;
    my $pid = open3(my $in, my $stdout, $err, 'bash', $script, @args);
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
is($body, 'fake-archive-bytes', 'temporary archive atomically linked to target');

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

my $pinned = run('', '', '-v', '2.61', '-o', $out);
is($pinned->{rc}, 0, 'explicit stable release fetched without API lookup');
is($pinned->{calls}, "archive\n", 'pinned version uses only constructed CPAN archive URL');
ok(-f File::Spec->catfile($out, 'JQ-Lite-2.61.tar.gz'), 'pinned archive stored safely');

my $extra = run('', '', '-v', '2.62', '-o', $out, 'unexpected');
ok($extra->{rc} != 0, 'extra positional input is rejected');
is($extra->{calls}, '', 'unexpected argument never contacts network');

done_testing;
