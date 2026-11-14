use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;
sub results {
    my ($input, $query) = @_;
    return [ $jq->run_query($input, $query) ];
}

my $input = '{"field":"items","items":[{"field":"items","id":1,"items":[]},{"field":"items","id":2,"items":[]},{"field":"items","id":3,"items":[]}]}';
my $nested = '{"field":"items","items":[{"field":"items","id":1,"items":[{"field":"items","id":4,"items":[]}]},{"field":"items","id":2,"items":[]},{"field":"items","id":3,"items":[]}]}';
my $child = 'recurse(.[.field][] | if .id == 2 then (1/0) else . end)';
my $root = $json->decode($input);
my $first = $root->{items}[0];
my $prior = [$root,$first];

subtest 'strict computed child stream preserves completed nodes' => sub {
    is_deeply(results($input, "try (. | ($child | .)) catch 42"),
        [@$prior,42], 'completed ancestor and sibling precede caught error');
    is_deeply(results($input, "try (. | ($child | .))"),
        $prior, 'implicit empty catch does not erase earlier nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch empty"),
        $prior, 'explicit catch empty retains completed nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch null"),
        [@$prior,undef], 'catch null follows completed results');
    is_deeply(results($input, "try (. | ($child | .)) catch (42,43)"),
        [@$prior,42,43], 'catch multi emits in source order');
    is_deeply(results($input, "try (. | ($child | type)) catch type"),
        ['object','object','string'], 'handler evaluates the error string');
    my $tree = $json->decode($nested);
    is_deeply(results($nested, "try (. | ($child | .)) catch 42"),
        [$tree,$tree->{items}[0],$tree->{items}[0]{items}[0],42],
        'nested recursion preserves depth-first completed descendants');
};

subtest 'pipeline, alternatives and upstream iterator boundaries' => sub {
    is_deeply(results($input, "try (. | ($child | (.,0))) catch 42"),
        [$root,0,$first,0,42], 'comma suffix follows each completed node');
    is_deeply(results($input, "try (. | (($child | .),99)) catch 42"),
        [@$prior,42], 'later comma alternative does not run after error');
    is_deeply(results($input, "try (. | (($child | .))) catch 42"),
        [@$prior,42], 'additional wrapping parentheses preserve order');
    is_deeply(results($input,
        "try (. | ($child | if .id == 1 then (1/0) else . end)) catch 42"),
        [$root,42], 'tail error stops child expansion');
    my $later = '{"field":"items","items":[{"field":"items","id":5,"items":[]}]}';
    is_deeply(results("[$input,$later]",
        "try (.[] | ($child | type)) catch 42"),
        ['object','object',42], 'outer array later value is skipped');
    is_deeply(results('{"groups":[' . $input . ',' . $later . ']}',
        "try (.groups[] | ($child | type)) catch 42"),
        ['object','object',42], 'outer named field later value is skipped');
};

subtest 'strict iteration errors, empty, multiple child streams' => sub {
    is_deeply(results('null', "try (. | ($child | .)) catch 42"),
        [undef,42], 'null node emitted before invalid computed key');
    is_deeply(results('3', "try (. | ($child | .)) catch 42"),
        [3,42], 'scalar root emitted before selector error');
    is_deeply(results('false', "try (. | ($child | .)) catch 42"),
        [JSON::PP::false,42], 'boolean root emitted before selector error');
    is_deeply(results('{}', "try (. | ($child | .)) catch 42"),
        [{},42], 'missing computed key errors after root');
    is_deeply(results('{"field":null}', "try (. | ($child | .)) catch 42"),
        [{field=>undef},42], 'explicit null computed key errors after root');
    is_deeply(results('{"field":"items"}', "try (. | ($child | .)) catch 42"),
        [{field=>'items'},42], 'missing selected array fails strict []');
    is_deeply(results('{"field":"items","items":null}',
        "try (. | ($child | .)) catch 42"),
        [{field=>'items',items=>undef},42], 'selected null fails strict []');
    is_deeply(results('{"field":"items","items":[]}',
        "try (. | ($child | .)) catch 42"),
        [{field=>'items',items=>[]}], 'empty array is valid strict iterator');
    is_deeply(results($input,
        'try (. | (recurse(.[.field][] | if .id == 2 then empty else . end) | .)) catch 42'),
        [$root,$first,$root->{items}[2]], 'empty child skips only that sibling');
    is_deeply(results($input,
        'try (. | (recurse(.[.field][] | empty) | .)) catch 42'),
        [$root], 'empty child filter stops recursion');
    is_deeply(results($input,
        'try (. | (recurse(.[.field][] | (.,.)) | type)) catch 42'),
        [('object') x 7], 'duplicate child results are traversed in order');
    my $missing = '{"field":"items","items":[{"id":1},{"id":2}]}';
    is_deeply(results($missing,
        'try (. | (recurse(.[.field][] | .) | .)) catch 42'),
        [$json->decode($missing),{id=>1},42],
        'missing selector on first child fails after child was emitted');
};

subtest 'literal special keys and existing behavior controls' => sub {
    for my $key ('a.b', 'full name', '') {
        my $tree = {
            field => $key,
            $key => [
                {field=>$key,id=>1,$key=>[]},
                {field=>$key,id=>2,$key=>[]}
            ]
        };
        is_deeply(results($json->encode($tree),
            "try (. | ($child | .)) catch 42"),
            [$tree,$tree->{$key}[0],42],
            "computed selector preserves literal key '$key'");
    }
    is_deeply(results($input, "try ($child | type) catch 42"),
        ['object','object',42], 'unwrapped custom recurse remains unchanged');
    is_deeply(results($input,
        'try (. | (recurse(.[.field][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [@$prior,42], 'optional computed child behavior remains correct');
    is_deeply(results('{"field":"items","items":null}',
        'try (. | (recurse(.[.field][]? | .) | .)) catch 42'),
        [{field=>'items',items=>undef}],
        'optional computed iterator still suppresses null array iteration');
    is_deeply(results($input,
        'try (. | (recurse(.items[] | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [@$prior,42], 'strict literal named child behavior unchanged');
};

done_testing;
