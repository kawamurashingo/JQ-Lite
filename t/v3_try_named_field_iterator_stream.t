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

subtest 'named field iterators retain completed earlier member results' => sub {
    my $mixed = '{"items":[{"name":"Ada"},3,{"name":"Later"}]}';
    is_deeply(results($mixed, 'try (.items[] | .["name"])'), ['Ada'],
        'no catch drops only the later error');
    is_deeply(results($mixed, 'try (.items[] | .["name"]) catch 42'),
        ['Ada',42], 'catch fallback follows successful earlier member');
    is_deeply(results($mixed, 'try (.items[] | .["name"]) catch null'),
        ['Ada',undef], 'catch null stays a visible result');
    is_deeply(results($mixed, 'try (.items[] | .["name"]) catch empty'),
        ['Ada'], 'catch empty does not remove prior output');
    is_deeply(results($mixed, 'try (.items[]? | .["name"]) catch 42'),
        ['Ada',42], 'optional head does not suppress later strict lookup');
};

subtest 'strict and optional named heads remain distinct' => sub {
    is_deeply(results('{"items":null}',
        'try (.items[]? | .["name"]) catch 42'), [],
        'optional head skips null-valued field');
    is_deeply(results('{"items":null}',
        'try (.items[] | .["name"]) catch 42'), [42],
        'strict head still fails on null');
    is_deeply(results('{"items":3}',
        'try (.items[]? | .["name"]) catch 8'), [],
        'optional head skips a noniterable number');
    is_deeply(results('{"items":[]}',
        'try (.items[] | .["name"]) catch 8'), [],
        'empty array is not an error');
};

subtest 'successful values, multi-stage and comma control cases' => sub {
    is_deeply(results('{"items":[{"name":"Ada"},{"name":"Bea"}]}',
        'try (.items[] | .["name"])'), ['Ada','Bea'],
        'successfully transformed elements retain order');
    is_deeply(results('{"items":[{"name":false},{"name":null},3]}',
        'try (.items[] | .["name"]) catch 8'),
        [JSON::PP::false,undef,8], 'JSON false and null are real values');
    is_deeply(results('{"items":[{"name":"Ada"},3]}',
        'try ((.items[] | .["name"]), 99) catch 8'),
        ['Ada',8], 'error skips later comma branch');
    is_deeply(results('{"items":[{"name":"Ada"},3]}',
        'try (.items[] | .["name"] | tostring) catch 8'),
        ['Ada',8], 'multi-stage tail preserves completed members');
    is_deeply(results('{"items":[{"name":"Ada"},3]}',
        'try (.items[] | .["name"]) catch type'),
        ['Ada','string'], 'catch still processes error string');
};

done_testing;
