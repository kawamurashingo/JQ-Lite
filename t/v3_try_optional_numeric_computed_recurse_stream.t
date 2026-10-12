use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq=JQ::Lite->new;
my $json=JSON::PP->new->allow_nonref;
sub results {
    my ($input,$filter)=@_;
    return [ $jq->run_query($input,$filter) ];
}

my $input='{"keys":["items"],"items":[{"keys":["items"],"id":1,"items":[]},{"keys":["items"],"id":2,"items":[]},{"keys":["items"],"id":3,"items":[]}]}';
my $root=$json->decode($input);
my $first=$root->{items}[0];
my $child='recurse(.[.keys[0]?][]? | if .id == 2 then (1/0) else . end)';

subtest 'optional numeric computed selector retains completed nodes' => sub {
    is_deeply(results($input,"try (. | ($child | .)) catch 42"),
        [$root,$first,42], 'earlier root and sibling survive late failure');
    is_deeply(results($input,"try (. | ($child | .))"),
        [$root,$first], 'implicit catch empty preserves emitted nodes');
    is_deeply(results($input,"try (. | ($child | .)) catch null"),
        [$root,$first,undef], 'catch null follows completed outputs');
    is_deeply(results($input,"try (. | ($child | .)) catch (42,43)"),
        [$root,$first,42,43], 'multi-valued catch follows outputs');
    is_deeply(results($input,"try (. | ($child | (.,0))) catch 42"),
        [$root,0,$first,0,42], 'per-node tail order is preserved');
    is_deeply(results($input,"try (. | (($child | .),99)) catch 42"),
        [$root,$first,42], 'later comma alternative is not executed');
    is_deeply(results($input,
        "try (. | ($child | if .id == 1 then (1/0) else . end)) catch 42"),
        [$root,42], 'tail error stops further traversal');
    my $nested={
        keys=>['items'],items=>[
            {keys=>['items'],id=>1,items=>[
                {keys=>['items'],id=>4,items=>[]}]},
            {keys=>['items'],id=>2,items=>[]}
        ]
    };
    is_deeply(results($json->encode($nested),
        "try (. | ($child | .)) catch 42"),
        [$nested,$nested->{items}[0],$nested->{items}[0]{items}[0],42],
        'nested descendants precede a later sibling error');
};

subtest 'optional numeric index does not suppress null computed key' => sub {
    is_deeply(results('null',"try (. | ($child | .)) catch 42"),
        [undef,42], 'null root is emitted before null-key failure');
    is_deeply(results('{}',"try (. | ($child | .)) catch 42"),
        [{},42], 'missing keys field yields an invalid null key');
    is_deeply(results('{"keys":[]}',"try (. | ($child | .)) catch 42"),
        [{keys=>[]},42], 'out-of-range index returns a null key');
    is_deeply(results('{"keys":null}',"try (. | ($child | .)) catch 42"),
        [{keys=>undef},42], 'null array produces an invalid null key');
    is_deeply(results('{"keys":3}',"try (. | ($child | .)) catch 42"),
        [{keys=>3}], 'optional numeric index suppresses scalar-index error');
    is_deeply(results('{"keys":{}}',"try (. | ($child | .)) catch 42"),
        [{keys=>{}}], 'optional numeric index suppresses object-index error');
    is_deeply(results('{"keys":false}',"try (. | ($child | .)) catch 42"),
        [{keys=>JSON::PP::false}], 'optional numeric index suppresses boolean-index error');
    is_deeply(results('{"keys":["items"]}',"try (. | ($child | .)) catch 42"),
        [{keys=>['items']}], 'missing selected child array is omitted');
    is_deeply(results('{"keys":["items"],"items":null}',
        "try (. | ($child | .)) catch 42"),
        [{keys=>['items'],items=>undef}], 'null selected child is omitted');
    is_deeply(results('{"keys":["items"]}',
        'try (. | (recurse(.[.keys[0]?][] | .) | .)) catch 42'),
        [{keys=>['items']},42], 'strict child iterator still raises');
    is_deeply(results('{"keys":3}',
        'try (. | (recurse(.[.keys[0]?][] | .) | .)) catch 42'),
        [{keys=>3}], 'empty optional selector stream avoids strict iterator');
};

subtest 'optional numeric stages compose with quoted field lookups' => sub {
    my $nested={
        cfg=>{names=>[['items']]},items=>[
            {cfg=>{names=>[['items']]},id=>1,items=>[]},
            {cfg=>{names=>[['items']]},id=>2,items=>[]}
        ]
    };
    my $first=$nested->{items}[0];
    for my $selector (
        '.cfg.names[0]?[0]?',
        '.cfg["names"][0]?[0]?',
        '.cfg."names"[0]?[0]?',
    ) {
        my $filter='try (. | (recurse(.['.$selector.'][]? | if .id == 2 then (1/0) else . end) | .)) catch 42';
        is_deeply(results($json->encode($nested),$filter),
            [$nested,$first,42],
            "optional nested numeric selector stages: $selector");
    }
    is_deeply(results($input,
        'try (. | (recurse(.[.keys[0]][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$root,$root->{items}[0],42],
        'previous non-optional numeric selector remains unchanged');
};

done_testing;
