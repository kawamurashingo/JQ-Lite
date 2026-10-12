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

subtest 'simple range generator keeps earlier values before a tail error' => sub {
    my $expr = 'range(0;5) | if . == 3 then (1 / 0) else . end';
    is_deeply(results('null', "try ($expr) catch 42"), [0,1,2,42],
        'catch follows three already completed range results');
    is_deeply(results('null', "try ($expr)"), [0,1,2],
        'try without catch suppresses only later failure');
    is_deeply(results('null', "try ($expr) catch empty"), [0,1,2],
        'catch empty retains prior range results');
    is_deeply(results('null', "try ($expr) catch null"), [0,1,2,undef],
        'catch null emits a real null after earlier outputs');
    is_deeply(results('null', "try ($expr) catch type"),
        [0,1,2,'string'], 'error-string handler input remains intact');
    is_deeply(results('null',
        'try (range(1;9;2) | if . == 5 then (1 / 0) else . end) catch 42'),
        [1,3,42], 'stepped range preserves earlier completed numbers');
    is_deeply(results('null',
        'try (range(10;1;-3) | if . == 4 then (1 / 0) else . end) catch 42'),
        [10,7,42], 'descending range stops after failure');
};

subtest 'empty and filtered range streams stay empty or ordered' => sub {
    is_deeply(results('null', 'try (range(0;0) | . + 1) catch 42'),
        [], 'empty range produces no fake null or error');
    is_deeply(results('null', 'try (range(0;3) | . + 1) catch 42'),
        [1,2,3], 'successful transformation preserves range sequence');
    is_deeply(results('null', 'try (range(0;5) | select(. > 2)) catch 42'),
        [3,4], 'filtered-out numbers do not stop later numbers');
    is_deeply(results('null', 'try (range(0;3) | .[]?) catch 42'),
        [], 'optional iterator drops noniterable numeric values');
    is_deeply(results('null', 'try (range(0;3) | .[]) catch 42'),
        [42], 'strict downstream iterator fails on first number');
    is_deeply(results('null', 'try (range("foo") | .) catch 42'),
        [42], 'invalid range bounds are still caught');
    is_deeply(results('null', 'try range(0;3)'), [0,1,2],
        'ordinary no-tail range remains unchanged');
};

subtest 'comma, null and false outputs remain distinguishable' => sub {
    is_deeply(results('null',
        'try ((range(0;5) | if . == 3 then (1 / 0) else . end), 99) catch 42'),
        [0,1,2,42], 'later comma branch is skipped after failure');
    is_deeply(results('null',
        '0, (try (range(0;5) | if . == 3 then (1 / 0) else . end) catch 42), 9'),
        [0,0,1,2,42,9], 'outside comma continues after caught error');
    is_deeply(results('null',
        'try (range(0;5) | if . == 3 then (1 / 0) else null end) catch 42'),
        [undef,undef,undef,42], 'null outputs are values, not omissions');
    is_deeply(results('null',
        'try (range(0;5) | if . == 2 then (1 / 0) else false end) catch 42'),
        [JSON::PP::false,JSON::PP::false,42], 'false values precede fallback');
    is_deeply(results('null',
        'try (range(0;5) | . + 1 | if . == 4 then (1 / 0) else . end) catch 42'),
        [1,2,3,42], 'multi-stage tails retain earlier values');
};

subtest 'large range stops as soon as the tail fails' => sub {
    is_deeply(results('null',
        'try (range(1000000000) | if . == 3 then (1 / 0) else . end) catch 42'),
        [0,1,2,42],
        'a billion-item range is not materialized after the early error');
};

done_testing;
