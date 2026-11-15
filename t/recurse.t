use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JSON::PP ();
use Scalar::Util qw(refaddr);
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;

subtest 'recurse without filter traverses nested values' => sub {
    my $json = q({
      "name": "alice",
      "roles": ["dev", "ops"]
    });

    my @results = $jq->run_query($json, 'recurse');

    is(scalar @results, 5, 'emits every node including scalars');
    is_deeply($results[0], { name => 'alice', roles => [ 'dev', 'ops' ] }, 'first result is original object');
    is($results[1], 'alice', 'visits string value before nested array');
    is_deeply($results[2], [ 'dev', 'ops' ], 'visits nested array');
    is($results[3], 'dev', 'visits first array element');
    is($results[4], 'ops', 'visits second array element');
};

subtest 'recurse with filter follows custom child relationships' => sub {
    my $tree_json = q({
      "name": "root",
      "children": [
        { "name": "child1" },
        { "name": "child2", "children": [ { "name": "grand" } ] }
      ]
    });

    my @names = $jq->run_query($tree_json, 'recurse(.children[]?) | .name');

    is_deeply(\@names, [ 'root', 'child1', 'child2', 'grand' ], 'traverses tree depth-first applying child filter');
};


# _apply_recurse pushes the children in reverse so the LIFO stack emits
# each subtree in original left-to-right order. Batch-pushing the reversed
# list must preserve the same order, null slots and typed leaf values.
my $codec = JSON::PP->new->allow_nonref->canonical;
my @walk_cases = (
    ['null', [undef], 'null root'],
    ['true', [JSON::PP::true], 'boolean root'],
    ['"leaf"', ['leaf'], 'text root'],
    ['5', [5], 'numeric root'],
    ['[]', [[]], 'empty array root'],
    ['{}', [{}], 'empty object root'],
    ['[1,2,3]', [[1,2,3],1,2,3], 'flat siblings'],
    ['[1,[2,3],4]', [[1,[2,3],4],1,[2,3],2,3,4],
        'left-to-right array depth-first traversal'],
    ['{"b":[2,3],"a":1}',
        [{a=>1,b=>[2,3]},1,[2,3],2,3],
        'object sorted keys and nested array'],
    ['[null,false,true]',
        [[undef,JSON::PP::false,JSON::PP::true],
            undef,JSON::PP::false,JSON::PP::true],
        'null and boolean children retain positions'],
    ['{"z":3,"a":{"x":1},"m":[4]}',
        [{a=>{x=>1},m=>[4],z=>3},{x=>1},1,[4],4,3],
        'nested object sibling order'],
    ['[[],{},[1]]',
        [[[],{},[1]],[],{},[1],1],
        'empty containers and last descendant'],
    ['{"a":[],"b":{}}',
        [{a=>[],b=>{}},[],{}],
        'empty sorted-key container children'],
);
for my $case (@walk_cases) {
    my ($raw, $expected, $label) = @$case;
    my $decoded = $codec->decode($raw);
    my $input_before = $codec->encode($decoded);
    my @direct = JQ::Lite::Util::_apply_recurse($jq, $decoded, undef);
    is_deeply(\@direct, $expected, "direct recurse ordered nodes: $label");
    is_deeply([ $jq->run_query($raw, 'recurse') ], $expected,
        "public recurse ordered nodes: $label");
    is($codec->encode($decoded), $input_before,
        "direct recurse does not mutate original: $label");
}

my $opaque_leaf = { b => [2] };
my $opaque_root = { a => [1,$opaque_leaf], c => JSON::PP::false };
my @opaque_results = JQ::Lite::Util::_apply_recurse(
    $jq, $opaque_root, undef
);
is(refaddr($opaque_results[0]), refaddr($opaque_root),
    'direct recurse preserves root identity');
is(refaddr($opaque_results[1]), refaddr($opaque_root->{a}),
    'direct recurse retains array identity');
is(refaddr($opaque_results[3]), refaddr($opaque_leaf),
    'direct recurse retains nested object identity');
is(refaddr($opaque_results[4]), refaddr($opaque_leaf->{b}),
    'direct recurse retains grandchild array identity');
is(refaddr($opaque_results[6]), refaddr($opaque_root->{c}),
    'direct recurse retains Boolean reference identity');

my $long_root = [0 .. 256];
my @long_results = JQ::Lite::Util::_apply_recurse(
    $jq, $long_root, undef
);
is_deeply(\@long_results, [$long_root,0 .. 256],
    '257-child stack yields all children in original order');
is(scalar(@long_results), 258,
    'long array emits root and exactly one result per child');

is_deeply([ $jq->run_query('[[1,[2]],[3,4]]', '.[] | recurse') ],
    [[1,[2]],1,[2],2,[3,4],3,4],
    'multiple roots remain ordered depth-first streams');
is_deeply([ $jq->run_query(
    '{"children":[{"name":"one"},{"name":"two","children":[{"name":"three"}]}],"name":"root"}',
    'recurse(.children[]?) | .name'
) ], ['root','one','two','three'],
    'custom child iterator keeps child order');
is_deeply([ $jq->run_query('[1,2]', 'recurse(.[]? | (.,.))') ],
    [[1,2],1,1,2,2],
    'duplicate custom children remain separate results');
is_deeply([ $jq->run_query('null', 'empty | recurse') ], [],
    'empty upstream remains empty');

my $strict_ok = eval { $jq->run_query('[1,2]', 'recurse(.[])'); 1 };
ok(!$strict_ok, 'strict explicit iteration still errors on scalar child');
like("$@", qr/Cannot iterate over number/,
    'strict recurse retains explicit numeric leaf error message');
is_deeply([ $jq->run_query('[1,2]', 'try recurse(.[]) catch 42') ],
    [[1,2],1,42],
    'try/catch preserves earlier values before child error');

done_testing;
