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

subtest 'completed middle comma alternatives feed downstream suffix' => sub {
    my $tail = 'range(0;3) | (., 1/0) | tostring';
    is_deeply(results('null', "try ($tail) catch 42"),
        ['0',42], 'first completed alternative flows through tostring');
    is_deeply(results('null', "try ($tail)"),
        ['0'], 'bare try retains completed output');
    is_deeply(results('null', "try ($tail) catch empty"),
        ['0'], 'empty catch does not erase prior result');
    is_deeply(results('null', "try ($tail) catch null"),
        ['0',undef], 'null catch appends a real JSON null');
    is_deeply(results('null', "try ($tail) catch type"),
        ['0','string'], 'error-string handler input remains unchanged');
    is_deeply(results('null', "try ($tail) catch (42,43)"),
        ['0',42,43], 'multiple handler results follow successful output');
    is_deeply(results('null',
        'try (range(0;3) | (. + 1, 1/0) | . + 10) catch 42'),
        [11,42], 'arithmetic suffix runs on completed alternative');
};

subtest 'empty, null, false and multiple successful alternatives' => sub {
    is_deeply(results('null',
        'try (range(0;3) | (null, false, 1/0) | type) catch 42'),
        ['null','boolean',42], 'null and false are passed to type');
    is_deeply(results('null',
        'try (range(0;3) | (., empty, 1/0) | tostring) catch 42'),
        ['0',42], 'empty alternative emits nothing and continues');
    is_deeply(results('null',
        'try (range(0;2) | (., . + 10) | . + 1) catch 42'),
        [1,11,2,12], 'successful comma alternatives preserve per-input order');
    is_deeply(results('null',
        'try (range(0;3) | . + 1 | (., 1/0) | tostring) catch 42'),
        ['1',42], 'an eager preceding transform keeps completed output');
};

subtest 'iterator, recurse, comma and generic heads share the fix' => sub {
    is_deeply(results('[7,8]',
        'try (.[] | (., 1/0) | tostring) catch 42'),
        ['7',42], 'root iterator preserves tail result');
    is_deeply(results('{"items":[7,8]}',
        'try (.items[] | (., 1/0) | tostring) catch 42'),
        ['7',42], 'named iterator preserves tail result');
    is_deeply(results('[[1],[2]]',
        'try (.[][] | (., 1/0) | tostring) catch 42'),
        ['1',42], 'nested iterator preserves tail result');
    is_deeply(results('null',
        'try ((0,1,2) | (., 1/0) | tostring) catch 42'),
        ['0',42], 'comma head preserves completed tail result');
    is_deeply(results('[1,[2]]',
        'try (recurse | (., 1/0) | type) catch 42'),
        ['array',42], 'default recurse preserves root type');
    is_deeply(results('[1,[2]]',
        'try (recurse(.[]) | (., 1/0) | type) catch 42'),
        ['array',42], 'strict recurse preserves root type');
    is_deeply(results('7',
        'try (. | (., 1/0) | tostring) catch 42'),
        ['7',42], 'generic head preserves output');
};

subtest 'comma scope and final-tail control' => sub {
    is_deeply(results('null',
        '0, (try (range(0;3) | (., 1/0) | tostring) catch 42), 9'),
        [0,'0',42,9], 'outer comma branches continue');
    is_deeply(results('null',
        'try ((range(0;3) | (., 1/0) | tostring), 9) catch 42'),
        ['0',42], 'inner comma branch stops after error');
    is_deeply(results('null',
        'try (range(0;3) | (., 1/0)) catch 42'),
        [0,42], 'previous final-tail streaming behavior remains');
};

done_testing;
