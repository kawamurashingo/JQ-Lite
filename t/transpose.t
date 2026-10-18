use strict;
use warnings;

use Test::More;
use JQ::Lite;
use JSON::PP qw(encode_json decode_json);

my $jq = JQ::Lite->new;

my $json = encode_json({ matrix => [ [1, 2, 3], [4, 5, 6] ] });
my @result = $jq->run_query($json, '.matrix | transpose');
my $expected = [ [1, 4], [2, 5], [3, 6] ];
is_deeply($result[0], $expected, 'transpose pivots arrays of arrays');

$json = encode_json({ jagged => [ [1, 2], [3] ] });
@result = $jq->run_query($json, '.jagged | transpose');
$expected = [ [1, 3] ];
is_deeply($result[0], $expected, 'transpose truncates to the shortest row');

$json = encode_json({ numbers => [1, 2, 3] });
my $decoded = decode_json($json);
@result = $jq->run_query($json, '.numbers | transpose');
is_deeply($result[0], $decoded->{numbers}, 'transpose leaves non-nested arrays unchanged');

$json = encode_json({ void => [] });
@result = $jq->run_query($json, '.void | transpose');
$expected = [];
is_deeply($result[0], $expected, 'transpose handles empty arrays');

# Both spellings preserve truncation, empty shapes and scalar passthrough.
for my $case (
    ['[[]]', [], 'empty inner row'],
    ['[[1,2],[]]', [], 'mixed empty and nonempty rows'],
    ['[[1],[2],[3]]', [[1,2,3]], 'single column with three rows'],
    ['[[1,2,3],[4,5]]', [[1,4],[2,5]], 'jagged rows'],
    ['[[null,1],[false,2]]', [
        [undef, JSON::PP::false], [1,2]
    ], 'null and boolean values'],
    ['[[1,2],3]', [[1,2],3], 'mixed outer array passes through'],
    ['null', undef, 'null passes through'],
    ['"raw"', 'raw', 'string passes through'],
) {
    my ($input, $expected, $label) = @$case;
    my @mapped = $jq->run_query($input, 'transpose()');
    is_deeply(\@mapped, [$expected], $label);
}

my $wide_rows = [[0 .. 256], [257 .. 513]];
my @wide_result = $jq->run_query(encode_json($wide_rows), 'transpose');
is(scalar(@wide_result), 1, 'wide transpose yields a single array');
is(scalar(@{ $wide_result[0] }), 257, 'wide transpose keeps all columns');
is_deeply($wide_result[0][0], [0,257], 'wide transpose first column');
is_deeply($wide_result[0][256], [256,513], 'wide transpose final column');

my @stream_results = $jq->run_query(
    encode_json([[[1,2],[3,4]], [], [[5],[6]], 'plain']),
    '.[] | transpose()'
);
is_deeply(\@stream_results, [
    [[1,3],[2,4]], [], [[5,6]], 'plain'
], 'transpose preserves multi-input stream positions and values');

done_testing();
