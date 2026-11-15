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

# One-level and unlimited flattening share recursion but must retain
# different depths, opaque objects and the exact JSON value types.
my @cases = (
    ['[1,[2,[3]],4]', '[1,2,[3],4]', '[1,2,3,4]', 'mixed depths'],
    ['[[[9]]]', '[[9]]', '[9]', 'three nested levels'],
    ['[[],[[]],[[[]]]]', '[[],[[]]]', '[]', 'nested empty arrays'],
    ['[[1],[2,3],[]]', '[1,2,3]', '[1,2,3]', 'shallow arrays'],
    ['[{"nested":[[7]]},[[{"x":[[8]]}]]]',
        '[{"nested":[[7]]},[{"x":[[8]]}]]',
        '[{"nested":[[7]]},{"x":[[8]]}]',
        'arrays inside objects remain opaque'],
    ['[null,false,true,0,"0",[[1]]]',
        '[null,false,true,0,"0",[1]]',
        '[null,false,true,0,"0",1]',
        'null and boolean preservation'],
    ['[[],[1,[2]],null]', '[1,[2],null]', '[1,2,null]', 'null after arrays'],
    ['[[[1]],[[2]]]', '[[1],[2]]', '[1,2]', 'parallel subarrays'],
    ['[[],[]]', '[]', '[]', 'all empty arrays'],
    ['[1,2,3]', '[1,2,3]', '[1,2,3]', 'no nested arrays'],
);

for my $case (@cases) {
    my ($input, $one, $all, $label) = @$case;
    is_deeply(run($input, 'flatten'), [$json->decode($one)],
        "flatten one level: $label");
    is_deeply(run($input, 'flatten_all'), [$json->decode($all)],
        "flatten all levels: $label");
    is_deeply(run($input, 'flatten_depth(1)'), [$json->decode($one)],
        "flatten_depth(1) agrees on $label");
}

for my $input ('null', 'true', 'false', '42', '"hello"', '{"a":[[2]]}') {
    my $expected = $json->decode($input);
    for my $name ('flatten', 'flatten_all') {
        is_deeply(run($input, $name), [$expected],
            "$name leaves non-array input $input alone");
    }
}

my $nested = '[[1,[2,[3]]],[],[4,[5]]]';
is_deeply(run($nested, 'flatten_depth(0)'), [$json->decode($nested)],
    'depth zero returns the original nested structure');
is_deeply(run($nested, 'flatten_depth(2)'),
    [$json->decode('[1,2,[3],4,5]')],
    'depth two flattens exactly two levels');
is_deeply(run($nested, 'flatten_all'),
    [$json->decode('[1,2,3,4,5]')],
    'unlimited flatten removes all nested array levels');

for my $name ('flatten', 'flatten_all') {
    my @inputs = ($json->decode('[[1,[2]]]'), undef, 42, $json->decode('[]'));
    my ($matched, $result) = JQ::Lite::Builtin->dispatch(
        $jq, $name, \@inputs
    );
    ok($matched, "$name is registered");
    my $first = $name eq 'flatten' ? [1,[2]] : [1,2];
    is_deeply($result, [$first, undef, 42, []],
        "$name retains all inputs and empty-array slots");
    my ($alias_matched, $alias_result) = JQ::Lite::Builtin->dispatch(
        $jq, "$name()", \@inputs
    );
    ok($alias_matched, "$name() is still registered");
    is_deeply($alias_result, $result,
        "$name() retains the same handler semantics");
    is_deeply(run($nested, "empty | $name"), [],
        "$name does not synthesize output after empty");
}

is_deeply(run('[[1,[2]],[],[[3]],null]', '.[] | flatten'),
    [[1,2],[],[3],undef], 'flatten preserves multi-input order and null');
is_deeply(run('[[1,[2]],[],[[3]],null]', '.[] | flatten_all'),
    [[1,2],[],[3],undef], 'flatten_all preserves multi-input order and null');

# The named internal helper remains callable after built-in registration is
# switched to the shared finite/unlimited depth traversal.
my $input = $json->decode('[[1,[2,[3]]],{"keep":[[4]]}]');
is_deeply(JQ::Lite::Util::_flatten_all($input),
    $json->decode('[1,2,3,{"keep":[[4]]}]'),
    '_flatten_all direct utility API keeps unlimited recursion');
is_deeply(JQ::Lite::Util::_flatten_depth($input, -1), $input,
    '_flatten_depth negative depth is still a no-op');

done_testing;
