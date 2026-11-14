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
my $input = '[1,[2],3]';
my $body = 'recurse | if . == 2 then (1/0) else . end';
my $optional = 'recurse(.[]?) | if . == 2 then (1/0) else . end';
my $prior = [[1,[2],3],1,[2]];

subtest 'nested recurse preserves completed ancestor and sibling outputs' => sub {
    is_deeply(results($input, "try (. | ($body)) catch 42"),
        [@$prior,42], 'nested default recurse emits before caught error');
    is_deeply(results($input, "try (. | ($optional)) catch 42"),
        [@$prior,42], 'nested optional-child recurse has the same order');
    is_deeply(results($input, "try (. | ($body))"),
        $prior, 'no-catch keeps completed results');
    is_deeply(results($input, "try (. | ($body)) catch null"),
        [@$prior,undef], 'null catch appends one real JSON null');
    is_deeply(results($input, "try (. | ($body)) catch empty"),
        $prior, 'empty catch leaves completed results intact');
    is_deeply(results($input, "try (. | ($body)) catch type"),
        [@$prior,'string'], 'handler receives the error string');
    is_deeply(results($input, "try (. | ($body)) catch (42,43)"),
        [@$prior,42,43], 'multi-output handler appends values');
    is_deeply(results($input, "try (. | (($body))) catch 42"),
        [@$prior,42], 'extra parentheses preserve stream order');
};

subtest 'downstream stages and comma alternatives stop after first error' => sub {
    is_deeply(results($input, "try (. | ($body) | type) catch 42"),
        ['array','number','array',42],
        'type receives each completed result before the failure');
    is_deeply(results($input, "try (. | (($body),99)) catch 42"),
        [@$prior,42], 'later nested comma alternative not evaluated');
    is_deeply(results($input, "try (. | (($optional),99)) catch 42"),
        [@$prior,42], 'optional recursion skips later comma alternative');
    is_deeply(results($input, "try (. | ($body) | (.,0)) catch 42"),
        [[1,[2],3],0,1,0,[2],0,42],
        'downstream comma follows depth-first completion order');
    is_deeply(results($input, "try (. | ($body) | (.,0) | type) catch 42"),
        ['array','number','number','number','array','number',42],
        'multi-stage suffix preserves all completed values');
    is_deeply(results($input, "0,(try (. | ($body)) catch 42),9"),
        [0,@$prior,42,9], 'outer comma alternatives continue');
    is_deeply(results($input, "try ((. | ($body)),9) catch 42"),
        [@$prior,42], 'inside comma alternative stops after error');
};

subtest 'outer selectors and successful recursion control' => sub {
    is_deeply(results('[[1,[2],3],[4]]',
        "try (.[] | ($body)) catch 42"),
        [@$prior,42], 'outer iterator stops before next array');
    is_deeply(results('{"items":[[1,[2],3],[4]]}',
        "try (.items[] | ($body)) catch 42"),
        [@$prior,42], 'named outer iterator stops before next member');
    is_deeply(results($input,
        "try (.[0] | ($body)) catch 42"),
        [1], 'scalar root emits once without recursive child values');
    is_deeply(results('null', 'try (. | (recurse | type))'),
        ['null'], 'null root emits itself once');
    is_deeply(results('false', 'try (. | (recurse | type))'),
        ['boolean'], 'false root emits itself once');
    is_deeply(results('[]', 'try (. | (recurse | type))'),
        ['array'], 'empty array emits only the root');
    is_deeply(results($input, 'try (. | (recurse | type))'),
        ['array','number','array','number','number'],
        'successful recursion retains depth-first visit order');
    is_deeply(results($input,
        'try (recurse | if . == 2 then (1/0) else . end) catch 42'),
        [@$prior,42], 'unwrapped recurse visitor remains unchanged');
};

done_testing;
