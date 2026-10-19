use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Util ();
use Scalar::Util qw(refaddr);

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


# Historically _collect_paths built @next, copied it for each returned
# path and used @next for recursion. Reusing the returned path directly
# must preserve DFS order, avoid changing the caller's prefix, and keep
# every returned path independent of its parent/siblings.
sub legacy_all_paths {
    my ($value, $prefix, $result) = @_;
    if (ref $value eq 'HASH') {
        for my $key (sort keys %$value) {
            my $child = $value->{$key};
            my @next = (@$prefix, $key);
            push @$result, [@next];
            legacy_all_paths($child, \@next, $result)
                if ref $child eq 'HASH' || ref $child eq 'ARRAY';
        }
        return;
    }
    if (ref $value eq 'ARRAY') {
        for (my $index = 0; $index < @$value; $index++) {
            my $child = $value->[$index];
            my @next = (@$prefix, $index);
            push @$result, [@next];
            legacy_all_paths($child, \@next, $result)
                if ref $child eq 'HASH' || ref $child eq 'ARRAY';
        }
        return;
    }
    push @$result, [@$prefix];
}

my @all_paths_cases = (
    ['{}', [], 'empty hash'],
    ['[]', [], 'empty array'],
    ['{"a":1}', [['a']], 'single object child'],
    ['[1,2,3]', [[0],[1],[2]], 'flat array'],
    ['{"b":{"c":3},"a":[1,2]}',
        [['a'],['a',0],['a',1],['b'],['b','c']],
        'sorted object keys and array descendants'],
    ['[null,false,{"k":true}]',
        [[0],[1],[2],[2,'k']],
        'null Boolean and nested object'],
    ['{"empty":[],"object":{}}',
        [['empty'],['object']], 'empty child containers emitted'],
    ['[[1,[2]],3]',
        [[0],[0,0],[0,1],[0,1,0],[1]],
        'nested array DFS'],
    ['{"":{"a.b":2},"\u65e5\u672c":[true,null]}',
        [[''],['','a.b'],["\x{65e5}\x{672c}"],
            ["\x{65e5}\x{672c}",0],["\x{65e5}\x{672c}",1]],
        'empty dotted and Unicode keys'],
    ['{"a":[{"x":{"y":0}},{}]}',
        [['a'],['a',0],['a',0,'x'],['a',0,'x','y'],['a',1]],
        'deep array-to-object nesting'],
    ['{"a":1,"b":{"x":2},"c":[3]}',
        [['a'],['b'],['b','x'],['c'],['c',0]],
        'alternating scalar and container siblings'],
    ['{"a":[1,{"x":[false,true]}],"b":{}}',
        [['a'],['a',0],['a',1],['a',1,'x'],['a',1,'x',0],
            ['a',1,'x',1],['b']],
        'nested Boolean leaves and empty hash'],
);
for my $case (@all_paths_cases) {
    my ($raw, $expected, $label) = @$case;
    my $value = $codec->decode($raw);
    my $original = $codec->encode($value);
    my @legacy;
    legacy_all_paths($value, [], \@legacy);
    my @current;
    JQ::Lite::Util::_collect_paths($value, [], \@current);
    is_deeply(\@current, \@legacy,
        "all-path recursion matches original implementation: $label");
    is_deeply(\@current, $expected,
        "all-path DFS produces expected paths: $label");
    is_deeply(results($raw, 'paths'), $expected,
        "public paths emits identical stream: $label");
    is($codec->encode($value), $original,
        "all-path traversal does not mutate input: $label");

    my @prefix = ('prefix', 7);
    my @prefixed_paths;
    JQ::Lite::Util::_collect_paths($value, \@prefix, \@prefixed_paths);
    is_deeply(\@prefixed_paths,
        [ map { ['prefix', 7, @$_] } @$expected ],
        "all-path recursion preserves caller prefix: $label");
    is_deeply(\@prefix, ['prefix', 7],
        "all-path recursion leaves caller prefix untouched: $label");
}

# Each output is a distinct path array. Mutating one output must never
# rewrite a sibling or a descendant, even when it served as the prefix
# for a recursive visit.
my $nested_source = { a => [ { x => 1 }, { y => 2 } ], z => 3 };
my $nested_original = $codec->encode($nested_source);
my @isolated;
JQ::Lite::Util::_collect_paths($nested_source, [], \@isolated);
my $isolated_before = $codec->encode(\@isolated);
my %addresses = map { refaddr($_) => 1 } @isolated;
is(scalar(keys %addresses), scalar(@isolated),
    'each returned path owns an independent array');
my $preserved_child = $codec->encode($isolated[1]);
$isolated[0]->[0] = 'modified';
is($codec->encode($isolated[1]), $preserved_child,
    'modifying parent output never changes its descendant');
isnt($codec->encode(\@isolated), $isolated_before,
    'output paths remain individually mutable by callers');
is($codec->encode($nested_source), $nested_original,
    'mutating a collected path does not affect source objects');

# A wide array exercises 257 sibling paths without sharing prefix storage.
my $wide_source = [0 .. 256];
my @wide;
JQ::Lite::Util::_collect_paths($wide_source, [], \@wide);
is_deeply(\@wide, [map { [$_] } 0 .. 256],
    '257 siblings preserve their original numeric indexes');
is(scalar(keys %{ { map { refaddr($_) => 1 } @wide } }), 257,
    '257 sibling outputs contain unique path references');
is_deeply(results($codec->encode($wide_source), 'paths'), \@wide,
    'public paths keeps the entire wide-array stream');

my (@scalar_root, @scalar_prefix);
JQ::Lite::Util::_collect_paths(undef, [], \@scalar_root);
JQ::Lite::Util::_collect_paths('value', ['here'], \@scalar_prefix);
is_deeply(\@scalar_root, [[]],
    'legacy private collector retains root-null empty path');
is_deeply(\@scalar_prefix, [['here']],
    'legacy private collector retains supplied scalar prefix');
is_deeply(results('null', 'paths'), [],
    'public paths continues to suppress null scalar roots');

done_testing;
