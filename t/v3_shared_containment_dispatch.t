use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Builtin ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;

# These functions share literal-argument parsing but intentionally have
# different types, duplicate handling and membership direction.
my @cases = (
    ['[1,2,3]', 'contains([2])', '[true]', 'jq array element subset'],
    ['[1]', 'contains([1,1])', '[true]', 'jq containment can reuse an element'],
    ['[1]', 'contains([2])', '[false]', 'jq missing array element'],
    ['[["a","b"]]', 'contains([["a"]])', '[true]', 'jq nested arrays'],
    ['{"a":{"b":1,"c":2}}', 'contains({"a":{"b":1}})', '[true]', 'jq nested object subset'],
    ['["1"]', 'contains([1])', '[false]', 'jq retains value type distinctions'],
    ['"banana"', 'contains("ana")', '[true]', 'jq string substring'],
    ['true', 'contains(true)', '[true]', 'jq matching booleans'],
    ['null', 'contains(null)', '[true]', 'jq matching nulls'],

    ['[1,2,3]', 'contains_subset([3,1])', '[true]', 'legacy unordered subset'],
    ['[1]', 'contains_subset([1,1])', '[false]', 'legacy subset counts duplicate elements'],
    ['[1,1]', 'contains_subset([1,1])', '[true]', 'legacy subset has enough duplicates'],
    ['["1"]', 'contains_subset([1])', '[true]', 'legacy numeric-string coercion'],
    ['{"a":{"b":1,"c":2}}', 'contains_subset({"a":{"b":1}})', '[true]', 'legacy nested object subset'],
    ['[1,2]', 'contains_subset([3])', '[false]', 'legacy missing subset'],
    ['"banana"', 'contains_subset(null)', '[false]', 'legacy null needle on string'],

    ['"perl"', 'inside(["perl","python"])', '[true]', 'legacy scalar membership in array'],
    ['2', 'inside([1,2,3])', '[true]', 'legacy number membership in array'],
    ['"an"', 'inside("banana")', '[true]', 'legacy string membership direction'],
    ['{"a":1}', 'inside({"a":1,"b":2})', '[true]', 'legacy object membership direction'],
    ['{"a":3}', 'inside({"a":1,"b":2})', '[false]', 'legacy object mismatch'],
    ['[1,2]', 'inside([1,2,3])', '[false]', 'legacy array membership is exact-element, not jq subset'],
    ['null', 'inside(null)', '[true]', 'legacy null membership'],
    ['"x"', 'inside(null)', '[false]', 'legacy null container'],
);

for my $case (@cases) {
    my ($input, $filter, $expected, $name) = @$case;
    is_deeply([ $jq->run_query($input, $filter) ], $json->decode($expected),
        "$filter: $name");
}

# Only jq-style contains produces structured errors for type mismatches.
for my $case (
    ['[1,2]', 'contains(1)', 'array', 'number'],
    ['"1"', 'contains(1)', 'string', 'number'],
    ['true', 'contains(false)', 'boolean', 'boolean'],
    ['null', 'contains("x")', 'null', 'string'],
) {
    my ($input, $filter, $left, $right) = @$case;
    my $ok = eval { $jq->run_query($input, $filter); 1 };
    ok(!$ok, "$filter rejects mismatched $left/$right");
    isa_ok($@, 'JQ::Lite::Error::Evaluation') unless $ok;
}

# Direct registry dispatch verifies captures for all three names and
# checks that the empty-argument spelling was not broadened.
for my $name ('contains', 'contains_subset', 'inside') {
    my ($matched, $outputs) = JQ::Lite::Builtin->dispatch(
        $jq, "$name([1,2])", [ [1,2] ]
    );
    ok($matched, "$name matches its parameterized registry entry");
    is(scalar @$outputs, 1, "$name emits one result per input");
    my ($empty_match) = JQ::Lite::Builtin->dispatch($jq, "$name()", [ [1] ]);
    ok(!$empty_match, "$name() remains outside the registered pattern");
    is_deeply([ $jq->run_query('[1,2]', "empty | $name([1])") ], [],
        "$name preserves an empty upstream stream");
}

is_deeply([ $jq->run_query('[[1,2],[1],[3,4]]',
    '.[] | contains_subset([1])') ],
    $json->decode('[true,true,false]'),
    'contains_subset preserves input stream order');

is_deeply([ $jq->run_query('[[1,2],[1],[3,4]]',
    '.[] | contains([1])') ],
    $json->decode('[true,true,false]'),
    'contains preserves input stream order');

done_testing;
