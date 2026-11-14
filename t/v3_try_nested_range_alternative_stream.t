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
my $gen = 'range(0;4) | if . == 2 then (1/0) else . end';

subtest 'nested range alternative retains completed values before error' => sub {
    is_deeply(results('null', "try (. | (($gen), 99)) catch 42"),
        [0,1,42], 'streamed range results survive a later inner failure');
    is_deeply(results('null', "try (. | (($gen), 99))"),
        [0,1], 'no catch retains earlier finished values');
    is_deeply(results('null', "try (. | (($gen), 99)) catch empty"),
        [0,1], 'empty handler does not erase results');
    is_deeply(results('null', "try (. | (($gen), 99)) catch null"),
        [0,1,undef], 'null handler emits one real null');
    is_deeply(results('null', "try (. | (($gen), 99)) catch type"),
        [0,1,'string'], 'catch still receives error as string');
    is_deeply(results('null', "try (. | (($gen), 99)) catch (42,43)"),
        [0,1,42,43], 'multiple handler results follow emitted values');
    is_deeply(results('null', "try (. | (($gen), 99) | tostring) catch 42"),
        ['0','1',42], 'each emitted value passes through suffix');
    is_deeply(results('null', "try (. | (($gen), 99) | (., . + 10)) catch 42"),
        [0,10,1,11,42], 'suffix comma alternatives retain depth-first order');
};

subtest 'generator input, nesting and sibling order' => sub {
    is_deeply(results('null', "try (range(1;3) | (($gen), 99)) catch 42"),
        [0,1,42], 'the first outer generator input fails before later inputs');
    is_deeply(results('null', "try (. | ((($gen),99),100)) catch 42"),
        [0,1,42], 'two wrapped comma layers keep completed outputs');
    is_deeply(results('null', "try (. | (0, ($gen), 99)) catch 42"),
        [0,0,1,42], 'prior outer sibling precedes the generator stream');
    is_deeply(results('[4,5]', "try (.[] | (($gen), 99)) catch 42"),
        [0,1,42], 'iterator only visits first input before caught error');
    is_deeply(results('null', "try (. | (($gen),99) | (.,1/0)) catch 42"),
        [0,42], 'downstream failure stops generator early');
};

subtest 'null, false, empty and complete inner generator' => sub {
    is_deeply(results('null',
        'try (. | ((range(0;4) | if . == 2 then (1/0) else null end),99)) catch 42'),
        [undef,undef,42], 'completed null outputs are visible');
    is_deeply(results('null',
        'try (. | ((range(0;4) | if . == 2 then (1/0) else false end),99)) catch 42'),
        [JSON::PP::false,JSON::PP::false,42],
        'completed false outputs are visible');
    is_deeply(results('null',
        'try (. | ((range(0;4) | if . == 2 then (1/0) else empty end),99)) catch 42'),
        [42], 'an empty tail skips values but not later errors');
    is_deeply(results('null',
        'try (. | ((range(0;3) | . + 1),99))'),
        [1,2,3,99], 'successful inner range continues to later sibling');
    is_deeply(results('null',
        'try (. | ((range(0;3) | . + 1),99) | tostring)'),
        ['1','2','3','99'], 'successful suffix output order is stable');
};

subtest 'huge inner range stops at the first error' => sub {
    is_deeply(results('null',
        'try (. | ((range(1000000000) | if . == 2 then (1/0) else . end),99)) catch 42'),
        [0,1,42], 'billion-item nested range is not fully materialized');
};

subtest 'controls for previous nested comma and range visitors' => sub {
    is_deeply(results('7', 'try (. | ((0,1/0),99)) catch 42'),
        [0,42], 'ordinary nested comma alternative is unchanged');
    is_deeply(results('null',
        'try (range(0;4) | if . == 2 then (1/0) else . end) catch 42'),
        [0,1,42], 'top-level lazy range path remains unchanged');
};

done_testing;
