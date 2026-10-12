use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;
sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

my $input  = '{"items":[{"id":1},{"id":2},{"id":3}]}';
my $nested = '{"items":[{"id":1,"items":[{"id":4}]},{"id":2},{"id":3}]}';
my $child  = 'recurse(."items"[]? | if .id == 2 then (1/0) else . end)';
my $root   = { items => [{id=>1},{id=>2},{id=>3}] };
my $prior  = [$root, {id=>1}];

subtest 'dot-quoted child pipelines retain already yielded nodes' => sub {
    is_deeply(results($input, "try (. | ($child | .)) catch 42"),
        [@$prior,42], 'root and prior child survive later error');
    is_deeply(results($input, "try (. | ($child | .))"),
        $prior, 'implicit empty catch retains completed results');
    is_deeply(results($input, "try (. | ($child | .)) catch empty"),
        $prior, 'explicit empty catch retains completed results');
    is_deeply(results($input, "try (. | ($child | .)) catch null"),
        [@$prior,undef], 'null catch emits one JSON null');
    is_deeply(results($input, "try (. | ($child | .)) catch (42,43)"),
        [@$prior,42,43], 'multiple catch results follow completed nodes');
    is_deeply(results($input, "try (. | ($child | type)) catch type"),
        ['object','object','string'], 'handler receives error as a string');
    is_deeply(results($nested, "try (. | ($child | .)) catch 42"),
        [{items=>[{id=>1,items=>[{id=>4}]},{id=>2},{id=>3}]},
         {id=>1,items=>[{id=>4}]},{id=>4},42],
        'descendant and earlier sibling keep depth-first order');
};

subtest 'downstream stream boundaries stop on the first error' => sub {
    is_deeply(results($input, "try (. | ($child | (.,0))) catch 42"),
        [$root,0,{id=>1},0,42], 'comma tail follows each yielded node');
    is_deeply(results($input, "try (. | (($child | .),99)) catch 42"),
        [@$prior,42], 'later comma alternative is not visited');
    is_deeply(results($input, "try (. | (($child | .))) catch 42"),
        [@$prior,42], 'balanced wrapping parentheses are supported');
    is_deeply(results($input,
        "try (. | ($child | if .id == 1 then (1/0) else . end)) catch 42"),
        [$root,42], 'tail failure stops traversal before later child');
    is_deeply(results("[$input," . '{"items":[{"id":4}]}' . "]",
        "try (.[] | ($child | type)) catch 42"),
        ['object','object',42], 'outer root iterator stops after failure');
    is_deeply(results('{"groups":[' . $input . ',{"items":[{"id":4}]}]}',
        "try (.groups[] | ($child | type)) catch 42"),
        ['object','object',42], 'outer named iterator stops after failure');
};

subtest 'child filtering, roots, and supported controls' => sub {
    is_deeply(results($input,
        'try (. | (recurse(."items"[]? | if .id == 2 then empty else . end) | .)) catch 42'),
        [$root,{id=>1},{id=>3}], 'empty child stream skips only one sibling');
    is_deeply(results($input,
        'try (. | (recurse(."items"[]? | empty) | .)) catch 42'),
        [$root], 'empty children leave the root');
    is_deeply(results($input,
        'try (. | (recurse(."items"[]? | (.,.)) | type)) catch 42'),
        ['object','object','object','object','object','object','object'],
        'duplicated children retain depth-first traversal');
    is_deeply(results('null', "try (. | ($child | .)) catch 42"),
        [undef], 'null root emits once');
    is_deeply(results('{"items":null}', "try (. | ($child | .)) catch 42"),
        [{items=>undef}], 'optional child iterator skips null');
    is_deeply(results('3', "try (. | ($child | .)) catch 42"),
        [3,42], 'invalid quoted field lookup fails after root output');
    is_deeply(results($input, "try ($child | type) catch 42"),
        ['object','object',42], 'unwrapped custom child control');
    is_deeply(results($input,
        'try (. | (recurse(.["items"][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [@$prior,42], 'bracket-quoted child control');
    is_deeply(results('{"a.b":[{"id":1},{"id":2},{"id":3}]}',
        'try (. | (recurse(."a.b"[]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [{ 'a.b' => [{id=>1},{id=>2},{id=>3}] },{id=>1},42],
        'literal dotted field name is not split');
    is_deeply(results('{"full name":[{"id":1},{"id":2},{"id":3}]}',
        'try (. | (recurse(."full name"[]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [{ 'full name' => [{id=>1},{id=>2},{id=>3}] },{id=>1},42],
        'literal spaced field name is preserved');
};

done_testing;
