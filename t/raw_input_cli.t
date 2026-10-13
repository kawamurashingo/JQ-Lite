use strict;
use warnings;
use Test::More;
use IPC::Open3;
use Symbol qw(gensym);
use Encode qw(encode);

sub run_cli {
    my (%opts) = @_;
    my @cmd = ($^X, 'bin/jq-lite', @{ $opts{args} // [] });

    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, @cmd);

    if (defined $opts{stdin}) {
        print {$in} $opts{stdin};
    }
    close $in;

    my $stdout = do { local $/; <$out> } // '';
    my $stderr = do { local $/; <$err> } // '';

    waitpid($pid, 0);
    my $exit_code = $? >> 8;

    return ($stdout, $stderr, $exit_code);
}

my ($stdout, $stderr, $exit) = run_cli(
    args  => [ '-R', '-c', '.' ],
    stdin => "foo\nbar\n",
);

is($stdout, "\"foo\"\n\"bar\"\n", '--raw-input processes each line as a separate string');
like($stderr, qr/^\s*\z/, 'no warnings emitted when reading raw lines');
is($exit, 0, 'process exits successfully for raw line input');

($stdout, $stderr, $exit) = run_cli(
    args  => [ '-R', '-s', '-c', '.' ],
    stdin => "alpha\nbeta\n",
);

is($stdout, "\"alpha\\nbeta\\n\"\n", '--raw-input with --slurp combines input into a single string');
like($stderr, qr/^\s*\z/, 'no warnings emitted when slurping raw text');
is($exit, 0, 'process exits successfully for slurped raw text');

($stdout, $stderr, $exit) = run_cli(
    args  => [ '-R', '-c', '.', 'nonexistent.json' ],
);

like($stderr, qr/No such file or directory|Cannot open file/, 'error surfaced when file is missing under --raw-input');
ok($exit != 0, 'nonexistent file under raw input causes non-zero exit');

($stdout, $stderr, $exit) = run_cli(
    args => [ '-R' ],
);

is($stdout, '', 'no output is produced when --raw-input is provided without a query');
like(
    $stderr,
    qr/^\[USAGE\]--raw-input requires a query when not using --slurp\./,
    'usage error is raised when --raw-input lacks a query'
);
is($exit, 5, '--raw-input without a query exits with usage code');

($stdout, $stderr, $exit) = run_cli(
    args => [ '-R', '-s' ],
);

is($stdout, '', 'no output is produced when --raw-input and --slurp are used without a query');
like(
    $stderr,
    qr/^\[USAGE\]--raw-input requires a query when used with --slurp\./,
    'usage error is raised when --raw-input --slurp lacks a query'
);
is($exit, 5, '--raw-input --slurp without a query exits with usage code');

my $japanese = "\x{65e5}\x{672c}x\n";
my $latin = "\x{e9}x\n";
my @unicode_cases = (
    [ ['-R','-c','index("x")'], $japanese, "6\n", 'Japanese first byte offset' ],
    [ ['-R','-c','rindex("x")'], $japanese, "6\n", 'Japanese last byte offset' ],
    [ ['-R','-c','indices("x")'], $japanese, "[6]\n", 'Japanese byte offsets' ],
    [ ['-R','-c','index("x")'], $latin, "2\n", 'Latin-1 first byte offset' ],
    [ ['-R','-c','rindex("x")'], $latin, "2\n", 'Latin-1 last byte offset' ],
    [ ['-R','-c','indices("x")'], $latin, "[2]\n", 'Latin-1 byte offsets' ],
    [ ['-R','-c','index("\u672c")'], $japanese, "3\n", 'first multibyte needle' ],
    [ ['-R','-c','rindex("\u672c")'], $japanese, "3\n", 'last multibyte needle' ],
    [ ['-R','-c','indices("\u672c")'], $japanese, "[3]\n", 'all multibyte needles' ],
    [ ['-R','-c','indices("x")'], $japanese.$latin, "[6]\n[2]\n", 'raw line output order' ],
    [ ['-R','-s','-c','index("x")'], $japanese.$latin, "6\n", 'slurped first byte offset' ],
    [ ['-R','-s','-c','rindex("x")'], $japanese.$latin, "10\n", 'slurped last byte offset' ],
    [ ['-R','-s','-c','indices("x")'], $japanese.$latin, "[6,10]\n", 'slurped byte offsets' ],
    [ ['-R','-s','-c','indices("\u672c")'], $japanese.$latin, "[3]\n", 'slurped multibyte needle' ],
    [ ['-R','-c','.'], $japanese, "\"\x{65e5}\x{672c}x\"\n", 'Japanese JSON output' ],
    [ ['-R','-c','.'], $latin, "\"\x{e9}x\"\n", 'Latin-1 JSON output' ],
    [ ['-R','-c','length'], $japanese, "3\n", 'Japanese character length' ],
    [ ['-R','-c','length'], $latin, "2\n", 'Latin-1 character length' ],
    [ ['-R','-r','.'], $japanese, $japanese, 'Japanese raw output' ],
    [ ['-R','-r','.'], $latin, $latin, 'Latin-1 raw output' ],
    [ ['-R','-s','-r','.'], $japanese.$latin, $japanese.$latin."\n", 'slurped raw output' ],
);
for my $case (@unicode_cases) {
    my ($args, $input, $expected, $name) = @$case;
    my ($out, $err, $rc) = run_cli(args=>$args, stdin=>encode('UTF-8', $input));
    is($rc, 0, "$name exits successfully");
    is($out, encode('UTF-8', $expected), "$name writes the expected bytes");
    is($err, '', "$name has no UTF-8 warnings");
}

done_testing;
