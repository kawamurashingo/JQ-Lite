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

my $input = '{"cfg":{"names":[["items"]]},"items":[{"cfg":{"names":[["items"]]},"id":1,"items":[]},{"cfg":{"names":[["items"]]},"id":2,"items":[]},{"cfg":{"names":[["items"]]},"id":3,"items":[]}]}';
my $nested = '{"cfg":{"names":[["items"]]},"items":[{"cfg":{"names":[["items"]]},"id":1,"items":[{"cfg":{"names":[["items"]]},"id":4,"items":[]}]},{"cfg":{"names":[["items"]]},"id":2,"items":[]},{"cfg":{"names":[["items"]]},"id":3,"items":[]}]}';
my $root = $json->decode($input);
my $first = $root->{items}[0];
my $prior = [$root, $first];

for my $selector ('.cfg["names"][0][0]', '.cfg."names"[0][0]') {
    my $child = 'recurse(.[' . $selector
        . '][]? | if .id == 2 then (1/0) else . end)';
    subtest "quoted-double-numeric selector $selector preserves streams" => sub {
        is_deeply(results($input, "try (. | ($child | .)) catch 42"),
            [@$prior,42], 'already emitted nodes precede caught error');
        is_deeply(results($input, "try (. | ($child | .))"),
            $prior, 'implicit catch empty retains completed outputs');
        is_deeply(results($input, "try (. | ($child | .)) catch empty"),
            $prior, 'explicit catch empty retains completed outputs');
        is_deeply(results($input, "try (. | ($child | .)) catch null"),
            [@$prior,undef], 'null catch follows completed nodes');
        is_deeply(results($input, "try (. | ($child | .)) catch (42,43)"),
            [@$prior,42,43], 'multi-result catch follows completed nodes');
        is_deeply(results($input, "try (. | ($child | type)) catch type"),
            ['object','object','string'], 'caught error is a string');
        my $tree = $json->decode($nested);
        is_deeply(results($nested, "try (. | ($child | .)) catch 42"),
            [$tree,$tree->{items}[0],$tree->{items}[0]{items}[0],42],
            'nested descendants preserve depth-first ordering');

        is_deeply(results($input, "try (. | ($child | (.,0))) catch 42"),
            [$root,0,$first,0,42], 'comma suffix follows each node');
        is_deeply(results($input, "try (. | (($child | .),99)) catch 42"),
            [@$prior,42], 'later comma branch is not evaluated');
        is_deeply(results($input, "try (. | (($child | .))) catch 42"),
            [@$prior,42], 'parentheses preserve the stream');
        is_deeply(results($input,
            "try (. | ($child | if .id == 1 then (1/0) else . end)) catch 42"),
            [$root,42], 'downstream failure stops before next child');

        my $other = '{"cfg":{"names":[["items"]]},"items":[{"cfg":{"names":[["items"]]},"id":5,"items":[]}]}';
        is_deeply(results("[$input,$other]",
            "try (.[] | ($child | type)) catch 42"),
            ['object','object',42], 'outer array stops on failure');
        is_deeply(results('{"groups":[' . $input . ',' . $other . ']}',
            "try (.groups[] | ($child | type)) catch 42"),
            ['object','object',42], 'outer named iterator stops on error');
    };

    subtest "selector $selector distinguishes iteration errors" => sub {
        is_deeply(results('null', "try (. | ($child | .)) catch 42"),
            [undef,42], 'null node is emitted before key error');
        is_deeply(results('3', "try (. | ($child | .)) catch 42"),
            [3,42], 'scalar root is emitted before selector error');
        is_deeply(results('false', "try (. | ($child | .)) catch 42"),
            [JSON::PP::false,42], 'boolean root is emitted before error');
        is_deeply(results('{}', "try (. | ($child | .)) catch 42"),
            [{},42], 'missing selector prefix errors');
        is_deeply(results('{"cfg":{}}', "try (. | ($child | .)) catch 42"),
            [{cfg=>{}},42], 'missing quoted selector field errors');
        is_deeply(results('{"cfg":{"names":[]}}',
            "try (. | ($child | .)) catch 42"),
            [{cfg=>{names=>[]}},42], 'out-of-range numeric index gives bad key');
        is_deeply(results('{"cfg":{"names":3}}',
            "try (. | ($child | .)) catch 42"),
            [{cfg=>{names=>3}},42], 'invalid numeric-index container errors');
        is_deeply(results('{"cfg":{"names":[["items"]]}}',
            "try (. | ($child | .)) catch 42"),
            [{cfg=>{names=>[['items']]}}], 'missing selected value is optional');
        is_deeply(results('{"cfg":{"names":[["items"]]},"items":null}',
            "try (. | ($child | .)) catch 42"),
            [{cfg=>{names=>[['items']]},items=>undef}],
            'null selected value is optional');
        is_deeply(results('{"cfg":{"names":[["items"]]},"items":[]}',
            "try (. | ($child | .)) catch 42"),
            [{cfg=>{names=>[['items']]},items=>[]}],
            'empty selected array ends recursion normally');

        my $strict = 'recurse(.[' . $selector . '][] | .)';
        is_deeply(results('{"cfg":{"names":[["items"]]}}',
            "try (. | ($strict | .)) catch 42"),
            [{cfg=>{names=>[['items']]}},42],
            'strict iterator errors after missing selected value');
        is_deeply(results('{"cfg":{"names":[["items"]]},"items":null}',
            "try (. | ($strict | .)) catch 42"),
            [{cfg=>{names=>[['items']]},items=>undef},42],
            'strict iterator errors after selected null');
        is_deeply(results('{"cfg":{"names":[["items"]]},"items":[]}',
            "try (. | ($strict | .)) catch 42"),
            [{cfg=>{names=>[['items']]},items=>[]}],
            'strict iterator accepts empty selected array');

        is_deeply(results($input,
            "try (. | (recurse(.[$selector][]? | empty) | .)) catch 42"),
            [$root], 'empty child pipeline keeps only the root');
        is_deeply(results($input,
            "try (. | (recurse(.[$selector][]? | if .id == 2 then empty else . end) | .)) catch 42"),
            [$root,$first,$root->{items}[2]], 'empty branch skips only one child');
        is_deeply(results($input,
            "try (. | (recurse(.[$selector][]? | (.,.)) | type)) catch 42"),
            [('object') x 7], 'double child pipeline visits every output');
        is_deeply(results($input, "try ($child | type) catch 42"),
            ['object','object',42], 'unwrapped recurse control unchanged');
    };
}

