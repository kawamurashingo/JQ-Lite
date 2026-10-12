use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Error ();

my $jq = JQ::Lite->new;

sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

subtest 'unhandled try errors produce an empty stream' => sub {
    is_deeply(results('null', 'try .[]'), [],
        'strict null iterator error emits no values');
    is_deeply(results('4', 'try .[]'), [],
        'strict number iterator error emits no values');
    is_deeply(results('true', 'try .[]'), [],
        'strict boolean iterator error emits no values');
    is_deeply(results('"hi"', 'try .[]'), [],
        'strict string iterator error emits no values');
    is_deeply(results('null', 'try (1 / 0)'), [],
        'division by zero inside try emits no values');
    is_deeply(results('{"items":null}', 'try .items[]'), [],
        'strict null field iteration is dropped by try');
    is_deeply(results('3', 'try .name'), [],
        'wrong-type named field error is dropped by try');
    is_deeply(results('{"items":7}', 'try .items[0]'), [],
        'wrong-type strict numeric index error is dropped by try');
    is_deeply(results('null', '0, try (1 / 0), 9'), [0,9],
        'failed comma branch does not append null');
    is_deeply(results('null', '0, try .[], 9'), [0,9],
        'comma branch preserves surrounding results');
};

subtest 'iterator suffix stays inside the try expression' => sub {
    is_deeply([JQ::Lite::Parser::parse_query('try .[]')],
        ['try .[]'], 'parser does not split strict iterator out of try');
    is_deeply([JQ::Lite::Parser::parse_query('try .items[]')],
        ['try .items[]'], 'parser preserves named iterator inside try');
    is_deeply([JQ::Lite::Parser::parse_query('0, try .[]')],
        ['0, try .[]'], 'comma alternative keeps iterator inside try');
    is_deeply(results('null', 'try (.[])'), [],
        'parenthesized strict iteration is caught');
    is_deeply(results('null', '0, try .[]'), [0],
        'failed later try branch does not erase prior result');
    is_deeply(results('{"items":[1,2]}', 'try .items[]'), [1,2],
        'valid nested iterator still expands under try');
    is_deeply(results('{"items":null}', 'try .items[]'), [],
        'failed nested strict iterator is caught');
    is_deeply(results('{"items":null}', 'try .items[] catch null'),
        [undef], 'explicit catch can still emit null after iteration');
};

subtest 'successful try values and explicit catches remain distinct' => sub {
    is_deeply(results('null', 'try null'), [undef],
        'successful null is a real value');
    is_deeply(results('null', 'try false'), [JSON::PP::false],
        'successful false is a real value');
    is_deeply(results('null', 'try 0'), [0],
        'successful zero is a real value');
    is_deeply(results('[1,2]', 'try .[]'), [1,2],
        'successful strict iterator preserves two values');
    is_deeply(results('{"one":7}', 'try .[]'), [7],
        'successful object iterator emits value');
    is_deeply(results('{}', 'try .name'), [undef],
        'missing field yields a null result, not an error');
    is_deeply(results('{"name":null}', 'try .name'), [undef],
        'explicit null object field retained');
    is_deeply(results('null', 'try empty'), [],
        'empty success remains empty');
    is_deeply(results('null', 'try .[]?'), [],
        'optional iterator empty success remains empty');
    is_deeply(results('null', 'try .[] catch null'), [undef],
        'explicit catch null still emits one null');
    is_deeply(results('null', 'try (1 / 0) catch null'), [undef],
        'explicit division catch null emits null');
    is_deeply(results('null', 'try (1 / 0) catch 42'), [42],
        'explicit constant catch still works');
    is_deeply(results('null', 'try (1 / 0) catch empty'), [],
        'explicit catch empty still omits the value');
    is_deeply(results('null', 'try []'), [[]],
        'try empty array constructor still emits one array');
    is_deeply(results('null', 'try [ ]'), [[]],
        'try whitespace empty array constructor still works');
    is_deeply(results('null', 'try ["catch me"]'),
        [['catch me']], 'try nonempty literal still works');
};

done_testing;
