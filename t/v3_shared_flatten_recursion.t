use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Builtin ();
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;

sub run {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

my $nested = '[0,[1,[2,[3]]],[],{"nested":[3,4]},null]';
my @cases = (
    [ 'flatten',          '[0,1,[2,[3]],{"nested":[3,4]},null]' ],
    [ 'flatten_all',      '[0,1,2,3,{"nested":[3,4]},null]' ],
    [ 'flatten_depth',    '[0,1,[2,[3]],{"nested":[3,4]},null]' ],
    [ 'flatten_depth()',  '[0,1,[2,[3]],{"nested":[3,4]},null]' ],
    [ 'flatten_depth(0)', $nested ],
    [ 'flatten_depth(1)', '[0,1,[2,[3]],{"nested":[3,4]},null]' ],
    [ 'flatten_depth(2)', '[0,1,2,[3],{"nested":[3,4]},null]' ],
    [ 'flatten_depth(3)', '[0,1,2,3,{"nested":[3,4]},null]' ],
    [ 'flatten_depth(8)', '[0,1,2,3,{"nested":[3,4]},null]' ],
);
for my $case (@cases) {
    my ($filter, $expected) = @$case;
    is_deeply(run($nested, $filter), [$json->decode($expected)],
        "$filter preserves expected flattening depth and object boundaries");
}

for my $input ('[]', '[[]]', '[[[]]]') {
    for my $filter ('flatten', 'flatten_all', 'flatten_depth(0)',
                    'flatten_depth(1)', 'flatten_depth(3)') {
        my $expected = $filter eq 'flatten_depth(0)' ? $input : '[]';
        is_deeply(run($input, $filter), [$json->decode($expected)],
            "$filter preserves empty nested array structure for $input");
    }
}

# Every non-array input is a passthrough; do not confuse boolean or null
# values with empty arrays or remove nested arrays inside objects.
for my $input ('null', 'true', 'false', '123', '"hello"',
               '{"a":[[1,2]],"b":null}') {
    my $expected = $json->decode($input);
    for my $filter ('flatten', 'flatten_all', 'flatten_depth(2)') {
        is_deeply(run($input, $filter), [$expected],
            "$filter passes nonarray input $input through");
    }
}

my $mixed = '[[null,false],[[true,0,"0"]]]';
my $expected = $json->decode('[null,false,true,0,"0"]');
is_deeply(run($mixed, 'flatten_all'), [$expected],
    'unlimited flatten keeps null, false, true, number and numeric string');
is_deeply(run($mixed, 'flatten_depth(3)'), [$expected],
    'finite flatten keeps JSON value types and original order');
is_deeply(run($mixed, 'flatten_depth(0)'), [$json->decode($mixed)],
    'zero depth preserves the original nested container');

# Direct API assertions pin the intended unlimited-depth sentinel and
# the existing zero/negative semantics without changing public syntax.
for my $depth (0, 1, 2, 3, 99) {
    my $input = $json->decode($nested);
    my $expected = $depth == 0 ? $json->decode($nested)
        : $depth == 1 ? $json->decode($cases[0][1])
        : $depth == 2 ? $json->decode($cases[6][1])
        : $json->decode($cases[1][1]);
    is_deeply(JQ::Lite::Util::_flatten_depth($input, $depth), $expected,
        "direct finite-depth recursion preserves depth $depth");
}
is_deeply(JQ::Lite::Util::_flatten_depth($json->decode($nested), -2),
    $json->decode($nested), 'negative direct depth remains a no-op');
is_deeply(JQ::Lite::Util::_flatten_depth($json->decode($nested), undef),
    $json->decode($cases[1][1]), 'undefined depth enables unlimited recursion');
is_deeply(JQ::Lite::Util::_flatten_all($json->decode($nested)),
    $json->decode($cases[1][1]), 'flatten_all preserves its direct helper API');

for my $name ('flatten', 'flatten_all') {
    my ($found, $outputs) = JQ::Lite::Builtin->dispatch(
        $jq, $name, [$json->decode('[[1,[2]]]'), undef, 42]
    );
    ok($found, "$name remains registered");
    is_deeply($outputs,
        $name eq 'flatten' ? [[[1,[2]]], undef, 42]
                          : [[1,2], undef, 42],
        "$name preserves the three-item direct stream");
    my ($alias, $alias_outputs) = JQ::Lite::Builtin->dispatch(
        $jq, "$name()", [$json->decode('[[1,[2]]]')]
    );
    ok($alias, "$name() alias remains registered");
    is_deeply($alias_outputs,
        $name eq 'flatten' ? [[[1,[2]]]] : [[1,2]],
        "$name() direct alias keeps legacy flattening behavior");
    is_deeply(run('null', "empty | $name"), [],
        "$name does not create values from an empty upstream stream");
}

is_deeply(run('[[1,[2]],[],[3,[4]]]', '.[] | flatten_all'),
    [[1,2], [], [3,4]],
    'full flatten retains ordered multi-value streams');
is_deeply(run('[[1,[2]],[],[3,[4]]]', '.[] | flatten'),
    [[1,[2]], [], [3,[4]]],
    'single flatten retains ordered multi-value streams');

done_testing;
