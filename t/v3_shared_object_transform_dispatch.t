use strict;
use warnings;
use Test::More;
use JSON::PP ();
use Scalar::Util qw(refaddr);
use JQ::Lite::Util ();
use JQ::Lite;
use JQ::Lite::Builtin ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;

sub results {
    my ($input, $query) = @_;
    return [ $jq->run_query($input, $query) ];
}

# Each function retains its own implementation; only the stream wrapper
# and the two accepted registered spellings are shared.
my @cases = (
    ['{"b":2,"a":1}', 'to_entries',
        '[[{"key":"a","value":1},{"key":"b","value":2}]]',
        'object entries remain key-sorted'],
    ['[false,null,"x"]', 'to_entries',
        '[[{"key":0,"value":false},{"key":1,"value":null},{"key":2,"value":"x"}]]',
        'array entries retain numeric indexes and JSON value types'],
    ['{}', 'to_entries', '[[]]', 'empty object'],
    ['[]', 'to_entries', '[[]]', 'empty array'],
    ['null', 'to_entries', '[null]', 'null passthrough'],
    ['"text"', 'to_entries', '["text"]', 'scalar passthrough'],

    ['[{"key":"b","value":true},{"key":"a","value":null}]',
        'from_entries', '[{"a":null,"b":true}]', 'object reconstruction'],
    ['[["name","Ada"],["active",false]]', 'from_entries',
        '[{"active":false,"name":"Ada"}]', 'tuple reconstruction'],
    ['[{"key":0,"value":"x"},{"key":1,"value":"y"}]', 'from_entries',
        '[["x","y"]]', 'contiguous numeric keys become an array'],
    ['[{"key":1,"value":"x"}]', 'from_entries',
        '[{"1":"x"}]', 'sparse numeric keys remain an object'],
    ['[{"key":"01","value":"x"}]', 'from_entries',
        '[{"01":"x"}]', 'leading zero keys stay strings'],
    ['[]', 'from_entries', '[{}]', 'empty entry array produces object'],
    ['[{"key":"a","value":1},{"key":"a","value":2}]',
        'from_entries', '[{"a":2}]', 'last duplicate key wins'],

    ['[{"a":1},{"a":2,"b":true},null,4,["ignored"]]',
        'merge_objects', '[{"a":2,"b":true}]',
        'merge order and non-object elements'],
    ['[{"a":1},{"a":null}]', 'merge_objects',
        '[{"a":null}]', 'later null overwrites earlier value'],
    ['[null,3,"a"]', 'merge_objects', '[{}]', 'no objects produces empty hash'],
    ['[]', 'merge_objects', '[{}]', 'empty array produces empty hash'],
    ['{"a":[1,2],"b":false}', 'merge_objects',
        '[{"a":[1,2],"b":false}]', 'object copy preserves nested types'],
    ['null', 'merge_objects', '[null]', 'null passthrough'],
    ['"value"', 'merge_objects', '["value"]', 'string passthrough'],
);

for my $case (@cases) {
    my ($input, $query, $expected, $label) = @$case;
    is_deeply(results($input, $query), $json->decode($expected),
        "$query: $label");
}

is_deeply(results('["p","q"]', 'to_entries | from_entries'),
    [['p','q']], 'entry roundtrip reconstructs an array');
is_deeply(results('[{"b":2,"a":1},[5,6],{}]', '.[] | to_entries'),
    $json->decode('[[{"key":"a","value":1},{"key":"b","value":2}],[{"key":0,"value":5},{"key":1,"value":6}],[]]'),
    'to_entries preserves multiple input order');
is_deeply(results('[[{"key":"a","value":1}],[],[["x",false]]]',
    '.[] | from_entries'),
    $json->decode('[{"a":1},{},{"x":false}]'),
    'from_entries preserves multiple input order');
is_deeply(results('[[{"a":1},{"a":2}],{},null]', '.[] | merge_objects'),
    $json->decode('[{"a":2},{},null]'),
    'merge_objects preserves multiple input order and null slot');

# Verify both registered spellings directly: public parenthesized syntax
# may pass through other expression handling before reaching the registry.
my @direct_inputs = (
    $json->decode('{"z":4}'),
    $json->decode('[]'),
    undef,
);
for my $name (qw(to_entries from_entries merge_objects)) {
    my ($matched, $bare);
    my ($alias_matched, $alias);
    if ($name eq 'from_entries') {
        my @valid = ($json->decode('[["a",1]]'), [], $json->decode('[["b",false]]'));
        ($matched, $bare) = JQ::Lite::Builtin->dispatch($jq, $name, \@valid);
        ($alias_matched, $alias) = JQ::Lite::Builtin->dispatch($jq, "$name()", \@valid);
    } else {
        ($matched, $bare) = JQ::Lite::Builtin->dispatch($jq, $name, \@direct_inputs);
        ($alias_matched, $alias) = JQ::Lite::Builtin->dispatch($jq, "$name()", \@direct_inputs);
    }
    ok($matched, "$name remains registered");
    ok($alias_matched, "$name() remains registered");
    is_deeply($alias, $bare, "$name() dispatch preserves bare-name results");
    is(scalar @$bare, 3, "$name keeps one result per upstream input");
    is_deeply(results('null', "empty | $name"), [],
        "$name preserves an empty upstream stream");
}

