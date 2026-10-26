use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Archive::Tar ();
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
like($source, qr/\$tar->extract or die/,
    'same validated Archive::Tar parser extracts archive');
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
