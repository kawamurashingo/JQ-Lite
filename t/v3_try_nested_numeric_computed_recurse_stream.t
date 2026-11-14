use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;

sub results {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

my $input = '{"keys":["items"],"items":[{"keys":["items"],"id":1,"items":[]},{"keys":["items"],"id":2,"items":[]},{"keys":["items"],"id":3,"items":[]}]}';
my $nested = '{"keys":["items"],"items":[{"keys":["items"],"id":1,"items":[{"keys":["items"],"id":4,"items":[]}]},{"keys":["items"],"id":2,"items":[]},{"keys":["items"],"id":3,"items":[]}]}';
my $child = 'recurse(.[.keys[0]][]? | if .id == 2 then (1/0) else . end)';
my $root = $json->decode($input);
my $first = $root->{items}[0];
my $prior = [$root,$first];

subtest 'numeric computed children preserve already emitted nodes' => sub {
    is_deeply(results($input, "try (. | ($child | .)) catch 42"),
        [@$prior,42], 'root and prior sibling precede caught failure');
    is_deeply(results($input, "try (. | ($child | .))"),
        $prior, 'implicit empty catch keeps earlier results');
    is_deeply(results($input, "try (. | ($child | .)) catch empty"),
        $prior, 'explicit catch empty keeps earlier results');
    is_deeply(results($input, "try (. | ($child | .)) catch null"),
        [@$prior,undef], 'catch null appends a JSON null');
    is_deeply(results($input, "try (. | ($child | .)) catch (42,43)"),
        [@$prior,42,43], 'multiple catches follow previous nodes');
    is_deeply(results($input, "try (. | ($child | type)) catch type"),
        ['object','object','string'], 'catch type sees an error string');
    my $tree = $json->decode($nested);
    is_deeply(results($nested, "try (. | ($child | .)) catch 42"),
        [$tree,$tree->{items}[0],$tree->{items}[0]{items}[0],42],
        'nested descendant appears before later failing sibling');
};

subtest 'pipeline and branch boundaries remain demand-driven' => sub {
    is_deeply(results($input, "try (. | ($child | (.,0))) catch 42"),
        [$root,0,$first,0,42], 'comma tail follows completed nodes');
    is_deeply(results($input, "try (. | (($child | .),99)) catch 42"),
        [@$prior,42], 'later comma alternative is not evaluated');
    is_deeply(results($input, "try (. | (($child | .))) catch 42"),
        [@$prior,42], 'extra balanced parentheses preserve stream');
    is_deeply(results($input,
        "try (. | ($child | if .id == 1 then (1/0) else . end)) catch 42"),
        [$root,42], 'downstream error stops traversal immediately');
    my $other = '{"keys":["items"],"items":[{"keys":["items"],"id":5,"items":[]}]}';
    is_deeply(results("[$input,$other]",
        "try (.[] | ($child | type)) catch 42"),
        ['object','object',42], 'outer array iterator stops after failure');
    is_deeply(results('{"groups":[' . $input . ',' . $other . ']}',
        "try (.groups[] | ($child | type)) catch 42"),
        ['object','object',42], 'outer named iterator stops after failure');
};

subtest 'numeric selector errors and optional child iteration' => sub {
    is_deeply(results('null', "try (. | ($child | .)) catch 42"),
        [undef,42], 'computed numeric key errors after null root');
    is_deeply(results('3', "try (. | ($child | .)) catch 42"),
        [3,42], 'number root emits before path selector failure');
    is_deeply(results('false', "try (. | ($child | .)) catch 42"),
        [JSON::PP::false,42], 'false root emits before selector failure');
    is_deeply(results('{}', "try (. | ($child | .)) catch 42"),
        [{},42], 'missing keys array creates invalid computed key');
    is_deeply(results('{"keys":[]}', "try (. | ($child | .)) catch 42"),
        [{keys=>[]},42], 'empty key list yields invalid null key');
    is_deeply(results('{"keys":null}', "try (. | ($child | .)) catch 42"),
        [{keys=>undef},42], 'null key list yields invalid null key');
    is_deeply(results('{"keys":3}', "try (. | ($child | .)) catch 42"),
        [{keys=>3},42], 'number-valued keys cannot be numerically indexed');
    is_deeply(results('{"keys":["items"]}', "try (. | ($child | .)) catch 42"),
        [{keys=>['items']}], 'optional iteration skips missing container');
    is_deeply(results('{"keys":["items"],"items":null}',
        "try (. | ($child | .)) catch 42"),
        [{keys=>['items'],items=>undef}],
        'optional iteration skips null selected container');
    is_deeply(results('{"keys":["items"],"items":[]}',
        "try (. | ($child | .)) catch 42"),
        [{keys=>['items'],items=>[]}],
        'empty selected container completes without error');
    my $missing_child = '{"keys":["items"],"items":[{"id":1}]}';
    is_deeply(results($missing_child,
        'try (. | (recurse(.[.keys[0]][]? | .) | .)) catch 42'),
        [$json->decode($missing_child),{id=>1},42],
        'missing selector in child errors after child was emitted');
};

subtest 'child pipeline variants and strict numeric selector' => sub {
    is_deeply(results($input,
        'try (. | (recurse(.[.keys[0]][]? | if .id == 2 then empty else . end) | .)) catch 42'),
        [$root,$first,$root->{items}[2]], 'empty child skips one subtree');
    is_deeply(results($input,
        'try (. | (recurse(.[.keys[0]][]? | empty) | .)) catch 42'),
        [$root], 'zero child stream leaves the root');
    is_deeply(results($input,
        'try (. | (recurse(.[.keys[0]][]? | (.,.)) | type)) catch 42'),
        [('object') x 7], 'duplicate child outputs remain depth-first');
    is_deeply(results($input,
        'try (. | (recurse(.[.keys[0]][] | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [@$prior,42], 'strict numeric computed form keeps completed outputs');
    is_deeply(results('{"keys":["items"]}',
        'try (. | (recurse(.[.keys[0]][] | .) | .)) catch 42'),
        [{keys=>['items']},42], 'strict iterator errors on missing selected container');
    is_deeply(results('{"keys":["items"],"items":null}',
        'try (. | (recurse(.[.keys[0]][] | .) | .)) catch 42'),
        [{keys=>['items'],items=>undef},42],
        'strict iterator errors on null selected container');
    is_deeply(results($input, "try ($child | type) catch 42"),
        ['object','object',42], 'unwrapped recurse control remains correct');
    is_deeply(results($input,
        'try (. | (recurse(.[.keys[0]][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [@$prior,42], 'optional numeric selector control remains correct');
};

subtest 'negative indices and dotted numeric selector prefixes' => sub {
    my $negative = {
        keys => ['unused','items'],
        items => [
            {keys=>['unused','items'],id=>1,items=>[]},
            {keys=>['unused','items'],id=>2,items=>[]}
        ]
    };
    is_deeply(results($json->encode($negative),
        'try (. | (recurse(.[.keys[-1]][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$negative,$negative->{items}[0],42],
        'negative numeric selector reads final key');
    is_deeply(results($json->encode($negative),
        'try (. | (recurse(.[.keys[-1]][] | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$negative,$negative->{items}[0],42],
        'strict negative numeric selector preserves streamed outputs');
    my $configured = {
        cfg=>{names=>['items']},
        items=>[
            {cfg=>{names=>['items']},id=>1,items=>[]},
            {cfg=>{names=>['items']},id=>2,items=>[]}
        ]
    };
    is_deeply(results($json->encode($configured),
        'try (. | (recurse(.[.cfg.names[0]][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$configured,$configured->{items}[0],42],
        'dotted computed selector with a numeric suffix');
    is_deeply(results($json->encode($configured),
        'try (. | (recurse(.[.cfg.names[0]][] | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$configured,$configured->{items}[0],42],
        'strict dotted numeric computed selector');
    for my $field ('a.b','full name','') {
        my $tree = {
            keys=>[$field],
            $field=>[
                {keys=>[$field],id=>1,$field=>[]},
                {keys=>[$field],id=>2,$field=>[]}
            ]
        };
        is_deeply(results($json->encode($tree),
            'try (. | (recurse(.[.keys[0]][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
            [$tree,$tree->{$field}[0],42],
            "numeric selector value '$field' is a literal key");
    }
};

done_testing;
