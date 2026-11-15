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

subtest 'nested inner comma errors retain completed values' => sub {
    my $body = '. | ((0, 1/0), 9)';
    is_deeply(results('7', "try ($body) catch 42"),
        [0,42], 'first nested output survives later error');
    is_deeply(results('7', "try ($body)"),
        [0], 'no catch retains prior completed value');
    is_deeply(results('7', "try ($body) catch null"),
        [0,undef], 'null catch is one real output');
    is_deeply(results('7', "try ($body) catch empty"),
        [0], 'empty catch does not erase output');
    is_deeply(results('7', "try ($body) catch type"),
        [0,'string'], 'catch receives an error string');
    is_deeply(results('7', "try ($body) catch (42,43)"),
        [0,42,43], 'multiple handler results are appended');
    is_deeply(results('7', 'try (. | (((0,1/0),9),10)) catch 42'),
        [0,42], 'three layers of parenthesized alternatives');
    is_deeply(results('7', 'try (. | (9, (0,1/0))) catch 42'),
        [9,0,42], 'earlier outer and inner alternatives persist');
};

subtest 'nested success, empty, null and false' => sub {
    is_deeply(results('7', 'try (. | (((0,1),2),3))'),
        [0,1,2,3], 'nested alternatives retain depth-first order');
    is_deeply(results('7', 'try (. | (((0,1),2),3) | tostring)'),
        ['0','1','2','3'], 'each completed value feeds the suffix');
    is_deeply(results('7', 'try (. | ((null,false),1/0)) catch 42'),
        [undef,JSON::PP::false,42],
        'null and false are emitted before error');
    is_deeply(results('7', 'try (. | ((empty,1),2)) catch 42'),
        [1,2], 'empty first nested value does not block later ones');
};

subtest 'source generators and downstream stages retain ordering' => sub {
    is_deeply(results('null',
        'try (range(0;2) | ((0,1/0),9)) catch 42'),
        [0,42], 'range halts after nested error');
    is_deeply(results('[7,8]',
        'try (.[] | ((.,1/0),99) | tostring) catch 42'),
        ['7',42], 'iterator preserves nested output through suffix');
    is_deeply(results('{"items":[7,8]}',
        'try (.items[] | ((.,1/0),99) | tostring) catch 42'),
        ['7',42], 'named iterator behaves the same');
    is_deeply(results('[1,[2]]',
        'try (recurse | ((.,1/0),99) | type) catch 42'),
        ['array',42], 'recurse root result is retained');
    is_deeply(results('null',
        'try (range(0;2) | ((., .+10),1/0)) catch 42'),
        [0,10,42], 'completed nested member suffixes retain order');
    is_deeply(results('7',
        'try (. | ((0,1),2) | if . == 1 then (1/0) else . end) catch 42'),
        [0,42], 'tail error interrupts later inner alternatives');
    is_deeply(results('null',
        'try (range(0;2) | ((0,1),2) | (.,1/0)) catch 42'),
        [0,42], 'multiple comma stages share nested expansion');
};

subtest 'outer comma and earlier simple comma controls' => sub {
    is_deeply(results('7', '0, (try (. | ((0,1/0),9)) catch 42),99'),
        [0,0,42,99], 'outer comma continues after caught error');
    is_deeply(results('7', 'try (. | (0,1/0,9)) catch 42'),
        [0,42], 'simple comma tail remains unchanged');
};

done_testing;
