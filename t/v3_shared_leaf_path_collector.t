use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;

sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

my @cases = (
    [
        '{"b":{"z":false,"a":[1,{"k":2}]},"a":true}',
        [['a'],['b','a',0],['b','a',1,'k'],['b','z']],
        'nested hash/array leaves keep sorted depth-first order',
    ],
    [
        '[null,[],{},[true,{"x":3}],false]',
        [[0],[3,0],[3,1,'x'],[4]],
        'null/booleans are leaves and empty containers produce no paths',
    ],
    [
        '{"a":[],"b":{},"c":{"x":null}}',
        [['c','x']],
        'empty nested containers are excluded but null leaf retained',
    ],
);
for my $case (@cases) {
    my ($json, $expected, $name) = @$case;
    is_deeply(results($json, 'paths(scalars)'), $expected,
        "paths(scalars): $name");
    is_deeply(results($json, 'leaf_paths'), [$expected],
        "leaf_paths: $name");
}

is_deeply(results('null', 'paths(scalars)'), [],
    'paths(scalars) excludes a scalar null root');
is_deeply(results('null', 'leaf_paths'), [[[]]],
    'leaf_paths emits the empty path for a scalar null root');
is_deeply(results('false', 'paths(scalars)'), [],
    'paths(scalars) excludes a scalar false root');
is_deeply(results('false', 'leaf_paths'), [[[]]],
    'leaf_paths emits the empty path for a boolean root');
is_deeply(results('[]', 'paths(scalars)'), [],
    'empty root array has no scalar leaves');
is_deeply(results('[]', 'leaf_paths'), [[]],
    'leaf_paths returns an empty path collection for empty root array');

# Keep the existing private helper's scalar-root behavior, not the leaf
# collector's special empty-path behavior. This protects callers of the
# already-defined internal function after it becomes a thin wrapper.
for my $scalar (undef, 12, 'text', JSON::PP::false) {
    my @paths;
    JQ::Lite::Util::_collect_scalar_paths($scalar, [], \@paths);
    is_deeply(\@paths, [], 'internal scalar-root collector remains empty');
}
for my $container ([], {}, [1,{"x"=>2}]) {
    my (@scalar, @leaf);
    JQ::Lite::Util::_collect_scalar_paths($container, [], \@scalar);
    JQ::Lite::Util::_collect_leaf_paths($container, [], \@leaf);
    is_deeply(\@scalar, \@leaf, 'both collectors agree on containers');
}

# Index-based iteration must retain empty, singleton, and long-array paths
# without constructing temporary index-range lists inside the collectors.
my $codec = JSON::PP->new->allow_nonref->canonical;
for my $size (0, 1, 8, 257) {
    my @items = $size ? (0 .. $size - 1) : ();
    my $raw = $codec->encode(\@items);
    my @expected = map { [$_] } 0 .. $#items;

    is_deeply(results($raw, 'paths'), \@expected,
        "paths emits every ordered index in $size-element array");
    is_deeply(results($raw, 'paths(scalars)'), \@expected,
        "paths(scalars) emits every leaf index in $size-element array");
    is_deeply(results($raw, 'leaf_paths'), [\@expected],
        "leaf_paths keeps one array result for $size-element array");

    my $data = $codec->decode($raw);
    my (@all, @scalar, @leaf);
    JQ::Lite::Util::_collect_paths($data, [], \@all);
    JQ::Lite::Util::_collect_scalar_paths($data, [], \@scalar);
    JQ::Lite::Util::_collect_leaf_paths($data, [], \@leaf);
    is_deeply(\@all, \@expected,
        "internal paths collector visits $size array slots");
    is_deeply(\@scalar, \@expected,
        "internal scalar collector visits $size array slots");
    is_deeply(\@leaf, \@expected,
        "internal leaf collector visits $size array slots");
    is($codec->encode($data), $raw,
        "all collectors preserve original $size-element array");
}

# Container paths include empty children; leaf paths omit them. Hash keys
# remain sorted, with array indexes visited from left to right.
my $nested_input = '{"z":[{"b":[true,false]},[],[null,{"a":2}]],"a":[]}';
my $nested_paths = [
    ['a'], ['z'], ['z',0], ['z',0,'b'], ['z',0,'b',0],
    ['z',0,'b',1], ['z',1], ['z',2], ['z',2,0],
    ['z',2,1], ['z',2,1,'a'],
];
my $nested_leaves = [
    ['z',0,'b',0], ['z',0,'b',1], ['z',2,0], ['z',2,1,'a'],
];
is_deeply(results($nested_input, 'paths'), $nested_paths,
    'paths keeps sorted hash and depth-first array order');
is_deeply(results($nested_input, 'paths(scalars)'), $nested_leaves,
    'scalar paths skip empty nested containers');
is_deeply(results($nested_input, 'leaf_paths'), [$nested_leaves],
    'leaf paths preserve nested array indexes and boolean/null leaves');
my $nested_data = $codec->decode($nested_input);
my (@nested_all, @nested_leaf);
JQ::Lite::Util::_collect_paths($nested_data, [], \@nested_all);
JQ::Lite::Util::_collect_leaf_paths($nested_data, [], \@nested_leaf);
is_deeply(\@nested_all, $nested_paths,
    'direct all-path collector preserves nested DFS ordering');
is_deeply(\@nested_leaf, $nested_leaves,
    'direct leaf collector preserves nested DFS ordering');

# An empty upstream must not grow results, whereas an empty array in the
# stream yields an empty leaf path collection but no individual paths.
my $stream_input = '[[],[2,3],["x"]]';
is_deeply(results($stream_input, '.[] | paths'),
    [[0],[1],[0]], 'paths retains ordered per-item stream output');
is_deeply(results($stream_input, '.[] | paths(scalars)'),
    [[0],[1],[0]], 'paths(scalars) retains ordered per-item output');
is_deeply(results($stream_input, '.[] | leaf_paths'),
    [[], [[0],[1]], [[0]]],
    'leaf_paths keeps one result for every upstream array');

done_testing;
