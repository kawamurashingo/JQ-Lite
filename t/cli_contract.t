use strict;
use warnings;
use Test::More;
use IPC::Open3;
use Symbol qw(gensym);
use File::Temp qw(tempfile);

# Allow overriding the binary path:
#   JQ_LITE_BIN=jq-lite prove -lv t/cli_contract.t
my $BIN = $ENV{JQ_LITE_BIN} || 'bin/jq-lite';

sub run_cmd {
    my (%opt) = @_;
    my $stdin = defined $opt{stdin} ? $opt{stdin} : '';
    my @cmd   = @{ $opt{cmd} };

    my $err = gensym;
    my ($in, $out);

    my $pid = eval { open3($in, $out, $err, @cmd) };
    if ($@) {
        return {
            rc  => 5,
            out => '',
            err => "[USAGE] failed to exec: $@",
        };
    }

    # write stdin
    if (defined $stdin && length $stdin) {
        print {$in} $stdin;
    }
    close $in;

    # slurp stdout / stderr
    local $/;
    my $stdout = <$out>;
    $stdout = '' unless defined $stdout;
    close $out;

    my $stderr = <$err>;
    $stderr = '' unless defined $stderr;
    close $err;

    waitpid($pid, 0);
    my $rc = ($? >> 8);

    return {
        rc  => $rc,
        out => $stdout,
        err => $stderr,
    };
}

sub assert_err_contract {
    my (%a) = @_;
    my $res    = $a{res};
    my $rc     = $a{rc};
    my $prefix = $a{prefix};
    my $name   = $a{name};

    is($res->{rc}, $rc, "$name: exit=$rc");

    # Contract: "first line MUST start with prefix"
    like($res->{err}, qr/\A\Q$prefix\E/, "$name: stderr first line prefix $prefix");

    is($res->{out}, '', "$name: stdout empty on error");
}

# ============================================================
# Exit codes + stderr prefixes
# ============================================================

# Compile error (basic)
{
    my $res = run_cmd(cmd => [$BIN, '.['], stdin => "{}\n");
    assert_err_contract(
        res    => $res,
        rc     => 2,
        prefix => '[COMPILE]',
        name   => 'compile error',
    );
}

# Compile error: empty filter segment
{
    my $res = run_cmd(cmd => [$BIN, '.foo |'], stdin => "{}\n");
    assert_err_contract(
        res    => $res,
        rc     => 2,
        prefix => '[COMPILE]',
        name   => 'compile error: empty filter segment',
    );
}

# ✅ NEW: compile MUST occur before input parsing
# If both filter and input are broken, COMPILE wins (exit=2), not INPUT.
{
    my $res = run_cmd(cmd => [$BIN, '.['], stdin => "{broken}\n");
    assert_err_contract(
        res    => $res,
        rc     => 2,
        prefix => '[COMPILE]',
        name   => 'compile precedes input parse (broken input still compile error)',
    );
}

# Runtime error
{
    my $res = run_cmd(
        cmd   => [$BIN, '.x + 1'],
        stdin => qq|{"x":"a"}\n|,
    );
    assert_err_contract(
        res    => $res,
        rc     => 3,
        prefix => '[RUNTIME]',
        name   => 'runtime error',
    );
}

# Runtime error: keys on scalar
{
    my $res = run_cmd(
        cmd   => [$BIN, 'keys'],
        stdin => qq|null\n|,
    );
    assert_err_contract(
        res    => $res,
        rc     => 3,
        prefix => '[RUNTIME]',
        name   => 'runtime error: keys on scalar',
    );
}

# Runtime error: delpaths requires array of path arrays
{
    my $res = run_cmd(
        cmd   => [$BIN, 'delpaths(["a"])'],
        stdin => qq|{"a":1}\n|,
    );

    assert_err_contract(
        res    => $res,
        rc     => 3,
        prefix => '[RUNTIME]',
        name   => 'runtime error: delpaths array-of-arrays enforcement',
    );

    like(
        $res->{err},
        qr/paths must be an array of path arrays/,
        'runtime error message mentions array of path arrays',
    );
}

# Input error
{
    my $res = run_cmd(
        cmd   => [$BIN, '.'],
        stdin => qq|{broken}\n|,
    );
    assert_err_contract(
        res    => $res,
        rc     => 4,
        prefix => '[INPUT]',
        name   => 'input error',
    );
}

