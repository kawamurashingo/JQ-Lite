use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $json = <<'JSON';
{
  "name": "Alice",
  "age": 30,
  "tiny": 1e-40,
  "huge": 1e40,
  "sci": "1e6",
  "active": true,
  "profile": {
    "country": "US"
  },
  "tags": ["perl", "json"],
  "empty": null
}
JSON

my $jq = JQ::Lite->new;

is_deeply([$jq->run_query($json, '.name | type')], ['string'], 'type of string');
is_deeply([$jq->run_query($json, '.age | type')], ['number'], 'type of number');
is_deeply([$jq->run_query($json, '.tiny | type')], ['number'], 'type treats scientific notation as number (tiny)');
is_deeply([$jq->run_query($json, '.huge | type')], ['number'], 'type treats scientific notation as number (huge)');
is_deeply([$jq->run_query($json, '.sci | type')], ['string'], 'type does not misclassify numeric-looking strings');
is_deeply([$jq->run_query($json, '.active | type')], ['boolean'], 'type of boolean');
is_deeply([$jq->run_query($json, '.profile | type')], ['object'], 'type of object');
is_deeply([$jq->run_query($json, '.tags | type')], ['array'], 'type of array');
is_deeply([$jq->run_query($json, '.empty | type')], ['null'], 'type of null');


my $decoder = JSON::PP->new->allow_nonref;
my @comparison_cases = (
    [ 'null', '"10" == 10', '[false]', 'string-number-distinct' ],
    [ 'null', '"10" != 10', '[true]', 'string-number-inequality' ],
    [ 'null', '"10" < "2"', '[true]', 'string-lexical-order' ],
    [ 'null', '10 < 2', '[false]', 'number-order' ],
    [ 'null', 'true == 1', '[false]', 'boolean-number-distinct' ],
    [ 'null', 'null == false', '[false]', 'null-false-distinct' ],
    [ 'null', 'false < true', '[true]', 'false-before-true' ],
    [ 'null', 'true < 0', '[true]', 'true-before-number' ],
    [ 'null', '0 < ""', '[true]', 'number-before-string' ],
    [ 'null', '"" < []', '[true]', 'string-before-array' ],
    [ 'null', '[] < {}', '[true]', 'array-before-object' ],
    [ 'null', '[1,2] < [1,3]', '[true]', 'array-lexical' ],
    [ 'null', '[1,2] < [1,2,0]', '[true]', 'array-prefix' ],
    [ 'null', '[1,2,0] > [1,2]', '[true]', 'array-prefix-reverse' ],
    [ 'null', '[1,2] == [1,2,0]', '[false]', 'array-prefix-equality' ],
    [ 'null', '[] < [0]', '[true]', 'array-empty-order' ],
    [ 'null', '["1"] == [1]', '[false]', 'array-nested-type' ],
    [ 'null', '[2] < [10]', '[true]', 'array-number-order' ],
    [ 'null', '["a+b",{}] == ["a+b",{}]', '[true]', 'array-compound-literals' ],
    [ 'null', '{"a":1,"b":2} == {"b":2,"a":1}', '[true]', 'object-equal' ],
    [ 'null', '{"a":"1"} == {"a":1}', '[false]', 'object-nested-type' ],
    [ 'null', '{"a":99} < {"b":0}', '[true]', 'object-key-order' ],
    [ 'null', '{"a":2} < {"a":10}', '[true]', 'object-value-order' ],
    [ 'null', '{} == {}', '[true]', 'object-empty-equality' ],
    [ 'null', '[1] <= [1]', '[true]', 'comparison-less-equal' ],
    [ 'null', '[1] >= [1]', '[true]', 'comparison-greater-equal' ],
    [ '[{"x":"10"},{"x":10},{"x":null},{}]', '.[] | select(.x == 10)', '[{"x":10}]', 'select-numeric-type' ],
    [ '[{"x":"10"},{"x":10}]', '.[] | select(.x == "10")', '[{"x":"10"}]', 'select-string-type' ],
    [ '[{"x":null},{}]', '.[] | select(.x == null)', '[{"x":null},{}]', 'select-null-and-missing' ],
    [ '[{"x":{"a":1}},{"x":{"a":"1"}}]', '.[] | select(.x == {"a":1})', '[{"x":{"a":1}}]', 'select-object-value' ],
    [ '[{"x":[2]},{"x":[10]},{"x":[11]}]', '.[] | select(.x < [10])', '[{"x":[2]}]', 'select-array-order' ],
    [ '{"x":"10","y":10}', '.x == .y', '[false]', 'ordinary-path-comparison' ],
    [ '[null,false,true,0,"0",[],{}]', '.[] | type', '["null","boolean","boolean","number","string","array","object"]', 'type-json-values' ],
    [ 'null', '["42",42,true,false,null,[],{}] | map(type)', '[["string","number","boolean","boolean","null","array","object"]]', 'type-literal-constructors' ],
    [ '10', '(tostring, .) | type', '["string","number"]', 'type-after-number-string-cache' ],
 );
for my $case (@comparison_cases) {
    my ($input, $query, $expected, $name) = @$case;
    is_deeply([ $jq->run_query($input, $query) ], $decoder->decode($expected), $name);
}

# Empty streams remain empty; an explicit JSON null still has type null.
is_deeply([ $jq->run_query('null', 'empty | type') ], [],
    'type does not synthesize a null from an empty stream');

is_deeply([ $jq->run_query('null', 'empty == null') ], [],
    'comparison does not synthesize a null from an empty operand');

done_testing();

