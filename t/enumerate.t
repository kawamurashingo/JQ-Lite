use strict;
use warnings;

use Test::More;
use JQ::Lite;
use JSON::PP;

my $jq = JQ::Lite->new;

my $json = encode_json({ numbers => [10, 20, 30] });
my $decoded = decode_json($json);

my @result = $jq->run_query($json, '.numbers | enumerate()');
my $expected = [
    { index => 0, value => 10 },
    { index => 1, value => 20 },
    { index => 2, value => 30 },
];

is_deeply($result[0], $expected, 'enumerate() pairs array values with indexes');

@result = $jq->run_query($json, '.numbers | enumerate() | map(.index)');
$expected = [0, 1, 2];
is_deeply($result[0], $expected, 'enumerate() works with map pipelines');

my $empty_json = encode_json({ items => [] });
@result = $jq->run_query($empty_json, '.items | enumerate()');
$expected = [];
is_deeply($result[0], $expected, 'enumerate() handles empty arrays');

@result = $jq->run_query($json, 'enumerate()');
is_deeply($result[0], $decoded, 'enumerate() leaves non-array values unchanged');



# Arrays retain one position per element, including null and nested values.
for my $case (
    ['[]', [], 'bare enumerate on an empty array'],
    ['[null]', [{ index => 0, value => undef }], 'null array entry'],
    ['[null,false,{"n":1},[2]]', [
        { index => 0, value => undef },
        { index => 1, value => JSON::PP::false },
        { index => 2, value => { n => 1 } },
        { index => 3, value => [2] },
    ], 'mixed array entries'],
    ['{"a":1}', { a => 1 }, 'object passthrough'],
    ['false', JSON::PP::false, 'boolean passthrough'],
) {
    my ($input, $expected, $label) = @$case;
    my @mapped = $jq->run_query($input, 'enumerate');
    is_deeply(\@mapped, [$expected], $label);
}

my $long_input = [0 .. 256];
my @long_result = $jq->run_query(encode_json($long_input), 'enumerate()');
is(scalar(@long_result), 1, 'long array produces one result');
is(scalar(@{ $long_result[0] }), 257, 'long array has all positions');
is_deeply($long_result[0][0], { index => 0, value => 0 },
    'long array first position');
is_deeply($long_result[0][256], { index => 256, value => 256 },
    'long array last position');

my @stream_results = $jq->run_query(
    encode_json([[], [10], [undef, 'x'], { a => 1 }]),
    '.[] | enumerate()'
);
is_deeply(\@stream_results, [
    [],
    [{ index => 0, value => 10 }],
    [{ index => 0, value => undef }, { index => 1, value => 'x' }],
    { a => 1 },
], 'enumerate preserves stream cardinality, order, and passthrough');

done_testing();
