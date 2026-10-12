use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq = JQ::Lite->new;

sub query_results {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

subtest 'direct missing object field produces one null' => sub {
    is_deeply(query_results('{}', '.missing'), [undef], 'missing field');
    is_deeply(query_results('{"a":1}', '.missing'), [undef], 'unrelated field');
    is_deeply(query_results('{"a":null}', '.a'), [undef], 'explicit null remains null');
    is_deeply(query_results('{"a":0}', '.a'), [0], 'zero is not missing');
};

subtest 'object field traversal through a missing or null value' => sub {
    is_deeply(query_results('{}', '.missing.value'), [undef], 'missing field chain');
    is_deeply(query_results('{"a":{}}', '.a.missing'), [undef], 'nested missing field');
    is_deeply(query_results('{"a":null}', '.a.b'), [undef], 'traversal through explicit null');
    is_deeply(query_results('null', '.a'), [undef], 'field access on null remains null');
    is_deeply(query_results('{}', '.missing?'), [undef], 'optional missing object field yields one JSON null');
    is_deeply(query_results('{"a":{"b":3}}', '.a.b'), [3], 'present nested field');
};

subtest 'do not confuse zero output with a null result' => sub {
    is_deeply(query_results('[]', '.[]'), [], 'empty array iterator emits nothing');
    is_deeply(query_results('{"a":[]}', '.a[]'), [], 'empty nested iterator emits nothing');
    is_deeply(query_results('{"a":[]}', '.a.value'), [], 'existing array projection semantics unchanged');
    is_deeply(query_results('{"a":[{"b":1},{}]}', '.a[].b'),
        [1, undef], 'iterator keeps missing object field as null');
};


my $decoder = JSON::PP->new->allow_nonref;
my @field_cases = (
    [ '{"type":"vm"}', '.type', '["vm"]', 'field-type' ],
    [ '{"length":99}', '.length', '[99]', 'field-length' ],
    [ '{"empty":null}', '.empty', '[null]', 'field-empty' ],
    [ '{"null":7}', '.null', '[7]', 'field-null' ],
    [ '{"true":false}', '.true', '[false]', 'field-true' ],
    [ '{"false":1}', '.false', '[1]', 'field-false' ],
    [ '{"keys":["a","b"]}', '.keys', '[["a","b"]]', 'field-keys' ],
    [ '{"values":false}', '.values', '[false]', 'field-values' ],
    [ '{"sum":4}', '.sum', '[4]', 'field-sum' ],
    [ '{"if":5}', '.if', '[5]', 'field-if' ],
    [ '{"config":{"type":"vm"}}', '.config.type', '["vm"]', 'field-nested-type' ],
    [ '{}', '.type', '[null]', 'field-missing-type' ],
    [ 'null', '.type', '[null]', 'field-null-context' ],
    [ '{"type":99}', '.type | type', '["number"]', 'field-then-type' ],
    [ '{"empty":null}', '.empty | type', '["null"]', 'field-null-then-type' ],
    [ 'null', 'empty | type', '[]', 'empty-then-type' ],
    [ '[]', '.[] | type', '[]', 'empty-iterator-then-type' ],
    [ 'null', 'select(false) | type', '[]', 'filtered-empty-then-type' ],
    [ '{}', '.missing[]? | type', '[]', 'optional-empty-then-type' ],
    [ 'null', 'empty | .type', '[]', 'empty-then-field' ],
    [ '{"type":"vm"}', 'type', '["object"]', 'bare-type' ],
    [ '{"length":99}', 'length', '[1]', 'bare-length' ],
    [ '{"type":"vm","length":99}', '.type, .length', '["vm",99]', 'field-comma' ],
    [ '[{"type":"vm"},{"type":"k8s"}]', '.[] | .type', '["vm","k8s"]', 'field-after-iteration' ],
    [ '{"type":"vm","length":99,"empty":null}', '{type,length,empty}', '[{"type":"vm","length":99,"empty":null}]', 'field-shorthand' ],
 );
for my $case (@field_cases) {
    my ($input, $filter, $expected, $name) = @$case;
    is_deeply(query_results($input, $filter), $decoder->decode($expected), $name);
}

is_deeply(query_results('[{"type":"vm"},{"type":"k8s"}]', '.type'),
    ['vm','k8s'], 'existing array projection extension remains available');
is_deeply(query_results('[]', '.name'), [],
    'existing empty array projection stays empty');

done_testing;