# Usage error: invalid --argjson
{
    my $res = run_cmd(
        cmd => [$BIN, '--argjson', 'x', '{broken}', '.'],
    );
    assert_err_contract(
        res    => $res,
        rc     => 5,
        prefix => '[USAGE]',
        name   => 'usage error: invalid --argjson',
    );
}

# Usage error: unknown option
{
    my $res = run_cmd(cmd => [$BIN, '--bogus-option']);
    assert_err_contract(
        res    => $res,
        rc     => 5,
        prefix => '[USAGE]',
        name   => 'usage error: unknown option',
    );
    like(
        $res->{err},
        qr/\A\[USAGE\]Unknown option: bogus-option\b/,
        'usage error: unknown option message is prefixed and concise'
    );
}

# ============================================================
# -e / --exit-status semantics
# ============================================================

# -e false => exit 1
{
    my $res = run_cmd(
        cmd   => [$BIN, '-e', '.'],
        stdin => "false\n",
    );
    is($res->{rc}, 1, '-e false => exit 1');
    like($res->{out}, qr/^false\b/m, '-e false => stdout contains false');
    like($res->{err}, qr/^\s*\z/s, '-e false => stderr empty');
}

# -e null => exit 1
{
    my $res = run_cmd(
        cmd   => [$BIN, '-e', '.'],
        stdin => "null\n",
    );
    is($res->{rc}, 1, '-e null => exit 1');
    like($res->{out}, qr/^null\b/m, '-e null => stdout contains null');
    like($res->{err}, qr/^\s*\z/s, '-e null => stderr empty');
}

# -e empty output => exit 1
{
    my $res = run_cmd(
        cmd   => [$BIN, '-e', 'empty'],
        stdin => "1\n",
    );
    is($res->{rc}, 1, '-e empty => exit 1');
    is($res->{out}, '', '-e empty => no stdout');
    like($res->{err}, qr/^\s*\z/s, '-e empty => stderr empty');
}

# ✅ UPDATED: -e truthiness fully matches jq: 0 is truthy => exit 0
{
    my $res = run_cmd(
        cmd   => [$BIN, '-e', '.'],
        stdin => "0\n",
    );
    is($res->{rc}, 0, '-e 0 => exit 0 (jq-compatible truthiness)');
    like($res->{out}, qr/^0\b/m, '-e 0 => stdout contains 0');
    like($res->{err}, qr/^\s*\z/s, '-e 0 => stderr empty');
}

# ✅ NEW: -e affects only exit code, not stdout formatting/content
{
    my $a = run_cmd(cmd => [$BIN, '.'],   stdin => qq|{"x":1}\n|);
    my $b = run_cmd(cmd => [$BIN, '-e', '.'], stdin => qq|{"x":1}\n|);

    is($a->{rc}, 0, 'no -e => exit 0');
    is($b->{rc}, 0, '-e truthy => exit 0');
    is($a->{out}, $b->{out}, '-e does not change stdout content/format');
    like($b->{err}, qr/^\s*\z/s, '-e stderr empty');
}

# ============================================================
# -n / --null-input
# ============================================================

# ✅ NEW: -n runs without reading stdin and succeeds
{
    my $res = run_cmd(
        cmd   => [$BIN, '-n', 'null'],
        stdin => "{broken}\n",  # should be ignored under -n
    );
    is($res->{rc}, 0, '-n null => exit 0');
    like($res->{out}, qr/^null\b/m, '-n null => outputs null');
    like($res->{err}, qr/^\s*\z/s, '-n null => stderr empty');
}

# ============================================================
# --arg / --argjson / --argfile semantics
# ============================================================

# --arg binds string
{
    my $res = run_cmd(
        cmd   => [$BIN, '--arg', 'greeting', 'hello', '$greeting'],
        stdin => "{}\n",
    );
    is($res->{rc}, 0, '--arg string => exit 0');
    like($res->{out}, qr/"hello"/, '--arg string => output "hello"');
    like($res->{err}, qr/^\s*\z/s, '--arg string => stderr empty');
}

# ✅ NEW: --arg missing value => usage error
{
    my $res = run_cmd(
        cmd => [$BIN, '--arg', 'x', '.'], # missing value
    );
    assert_err_contract(
        res    => $res,
        rc     => 5,
        prefix => '[USAGE]',
        name   => 'usage error: --arg missing value',
    );
}

