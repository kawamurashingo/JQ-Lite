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

subtest 'final comma tail preserves completed results before error' => sub {
    my $filter = 'range(0;3) | (., 1/0)';
    is_deeply(results('null', "try ($filter) catch 42"),
        [0,42], 'first complete comma result precedes catch');
    is_deeply(results('null', "try ($filter)"),
        [0], 'no-catch suppresses error without erasing output');
    is_deeply(results('null', "try ($filter) catch null"),
        [0,undef], 'catch null appends real JSON null');
    is_deeply(results('null', "try ($filter) catch empty"),
        [0], 'catch empty retains complete outputs');
    is_deeply(results('null', "try ($filter) catch type"),
        [0,'string'], 'handler input stays the error string');
    is_deeply(results('null', "try ($filter) catch (42,43)"),
        [0,42,43], 'multi-result handler follows prior outputs');
    is_deeply(results('null',
        'try (range(0;3) | (null, false, 1/0)) catch 42'),
        [undef,JSON::PP::false,42],
        'null and false are outputs before the last error');
    is_deeply(results('null',
        'try (range(0;3) | (., empty, 1/0)) catch 42'),
        [0,42], 'empty alternative emits nothing but continues');
};

subtest 'multi-stage and successful tail comma streams' => sub {
    is_deeply(results('null',
        'try (range(0;2) | (. + 1, . + 2)) catch 42'),
        [1,2,2,3], 'all successful final alternatives run per input');
    is_deeply(results('null',
        'try (range(0;3) | . + 1 | (., 1/0)) catch 42'),
        [1,42], 'preceding transform completes before comma tail');
    is_deeply(results('null',
        'try (range(0;3) | select(. > 1) | (., 1/0)) catch 42'),
        [2,42], 'filtered-out upstream values are skipped');
};

subtest 'existing generators and general head feed final comma tail' => sub {
    is_deeply(results('[7,8]', 'try (.[] | (., 1/0)) catch 42'),
        [7,42], 'strict root iterator emits earlier tail result');
    is_deeply(results('{"items":[7,8]}',
        'try (.items[] | (., 1/0)) catch 42'),
        [7,42], 'named-field iterator behaves the same');
    is_deeply(results('[[1],[2]]', 'try (.[][] | (., 1/0)) catch 42'),
        [1,42], 'nested iterator uses final comma handler');
    is_deeply(results('null', 'try ((0,1,2) | (., 1/0)) catch 42'),
        [0,42], 'comma-head alternatives feed final comma stage');
    is_deeply(results('[1,[2]]', 'try (recurse | (., 1/0)) catch 42'),
        [[1,[2]],42], 'recurse root output survives final error');
    is_deeply(results('[1,[2]]',
        'try (recurse(.[]) | (., 1/0)) catch 42'),
        [[1,[2]],42], 'strict recurse stops before expanding root');
    is_deeply(results('7', 'try (. | (., 1/0)) catch 42'),
        [7,42], 'ordinary identity head is also streamed');
};

subtest 'comma controls and outer try behavior remain distinct' => sub {
    is_deeply(results('null',
        '0, (try (range(0;3) | (., 1/0)) catch 42), 9'),
        [0,0,42,9], 'outside comma continues after caught error');
    is_deeply(results('null',
        'try ((range(0;3) | (., 1/0)), 99) catch 42'),
        [0,42], 'inside comma skips later branch after error');
    is_deeply(results('null', 'try (0, (1/0), 9) catch 42'),
        [0,42], 'standalone comma try retains previous semantics');
};

done_testing;
