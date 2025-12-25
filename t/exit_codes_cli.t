use strict;
use warnings;
use Test::More;
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my $BIN = $ENV{JQLITE_BIN} // 'bin/jq-lite';

sub run_cmd {
    my (%opt) = @_;
    my $stdin = defined $opt{stdin} ? $opt{stdin} : "";
    my @cmd   = @{ $opt{cmd} };

    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, @cmd);

    print {$in} $stdin;
    close $in;

    local $/;
    my $stdout = <$out> // '';
    my $stderr = <$err> // '';
    close $out;
    close $err;

    waitpid($pid, 0);
    my $code = $? >> 8;

    return ($code, $stdout, $stderr);
}

sub like_prefix {
    my ($stderr, $prefix, $name) = @_;
    like($stderr, qr/^\Q$prefix\E/m, $name);
}

# --- Success (0) ---
{
    my ($code, $out, $err) = run_cmd(
        cmd   => [$BIN, '.'],
        stdin => "{}\n",
    );
    is($code, 0, "success: exit 0");
    like($out, qr/^\{\s*/s, "success: stdout has JSON");
    is($err, '', "success: stderr empty");
}

# --- -e falsey => 1 ---
{
    my ($code, $out, $err) = run_cmd(
        cmd   => [$BIN, '-e', '.'],
        stdin => "false\n",
    );
    is($code, 1, "-e false => exit 1");
    is($out, "false\n", "-e: stdout still prints result");
    is($err, "", "-e false: stderr empty");
}

# --- -e empty output => 1 (e.g. empty filter) ---
# jq-compatible-ish: `.[]` on [] => no output; with -e => 1
{
    my ($code, $out, $err) = run_cmd(
        cmd   => [$BIN, '-e', '.[]'],
        stdin => "[]\n",
    );
    is($code, 1, "-e empty output => exit 1");
    is($out, "", "-e empty output: stdout empty");
    is($err, "", "-e empty output: stderr empty");
}

# --- Compile error => 2 + [COMPILE], stdout empty ---
{
    my ($code, $out, $err) = run_cmd(
        cmd   => [$BIN, '.['],
        stdin => "{}\n",
    );
    is($code, 2, "compile error: exit 2");
    is($out, "", "compile error: stdout empty");
    like_prefix($err, '[COMPILE]', "compile error: stderr prefix");
}

# --- Runtime error => 3 + [RUNTIME], stdout empty ---
{
    my ($code, $out, $err) = run_cmd(
        cmd   => [$BIN, '.x + 1'],
        stdin => "{\"x\":\"a\"}\n",
    );
    is($code, 3, "runtime error: exit 3");
    is($out, "", "runtime error: stdout empty");
    like_prefix($err, '[RUNTIME]', "runtime error: stderr prefix");
}

# --- Input error => 4 + [INPUT], stdout empty ---
{
    my ($code, $out, $err) = run_cmd(
        cmd   => [$BIN, '.'],
        stdin => "{broken}\n",
    );
    is($code, 4, "input error: exit 4");
    is($out, "", "input error: stdout empty");
    like_prefix($err, '[INPUT]', "input error: stderr prefix");
}

# --- Usage error (invalid --argjson) => 5 + [USAGE], stdout empty ---
{
    my ($code, $out, $err) = run_cmd(
        cmd   => [$BIN, '--argjson', 'x', '{broken}', '.'],
        stdin => "{}\n",
    );
    is($code, 5, "usage error: invalid --argjson => exit 5");
    is($out, "", "usage error: stdout empty");
    like_prefix($err, '[USAGE]', "usage error: stderr prefix");
}

# --- --argjson scalar allowed (must be success) ---
{
    my ($code, $out, $err) = run_cmd(
        cmd   => [$BIN, '--argjson', 'x', '1', '$x'],
        stdin => "{}\n",
    );
    is($code, 0, "--argjson scalar 1 allowed: exit 0");
    is($out, "1\n", "--argjson scalar 1: stdout");
    is($err, "", "--argjson scalar 1: stderr empty");
}

# --- Broken pipe: jq-lite ... | head ---
# Expect: no [RUNTIME]/etc, exit 0 (or -e semantics if you choose to test that too)
{
    my $cmd = qq{printf '[1,2,3,4,5]\\n' | $BIN '.[]' | head -n 1 >/dev/null 2>t/.sigpipe.err};
    my $rc = system('bash', '-lc', $cmd);
    my $code = $rc >> 8;

    open my $fh, '<', 't/.sigpipe.err' or die $!;
    local $/;
    my $err = <$fh> // '';
    close $fh;
    unlink 't/.sigpipe.err';

    is($code, 0, "SIGPIPE/EPIPE: exit 0");
    is($err, "", "SIGPIPE/EPIPE: no stderr");
}

done_testing();
