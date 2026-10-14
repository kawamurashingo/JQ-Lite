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
done_testing;
