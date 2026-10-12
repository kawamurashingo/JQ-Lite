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
    my $n = {
        first=>'children', second=>'block', third=>'nodes',
        children=>{block=>{nodes=>$children || []}}
    };
    $n->{id}=$id if defined $id;
    return $n;
}
my $root = node(undef,[node(1,[]),node(2,[]),node(3,[])]);
my $nested = node(undef,[
    node(1,[node(4,[])]), node(2,[]), node(3,[])
]);
my $prior = [$root,$root->{children}{block}{nodes}[0]];
my $head = 'recurse(.[.first][.second][.third][]? | if .id == 2 then (1/0) else . end)';
subtest 'three selector stages preserve completed recursion nodes' => sub {
    my $input=$json->encode($root);
    is_deeply(results($input,"try (. | ($head | .)) catch 42"),
        [@$prior,42], 'root and first child retained on later error');
    is_deeply(results($input,"try (. | ($head | .))"),
        $prior, 'implicit catch empty preserves earlier outputs');
    is_deeply(results($input,"try (. | ($head | .)) catch null"),
        [@$prior,undef], 'null catch follows prior outputs');
    is_deeply(results($input,"try (. | ($head | .)) catch (42,43)"),
        [@$prior,42,43], 'multiple catches follow previous nodes');
    is_deeply(results($input,"try (. | ($head | type)) catch type"),
        ['object','object','string'], 'catch sees error string');
    is_deeply(results($json->encode($nested),
        "try (. | ($head | .)) catch 42"),
        [$nested,$nested->{children}{block}{nodes}[0],
         $nested->{children}{block}{nodes}[0]{children}{block}{nodes}[0],42],
        'depth-first descendant precedes later failed sibling');
    is_deeply(results($input,"try (. | ($head | (.,0))) catch 42"),
        [$root,0,$root->{children}{block}{nodes}[0],0,42],
        'comma tail preserves per-node order');
    is_deeply(results($input,"try (. | (($head | .),99)) catch 42"),
        [@$prior,42], 'later comma alternative suppressed');
    is_deeply(results($input,
        "try (. | ($head | if .id == 1 then (1/0) else . end)) catch 42"),
        [$root,42], 'tail failure stops later children');
};

subtest 'optional versus strict and selector key errors' => sub {
    is_deeply(results('null',"try (. | ($head | .)) catch 42"),
        [undef,42], 'null root emitted before selector failure');
    is_deeply(results('{}',"try (. | ($head | .)) catch 42"),
        [{},42], 'missing first selector key fails after root');
    my $missing = {first=>'children',second=>'block',third=>'nodes'};
    is_deeply(results($json->encode($missing),
        'try (. | (recurse(.[.first][.second][.third][]? | .) | .)) catch 42'),
        [$missing], 'optional iterator skips absent selected array');
    is_deeply(results($json->encode($missing),
        'try (. | (recurse(.[.first][.second][.third][] | .) | .)) catch 42'),
        [$missing,42], 'strict iterator fails on absent selected array');
    my $empty=node(undef,[]);
    is_deeply(results($json->encode($empty),
        'try (. | (recurse(.[.first][.second][.third][]? | .) | .)) catch 42'),
        [$empty], 'empty child array ends normally');
    is_deeply(results($json->encode($root),
        'try (. | (recurse(.[.first][.second][.third][]? | (.,.)) | type)) catch 42'),
        [('object') x 7], 'duplicate child outputs retain depth-first order');
};

subtest 'mixed quoted and numeric stages resolve from each node' => sub {
    sub indexed {
        my ($id,$children)=@_;
        my $n = {
            cfg=>{first=>['children'],second=>['block'],third=>['nodes']},
            children=>{block=>{nodes=>$children || []}}
        };
        $n->{id}=$id if defined $id;
        return $n;
    }
    my $tree=indexed(undef,[indexed(1,[]),indexed(2,[])]);
    my $child = 'recurse(.[.cfg["first"][0]][.cfg."second"[0]][.cfg.third[-1]][]? | if .id == 2 then (1/0) else . end)';
    is_deeply(results($json->encode($tree),
        "try (. | ($child | .)) catch 42"),
        [$tree,$tree->{children}{block}{nodes}[0],42],
        'mixed field and signed numeric selector stages');
    is_deeply(results($json->encode($tree),
        'try (. | (recurse(.[.cfg["first"][0]][.cfg."second"[0]][.cfg.third[-1]][] | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$tree,$tree->{children}{block}{nodes}[0],42],
        'strict mixed selectors preserve earlier outputs');
    is_deeply(results($json->encode($root),
        'try (. | (recurse(.[.first][.second][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$root,42], 'old two-selector behavior is not reinterpreted');
};
done_testing;