# --argjson allows scalar JSON
{
    my $res = run_cmd(
        cmd   => [$BIN, '--argjson', 'x', '1', '$x'],
        stdin => "null\n",
    );
    is($res->{rc}, 0, '--argjson scalar => exit 0');
    like($res->{out}, qr/^1\b/m, '--argjson scalar => output 1');
    like($res->{err}, qr/^\s*\z/s, '--argjson scalar => stderr empty');
}

# ✅ NEW: --argjson scalar variations (string/true/null)
{
    my $res_s = run_cmd(cmd => [$BIN, '--argjson', 'x', '"hi"', '$x'], stdin => "null\n");
    is($res_s->{rc}, 0, '--argjson string scalar => exit 0');
    like($res_s->{out}, qr/^"hi"\b/m, '--argjson string scalar => output "hi"');

    my $res_t = run_cmd(cmd => [$BIN, '--argjson', 'x', 'true', '$x'], stdin => "null\n");
    is($res_t->{rc}, 0, '--argjson true scalar => exit 0');
    like($res_t->{out}, qr/^true\b/m, '--argjson true scalar => output true');

    my $res_n = run_cmd(cmd => [$BIN, '--argjson', 'x', 'null', '$x'], stdin => "null\n");
    is($res_n->{rc}, 0, '--argjson null scalar => exit 0');
    like($res_n->{out}, qr/^null\b/m, '--argjson null scalar => output null');
}

# ✅ NEW: --argfile missing/unreadable => usage error
{
    my $res = run_cmd(
        cmd   => [$BIN, '--argfile', 'x', '/no/such/file.json', '$x'],
        stdin => "{}\n",
    );
    assert_err_contract(
        res    => $res,
        rc     => 5,
        prefix => '[USAGE]',
        name   => 'usage error: --argfile missing',
    );
}

# ✅ NEW: --argfile invalid JSON => usage error
{
    my ($fh, $path) = tempfile();
    print {$fh} "{broken}\n";
    close $fh;

    my $res = run_cmd(
        cmd   => [$BIN, '--argfile', 'x', $path, '$x'],
        stdin => "{}\n",
    );
    assert_err_contract(
        res    => $res,
        rc     => 5,
        prefix => '[USAGE]',
        name   => 'usage error: --argfile invalid JSON',
    );
}

# ✅ NEW: --argfile valid JSON binds => success
{
    my ($fh, $path) = tempfile();
    print {$fh} "{\"a\":1}\n";
    close $fh;

    my $res = run_cmd(
        cmd   => [$BIN, '--argfile', 'x', $path, '$x.a'],
        stdin => "{}\n",
    );
    is($res->{rc}, 0, '--argfile valid => exit 0');
    like($res->{out}, qr/^1\b/m, '--argfile binds JSON');
    like($res->{err}, qr/^\s*\z/s, '--argfile stderr empty');
}

# ============================================================
# Broken pipe (SIGPIPE / EPIPE)
# ============================================================

{
    # Capture stderr to verify "no error message"
    my ($fh, $errfile) = tempfile();
    close $fh;

    # Finite input to avoid hanging, but still trigger early pipe close
    my $cmd = "yes '{}' | head -n 2000 | $BIN '.' 1>/dev/null 2>'$errfile' | head -n 1 >/dev/null";
    my $rc = system('sh', '-c', $cmd);
    $rc = ($rc >> 8);

    ok($rc == 0 || $rc == 1, "broken pipe is not fatal (exit=$rc)");

    my $esize = -s $errfile;
    $esize = 0 unless defined $esize;
    is($esize, 0, 'broken pipe prints nothing to stderr');

    unlink $errfile;
}

# paths() and paths(scalars) on scalar input should be no-ops with success
{
    my $res_paths = run_cmd(
        cmd   => [$BIN, 'paths'],
        stdin => qq|"hi"\n|,
    );

    is($res_paths->{rc}, 0, 'paths on scalar exits 0');
    is($res_paths->{out}, '', 'paths on scalar emits no output');
    is($res_paths->{err}, '', 'paths on scalar emits no errors');

    my $res_scalar_paths = run_cmd(
        cmd   => [$BIN, 'paths(scalars)'],
        stdin => qq|true\n|,
    );

    is($res_scalar_paths->{rc}, 0, 'paths(scalars) on scalar exits 0');
    is($res_scalar_paths->{out}, '', 'paths(scalars) on scalar emits no output');
    is($res_scalar_paths->{err}, '', 'paths(scalars) on scalar emits no errors');
}

done_testing();

