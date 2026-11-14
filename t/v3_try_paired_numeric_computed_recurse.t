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
my $input = '{"cfg":{"first":["children"],"second":["list"]},"children":{"list":[{"cfg":{"first":["children"],"second":["list"]},"id":1,"children":{"list":[]}},{"cfg":{"first":["children"],"second":["list"]},"id":2,"children":{"list":[]}},{"cfg":{"first":["children"],"second":["list"]},"id":3,"children":{"list":[]}}]}}';
my $nested = '{"cfg":{"first":["children"],"second":["list"]},"children":{"list":[{"cfg":{"first":["children"],"second":["list"]},"id":1,"children":{"list":[{"cfg":{"first":["children"],"second":["list"]},"id":4,"children":{"list":[]}}]}},{"cfg":{"first":["children"],"second":["list"]},"id":2,"children":{"list":[]}},{"cfg":{"first":["children"],"second":["list"]},"id":3,"children":{"list":[]}}]}}';
my $root = $json->decode($input);
my $prior = [$root,$root->{children}{list}[0]];

my @forms = (
    ['.cfg.first[0]', '.cfg.second[0]'],
    ['.cfg["first"][0]', '.cfg.second[0]'],
    ['.cfg.first[0]', '.cfg["second"][0]'],
    ['.cfg."first"[0]', '.cfg."second"[0]'],
    ['.cfg["first"][0]', '.cfg."second"[0]'],
    ['.cfg.first[-1]', '.cfg.second[-1]'],
);
for my $pair (@forms) {
    my ($first,$second) = @$pair;
    my $child = "recurse(.[$first][$second][]? | if .id == 2 then (1/0) else . end)";
    subtest "$first / $second" => sub {
        is_deeply(results($input,"try (. | ($child | .)) catch 42"),
            [@$prior,42], 'earlier nodes survive failing sibling');
        is_deeply(results($input,"try (. | ($child | .)) catch empty"),
            $prior, 'empty catch does not erase completed outputs');
        is_deeply(results($input,"try (. | ($child | .)) catch null"),
            [@$prior,undef], 'null catch appends one JSON null');
        is_deeply(results($input,"try (. | ($child | (.,0))) catch 42"),
            [$root,0,$root->{children}{list}[0],0,42],
            'comma tail is ordered per node');
        is_deeply(results($input,"try (. | (($child | .),99)) catch 42"),
            [@$prior,42], 'later comma alternative is skipped');
        my $tree = $json->decode($nested);
        is_deeply(results($nested,"try (. | ($child | .)) catch 42"),
            [$tree,$tree->{children}{list}[0],
             $tree->{children}{list}[0]{children}{list}[0],42],
            'nested descendants appear depth-first');
        is_deeply(results('null',"try (. | ($child | .)) catch 42"),
            [undef,42], 'null selector error occurs after node output');
        is_deeply(results('{"cfg":{"first":["children"],"second":["list"]}}',
            "try (. | ($child | .)) catch 42"),
            [{cfg=>{first=>['children'],second=>['list']}}],
            'optional iterator skips missing selected children');
        is_deeply(results('{"cfg":{"first":["children"],"second":["list"]}}',
            "try (. | (recurse(.[$first][$second][] | .) | .)) catch 42"),
            [{cfg=>{first=>['children'],second=>['list']}},42],
            'strict iterator raises after previous root');
        is_deeply(results($input,
            "try (. | (recurse(.[$first][$second][]? | (.,.)) | type)) catch 42"),
            [('object') x 7], 'duplicate child outputs retain order');
    };
}

subtest 'signed index and optional suffix combinations' => sub {
    my $d = $json->decode($input);
    is_deeply(results($input,
        'try (. | (recurse(.[.cfg.first[0]][.cfg.second][]? | .) | .)) catch 42'),
        [$d,42], 'one indexed selector plus an array-valued key errors');
    is_deeply(results($input,
        'try (. | (recurse(.[.cfg.first[0]][.cfg.second[0]][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$d,$d->{children}{list}[0],42], 'two indexed selectors yield prior nodes');
};

done_testing;
