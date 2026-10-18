use strict;
use warnings;
use Test::More;
use JSON::PP ();
use Scalar::Util qw(refaddr);
use JQ::Lite;
use JQ::Lite::Builtin ();
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;

sub run {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# An initially empty %merged already represents both cases of the
# old "saw an object" flag: no hashes => {}, otherwise merged fields.
# Keep rightmost-wins precedence, non-object skipping and value types.
my @cases = (
    ['[]', '{}', 'empty array'],
    ['[null]', '{}', 'null-only array'],
    ['[null,false,0,"",[]]', '{}', 'no object among mixed values'],
    ['[{},null]', '{}', 'empty object before null'],
    ['[null,{},false]', '{}', 'empty object among scalars'],
    ['[{},{}]', '{}', 'several empty objects'],
    ['[{"x":1}]', '{"x":1}', 'single object'],
    ['[{"x":1},{"y":2}]', '{"x":1,"y":2}', 'disjoint keys'],
    ['[{"x":1},{"x":2}]', '{"x":2}', 'later duplicate key wins'],
    ['[{"x":1},{"x":null}]', '{"x":null}', 'later null overwrites'],
    ['[{"x":null},{"x":false}]', '{"x":false}', 'later false overwrites'],
    ['[{"x":true},{"x":0}]', '{"x":0}', 'later numeric zero overwrites'],
    ['[{"a":[1]},{"a":[2]}]', '{"a":[2]}', 'array value replacement'],
    ['[{"a":{"inner":[1]}},{"b":true}]',
        '{"a":{"inner":[1]},"b":true}', 'nested objects kept opaque'],
    ['[{},{"a":1},false,{"a":2},null,{"b":"v"}]',
        '{"a":2,"b":"v"}', 'ignored elements and ordered updates'],
    ['[{"01":"one"},{"1":"other"}]',
        '{"01":"one","1":"other"}', 'numeric-looking keys remain distinct'],
    ['{"key":true}', '{"key":true}', 'standalone hash remains a shallow copy'],
    ['null', 'null', 'null passthrough'],
    ['true', 'true', 'true passthrough'],
    ['false', 'false', 'false passthrough'],
    ['7', '7', 'number passthrough'],
    ['"text"', '"text"', 'string passthrough'],
);

for my $case (@cases) {
    my ($input, $expected, $label) = @$case;
    my $want = $json->decode($expected);
    is_deeply(run($input, 'merge_objects'), [$want],
        "public merge_objects keeps $label");
    is_deeply(run($input, 'merge_objects()'), [$want],
        "parenthesized merge_objects keeps $label");
    is_deeply(JQ::Lite::Util::_apply_merge_objects($json->decode($input)),
        $want, "direct merge utility keeps $label");
}

# The result is always a fresh top-level hash when the input is an
# array or hash, even when there were no valid object elements.
my $empty = [];
my $nonhash = [undef, JSON::PP::false, 4, [1]];
my $first_empty = JQ::Lite::Util::_apply_merge_objects($empty);
my $second_empty = JQ::Lite::Util::_apply_merge_objects($empty);
is_deeply($first_empty, {}, 'empty array returns a hash reference');
isnt(refaddr($first_empty), refaddr($second_empty),
    'separate empty array calls return distinct hashes');
is_deeply(JQ::Lite::Util::_apply_merge_objects($nonhash), {},
    'non-object array returns a fresh empty hash');

my $nested = [1, 2];
my $input_hash = { keep => $nested, flag => JSON::PP::true };
my $hash_copy = JQ::Lite::Util::_apply_merge_objects($input_hash);
is_deeply($hash_copy, $input_hash, 'standalone object copy keeps all fields');
isnt(refaddr($hash_copy), refaddr($input_hash),
    'standalone object gets a new top-level hash');
is(refaddr($hash_copy->{keep}), refaddr($nested),
    'standalone object copy keeps nested value reference');

my $left = { a => [1], conflict => { old => 1 } };
my $right = { b => JSON::PP::false, conflict => { new => 2 } };
my $merged = JQ::Lite::Util::_apply_merge_objects([$left, undef, $right]);
is_deeply($merged,
    { a => [1], b => JSON::PP::false, conflict => { new => 2 } },
    'array objects combine with rightmost-wins field values');
is(refaddr($merged->{a}), refaddr($left->{a}),
    'merged object retains left nested array reference');
is(refaddr($merged->{conflict}), refaddr($right->{conflict}),
    'merged object retains later nested object reference');
isnt(refaddr($merged), refaddr($left),
    'array merge does not reuse first input object');

# Direct registry dispatch preserves both names, output cardinality,
# non-array identities, and ordered empty-object results.
my $truth = JSON::PP::true;
my $falsity = JSON::PP::false;
my $object = { x => [3] };
my @inputs = ([], [undef], [ { a => 1 }, { a => 2 } ],
              $object, undef, $truth, $falsity, 9, 's');
my @expected = ({}, {}, { a => 2 }, $object, undef,
                $truth, $falsity, 9, 's');
for my $name ('merge_objects', 'merge_objects()') {
    my ($found, $output) =
        JQ::Lite::Builtin->dispatch($jq, $name, \@inputs);
    ok($found, "$name remains registered");
    is_deeply($output, \@expected, "$name preserves direct stream values");
    is(scalar @$output, scalar @inputs,
        "$name preserves one output for every input");
    isnt(refaddr($output->[3]), refaddr($object),
        "$name copies a standalone hash");
    is(refaddr($output->[3]{x}), refaddr($object->{x}),
        "$name keeps standalone nested array identity");
    is(refaddr($output->[5]), refaddr($truth),
        "$name preserves true reference");
    is(refaddr($output->[6]), refaddr($falsity),
        "$name preserves false reference");
    my ($empty_found, $empty_output) =
        JQ::Lite::Builtin->dispatch($jq, $name, []);
    ok($empty_found, "$name matches empty input streams");
    is_deeply($empty_output, [],
        "$name does not synthesize values from empty streams");
}

is_deeply(run('[[],[null],[{"x":1},{"x":2}],null]',
             '.[] | merge_objects'),
    [{}, {}, {x => 2}, undef],
    'upstream iteration retains ordered merged and null values');
is_deeply(run('null', 'empty | merge_objects'), [],
    'empty upstream pipeline produces no result');

my %registered = map { $_ => 1 } JQ::Lite::Builtin->registered_names;
ok($registered{merge_objects}, 'bare exact registry key remains');
ok($registered{'merge_objects()'}, 'parenthesized registry alias remains');


# Incremental hash assignment must preserve all historical merge outcomes.
# Test multiple overwrite rounds, nulls, booleans, numeric-looking keys,
# and elements that are not objects, including both public names.
my @incremental_cases = (
    ['[{"first":1},{"second":2}]', '{"first":1,"second":2}',
        'disjoint fields'],
    ['[{"a":1},{"a":null}]', '{"a":null}',
        'later explicit null wins'],
    ['[{"a":true},{"a":false}]', '{"a":false}',
        'later false wins'],
    ['[{"a":{"old":1}},{"a":{"new":2}}]', '{"a":{"new":2}}',
        'later nested object replaces earlier'],
    ['[{"nested":[1,2]},{"other":7}]',
        '{"nested":[1,2],"other":7}', 'nested values remain opaque'],
    ['[{},{"x":2},{}]', '{"x":2}', 'interleaved empty hashes'],
    ['[null,5,["skip"],{"x":1},false,{"y":2}]',
        '{"x":1,"y":2}', 'non-object elements skipped'],
    ['[{"01":"leading"},{"1":"numeric"}]',
        '{"01":"leading","1":"numeric"}', 'distinct numeric-looking keys'],
    ['[{"a":"v"},{"a":0},{"a":"w"}]', '{"a":"w"}',
        'multiple replacements retain final string'],
    ['[{"a":null},{"b":null}]', '{"a":null,"b":null"}',
        'disjoint null-valued fields'],
);
for my $case (@incremental_cases) {
    my ($input, $expected_raw, $label) = @$case;
    my $want = $json->decode($expected_raw);
    is_deeply(JQ::Lite::Util::_apply_merge_objects($json->decode($input)),
        $want, "incremental direct merge: $label");
    is_deeply(run($input, 'merge_objects'), [$want],
        "incremental public merge: $label");
    is_deeply(run($input, 'merge_objects()'), [$want],
        "incremental parenthesized merge: $label");
}

# A long sequence of mostly unique fields previously rebuilt the entire
# accumulated hash on every element. Verify all keys remain present,
# rightmost precedence and shallow reference identity for nested values.
my @many_objects = map {
    { "item_$_" => $_, common => $_, nested => { source => $_ } }
} (0 .. 256);
splice @many_objects, 3, 0, undef, JSON::PP::false, ['ignored'];
my %expected_many = (common => 256, nested => { source => 256 });
for my $i (0 .. 256) {
    $expected_many{"item_$i"} = $i;
}
my $many_merged = JQ::Lite::Util::_apply_merge_objects(\@many_objects);
is_deeply($many_merged, \%expected_many,
    '257 object updates retain all unique fields and last values');
is(scalar(keys %$many_merged), 259,
    'incremental long merge retains all 257 unique and two shared keys');
is($many_merged->{common}, 256, 'long merge keeps last overwritten field');
is($many_merged->{item_0}, 0, 'first unique field remains');
is($many_merged->{item_256}, 256, 'last unique field remains');
is(refaddr($many_merged->{nested}), refaddr($many_objects[-1]{nested}),
    'latest nested object is retained by reference');
isnt(refaddr($many_merged), refaddr($many_objects[0]),
    'merge creates a new result rather than modifying first source hash');
is_deeply($many_objects[0],
    { item_0 => 0, common => 0, nested => { source => 0 } },
    'first source hash is not changed by subsequent overwrites');
is_deeply($many_objects[-1],
    { item_256 => 256, common => 256, nested => { source => 256 } },
    'last source hash is not modified by merging');
my $large_input = $json->encode(\@many_objects);
is_deeply(run($large_input, 'merge_objects'), [\%expected_many],
    'public long merge retains complete key/value set');
is_deeply(run($large_input, 'merge_objects()'), [\%expected_many],
    'parenthesized long merge retains complete key/value set');
is_deeply(run('[[{"x":1},{"x":2}],[],[{"a":7},false,{"b":8}]]',
    '.[] | merge_objects'), [{x=>2},{},{a=>7,b=>8}],
    'incremental merge preserves independent upstream stream results');

done_testing;
