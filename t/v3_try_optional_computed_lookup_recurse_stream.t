use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;
sub results {
    my ($input,$filter) = @_;
    return [ $jq->run_query($input,$filter) ];
}
my $input='{"key":"items","items":[{"key":"items","id":1,"items":[]},{"key":"items","id":2,"items":[]},{"key":"items","id":3,"items":[]}]}';
my $root=$json->decode($input);
my $first=$root->{items}[0];
my $child='recurse(.[.key]?[]? | if .id == 2 then (1/0) else . end)';

subtest 'optional computed lookup streams prior recursive outputs' => sub {
    is_deeply(results($input,"try (. | ($child | .)) catch 42"),
        [$root,$first,42], 'completed root and first child precede error');
    is_deeply(results($input,"try (. | ($child | .))"),
        [$root,$first], 'implicit empty handler keeps prior outputs');
    is_deeply(results($input,"try (. | ($child | .)) catch null"),
        [$root,$first,undef], 'null handler follows prior outputs');
    is_deeply(results($input,"try (. | ($child | .)) catch (42,43)"),
        [$root,$first,42,43], 'two catch outputs preserve ordering');
    is_deeply(results($input,"try (. | ($child | (.,0))) catch 42"),
        [$root,0,$first,0,42], 'comma tail follows completed nodes');
    is_deeply(results($input,"try (. | (($child | .),99)) catch 42"),
        [$root,$first,42], 'later comma alternative does not run');
    is_deeply(results($input,
        "try (. | ($child | if .id == 1 then (1/0) else . end)) catch 42"),
        [$root,42], 'downstream tail error stops further expansion');
    my $nested = {
        key=>'items',items=>[
            {key=>'items',id=>1,items=>[
                {key=>'items',id=>4,items=>[]}]},
            {key=>'items',id=>2,items=>[]}
        ]
    };
    is_deeply(results($json->encode($nested),
        "try (. | ($child | .)) catch 42"),
        [$nested,$nested->{items}[0],$nested->{items}[0]{items}[0],42],
        'nested descendants precede failing sibling');
};

subtest 'outer computed optionality differs from selector optionality' => sub {
    is_deeply(results('null',"try (. | ($child | .)) catch 42"),
        [undef], 'null computed key is suppressed by optional lookup');
    is_deeply(results('{}',"try (. | ($child | .)) catch 42"),
        [{}], 'missing null key is suppressed by optional lookup');
    is_deeply(results('{"key":null}',"try (. | ($child | .)) catch 42"),
        [{key=>undef}], 'explicit null key produces no child results');
    is_deeply(results('{"key":3}',"try (. | ($child | .)) catch 42"),
        [{key=>3}], 'invalid numeric key is suppressed by optional lookup');
    is_deeply(results('3',"try (. | ($child | .)) catch 42"),
        [3,42], 'selector field access still errors on scalar input');
    is_deeply(results('false',"try (. | ($child | .)) catch 42"),
        [JSON::PP::false,42], 'boolean selector access still errors');
    is_deeply(results('{"key":"items"}',"try (. | ($child | .)) catch 42"),
        [{key=>'items'}], 'valid key with missing selected field skips iteration');
    is_deeply(results('{"key":"items"}',
        'try (. | (recurse(.[.key]?[] | .) | .)) catch 42'),
        [{key=>'items'},42], 'strict iteration rejects missing selected value');
    is_deeply(results('{}',
        'try (. | (recurse(.[.key]?[] | .) | .)) catch 42'),
        [{}], 'empty optional computed lookup skips strict iteration');
};

subtest 'computed selector errors are not swallowed by outer question mark' => sub {
    is_deeply(results('{"cfg":3}',
        'try (. | (recurse(.[.cfg.name]?[]? | .) | .)) catch 42'),
        [{cfg=>3},42], 'bad dotted selector errors before computed optionality');
    is_deeply(results('{"cfg":3}',
        'try (. | (recurse(.[.cfg."name"]?[]? | .) | .)) catch 42'),
        [{cfg=>3},42], 'bad dot-quoted selector errors before optionality');
    is_deeply(results('{"cfg":3}',
        'try (. | (recurse(.[.cfg["name"]]?[]? | .) | .)) catch 42'),
        [{cfg=>3},42], 'bad bracket-quoted selector errors before optionality');
    my $input='{"cfg":{"name":"items"},"items":[{"cfg":{"name":"items"},"id":1,"items":[]},{"cfg":{"name":"items"},"id":2,"items":[]}]}';
    my $tree=$json->decode($input);
    for my $sel ('.cfg.name', '.cfg."name"', '.cfg["name"]') {
        my $filter='try (. | (recurse(.['.$sel.']?[]? | if .id == 2 then (1/0) else . end) | .)) catch 42';
        is_deeply(results($input,$filter),[$tree,$tree->{items}[0],42],
            "optional computed lookup $sel preserves prior outputs");
    }

    my $paired = {
        first=>'items',second=>'nodes',items=>{nodes=>[
            {first=>'items',second=>'nodes',id=>1,items=>{nodes=>[]}},
            {first=>'items',second=>'nodes',id=>2,items=>{nodes=>[]}}
        ]}
    };
    is_deeply(results($json->encode($paired),
        'try (. | (recurse(.[.first]?[.second]?[]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$paired,$paired->{items}{nodes}[0],42],
        'two optional computed lookup stages preserve earlier outputs');
    is_deeply(results($input,
        'try (. | (recurse(.[.cfg.name][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$tree,$tree->{items}[0],42],
        'previous strict computed lookup remains unchanged');
};
done_testing;
