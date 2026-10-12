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

my $input = '{"cfg":{"names":[[["items"]]]},"items":[{"cfg":{"names":[[["items"]]]},"id":1,"items":[]},{"cfg":{"names":[[["items"]]]},"id":2,"items":[]},{"cfg":{"names":[[["items"]]]},"id":3,"items":[]}]}';
my $nested = '{"cfg":{"names":[[["items"]]]},"items":[{"cfg":{"names":[[["items"]]]},"id":1,"items":[{"cfg":{"names":[[["items"]]]},"id":4,"items":[]}]},{"cfg":{"names":[[["items"]]]},"id":2,"items":[]},{"cfg":{"names":[[["items"]]]},"id":3,"items":[]}]}';
my $child = 'recurse(.[.cfg.names[0][0][0]][]? | if .id == 2 then (1/0) else . end)';
my $root = $json->decode($input);
my $first = $root->{items}[0];
my $prior = [$root,$first];

subtest 'three signed indices retain prior nodes before try errors' => sub {
    is_deeply(results($input, "try (. | ($child | .)) catch 42"),
        [@$prior,42], 'root and prior sibling precede later child failure');
    is_deeply(results($input, "try (. | ($child | .))"),
        $prior, 'implicit empty catch preserves completed nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch empty"),
        $prior, 'explicit empty catch preserves completed nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch null"),
        [@$prior,undef], 'null catch follows completed nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch (42,43)"),
        [@$prior,42,43], 'multi-valued catch follows completed nodes');
    is_deeply(results($input, "try (. | ($child | type)) catch type"),
        ['object','object','string'], 'error is a string in catch handler');

    my $tree = $json->decode($nested);
    is_deeply(results($nested, "try (. | ($child | .)) catch 42"),
        [$tree,$tree->{items}[0],$tree->{items}[0]{items}[0],42],
        'nested descendants preserve depth-first order');
};

subtest 'downstream stages and outer inputs maintain ordering' => sub {
    is_deeply(results($input, "try (. | ($child | (.,0))) catch 42"),
        [$root,0,$first,0,42], 'comma tail follows each completed value');
    is_deeply(results($input, "try (. | (($child | .),99)) catch 42"),
        [@$prior,42], 'later comma alternative is not visited');
    is_deeply(results($input, "try (. | (($child | .))) catch 42"),
        [@$prior,42], 'extra parentheses do not erase completed stream');
    is_deeply(results($input,
        "try (. | ($child | if .id == 1 then (1/0) else . end)) catch 42"),
        [$root,42], 'tail failure stops further traversal');

    my $second = '{"cfg":{"names":[[["items"]]]},"items":[{"cfg":{"names":[[["items"]]]},"id":5,"items":[]}]}';
    is_deeply(results("[$input,$second]",
        "try (.[] | ($child | type)) catch 42"),
        ['object','object',42], 'outer array iterator stops after failure');
    is_deeply(results('{"groups":[' . $input . ',' . $second . ']}',
        "try (.groups[] | ($child | type)) catch 42"),
        ['object','object',42], 'outer named iterator stops after failure');
};

subtest 'invalid selectors and strict vs optional child iterators' => sub {
    is_deeply(results('null', "try (. | ($child | .)) catch 42"),
        [undef,42], 'null node is emitted before selector error');
    is_deeply(results('3', "try (. | ($child | .)) catch 42"),
        [3,42], 'number root emits before selector error');
    is_deeply(results('{}', "try (. | ($child | .)) catch 42"),
        [{},42], 'missing selector fields produce invalid computed key');
    is_deeply(results('{"cfg":{"names":[]}}',
        "try (. | ($child | .)) catch 42"),
        [{cfg=>{names=>[]}},42], 'out of range first index gives invalid key');
    is_deeply(results('{"cfg":{"names":[[[]]]}}',
        "try (. | ($child | .)) catch 42"),
        [{cfg=>{names=>[[]]}},42], 'out of range second index gives invalid key');
    is_deeply(results('{"cfg":{"names":3}}',
        "try (. | ($child | .)) catch 42"),
        [{cfg=>{names=>3}},42], 'number selector container errors');
    is_deeply(results('{"cfg":{"names":[[["items"]]]}}',
        "try (. | ($child | .)) catch 42"),
        [{cfg=>{names=>[[['items']]]}}],
        'optional iterator skips selected missing field');
    is_deeply(results('{"cfg":{"names":[[["items"]]]},"items":null}',
        "try (. | ($child | .)) catch 42"),
        [{cfg=>{names=>[[['items']]]},items=>undef}],
        'optional iterator skips selected null');
    is_deeply(results('{"cfg":{"names":[[["items"]]]},"items":[]}',
        "try (. | ($child | .)) catch 42"),
        [{cfg=>{names=>[[['items']]]},items=>[]}],
        'empty selected array finishes without error');
    is_deeply(results('{"cfg":{"names":[[["items"]]]}}',
        'try (. | (recurse(.[.cfg.names[0][0][0]][] | .) | .)) catch 42'),
        [{cfg=>{names=>[[['items']]]}},42],
        'strict iterator raises for missing selected field');
    is_deeply(results('{"cfg":{"names":[[["items"]]]},"items":null}',
        'try (. | (recurse(.[.cfg.names[0][0][0]][] | .) | .)) catch 42'),
        [{cfg=>{names=>[[['items']]]},items=>undef},42],
        'strict iterator raises for null selected field');
    my $missing = '{"cfg":{"names":[[["items"]]]},"items":[{"id":1}]}';
    is_deeply(results($missing,
        'try (. | (recurse(.[.cfg.names[0][0][0]][]? | .) | .)) catch 42'),
        [$json->decode($missing),{id=>1},42],
        'selector error occurs after emitting completed child');
};

subtest 'duplicate, empty, negative and stable controls' => sub {
    is_deeply(results($input,
        'try (. | (recurse(.[.cfg.names[0][0][0]][]? | empty) | .)) catch 42'),
        [$root], 'empty child filter does not recurse');
    is_deeply(results($input,
        'try (. | (recurse(.[.cfg.names[0][0][0]][]? | if .id == 2 then empty else . end) | .)) catch 42'),
        [$root,$first,$root->{items}[2]], 'empty result skips one child only');
    is_deeply(results($input,
        'try (. | (recurse(.[.cfg.names[0][0][0]][]? | (.,.)) | type)) catch 42'),
        [('object') x 7], 'duplicate child results keep depth-first order');

    my $negative = {
        cfg=>{names=>[[['unused','items']]]},
        items=>[
            {cfg=>{names=>[[['unused','items']]]},id=>1,items=>[]},
            {cfg=>{names=>[[['unused','items']]]},id=>2,items=>[]}
        ]
    };
    is_deeply(results($json->encode($negative),
        'try (. | (recurse(.[.cfg.names[-1][-1][-1]][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$negative,$negative->{items}[0],42],
        'three negative indices select final nested key');
    is_deeply(results($json->encode($negative),
        'try (. | (recurse(.[.cfg.names[-1][-1][-1]][] | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$negative,$negative->{items}[0],42],
        'strict numeric triple selector also streams');

    is_deeply(results($input,
        'try (. | (recurse(.[.cfg.names[0][0]][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$root,42], 'two numeric indices returning an array are not a key');
    is_deeply(results($input,
        'try (. | (recurse(.[.cfg.names[0][0][0]][] | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [@$prior,42], 'strict triple numeric child iterators stream');
    is_deeply(results($input, "try ($child | type) catch 42"),
        ['object','object',42], 'unwrapped custom recurse remains compatible');
};

done_testing;
