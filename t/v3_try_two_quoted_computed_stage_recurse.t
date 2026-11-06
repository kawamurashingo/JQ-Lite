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
my $source = '{"cfg":{"first":"children","second":"list"},"children":{"list":[{"cfg":{"first":"children","second":"list"},"id":1,"children":{"list":[]}},{"cfg":{"first":"children","second":"list"},"id":2,"children":{"list":[]}},{"cfg":{"first":"children","second":"list"},"id":3,"children":{"list":[]}}]}}';
my $nested = '{"cfg":{"first":"children","second":"list"},"children":{"list":[{"cfg":{"first":"children","second":"list"},"id":1,"children":{"list":[{"cfg":{"first":"children","second":"list"},"id":4,"children":{"list":[]}}]}},{"cfg":{"first":"children","second":"list"},"id":2,"children":{"list":[]}},{"cfg":{"first":"children","second":"list"},"id":3,"children":{"list":[]}}]}}';
my $root = $json->decode($source);
my $prior = [$root,$root->{children}{list}[0]];

my @variants = (
    ['.cfg["first"]', '.cfg.second'],
    ['.cfg."first"', '.cfg.second'],
    ['.cfg.first', '.cfg["second"]'],
    ['.cfg.first', '.cfg."second"'],
    ['.cfg["first"]', '.cfg["second"]'],
    ['.cfg."first"', '.cfg."second"'],
    ['.cfg["first"]', '.cfg."second"'],
);
for my $stages (@variants) {
    my ($a,$b) = @$stages;
    my $child = "recurse(.[$a][$b][]? | if .id == 2 then (1/0) else . end)";
    subtest "two computed stages $a / $b" => sub {
        is_deeply(results($source,"try (. | ($child | .)) catch 42"),
            [@$prior,42], 'completed parent and sibling before error');
        is_deeply(results($source,"try (. | ($child | .))"),
            $prior, 'implicit catch retains completed outputs');
        is_deeply(results($source,"try (. | ($child | .)) catch null"),
            [@$prior,undef], 'catch null follows the prior outputs');
        is_deeply(results($source,"try (. | ($child | (.,0))) catch 42"),
            [$root,0,$root->{children}{list}[0],0,42],
            'comma tail preserves per-node output order');
        is_deeply(results($source,"try (. | (($child | .),99)) catch 42"),
            [@$prior,42], 'later comma branch is suppressed');
        is_deeply(results($source,
            "try (. | ($child | if .id == 1 then (1/0) else . end)) catch 42"),
            [$root,42], 'downstream error stops child traversal');
        my $tree = $json->decode($nested);
        is_deeply(results($nested,"try (. | ($child | .)) catch 42"),
            [$tree,$tree->{children}{list}[0],
             $tree->{children}{list}[0]{children}{list}[0],42],
            'nested completed descendants precede later sibling failure');
        is_deeply(results('null',"try (. | ($child | .)) catch 42"),
            [undef,42], 'null node yields before selector error');
        is_deeply(results('{"cfg":{"first":"children","second":"list"}}',
            "try (. | ($child | .)) catch 42"),
            [{cfg=>{first=>'children',second=>'list'}}],
            'optional child iterator skips missing selected value');
        is_deeply(results('{"cfg":{"first":"children","second":"list"}}',
            "try (. | (recurse(.[$a][$b][] | .) | .)) catch 42"),
            [{cfg=>{first=>'children',second=>'list'}},42],
            'strict child iterator raises on missing selected value');
        is_deeply(results($source,
            "try (. | (recurse(.[$a][$b][]? | (.,.)) | type)) catch 42"),
            [('object') x 7],
            'duplicate custom children retain depth-first ordering');
    };
}

subtest 'quoted field keys remain literal in each selector stage' => sub {
    my $special = {
        cfg=>{'a.b'=>'children','x]y'=>'list'},
        children=>{list=>[
            {cfg=>{'a.b'=>'children','x]y'=>'list'},id=>1,
             children=>{list=>[]}},
            {cfg=>{'a.b'=>'children','x]y'=>'list'},id=>2,
             children=>{list=>[]}}
        ]}
    };
    my $child = 'recurse(.[.cfg["a.b"]][.cfg."x]y"][]? | if .id == 2 then (1/0) else . end)';
    is_deeply(results($json->encode($special),
        "try (. | ($child | .)) catch 42"),
        [$special,$special->{children}{list}[0],42],
        'punctuation in quoted selector fields is not path syntax');
};

subtest 'earlier two-identifier selector form is unchanged' => sub {
    my $plain = '{"first":"children","second":"list","children":{"list":[{"first":"children","second":"list","id":1,"children":{"list":[]}},{"first":"children","second":"list","id":2,"children":{"list":[]}}]}}';
    my $root = $json->decode($plain);
    is_deeply(results($plain,
        'try (. | (recurse(.[.first][.second][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$root,$root->{children}{list}[0],42],
        'previous simple computed selector streaming is preserved');
};
done_testing;
