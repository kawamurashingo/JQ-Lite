use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JSON::PP ();

my $jq = JQ::Lite->new;

sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

subtest 'an empty catch filter never manufactures JSON null' => sub {
    for my $json ('null', '3', 'true', '"hello"') {
        is_deeply(results($json, 'try (1 / 0) catch .[]?'), [],
            "optional catch iterator on $json produces no values");
    }
    is_deeply(results('null', 'try (1 / 0) catch (.[]?)'), [],
        'parenthesized optional catch iterator stays empty');
    is_deeply(results('null', 'try (1 / 0) catch (empty | 9)'), [],
        'catch pipeline with an empty first stage stays empty');
    is_deeply(results('null', '0, (try (1 / 0) catch .[]?), 9'),
        [0, 9], 'empty catch preserves surrounding comma alternatives');
};

subtest 'successful try and real catch values are unchanged' => sub {
    is_deeply(results('null', 'try 5 catch .[]?'), [5],
        'successful try never runs the catch handler');
    is_deeply(results('null', 'try (1 / 0) catch null'), [undef],
        'explicit catch null still returns one null');
    is_deeply(results('null', 'try (1 / 0) catch empty'), [],
        'explicit catch empty continues returning no values');
    is_deeply(results('{"num":1,"den":0}',
        '. as $original | try (.num / .den) catch $original.den'), [0],
        'bound original input remains available in a catch handler');
};

done_testing;
