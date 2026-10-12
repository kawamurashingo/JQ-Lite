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

subtest 'second comma stage failure preserves earlier completed output' => sub {
    my $body = 'range(0;2) | (., . + 10) | (., 1/0)';
    is_deeply(results('null', "try ($body) catch 42"),
        [0,42], 'first completed suffix output precedes catch');
    is_deeply(results('null', "try ($body)"), [0],
        'bare try suppresses error after completed output');
    is_deeply(results('null', "try ($body) catch null"), [0,undef],
        'real null fallback is retained');
    is_deeply(results('null', "try ($body) catch empty"), [0],
        'empty fallback does not remove prior output');
    is_deeply(results('null', "try ($body) catch type"),
        [0,'string'], 'caught error is the handler string input');
    is_deeply(results('null', "try ($body) catch (42,43)"),
        [0,42,43], 'multiple handler outputs follow prior values');
    is_deeply(results('null',
        'try (range(0;2) | (., . + 10) | (., 1/0) | tostring) catch 42'),
        ['0',42], 'completed middle result flows through suffix');
    is_deeply(results('null',
        'try (range(0;2) | (., 1/0) | (., . + 100)) catch 42'),
        [0,100,42], 'failure in first comma stage follows completed suffix');
};

subtest 'multiple successful stages retain depth-first order' => sub {
    is_deeply(results('null',
        'try (range(0;2) | (., . + 10) | (., . + 100))'),
        [0,100,10,110,1,101,11,111],
        'second stage completes for each output of first stage');
    is_deeply(results('null',
        'try (range(0;2) | (., . + 10) | (., . + 100) | tostring)'),
        ['0','100','10','110','1','101','11','111'],
        'trailing string transform retains stream order');
    is_deeply(results('null',
        'try (range(0;2) | (., . + 10) | (., . + 100) | (., 1/0)) catch 42'),
        [0,42], 'three comma stages stop on first error');
    is_deeply(results('null',
        'try (range(0;2) | (null, false) | (., 1/0)) catch 42'),
        [undef,42], 'null is a completed output before the error');
    is_deeply(results('null',
        'try (range(0;2) | (empty, .) | (., 1/0)) catch 42'),
        [0,42], 'empty alternative skips its own input');
};

subtest 'source visitors and generic input share stage ordering' => sub {
    is_deeply(results('[1,2]',
        'try (.[] | (., . + 10) | (., 1/0)) catch 42'),
        [1,42], 'root iterator stream preserves first output');
    is_deeply(results('{"items":[1,2]}',
        'try (.items[] | (., . + 10) | (., 1/0)) catch 42'),
        [1,42], 'named iterator behaves the same');
    is_deeply(results('[[1],[2]]',
        'try (.[][] | (., . + 10) | (., 1/0)) catch 42'),
        [1,42], 'nested iterator behaves the same');
    is_deeply(results('[1,[2]]',
        'try (recurse | (., 0) | (., 1/0)) catch 42'),
        [[1,[2]],42], 'default recurse preserves root output');
    is_deeply(results('[1,[2]]',
        'try (recurse(.[]) | (., 0) | (., 1/0)) catch 42'),
        [[1,[2]],42], 'strict recurse preserves root output');
    is_deeply(results('null',
        'try ((0,1) | (., . + 10) | (., 1/0)) catch 42'),
        [0,42], 'parenthesized comma head is streamed');
    is_deeply(results('1',
        'try (. | (., . + 10) | (., 1/0)) catch 42'),
        [1,42], 'non-generator head is streamed');
};

subtest 'outer try bounds and previous one-stage behavior' => sub {
    is_deeply(results('null',
        '0, (try (range(0;2) | (., . + 10) | (., 1/0)) catch 42), 9'),
        [0,0,42,9], 'outside comma continues after catch');
    is_deeply(results('null',
        'try ((range(0;2) | (., . + 10) | (., 1/0)), 9) catch 42'),
        [0,42], 'later inside comma alternative is not evaluated');
    is_deeply(results('null',
        'try (range(0;2) | (., 1/0) | tostring) catch 42'),
        ['0',42], 'one middle comma stage remains unchanged');
};

done_testing;
