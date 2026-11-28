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

subtest 'nested range without comma retains completed outputs' => sub {
    is_deeply(results('null', "try (. | ($gen)) catch 42"),
        [0,1,42], 'completed inner outputs precede caught error');
    is_deeply(results('null', "try (. | ($gen))"),
        [0,1], 'no-catch preserves completed values');
    is_deeply(results('null', "try (. | ($gen)) catch empty"),
        [0,1], 'empty catch preserves prior outputs');
    is_deeply(results('null', "try (. | ($gen)) catch null"),
        [0,1,undef], 'explicit null catch appends one real null');
    is_deeply(results('null', "try (. | ($gen)) catch type"),
        [0,1,'string'], 'error reaches handler as string');
    is_deeply(results('null', "try (. | ($gen)) catch (42,43)"),
        [0,1,42,43], 'handler output multiplicity remains intact');
    is_deeply(results('null', "try (. | ($gen) | tostring) catch 42"),
        ['0','1',42], 'suffix observes preceding inner range values');
    is_deeply(results('null', "try (. | ($gen) | (., .+10)) catch 42"),
        [0,10,1,11,42], 'comma suffix receives each completed output');
    is_deeply(results('null', "try (. | (($gen))) catch 42"),
        [0,1,42], 'another layer of balanced parentheses is valid');
};

subtest 'outer generators and simple input selectors' => sub {
    is_deeply(results('null', "try (range(1;3) | ($gen)) catch 42"),
        [0,1,42], 'later outer range inputs are not requested');
    is_deeply(results('[5,6]', "try (.[] | ($gen)) catch 42"),
        [0,1,42], 'later array members are not processed');
    is_deeply(results('{"items":[5,6]}',
        "try (.items[] | ($gen)) catch 42"),
        [0,1,42], 'named iterator yields the same partial stream');
    is_deeply(results('[5,6]', "try (.[0] | ($gen)) catch 42"),
        [0,1,42], 'array-index selector is a valid prefix');
    is_deeply(results('{"foo":5}', "try (.foo | ($gen)) catch 42"),
        [0,1,42], 'field selector is a valid prefix');
};

subtest 'successful and filtered values remain distinct' => sub {
    is_deeply(results('null', 'try (. | (range(0;0) | . + 1))'),
        [], 'empty range stays an empty stream');
    is_deeply(results('null', 'try (. | (range(0;3) | . + 1))'),
        [1,2,3], 'successful nested range outputs retain order');
    is_deeply(results('null',
        'try (. | (range(0;3) | . + 1) | tostring)'),
        ['1','2','3'], 'downstream transform retains order');
    is_deeply(results('null',
        'try (. | (range(0;4) | if . == 2 then (1/0) else null end)) catch 42'),
        [undef,undef,42], 'completed null values remain visible');
    is_deeply(results('null',
        'try (. | (range(0;4) | if . == 2 then (1/0) else false end)) catch 42'),
        [JSON::PP::false,JSON::PP::false,42],
        'completed false values remain visible');
    is_deeply(results('null',
        'try (. | (range(0;4) | if . == 2 then (1/0) else empty end)) catch 42'),
        [42], 'empty filter skips prior values but not the later error');
};

subtest 'very large nested range and previous controls' => sub {
    is_deeply(results('null',
        'try (. | (range(1000000000) | if . == 2 then (1/0) else . end)) catch 42'),
        [0,1,42], 'billion-item nested range stops at first error');
    is_deeply(results('null', "try (. | (($gen),99)) catch 42"),
        [0,1,42], 'prior nested comma routing remains unchanged');
    is_deeply(results('null',
        'try (range(0;4) | if . == 2 then (1/0) else . end) catch 42'),
        [0,1,42], 'unwrapped range generator remains unchanged');
};

done_testing;
