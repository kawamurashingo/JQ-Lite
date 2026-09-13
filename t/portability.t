use strict;
use warnings;

use Test::More;
use File::Find;
use File::Spec;
use File::Temp qw(tempdir);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

use lib 'lib';
use JQ::Lite;

subtest 'core library stays platform-neutral' => sub {
    my @perl_files;
    find(
        sub {
            return unless -f $_;
            return unless /\.pm\z/;
            push @perl_files, $File::Find::name;
        },
        'lib',
    );

    ok(@perl_files, 'found Perl library files');

    my @forbidden = (
        [ qr/\bsystem\s*\(/, 'system()' ],
        [ qr/\bqx\s*\//,      'qx//' ],
        [ qr{/dev/},             '/dev/* path' ],
        [ qr/\bstty\b/,        'stty' ],
        [ qr/\bclear\b/,       'clear command' ],
    );

    for my $path (@perl_files) {
        open my $fh, '<', $path or die "Cannot read $path: $!";
        local $/;
        my $source = <$fh>;
        close $fh;

        for my $check (@forbidden) {
            my ($pattern, $label) = @{$check};
            unlike($source, $pattern, "$path does not depend on $label");
        }
    }
};

subtest 'core query works without a shell' => sub {
    local $ENV{PATH} = '';

    my $jq = JQ::Lite->new;
    my @result = $jq->run_query(
        '{"users":[{"name":"Ada"},{"name":"Grace"}]}',
        '.users[].name',
    );

    is_deeply(\@result, [qw(Ada Grace)], 'representative core query succeeds');
};

subtest 'non-interactive CLI works through perl on this platform' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $input = File::Spec->catfile($tmpdir, 'input.json');

    open my $fh, '>', $input or die "Cannot write $input: $!";
    print {$fh} "{\"items\":[1,2,3]}\n";
    close $fh;

    my $err = gensym;
    my $pid = open3(
        my $stdin,
        my $stdout,
        $err,
        $^X,
        File::Spec->catfile('bin', 'jq-lite'),
        '-c',
        '.items | length',
        $input,
    );
    close $stdin;

    local $/;
    my $out = <$stdout>;
    my $stderr = <$err>;
    close $stdout;
    close $err;

    waitpid($pid, 0);
    my $exit = $? >> 8;

    is($exit, 0, 'CLI exits successfully');
    is($stderr // '', '', 'CLI writes no stderr');
    is($out // '', "3\n", 'CLI produces expected output');
};

done_testing;
