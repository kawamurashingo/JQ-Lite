use strict;
use warnings;
use Test::More;
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

done_testing;
