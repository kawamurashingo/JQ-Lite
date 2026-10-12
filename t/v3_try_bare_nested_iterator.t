use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq = JQ::Lite->new;

sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

subtest 'bare nested root iterators emit member values' => sub {
    is_deeply(results('[[1],[2]]', 'try .[][]'), [1,2],
        'bare nested root iterator emits two values');
    is_deeply(results('[[1],3,[2]]', 'try .[][]'), [1],
        'no catch retains completed values before strict inner error');
    is_deeply(results('[[1],3,[2]]', 'try .[][] catch 42'), [1,42],
        'catch follows the preceding value');
    is_deeply(results('[[1],3,[2]]', 'try .[][] catch null'), [1,undef],
        'explicit null remains distinct from an empty stream');
    is_deeply(results('[[1],3,[2]]', 'try .[][] catch empty'), [1],
        'explicit empty suppresses only the failed path');
    is_deeply(results('[[1],3,[2]]', 'try .[][] catch type'),
        [1,'string'], 'catch receives the error string');
    is_deeply(results('[[1],3,[2]]', 'try .[][]?'), [1,2],
        'optional inner iterator skips the scalar member');
    is_deeply(results('[[1],3,[2]]', 'try .[]?[] catch 42'), [1,42],
        'optional outer iterator does not suppress a strict inner error');
    is_deeply(results('[[null,false],3]', 'try .[][] catch 42'),
        [undef, JSON::PP::false,42],
        'completed JSON null and false values are retained');
    is_deeply(results('[]', 'try .[][]'), [],
        'empty root produces no synthetic null');
};

subtest 'bare nested named field iterators' => sub {
    is_deeply(results('{"items":[[1],[2]]}', 'try .items[][]'), [1,2],
        'named double iterator emits its two values');
    is_deeply(results('{"items":[[1],3,[2]]}',
        'try .items[][] catch 42'), [1,42],
        'later inner error emits one fallback after prior result');
    is_deeply(results('{"items":[[1],3,[2]]}', 'try .items[][]'), [1],
        'bare named iterator with no catch retains partial success');
    is_deeply(results('{"items":[[1],3,[2]]}', 'try .items[][]?'), [1,2],
        'optional inner named stage skips scalar');
    is_deeply(results('{"items":null}', 'try .items[]?[] catch 42'), [],
        'optional outer named stage skips a null field');
};

subtest 'comma and single-stage controls' => sub {
    is_deeply(results('[[1],3,[2]]', '0, try .[][], 9'), [0,1,9],
        'outside comma alternatives continue after the try');
    is_deeply(results('[[1],3,[2]]', 'try (.[][], 9) catch 42'),
        [1,42], 'inside comma alternatives stop at the first error');
    is_deeply(results('[1,2]', 'try .[]'), [1,2],
        'single strict iterator remains unaffected');
    is_deeply(results('null', 'try []'), [[]],
        'empty-array constructor still emits an empty array');
};

done_testing;
