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

my $input = '{"cfg":{"selected":"items"},"items":[{"cfg":{"selected":"items"},"id":1,"items":[]},{"cfg":{"selected":"items"},"id":2,"items":[]},{"cfg":{"selected":"items"},"id":3,"items":[]}]}';
my $nested = '{"cfg":{"selected":"items"},"items":[{"cfg":{"selected":"items"},"id":1,"items":[{"cfg":{"selected":"items"},"id":4,"items":[]}]},{"cfg":{"selected":"items"},"id":2,"items":[]},{"cfg":{"selected":"items"},"id":3,"items":[]}]}';
my $child = 'recurse(.[.cfg["selected"]][]? | if .id == 2 then (1/0) else . end)';
my $root = $json->decode($input);
my $first = $root->{items}[0];
my $prior = [$root,$first];

subtest 'bracket-quoted computed child retains completed nodes' => sub {
    is_deeply(results($input, "try (. | ($child | .)) catch 42"),
        [@$prior,42], 'root and earlier sibling survive later child error');
    is_deeply(results($input, "try (. | ($child | .))"),
        $prior, 'implicit catch empty preserves already completed nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch empty"),
        $prior, 'explicit catch empty preserves earlier nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch null"),
        [@$prior,undef], 'catch null appends one JSON null');
    is_deeply(results($input, "try (. | ($child | .)) catch (42,43)"),
        [@$prior,42,43], 'multi-result catch follows prior nodes');
    is_deeply(results($input, "try (. | ($child | type)) catch type"),
        ['object','object','string'], 'catch receives an error string');

    my $tree = $json->decode($nested);
    is_deeply(results($nested, "try (. | ($child | .)) catch 42"),
        [$tree,$tree->{items}[0],$tree->{items}[0]{items}[0],42],
        'nested completed descendants appear in depth-first order');
};

subtest 'downstream and outer streams stop on first error' => sub {
    is_deeply(results($input, "try (. | ($child | (.,0))) catch 42"),
        [$root,0,$first,0,42], 'comma suffix follows each complete node');
    is_deeply(results($input, "try (. | (($child | .),99)) catch 42"),
        [@$prior,42], 'later comma alternative is not evaluated');
    is_deeply(results($input, "try (. | (($child | .))) catch 42"),
        [@$prior,42], 'extra parentheses retain the emitted stream');
    is_deeply(results($input,
        "try (. | ($child | if .id == 1 then (1/0) else . end)) catch 42"),
        [$root,42], 'tail error stops recursion before next child');

    my $other = '{"cfg":{"selected":"items"},"items":[{"cfg":{"selected":"items"},"id":5,"items":[]}]}';
    is_deeply(results("[$input,$other]",
        "try (.[] | ($child | type)) catch 42"),
        ['object','object',42], 'outer array skips its later input');
    is_deeply(results('{"groups":[' . $input . ',' . $other . ']}',
        "try (.groups[] | ($child | type)) catch 42"),
        ['object','object',42], 'outer named iterator skips its later input');
};

