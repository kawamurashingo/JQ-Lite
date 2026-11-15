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
my $input = '{"key":"items","items":[{"key":"items","id":1,"items":[]},{"key":"items","id":2,"items":[]},{"key":"items","id":3,"items":[]}]}';
my $root = $json->decode($input);
my $first = $root->{items}[0];
my $child = 'recurse(.[.key?][]? | if .id == 2 then (1/0) else . end)';

subtest 'optional field computed recurse preserves completed output' => sub {
    is_deeply(results($input,"try (. | ($child | .)) catch 42"),
        [$root,$first,42], 'completed node and prior sibling precede failure');
    is_deeply(results($input,"try (. | ($child | .))"),
        [$root,$first], 'implicit empty catch keeps prior results');
    is_deeply(results($input,"try (. | ($child | .)) catch null"),
        [$root,$first,undef], 'catch null follows prior results');
    is_deeply(results($input,"try (. | ($child | .)) catch (42,43)"),
        [$root,$first,42,43], 'multiple caught outputs keep order');
    is_deeply(results($input,"try (. | ($child | (.,0))) catch 42"),
        [$root,0,$first,0,42], 'comma tail follows each completed value');
    is_deeply(results($input,"try (. | (($child | .),99)) catch 42"),
        [$root,$first,42], 'later comma alternative never runs');
    is_deeply(results($input,
        "try (. | ($child | if .id == 1 then (1/0) else . end)) catch 42"),
        [$root,42], 'downstream error stops child traversal');
    my $nested = {
        key=>'items', items=>[
            {key=>'items',id=>1,items=>[{key=>'items',id=>4,items=>[]}]},
            {key=>'items',id=>2,items=>[]}
        ]
    };
    is_deeply(results($json->encode($nested),
        "try (. | ($child | .)) catch 42"),
        [$nested,$nested->{items}[0],$nested->{items}[0]{items}[0],42],
        'grandchild precedes later failing sibling');
};

subtest 'optional field lookup does not mask null keys' => sub {
    is_deeply(results('null',"try (. | ($child | .)) catch 42"),
        [undef,42], 'null root emitted before invalid null computed key');
    is_deeply(results('{}',"try (. | ($child | .)) catch 42"),
        [{},42], 'missing field on object still yields null key');
    is_deeply(results('{"key":null}',"try (. | ($child | .)) catch 42"),
        [{key=>undef},42], 'explicit null computed key fails');
    is_deeply(results('{"key":3}',"try (. | ($child | .)) catch 42"),
        [{key=>3},42], 'number cannot index object as a computed key');
    is_deeply(results('3',"try (. | ($child | .)) catch 42"),
        [3], 'optional field suppresses invalid scalar field lookup');
    is_deeply(results('false',"try (. | ($child | .)) catch 42"),
        [JSON::PP::false], 'optional field suppresses boolean lookup');
    is_deeply(results('{"key":"items"}',"try (. | ($child | .)) catch 42"),
        [{key=>'items'}], 'optional child iterator skips missing container');
    is_deeply(results('{"key":"items"}',
        'try (. | (recurse(.[.key?][] | .) | .)) catch 42'),
        [{key=>'items'},42], 'strict child iterator still raises');
    is_deeply(results('3',
        'try (. | (recurse(.[.key?][] | .) | .)) catch 42'),
        [3], 'empty selector stream suppresses strict iteration');
};

subtest 'optional dotted and JSON-quoted fields' => sub {
    my $input = '{"cfg":{"name":"items"},"items":[{"cfg":{"name":"items"},"id":1,"items":[]},{"cfg":{"name":"items"},"id":2,"items":[]}]}';
    my $tree = $json->decode($input);
    for my $selector (
        '.cfg.name?',
        '.cfg."name"?',
        '.cfg["name"]?',
        '.cfg?.name?',
        '.cfg?["name"]?',
    ) {
        my $child = 'recurse(.[' . $selector
            . '][]? | if .id == 2 then (1/0) else . end)';
        is_deeply(results($input,"try (. | ($child | .)) catch 42"),
            [$tree,$tree->{items}[0],42],
            "optional selector $selector preserves prior nodes");
        is_deeply(results('{"cfg":3}',
            "try (. | ($child | .)) catch 42"),
            [{cfg=>3}],
            "optional field $selector retains stage-specific errors");
    }
    my $special = {
        cfg=>{'a.b'=>'items'},
        items=>[
            {cfg=>{'a.b'=>'items'},id=>1,items=>[]},
            {cfg=>{'a.b'=>'items'},id=>2,items=>[]}
        ]
    };
    is_deeply(results($json->encode($special),
        'try (. | (recurse(.[.cfg["a.b"]?][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$special,$special->{items}[0],42],
        'period within JSON-quoted field remains literal');
    my $paired = {
        first=>{k=>'items'}, second=>{k=>'nodes'},items=>{nodes=>[
            {first=>{k=>'items'},second=>{k=>'nodes'},id=>1,items=>{nodes=>[]}},
            {first=>{k=>'items'},second=>{k=>'nodes'},id=>2,items=>{nodes=>[]}}
        ]}
    };
    is_deeply(results($json->encode($paired),
        'try (. | (recurse(.[.first.k?][.second.k?][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$paired,$paired->{items}{nodes}[0],42],
        'two optional selectors independently resolve on current node');
};

done_testing;
