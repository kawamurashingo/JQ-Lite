use strict;
use warnings;
use Test::More;
use JSON::PP ();
use Scalar::Util qw(refaddr);
use JQ::Lite;
use JQ::Lite::Builtin ();
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;

sub results {
    my ($input, $query) = @_;
    return [ $jq->run_query($input, $query) ];
}

# _flatten_depth already returns its input unchanged unless it is an
# array. Removing the extra builtin-level ARRAY guard must preserve all
# jq value types, including JSON booleans and opaque nested objects.
for my $input (
    'null', 'true', 'false', '0', '"0"', '"hello"',
    '{"nested":[[1,2]],"active":true}',
) {
    for my $filter (
        'flatten', 'flatten()', 'flatten_all', 'flatten_all()',
        'flatten_depth', 'flatten_depth()', 'flatten_depth(0)',
        'flatten_depth(2)',
    ) {
        is_deeply(results($input, $filter), [$json->decode($input)],
            "$filter passes non-array $input through unchanged");
    }
}

my @array_cases = (
    ['[]', '[]', '[]', 'empty array'],
    [
        '[[1,[2,[3]]],{"keep":[[4]]},null]',
        '[1,[2,[3]],{"keep":[[4]]},null]',
        '[1,2,3,{"keep":[[4]]},null]',
        'nested arrays and opaque object',
    ],
    [
        '[[true,false],[],[[0,"0"]]]',
        '[true,false,[0,"0"]]',
        '[true,false,0,"0"]',
        'boolean and numeric-string slots',
    ],
);

for my $case (@array_cases) {
    my ($input, $one, $all, $label) = @$case;
    for my $spec (
        ['flatten', $one],
        ['flatten()', $one],
        ['flatten_all', $all],
        ['flatten_all()', $all],
        ['flatten_depth', $one],
        ['flatten_depth()', $one],
        ['flatten_depth(0)', $input],
        ['flatten_depth(1)', $one],
        ['flatten_depth(8)', $all],
    ) {
        my ($filter, $expected) = @$spec;
        is_deeply(results($input, $filter), [$json->decode($expected)],
            "$filter preserves $label");
    }
}

# Direct dispatch must retain one result per stream item and pass through
# non-arrays *by reference*, not just by value.
my $truth = JSON::PP::true;
my $falsity = JSON::PP::false;
my $object = { nested => [[5]], active => $truth };
my $nested = [[1,[2,[3]]]];
my @inputs = (undef, $truth, $falsity, 42, '42', $object, $nested);

for my $spec (
    ['flatten', [1,[2,[3]]]],
    ['flatten()', [1,[2,[3]]]],
    ['flatten_all', [1,2,3]],
    ['flatten_all()', [1,2,3]],
    ['flatten_depth(0)', $nested],
    ['flatten_depth(1)', [1,[2,[3]]]],
    ['flatten_depth(2)', [1,2,[3]]],
    ['flatten_depth(-3)', $nested],
) {
    my ($filter, $array_expected) = @$spec;
    my ($matched, $outputs) =
        JQ::Lite::Builtin->dispatch($jq, $filter, \@inputs);
    ok($matched, "$filter remains registered");
    is_deeply($outputs,
        [undef, $truth, $falsity, 42, '42', $object, $array_expected],
        "$filter keeps ordered stream values and array depth");
    is(refaddr($outputs->[1]), refaddr($truth),
        "$filter preserves true boolean identity");
    is(refaddr($outputs->[2]), refaddr($falsity),
        "$filter preserves false boolean identity");
    is(refaddr($outputs->[5]), refaddr($object),
        "$filter preserves object identity");
    my ($empty_match, $empty_values) =
        JQ::Lite::Builtin->dispatch($jq, $filter, []);
    ok($empty_match, "$filter is valid on an empty direct stream");
    is_deeply($empty_values, [],
        "$filter does not generate values from an empty stream");
}

is_deeply(results('[[[1,[2]]],null,{"keep":[[3]]},true]',
    '.[] | flatten'), [[[1,[2]]], undef, {keep => [[3]]}, $truth],
    'flatten preserves order for mixed value streams');
is_deeply(results('[[[1,[2]]],null,{"keep":[[3]]},true]',
    '.[] | flatten_all'), [[1,2], undef, {keep => [[3]]}, $truth],
    'flatten_all preserves order for mixed value streams');
is_deeply(results('null', 'empty | flatten_depth(2)'), [],
    'bounded flatten keeps an empty upstream stream');

# Keep the utility's own fast-return boundary explicit.
is_deeply(JQ::Lite::Util::_flatten_depth($object, 10), $object,
    'internal helper passes non-array objects unchanged');
is(refaddr(JQ::Lite::Util::_flatten_depth($object, undef)),
    refaddr($object), 'internal helper preserves non-array identity');

done_testing;
