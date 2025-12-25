use strict;
use warnings;
use Test::More;
use IPC::Open3;
use Symbol qw(gensym);
use File::Spec;
use Cwd qw(abs_path);
use FindBin;

my $exe = abs_path(File::Spec->catfile($FindBin::Bin, '..', 'bin', 'jq-lite'));

sub run_cli {
    my ($input, @args) = @_;

    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $^X, $exe, @args);
    if (defined $input) {
        print {$in} $input;
    }
    close $in;

    my $stdout = do { local $/; <$out> } // '';
    my $stderr = do { local $/; <$err> } // '';
    close $out;
    close $err;

    waitpid($pid, 0);
    my $exit = $? >> 8;

    return ($stdout, $stderr, $exit);
}

subtest 'compile/runtime/input/usage exit codes' => sub {
    my ($stdout, $stderr, $exit);

    ($stdout, $stderr, $exit) = run_cli("{\"x\":1}\n", '.[');
    is($stdout, '', 'compile error does not emit stdout');
    like($stderr, qr/^\[COMPILE\]/, 'compile errors are prefixed');
    is($exit, 2, 'compile errors exit with code 2');

    ($stdout, $stderr, $exit) = run_cli("{\"x\":\"a\"}\n", '.x + 1');
    is($stdout, '', 'runtime error does not emit stdout');
    like($stderr, qr/^\[RUNTIME\]/, 'runtime errors are prefixed');
    is($exit, 3, 'runtime errors exit with code 3');

    ($stdout, $stderr, $exit) = run_cli("{broken}\n", '.');
    is($stdout, '', 'input error does not emit stdout');
    like($stderr, qr/^\[INPUT\]/, 'input errors are prefixed');
    is($exit, 4, 'input errors exit with code 4');

    ($stdout, $stderr, $exit) = run_cli(undef, '--argjson', 'cfg', '{invalid}', '-n', '$cfg');
    is($stdout, '', 'usage error does not emit stdout');
    like($stderr, qr/^\[USAGE\] invalid JSON for --argjson cfg:/, 'usage errors are prefixed');
    is($exit, 5, 'usage errors exit with code 5');
};

subtest '-e exit status handling' => sub {
    my ($stdout, $stderr, $exit);

    ($stdout, $stderr, $exit) = run_cli("false\n", '-e', '.');
    is($stdout, "false\n", 'false is still printed');
    is($stderr, '', 'false produces no stderr');
    is($exit, 1, '-e returns 1 for false');

    ($stdout, $stderr, $exit) = run_cli("null\n", '-e', '.');
    is($stdout, "null\n", 'null is still printed');
    is($stderr, '', 'null produces no stderr');
    is($exit, 1, '-e returns 1 for null');

    ($stdout, $stderr, $exit) = run_cli("[]\n", '-e', 'empty');
    is($stdout, '', 'empty filter emits no output');
    is($stderr, '', 'empty filter produces no stderr');
    is($exit, 1, '-e returns 1 when output is empty');

    ($stdout, $stderr, $exit) = run_cli("1\n", '-e', '.');
    is($stdout, "1\n", 'truthy values are printed');
    is($stderr, '', 'truthy produces no stderr');
    is($exit, 0, '-e returns 0 for truthy results');
};

DONE_TESTING:
done_testing;