subtest 'negative double indices and literal special keys' => sub {
    my $tree = {
        cfg=>{names=>[['unused','items']]},
        items=>[
            {cfg=>{names=>[['unused','items']]},id=>1,items=>[]},
            {cfg=>{names=>[['unused','items']]},id=>2,items=>[]}
        ]
    };
    for my $selector ('.cfg["names"][-1][-1]', '.cfg."names"[-1][-1]') {
        my $filter = 'try (. | (recurse(.[' . $selector
            . '][]? | if .id == 2 then (1/0) else . end) | .)) catch 42';
        is_deeply(results($json->encode($tree),$filter),
            [$tree,$tree->{items}[0],42],
            "negative numeric index via $selector");
    }

    for my $field ('a.b', 'full name', 'x]y') {
        my $data = {
            cfg=>{$field=>[['items']]},
            items=>[
                {cfg=>{$field=>[['items']]},id=>1,items=>[]},
                {cfg=>{$field=>[['items']]},id=>2,items=>[]}
            ]
        };
        my $literal = $json->encode($field);
        for my $quoted ('.cfg[' . $literal . '][0][0]',
                        '.cfg.' . $literal . '[0][0]') {
            my $filter = 'try (. | (recurse(.[' . $quoted
                . '][]? | if .id == 2 then (1/0) else . end) | .)) catch 42';
            is_deeply(results($json->encode($data),$filter),
                [$data,$data->{items}[0],42],
                "literal quoted selector field $field is preserved");
        }
    }
};

done_testing;
