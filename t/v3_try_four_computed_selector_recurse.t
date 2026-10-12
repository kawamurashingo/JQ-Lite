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
sub node {
    my ($id,$children) = @_;
    my $n = {a=>'children',b=>'block',c=>'leaf',d=>'items',
        children=>{block=>{leaf=>{items=>$children || []}}}};
    $n->{id} = $id if defined $id;
    return $n;
}
my $root = node(undef,[node(1,[]),node(2,[]),node(3,[])]);
my $nested = node(undef,[node(1,[node(4,[])]),node(2,[]),node(3,[])]);
my $first = $root->{children}{block}{leaf}{items}[0];
my $child = 'recurse(.[.a][.b][.c][.d][]? | if .id == 2 then (1/0) else . end)';
my $json_input = $json->encode($root);

subtest 'four computed selector stages retain streamed outputs' => sub {
    is_deeply(results($json_input,"try (. | ($child | .)) catch 42"),
        [$root,$first,42], 'completed ancestors and siblings survive later error');
    is_deeply(results($json_input,"try (. | ($child | .))"),
        [$root,$first], 'implicit catch empty preserves earlier nodes');
    is_deeply(results($json_input,"try (. | ($child | .)) catch empty"),
        [$root,$first], 'explicit catch empty preserves earlier nodes');
    is_deeply(results($json_input,"try (. | ($child | .)) catch null"),
        [$root,$first,undef], 'catch null follows completed results');
    is_deeply(results($json_input,"try (. | ($child | .)) catch (42,43)"),
        [$root,$first,42,43], 'multiple catch outputs preserve order');
    is_deeply(results($json_input,"try (. | ($child | type)) catch type"),
        ['object','object','string'], 'catch receives error text');
    is_deeply(results($json->encode($nested),
        "try (. | ($child | .)) catch 42"),
        [$nested,$nested->{children}{block}{leaf}{items}[0],
            $nested->{children}{block}{leaf}{items}[0]{children}{block}{leaf}{items}[0],42],
        'nested descendants appear in depth-first order');
    is_deeply(results($json_input,"try (. | ($child | (.,0))) catch 42"),
        [$root,0,$first,0,42], 'comma suffix runs after each completed output');
    is_deeply(results($json_input,"try (. | (($child | .),99)) catch 42"),
        [$root,$first,42], 'later comma alternative does not run');
    is_deeply(results($json_input,
        "try (. | ($child | if .id == 1 then (1/0) else . end)) catch 42"),
        [$root,42], 'downstream failure stops child expansion');
};

subtest 'selector error and strict/optional iterator boundaries' => sub {
    is_deeply(results('null',"try (. | ($child | .)) catch 42"),
        [undef,42], 'null node is emitted before computed-key error');
    is_deeply(results('{}',"try (. | ($child | .)) catch 42"),
        [{},42], 'missing selector key fails after emitting object');
    my $missing = {a=>'children',b=>'block',c=>'leaf',d=>'items'};
    is_deeply(results($json->encode($missing),
        'try (. | (recurse(.[.a][.b][.c][.d][]? | .) | .)) catch 42'),
        [$missing], 'optional iterator skips missing selected array');
    is_deeply(results($json->encode($missing),
        'try (. | (recurse(.[.a][.b][.c][.d][] | .) | .)) catch 42'),
        [$missing,42], 'strict iterator errors after root');
    my $empty = node(undef,[]);
    is_deeply(results($json->encode($empty),
        'try (. | (recurse(.[.a][.b][.c][.d][]? | .) | .)) catch 42'),
        [$empty], 'empty selected list ends recursion');
    is_deeply(results($json_input,
        'try (. | (recurse(.[.a][.b][.c][.d][]? | (.,.)) | type)) catch 42'),
        [('object') x 7], 'duplicate children traverse depth-first');
};

subtest 'mixed quoted and numeric selector stages' => sub {
    sub indexed {
        my ($id,$kids) = @_;
        my $n = {cfg=>{a=>['children'],b=>['block'],c=>['leaf'],d=>['items']},
            children=>{block=>{leaf=>{items=>$kids || []}}}};
        $n->{id}=$id if defined $id;
        return $n;
    }
    my $tree=indexed(undef,[indexed(1,[]),indexed(2,[])]);
    my $expr='recurse(.[.cfg["a"][0]][.cfg."b"[0]][.cfg.c[-1]][.cfg.d[0]][]? | if .id == 2 then (1/0) else . end)';
    is_deeply(results($json->encode($tree),
        "try (. | ($expr | .)) catch 42"),
        [$tree,$tree->{children}{block}{leaf}{items}[0],42],
        'quoted and negative numeric paths preserve output order');
    is_deeply(results($json->encode($tree),
        'try (. | (recurse(.[.cfg["a"][0]][.cfg."b"[0]][.cfg.c[-1]][.cfg.d[0]][] | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$tree,$tree->{children}{block}{leaf}{items}[0],42],
        'strict quoted/numeric four-selector form preserves outputs');
};

done_testing;
