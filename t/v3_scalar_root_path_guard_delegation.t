use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;

sub run {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# _collect_scalar_paths already returns before visiting any root leaf.
# Removing the same check from _apply_scalar_paths must NOT make scalar
# roots emit [[]]: that remains the intentionally different leaf_paths
# contract (paths(scalars) emits an empty stream for a scalar root).
for my $raw ('null', 'true', 'false', '0', '-12', '3.5',
             '""', '"text"') {
    my $value = $json->decode($raw);
    is_deeply(run($raw, 'paths(scalars)'), [],
        "paths(scalars) emits nothing from scalar root $raw");
    is_deeply(JQ::Lite::Util::_apply_scalar_paths($value), [],
        "direct scalar paths returns empty collection for $raw");
    my @collected;
    JQ::Lite::Util::_collect_scalar_paths($value, [], \@collected);
    is_deeply(\@collected, [],
        "collector's scalar-root guard remains effective for $raw");
    is_deeply(run($raw, 'leaf_paths'), [[[]]],
        "leaf_paths still exposes the empty root path for $raw");
}

# Both public path enumerators share the leaf traversal for containers,
# but they differ in stream shape. Confirm the same paths in each
# public and direct helper, with hash keys sorted and arrays in order.
my @cases = (
    ['[]', '[]', 'empty array'],
    ['{}', '[]', 'empty object'],
    ['[null,true,false]', '[[0],[1],[2]]', 'null and boolean leaves'],
    ['{"b":2,"a":1}', '[["a"],["b"]]', 'sorted object keys'],
    ['{"nested":{"a":0},"empty":[]}',
        '[["nested","a"]]', 'empty container is not a leaf'],
    ['[1,[],{},[false,{"x":null}]]',
        '[[0],[3,0],[3,1,"x"]]', 'nested mixed array'],
    ['{"a":{"b":[1,{"c":"x"}]},"z":true}',
        '[["a","b",0],["a","b",1,"c"],["z"]]', 'nested object and array'],
    ['[{"x":[{"y":4}]},null]',
        '[[0,"x",0,"y"],[1]]', 'nested and terminal array slots'],
    ['[[],{}]', '[]', 'array of empty containers'],
    ['{"empty":[],"none":{},"null":null}',
        '[["null"]]', 'empty children skipped'],
    ['{"nested":[{"a":[true]},{"b":false}]}',
        '[["nested",0,"a",0],["nested",1,"b"]]',
        'nested keys and boolean values'],
    ['[[1],[2,[3]]]',
        '[[0,0],[1,0],[1,1,0]]', 'nested arrays'],
);

for my $case (@cases) {
    my ($raw, $expected_json, $label) = @$case;
    my $value = $json->decode($raw);
    my $expected = $json->decode($expected_json);
    is_deeply(run($raw, 'paths(scalars)'), $expected,
        "public scalar path stream: $label");
    is_deeply(JQ::Lite::Util::_apply_scalar_paths($value), $expected,
        "direct scalar path wrapper: $label");
    my @scalar;
    JQ::Lite::Util::_collect_scalar_paths($value, [], \@scalar);
    is_deeply(\@scalar, $expected,
        "scalar collector still handles container: $label");
    my @leaf;
    JQ::Lite::Util::_collect_leaf_paths($value, [], \@leaf);
    is_deeply(\@leaf, $expected,
        "shared leaf traversal retains paths: $label");
    is_deeply(run($raw, 'leaf_paths'), [$expected],
        "leaf_paths retains its collection shape: $label");
}

# The collector must preserve existing results when asked to process a
# scalar root, and prepend the supplied parent path for container roots.
my @existing = (['keep']);
JQ::Lite::Util::_collect_scalar_paths(JSON::PP::false, ['prefix'], \@existing);
is_deeply(\@existing, [['keep']],
    'scalar-root guard does not alter an already populated destination');
my @prefixed;
JQ::Lite::Util::_collect_scalar_paths({ a => [1, undef] },
                                      ['parent'], \@prefixed);
is_deeply(\@prefixed, [['parent','a',0], ['parent','a',1]],
    'container collection retains the passed path prefix');

is_deeply(run('[{"a":1},null,{"b":[true,false]},[]]',
              '.[] | paths(scalars)'),
    [['a'], ['b',0], ['b',1]],
    'multiple upstream values produce ordered scalar paths only');
is_deeply(run('[{"a":1},null,{"b":[true,false]},[]]',
              '.[] | leaf_paths'),
    [[['a']], [[]], [['b',0],['b',1]], []],
    'leaf_paths retains one path collection per upstream value');
is_deeply(run('null', 'empty | paths(scalars)'), [],
    'empty upstream stream remains empty for scalar path filter');
is_deeply(run('null', 'empty | leaf_paths'), [],
    'empty upstream stream remains empty for leaf path filter');

my $opaque_scalar = do { my $n = 7; \$n };
is_deeply(JQ::Lite::Util::_apply_scalar_paths($opaque_scalar), [],
    'opaque scalar reference is still treated as a leaf root');
my @opaque_paths;
JQ::Lite::Util::_collect_scalar_paths($opaque_scalar, [], \@opaque_paths);
is_deeply(\@opaque_paths, [],
    'internal helper excludes opaque scalar-reference root');

done_testing;