subtest 'selector failures are distinct from optional iteration' => sub {
    is_deeply(results('null', "try (. | ($child | .)) catch 42"),
        [undef,42], 'null root is emitted before selector-key error');
    is_deeply(results('3', "try (. | ($child | .)) catch 42"),
        [3,42], 'number root is emitted before field access error');
    is_deeply(results('false', "try (. | ($child | .)) catch 42"),
        [JSON::PP::false,42], 'boolean root is emitted before selector error');
    is_deeply(results('{}', "try (. | ($child | .)) catch 42"),
        [{},42], 'missing cfg selector key is an error');
    is_deeply(results('{"cfg":{}}', "try (. | ($child | .)) catch 42"),
        [{cfg=>{}},42], 'missing selected selector key is an error');
    is_deeply(results('{"cfg":{"selected":null}}',
        "try (. | ($child | .)) catch 42"),
        [{cfg=>{selected=>undef}},42], 'null computed key is an error');
    is_deeply(results('{"cfg":9}', "try (. | ($child | .)) catch 42"),
        [{cfg=>9},42], 'wrong intermediate type error survives []?');
    is_deeply(results('{"cfg":{"selected":"items"}}',
        "try (. | ($child | .)) catch 42"),
        [{cfg=>{selected=>'items'}}], 'missing selected array is omitted');
    is_deeply(results('{"cfg":{"selected":"items"},"items":null}',
        "try (. | ($child | .)) catch 42"),
        [{cfg=>{selected=>'items'},items=>undef}],
        'selected null array is omitted by []?');
    is_deeply(results('{"cfg":{"selected":"items"},"items":[]}',
        "try (. | ($child | .)) catch 42"),
        [{cfg=>{selected=>'items'},items=>[]}],
        'empty selected array ends recursion without an error');
    my $missing_child = '{"cfg":{"selected":"items"},"items":[{"id":1}]}';
    is_deeply(results($missing_child,
        'try (. | (recurse(.[.cfg["selected"]][]? | .) | .)) catch 42'),
        [$json->decode($missing_child),{id=>1},42],
        'missing selector on a child fails after that child was yielded');
};

subtest 'child streams and strict/legacy controls' => sub {
    is_deeply(results($input,
        'try (. | (recurse(.[.cfg["selected"]][]? | if .id == 2 then empty else . end) | .)) catch 42'),
        [$root,$first,$root->{items}[2]], 'empty child skips its own subtree');
    is_deeply(results($input,
        'try (. | (recurse(.[.cfg["selected"]][]? | empty) | .)) catch 42'),
        [$root], 'empty child pipeline retains the root');
    is_deeply(results($input,
        'try (. | (recurse(.[.cfg["selected"]][]? | (.,.)) | type)) catch 42'),
        [('object') x 7], 'multiple children preserve depth-first order');

    is_deeply(results($input, "try ($child | type) catch 42"),
        ['object','object',42], 'unwrapped recurse retains existing behavior');
    is_deeply(results($input,
        'try (. | (recurse(.[.cfg.selected][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [@$prior,42], 'dot-only computed selector remains compatible');
    is_deeply(results($input,
        'try (. | (recurse(.[.cfg."selected"][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [@$prior,42], 'dot-quoted selector control retains results');

    is_deeply(results($input,
        'try (. | (recurse(.[.cfg["selected"]][] | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [@$prior,42], 'strict bracket-quoted computed child streams');
    is_deeply(results('{"cfg":{"selected":"items"}}',
        'try (. | (recurse(.[.cfg["selected"]][] | .) | .)) catch 42'),
        [{cfg=>{selected=>'items'}},42],
        'strict missing child array throws after current node');
    is_deeply(results('{"cfg":{"selected":"items"},"items":null}',
        'try (. | (recurse(.[.cfg["selected"]][] | .) | .)) catch 42'),
        [{cfg=>{selected=>'items'},items=>undef},42],
        'strict null child array throws after current node');
};

subtest 'special JSON-quoted selector fields remain literal' => sub {
    for my $case (
        ['a.b', 'a.b'],
        ['full name', 'full name'],
        ['x]y', 'x]y'],
    ) {
        my ($name, $filter_name) = @$case;
        my $node1 = { cfg=>{$name=>'items'}, id=>1, items=>[] };
        my $node2 = { cfg=>{$name=>'items'}, id=>2, items=>[] };
        my $tree = { cfg=>{$name=>'items'}, items=>[$node1,$node2] };
        my $quoted = $json->encode($filter_name);
        my $filter = 'try (. | (recurse(.[.cfg[' . $quoted
            . '][]? | if .id == 2 then (1/0) else . end) | .)) catch 42';
        is_deeply(results($json->encode($tree), $filter),
            [$tree,$node1,42],
            "quoted selector '$name' is not split or truncated");
    }
};

done_testing;