# The strict reconstruction errors must not be swallowed by the shared
# wrapper or converted into empty streams.
for my $case (
    ['"x"', qr/^from_entries\(\): argument must be an array/, 'non-array'],
    ['[{"value":1}]', qr/^from_entries\(\): entry is missing key/, 'missing key'],
    ['[{"key":"x"}]', qr/^from_entries\(\): entry is missing value/, 'missing value'],
    ['[1]', qr/^from_entries\(\): entry must be an object or \[key, value\] tuple/, 'invalid entry'],
    ['[["x"]]', qr/^from_entries\(\): entry must have a key and value/, 'short tuple'],
    ['[[{"x":1},2]]', qr/^from_entries\(\): key must be a string/, 'non-string key'],
) {
    my ($input, $pattern, $label) = @$case;
    my $ok = eval { $jq->run_query($input, 'from_entries'); 1 };
    ok(!$ok, "from_entries still rejects $label");
    like("$@", $pattern, "from_entries preserves $label error message");
}

my %registered = map { $_ => 1 } JQ::Lite::Builtin->registered_names;
for my $name (qw(to_entries from_entries merge_objects)) {
    ok($registered{$name}, "$name exact spelling remains registered");
    ok($registered{"$name()"}, "$name() alias remains registered");
}


# Array to_entries now constructs entries directly by index. Protect
# empty arrays, ordered numeric keys, long inputs and roundtrips.
for my $size (0, 1, 9, 257) {
    my @items = map { $_ % 7 == 0 ? undef : $_ } (0 .. $size - 1);
    my $input = $json->encode(\@items);
    my $expected = [
        map { { key => $_, value => $items[$_] } } (0 .. $#items)
    ];
    my $direct = JQ::Lite::Util::_to_entries(\@items);
    is_deeply($direct, $expected,
        "direct to_entries preserves ordered $size-element array");
    is_deeply(results($input, 'to_entries'), [$expected],
        "public to_entries preserves ordered $size-element array");
    is_deeply([ map { $_->{key} } @$direct ], [ 0 .. $#items ],
        "to_entries assigns consecutive numeric keys for $size items");
    is(scalar(@$direct), $size,
        "to_entries returns exactly $size entries");
    if ($size) {
        is_deeply(results($input, 'to_entries | from_entries'), [\@items],
            "to_entries/from_entries roundtrip for $size contiguous items");
    }
}

# The entry wrappers are new, but their values still reference the same
# original nested objects/arrays and JSON::PP boolean instances.
my $nested_object = { k => [2, 3] };
my $nested_array = [-4, 5];
my $true = JSON::PP::true;
my $false = JSON::PP::false;
my $mixed = [undef, $true, $false, '007', $nested_object, $nested_array];
my $mixed_direct = JQ::Lite::Util::_to_entries($mixed);
is_deeply([ map { $_->{key} } @$mixed_direct ], [0,1,2,3,4,5],
    'mixed array entries preserve every numeric key');
is(refaddr($mixed_direct->[1]{value}), refaddr($true),
    'true retains its boolean reference');
is(refaddr($mixed_direct->[2]{value}), refaddr($false),
    'false retains its boolean reference');
is($mixed_direct->[3]{value}, '007',
    'numeric-looking string keeps its text');
is(refaddr($mixed_direct->[4]{value}), refaddr($nested_object),
    'nested object retains reference identity');
is(refaddr($mixed_direct->[5]{value}), refaddr($nested_array),
    'nested array retains reference identity');
isnt(refaddr($mixed_direct->[4]), refaddr($nested_object),
    'entry itself is a new wrapper object');
is_deeply($mixed, [undef, $true, $false, '007', $nested_object, $nested_array],
    'array conversion does not alter caller values');
is_deeply(results($json->encode($mixed), 'to_entries'),
    [ $json->decode('[{"key":0,"value":null},{"key":1,"value":true},'
        . '{"key":2,"value":false},{"key":3,"value":"007"},'
        . '{"key":4,"value":{"k":[2,3]}},'
        . '{"key":5,"value":[-4,5]}]') ],
    'public mixed array conversion preserves value types');

# The unchanged object sorting and scalar fallback paths stay intact.
is_deeply(JQ::Lite::Util::_to_entries({ z => 2, a => 1 }),
    [{ key => 'a', value => 1 }, { key => 'z', value => 2 }],
    'object entry keys remain sorted');
my $scalar = 'word';
is(JQ::Lite::Util::_to_entries($scalar), $scalar,
    'non-container text still passes through');
ok(!defined JQ::Lite::Util::_to_entries(undef),
    'null still passes through');
is_deeply(results('[[3,2],[],[9]]', '.[] | to_entries'),
    [ [{key=>0,value=>3},{key=>1,value=>2}], [], [{key=>0,value=>9}] ],
    'to_entries keeps output order with empty arrays inside streams');

done_testing;
