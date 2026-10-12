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

my $input = '{"cfg":{"key":"items"},"items":[{"cfg":{"key":"items"},"id":1,"items":[]},{"cfg":{"key":"items"},"id":2,"items":[]},{"cfg":{"key":"items"},"id":3,"items":[]}]}';
my $nested = '{"cfg":{"key":"items"},"items":[{"cfg":{"key":"items"},"id":1,"items":[{"cfg":{"key":"items"},"id":4,"items":[]}]},{"cfg":{"key":"items"},"id":2,"items":[]},{"cfg":{"key":"items"},"id":3,"items":[]}]}';
my $child = 'recurse(.[.cfg.key][]? | if .id == 2 then (1/0) else . end)';
my $root = $json->decode($input);
my $first = $root->{items}[0];
my $prior = [$root,$first];

subtest 'dotted computed child retains previous streamed results' => sub {
    is_deeply(results($input, "try (. | ($child | .)) catch 42"),
        [@$prior,42], 'root and first child survive later error');
    is_deeply(results($input, "try (. | ($child | .))"),
        $prior, 'implicit catch empty retains completed nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch empty"),
        $prior, 'explicit catch empty retains earlier nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch null"),
        [@$prior,undef], 'catch null appends one null');
    is_deeply(results($input, "try (. | ($child | .)) catch (42,43)"),
        [@$prior,42,43], 'multi-value catch follows prior nodes');
    is_deeply(results($input, "try (. | ($child | type)) catch type"),
        ['object','object','string'], 'handler sees error as a string');
    my $tree = $json->decode($nested);
    is_deeply(results($nested, "try (. | ($child | .)) catch 42"),
        [$tree,$tree->{items}[0],$tree->{items}[0]{items}[0],42],
        'nested child streams remain depth-first');
};

subtest 'later pipeline and outer inputs stop after the error' => sub {
    is_deeply(results($input, "try (. | ($child | (.,0))) catch 42"),
        [$root,0,$first,0,42], 'comma tail follows each recursive result');
    is_deeply(results($input, "try (. | (($child | .),99)) catch 42"),
        [@$prior,42], 'later alternative does not execute');
    is_deeply(results($input, "try (. | (($child | .))) catch 42"),
        [@$prior,42], 'extra balanced parentheses retain order');
    is_deeply(results($input,
        "try (. | ($child | if .id == 1 then (1/0) else . end)) catch 42"),
        [$root,42], 'tail error prevents later child expansion');
    my $other = '{"cfg":{"key":"items"},"items":[{"cfg":{"key":"items"},"id":5,"items":[]}]}';
    is_deeply(results("[$input,$other]",
        "try (.[] | ($child | type)) catch 42"),
        ['object','object',42], 'outer array iterator stops');
    is_deeply(results('{"groups":[' . $input . ',' . $other . ']}',
        "try (.groups[] | ($child | type)) catch 42"),
        ['object','object',42], 'outer named iterator stops');
};

subtest 'dotted selector error and optional iterator boundaries' => sub {
    is_deeply(results('null', "try (. | ($child | .)) catch 42"),
        [undef,42], 'selector on null fails after root is emitted');
    is_deeply(results('3', "try (. | ($child | .)) catch 42"),
        [3,42], 'scalar root selector failure is caught');
    is_deeply(results('false', "try (. | ($child | .)) catch 42"),
        [JSON::PP::false,42], 'boolean root is emitted before error');
    is_deeply(results('{}', "try (. | ($child | .)) catch 42"),
        [{},42], 'missing cfg selector key raises');
    is_deeply(results('{"cfg":{}}', "try (. | ($child | .)) catch 42"),
        [{cfg=>{}},42], 'missing cfg.key selector raises');
    is_deeply(results('{"cfg":{"key":null}}',
        "try (. | ($child | .)) catch 42"),
        [{cfg=>{key=>undef}},42], 'null computed key raises');
    is_deeply(results('{"cfg":9}', "try (. | ($child | .)) catch 42"),
        [{cfg=>9},42], 'bad selector intermediate type is not optional');
    is_deeply(results('{"cfg":{"key":"items"}}',
        "try (. | ($child | .)) catch 42"),
        [{cfg=>{key=>'items'}}], 'selected missing array is skipped by []?');
    is_deeply(results('{"cfg":{"key":"items"},"items":null}',
        "try (. | ($child | .)) catch 42"),
        [{cfg=>{key=>'items'},items=>undef}],
        'selected null array is skipped by []?');
    is_deeply(results('{"cfg":{"key":"items"},"items":[]}',
        "try (. | ($child | .)) catch 42"),
        [{cfg=>{key=>'items'},items=>[]}], 'empty array ends recursion');
    my $missing_child = '{"cfg":{"key":"items"},"items":[{"id":1}]}';
    is_deeply(results($missing_child,
        'try (. | (recurse(.[.cfg.key][]? | .) | .)) catch 42'),
        [$json->decode($missing_child),{id=>1},42],
        'child missing computed selector fails after child emitted');
};

subtest 'custom children and supported controls' => sub {
    is_deeply(results($input,
        'try (. | (recurse(.[.cfg.key][]? | if .id == 2 then empty else . end) | .)) catch 42'),
        [$root,$first,$root->{items}[2]], 'empty child skips only its own subtree');
    is_deeply(results($input,
        'try (. | (recurse(.[.cfg.key][]? | empty) | .)) catch 42'),
        [$root], 'zero child stream leaves root');
    is_deeply(results($input,
        'try (. | (recurse(.[.cfg.key][]? | (.,.)) | type)) catch 42'),
        [('object') x 7], 'multiple child outputs preserve depth-first order');
    is_deeply(results($input, "try ($child | type) catch 42"),
        ['object','object',42], 'unwrapped custom recurse is unchanged');
    is_deeply(results($input,
        'try (. | (recurse(.[.cfg.key][] | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [@$prior,42], 'strict dotted computed form uses same routing');
    is_deeply(results('{"cfg":{"key":"items"}}',
        'try (. | (recurse(.[.cfg.key][] | .) | .)) catch 42'),
        [{cfg=>{key=>'items'}},42], 'strict selected missing array errors');
    is_deeply(results('{"cfg":{"key":"items"},"items":null}',
        'try (. | (recurse(.[.cfg.key][] | .) | .)) catch 42'),
        [{cfg=>{key=>'items'},items=>undef},42],
        'strict selected null array errors');
    is_deeply(results($input,
        'try (. | (recurse(.[.cfg.key][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [@$prior,42], 'optional dotted case remains correct');
    for my $key ('a.b', 'full name') {
        my $tree = {
            cfg => {key=>$key},
            $key => [
                {cfg=>{key=>$key},id=>1,$key=>[]},
                {cfg=>{key=>$key},id=>2,$key=>[]}
            ]
        };
        is_deeply(results($json->encode($tree),
            "try (. | ($child | .)) catch 42"),
            [$tree,$tree->{$key}[0],42],
            "computed dotted selector preserves literal key '$key'");
    }
};

done_testing;
