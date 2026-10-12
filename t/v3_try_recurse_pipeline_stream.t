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

subtest 'recurse emits previously completed values before a tail error' => sub {
    my $input = '[1,[2],3]';
    my $body = 'recurse | if . == 2 then (1 / 0) else . end';
    my $prior = [[1,[2],3], 1, [2]];
    is_deeply(results($input, "try ($body) catch 42"),
        [@$prior,42], 'catch follows completed ancestor and sibling outputs');
    is_deeply(results($input, "try ($body)"),
        $prior, 'no-catch suppresses only the failing remainder');
    is_deeply(results($input, "try ($body) catch empty"),
        $prior, 'empty catch leaves completed values alone');
    is_deeply(results($input, "try ($body) catch null"),
        [@$prior,undef], 'explicit null catch is a real output');
    is_deeply(results($input, "try ($body) catch type"),
        [@$prior,'string'], 'catch receives the error string');
    is_deeply(results($input, "try ($body) catch (42, 43)"),
        [@$prior,42,43], 'multiple handler outputs follow completed stream');
    is_deeply(results($input,
        'try (recurse(.[]?) | if . == 2 then (1 / 0) else . end) catch 42'),
        [@$prior,42], 'optional-child recursion follows the same order');
};

subtest 'branch boundaries and successful recursion controls' => sub {
    my $input = '[1,[2],3]';
    my $body = 'recurse | if . == 2 then (1 / 0) else . end';
    is_deeply(results($input, "try (($body), 99) catch 42"),
        [[1,[2],3],1,[2],42], 'later comma alternative is skipped');
    is_deeply(results($input, "0, (try ($body) catch 42), 9"),
        [0,[1,[2],3],1,[2],42,9],
        'surrounding comma alternatives remain in order');
    is_deeply(results($input, "try ($body | tostring) catch 42"),
        ['[1,[2],3]','1','[2]',42],
        'multi-stage tail retains previously completed outputs');
    is_deeply(results($input,
        'try (recurse | if . == 1 then (1 / 0) else . end) catch 42'),
        [[1,[2],3],42], 'early error prevents later descendants');
    is_deeply(results($input,
        'try (recurse | select(type == "number"))'),
        [1,2,3], 'skipped values do not stop recursion');
    is_deeply(results($input, 'try (recurse(.[]?) | .) catch 42'),
        [[1,[2],3],1,[2],2,3],
        'fully successful optional recursion retains depth-first order');
    is_deeply(results($input, 'try (recurse(.[]?) | type) catch 42'),
        ['array','number','array','number','number'],
        'all visited members are evaluated once');
};

subtest 'null, false and bare recurse controls' => sub {
    is_deeply(results('null', 'try (recurse | type) catch 42'),
        ['null'], 'null input is still yielded as an actual value');
    is_deeply(results('false', 'try (recurse | type) catch 42'),
        ['boolean'], 'false input has boolean type');
    is_deeply(results('[]', 'try (recurse | type) catch 42'),
        ['array'], 'empty array produces its root but no children');
    is_deeply(results('[1,[2],3]', 'try recurse'),
        [[1,[2],3],1,[2],2,3],
        'bare recursion remains on the existing path');
    is_deeply(results('null', 'try []'),
        [[]], 'array constructor remains unaffected');
};

done_testing;
