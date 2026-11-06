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
my $json = JSON::PP->new->allow_nonref;
my $input = '{"field":"items","items":[{"field":"items","id":1,"items":[]},{"field":"items","id":2,"items":[]},{"field":"items","id":3,"items":[]}]}';
my $nested = '{"field":"items","items":[{"field":"items","id":1,"items":[{"field":"items","id":4,"items":[]}]},{"field":"items","id":2,"items":[]},{"field":"items","id":3,"items":[]}]}';
my $child = 'recurse(.[.field][]? | if .id == 2 then (1/0) else . end)';
my $root = $json->decode($input);
my $first = $root->{items}[0];
my $prior = [$root, $first];

subtest 'completed recursive nodes survive later computed-child errors' => sub {
    is_deeply(results($input, "try (. | ($child | .)) catch 42"),
        [@$prior,42], 'root and first child precede caught error');
    is_deeply(results($input, "try (. | ($child | .))"),
        $prior, 'implicit catch empty retains earlier nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch empty"),
        $prior, 'explicit catch empty retains earlier nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch null"),
        [@$prior,undef], 'catch null adds one JSON null');
    is_deeply(results($input, "try (. | ($child | .)) catch (42,43)"),
        [@$prior,42,43], 'multiple catches follow prior nodes');
    is_deeply(results($input, "try (. | ($child | type)) catch type"),
        ['object','object','string'], 'catch type sees an error string');
    my $nested_root = $json->decode($nested);
    is_deeply(results($nested, "try (. | ($child | .)) catch 42"),
        [$nested_root, $nested_root->{items}[0],
         $nested_root->{items}[0]{items}[0],42],
        'nested descendants appear before later sibling error');
};

subtest 'downstream and outer pipeline boundaries' => sub {
    is_deeply(results($input, "try (. | ($child | (.,0))) catch 42"),
        [$root,0,$first,0,42], 'comma tail emits per recursive node');
    is_deeply(results($input, "try (. | (($child | .),99)) catch 42"),
        [@$prior,42], 'later comma alternative is not evaluated');
    is_deeply(results($input, "try (. | (($child | .))) catch 42"),
        [@$prior,42], 'extra wrapping parentheses retain streams');
    is_deeply(results($input,
        "try (. | ($child | if .id == 1 then (1/0) else . end)) catch 42"),
        [$root,42], 'tail failure prevents later child expansion');
    my $other = '{"field":"items","items":[{"field":"items","id":5,"items":[]}]}';
    is_deeply(results("[$input,$other]",
        "try (.[] | ($child | type)) catch 42"),
        ['object','object',42], 'later outer array input is skipped');
    is_deeply(results('{"groups":[' . $input . ',' . $other . ']}',
        "try (.groups[] | ($child | type)) catch 42"),
        ['object','object',42], 'later named-field iterator is skipped');
};

subtest 'child values and computed selector error boundaries' => sub {
    is_deeply(results($input,
        'try (. | (recurse(.[.field][]? | if .id == 2 then empty else . end) | .)) catch 42'),
        [$root,$first,$root->{items}[2]], 'empty child skips only one sibling');
    is_deeply(results($input,
        'try (. | (recurse(.[.field][]? | empty) | .)) catch 42'),
        [$root], 'empty child stream retains the root');
    is_deeply(results($input,
        'try (. | (recurse(.[.field][]? | (.,.)) | type)) catch 42'),
        [('object') x 7], 'duplicated children remain depth-first');
    is_deeply(results('null', "try (. | ($child | .)) catch 42"),
        [undef,42], 'selector error after null root is not hidden by []?');
    is_deeply(results('3', "try (. | ($child | .)) catch 42"),
        [3,42], 'scalar root field-lookup error is caught');
    is_deeply(results('{}', "try (. | ($child | .)) catch 42"),
        [{},42], 'missing computed key is a runtime error');
    is_deeply(results('{"field":null}', "try (. | ($child | .)) catch 42"),
        [{field=>undef},42], 'explicit null computed key errors');
    is_deeply(results('{"field":"items"}', "try (. | ($child | .)) catch 42"),
        [{field=>'items'}], 'missing selected array is omitted');
    is_deeply(results('{"field":"items","items":null}',
        "try (. | ($child | .)) catch 42"),
        [{field=>'items',items=>undef}], 'optional iteration drops selected null');
    is_deeply(results('{"field":"items","items":[]}',
        "try (. | ($child | .)) catch 42"),
        [{field=>'items',items=>[]}], 'empty computed array ends recursion');
    my $missing = '{"field":"items","items":[{"id":1}]}';
    is_deeply(results($missing,
        'try (. | (recurse(.[.field][]? | .) | .)) catch 42'),
        [$json->decode($missing),{id=>1},42],
        'missing child selector fails after already yielded child');
    is_deeply(results('false', "try (. | ($child | .)) catch 42"),
        [JSON::PP::false,42], 'boolean root emits before selector error');
};

subtest 'special computed keys and supported controls' => sub {
    is_deeply(results($input, "try ($child | type) catch 42"),
        ['object','object',42], 'unwrapped custom recurse remains unchanged');
    is_deeply(results($input,
        'try (. | (recurse(.["items"][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [@$prior,42], 'literal-quoted child pipeline remains unchanged');
    for my $key ('a.b', 'full name') {
        my $data = {
            field => $key,
            $key => [
                { field => $key, id => 1, $key => [] },
                { field => $key, id => 2, $key => [] }
            ]
        };
        is_deeply(results($json->encode($data),
            "try (. | ($child | .)) catch 42"),
            [$data, $data->{$key}[0],42],
            "computed selector treats '$key' as one literal key");
    }
};

done_testing;
