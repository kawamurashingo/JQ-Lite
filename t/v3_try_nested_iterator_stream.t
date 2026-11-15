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

subtest 'nested root iterators keep earlier completed outputs' => sub {
    my $mixed = '[[{"name":"Ada"}],[3],[{"name":"Later"}]]';
    is_deeply(results($mixed,
        'try (.[][] | .["name"]) catch 42'), ['Ada', 42],
        'the later bad inner member stops evaluation and invokes catch');
    is_deeply(results($mixed,
        'try (.[][] | .["name"])'), ['Ada'],
        'no catch retains only the completed output');
    is_deeply(results($mixed,
        'try (.[][] | .["name"]) catch null'), ['Ada', undef],
        'catch null appends one real JSON null');
    is_deeply(results($mixed,
        'try (.[][] | .["name"]) catch empty'), ['Ada'],
        'catch empty keeps earlier completed output');
    is_deeply(results($mixed,
        'try (.[][] | .["name"]) catch type'), ['Ada','string'],
        'catch receives the error message string');
    is_deeply(results($mixed,
        'try (.[][] | .["name"] | tostring) catch 42'),
        ['Ada',42], 'multi-stage tail preserves completed elements');
    is_deeply(results($mixed,
        'try ((.[][] | .["name"]), 99) catch 42'),
        ['Ada',42], 'later comma branches are skipped after error');
};

subtest 'an invalid inner iterator fails after earlier members' => sub {
    my $mixed = '[[1],3,[2]]';
    is_deeply(results($mixed, 'try (.[][] | .) catch 42'), [1,42],
        'strict inner iterator invokes catch at the first scalar');
    is_deeply(results($mixed, 'try (.[][] | .)'), [1],
        'no-catch drops only the failing member and later members');
    is_deeply(results($mixed, 'try (.[][]? | .) catch 42'), [1,2],
        'optional second iterator skips scalar inner members');
    is_deeply(results($mixed, 'try (.[]?[] | .) catch 42'), [1,42],
        'optional outer iterator does not suppress strict inner errors');
    is_deeply(results('[[null,false],3]',
        'try (.[][] | .) catch 42'), [undef, JSON::PP::false,42],
        'null and false are retained before inner iterator error');
};

subtest 'named nested iterator heads and controls' => sub {
    is_deeply(results('{"items":[[{"name":"Ada"}],[3],[{"name":"Later"}]]}',
        'try (.items[][] | .["name"]) catch 42'), ['Ada',42],
        'named double iterator preserves completed earlier members');
    is_deeply(results('{"items":[[1],3,[2]]}',
        'try (.items[][] | .) catch 42'), [1,42],
        'named strict inner iterator raises at the scalar member');
    is_deeply(results('{"items":[[1],3,[2]]}',
        'try (.items[][]? | .) catch 42'), [1,2],
        'named optional inner iterator skips scalar members');
    is_deeply(results('{"items":null}',
        'try (.items[]?[] | .) catch 42'), [],
        'optional outer named iterator skips null field');
    is_deeply(results('[[1,2],[3]]',
        'try (.[][] | . + 10)'), [11,12,13],
        'fully successful nested stream keeps source order');
    is_deeply(results('[]',
        'try (.[][] | .) catch 42'), [],
        'empty root input yields no values');
};

done_testing;
