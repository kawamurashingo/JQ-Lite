use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;
sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

my $input = '{"items":[{"id":1,"items":[]},{"id":2,"items":[]},{"id":3,"items":[]}]}';
my $nested = '{"items":[{"id":1,"items":[{"id":4,"items":[]}]},{"id":2,"items":[]},{"id":3,"items":[]}]}';
my $child = 'recurse(.items[] | if .id == 2 then (1/0) else . end)';
my $root = { items => [
    {id=>1,items=>[]}, {id=>2,items=>[]}, {id=>3,items=>[]}
] };
my $first = {id=>1,items=>[]};
my $prior = [$root, $first];

subtest 'strict named children retain earlier streamed results' => sub {
    is_deeply(results($input, "try (. | ($child | .)) catch 42"),
        [@$prior,42], 'root and first child precede the caught error');
    is_deeply(results($input, "try (. | ($child | .))"),
        $prior, 'implicit empty catch retains prior nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch empty"),
        $prior, 'explicit empty catch retains prior nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch null"),
        [@$prior,undef], 'null catch follows prior nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch (42,43)"),
        [@$prior,42,43], 'multi-output catch follows prior nodes');
    is_deeply(results($input, "try (. | ($child | type)) catch type"),
        ['object','object','string'], 'catch handler sees error string');
    is_deeply(results($nested, "try (. | ($child | .)) catch 42"),
        [
            {items=>[
                {id=>1,items=>[{id=>4,items=>[]}]},
                {id=>2,items=>[]}, {id=>3,items=>[]}
            ]},
            {id=>1,items=>[{id=>4,items=>[]}]},
            {id=>4,items=>[]},
            42
        ], 'nested children precede later failing siblings');
};

subtest 'pipeline boundaries and short circuit ordering' => sub {
    is_deeply(results($input, "try (. | ($child | (.,0))) catch 42"),
        [$root,0,$first,0,42], 'comma tail follows each completed node');
    is_deeply(results($input, "try (. | (($child | .),99)) catch 42"),
        [@$prior,42], 'later comma sibling is not visited');
    is_deeply(results($input, "try (. | (($child | .))) catch 42"),
        [@$prior,42], 'extra balanced parentheses keep order');
    is_deeply(results($input,
        "try (. | ($child | if .id == 1 then (1/0) else . end)) catch 42"),
        [$root,42], 'tail error stops recursion before further children');
    is_deeply(results("[$input," . '{"items":[{"id":4,"items":[]}]}' . "]",
        "try (.[] | ($child | type)) catch 42"),
        ['object','object',42], 'outer array iterator stops on error');
    is_deeply(results('{"groups":[' . $input . ',{"items":[{"id":4,"items":[]}]}]}',
        "try (.groups[] | ($child | type)) catch 42"),
        ['object','object',42], 'outer named iterator stops on error');
};

subtest 'strict iterator errors and optional controls' => sub {
    is_deeply(results('null', "try (. | ($child | .)) catch 42"),
        [undef,42], 'strict named expansion throws after null root');
    is_deeply(results('{"items":[{"id":1},{"id":2}]}',
        'try (. | (recurse(.items[] | .) | .)) catch 42'),
        [{items=>[{id=>1},{id=>2}]},{id=>1},42],
        'strict missing child field errors after completed child');
    is_deeply(results($input,
        'try (. | (recurse(.items[] | empty) | .)) catch 42'),
        [$root], 'empty child pipeline yields only the root');
    is_deeply(results($input,
        'try (. | (recurse(.items[] | if .id == 2 then empty else . end) | .)) catch 42'),
        [$root,$first,{id=>3,items=>[]}], 'empty child skips only one sibling');
    is_deeply(results('{"items":[{"id":1,"items":[]},{"id":2,"items":[]}]}',
        'try (. | (recurse(.items[] | (.,.)) | type)) catch 42'),
        ['object','object','object','object','object'],
        'each duplicated child is visited once per output');
    is_deeply(results('{"items":[]}',
        'try (. | (recurse(.items[] | .) | type)) catch 42'),
        ['object'], 'empty named array has no strict expansion error');
    is_deeply(results($input, "try ($child | type) catch 42"),
        ['object','object',42], 'unwrapped strict named child control');
    is_deeply(results($input,
        'try (. | (recurse(.items[]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [@$prior,42], 'optional named child control remains unchanged');
    is_deeply(results($input,
        'try (. | (recurse(.["items"][] | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [@$prior,42], 'strict bracket-quoted child iterator');
    is_deeply(results($input,
        'try (. | (recurse(."items"[] | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [@$prior,42], 'strict dot-quoted child iterator');
    is_deeply(results('{"a.b":[{"id":1,"a.b":[]},{"id":2,"a.b":[]}]}',
        'try (. | (recurse(."a.b"[] | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [{'a.b'=>[{id=>1,'a.b'=>[]},{id=>2,'a.b'=>[]}]},
         {id=>1,'a.b'=>[]},42], 'strict dot-quoted dotted field is literal');
    is_deeply(results('{"full name":[{"id":1,"full name":[]},{"id":2,"full name":[]}]}',
        'try (. | (recurse(.["full name"][] | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [{'full name'=>[{id=>1,'full name'=>[]},{id=>2,'full name'=>[]}]},
         {id=>1,'full name'=>[]},42], 'strict bracket-quoted spaced field');
};

done_testing;
