use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Error ();

my $jq = JQ::Lite->new;

sub results {
    my ($json, $query) = @_;
    return [ $jq->run_query($json, $query) ];
}

subtest 'updated root, not the updated leaf' => sub {
    is_deeply(results('{"a":1,"b":10}', '.a |= . + 1'),
        [{ a => 2, b => 10 }], 'updates a field and preserves siblings');
    is_deeply(results('{"a":{"b":2,"c":4}}', '.a.b |= . + 3'),
        [{ a => { b => 5, c => 4 } }], 'updates nested path');
    is_deeply(results('{"a":[1,2]}', '.a[1] |= . + 1'),
        [{ a => [1, 3] }], 'updates an indexed array element');
    is_deeply(results('[2]', '.[0] |= . + 1'),
        [[3]], 'updates root array element');
};

subtest 'missing and JSON null targets are evaluated as null' => sub {
    is_deeply(results('{}', '.missing |= . + 1'),
        [{ missing => 1 }], 'creates a missing field from null + 1');
    is_deeply(results('{"a":null}', '.a |= . + 1'),
        [{ a => 1 }], 'replaces an explicit null');
    is_deeply(results('{"a":{}}', '.a.b |= . + 1'),
        [{ a => { b => 1 } }], 'creates a missing nested field');
    is_deeply(results('null', '.x |= . + 1'),
        [{ x => 1 }], 'null root becomes an object');
    is_deeply(results('null', '.[0] |= . + 1'),
        [[1]], 'null root becomes an array');
};

subtest 'right hand filter receives the old target only' => sub {
    is_deeply(results('{"a":2,"b":99}', '.a |= . * 3'),
        [{ a => 6, b => 99 }], 'arithmetic uses old a, not root');
    is_deeply(results('{"a":{"b":2}}', '.a |= .b + 1'),
        [{ a => 3 }], 'RHS path is relative to the old a');
    is_deeply(results('{"a":1}', '.a |= .'),
        [{ a => 1 }], 'identity update');
    is_deeply(results('{"a":1}', '.a |= null'),
        [{ a => undef }], 'literal null replacement');
    is_deeply(results('{"a":1}', '.a |= 7'),
        [{ a => 7 }], 'constant replacement');
};

subtest 'zero-result update deletes the selected path' => sub {
    is_deeply(results('{"a":1,"b":2}', '.a |= empty'),
        [{ b => 2 }], 'delete object key and retain siblings');
    is_deeply(results('{"a":{"b":1,"c":2}}', '.a.b |= empty'),
        [{ a => { c => 2 } }], 'delete a nested key');
    is_deeply(results('[10,20,30]', '.[1] |= empty'),
        [[10,30]], 'splice array element rather than writing null');
    is_deeply(results('{"a":[10,20]}', '.a[0] |= empty'),
        [{ a => [20] }], 'splice nested array element');
    is_deeply(results('{"a":1}', '.a |= (empty)'),
        [{}], 'parenthesized empty expression deletes');
};

subtest 'deleting a missing target never creates a container' => sub {
    is_deeply(results('{}', '.missing |= empty'),
        [{}], 'missing object key remains missing');
    is_deeply(results('{"a":{}}', '.a.b |= empty'),
        [{ a => {} }], 'missing nested object key stays absent');
    is_deeply(results('{"a":null}', '.a.b |= empty'),
        [{ a => undef }], 'null intermediate remains null');
    is_deeply(results('null', '.a |= empty'),
        [undef], 'null root remains null');
    is_deeply(results('null', '.[0] |= empty'),
        [undef], 'null root index remains null');
    is_deeply(results('[10,20]', '.[5] |= empty'),
        [[10,20]], 'out-of-bounds array index is unchanged');
    is_deeply(results('{"a":[10,20]}', '.a[5] |= empty'),
        [{ a => [10,20] }], 'out-of-bounds nested array index is unchanged');
};

subtest 'other zero-result filters also delete' => sub {
    is_deeply(results('{"a":1}', '.a |= select(false)'),
        [{}], 'select(false) produces no value and deletes path');
};

subtest 'multi-result RHS uses only its first emitted value' => sub {
    is_deeply(results('{"a":1,"b":7}', '.a |= (10,20)'),
        [{ a => 10, b => 7 }], 'first value selected and root retained');
    is_deeply(results('{"a":1}', '.a |= (1,2,3)'),
        [{ a => 1 }], 'three-value stream emits one updated root');
    is_deeply(results('{"a":2}', '.a |= (., . + 1)'),
        [{ a => 2 }], 'first RHS value is the old target');
    is_deeply(results('{"a":{"b":2}}', '.a |= (.b, 10)'),
        [{ a => 2 }], 'RHS path evaluates against the original leaf');
    is_deeply(results('{"a":1}', '.a |= (null, 2)'),
        [{ a => undef }], 'first JSON null is retained, not deletion');
    is_deeply(results('{"a":1}', '.a |= (false, 2)'),
        [{ a => JSON::PP::false }], 'first JSON false is retained');
    is_deeply(results('{"a":1}', '.a |= (empty, 5)'),
        [{ a => 5 }], 'zero-output branch skipped before first value');
    is_deeply(results('{"a":1}', '.a |= (select(false), 9)'),
        [{ a => 9 }], 'first later output is used');
    is_deeply(results('{"a":[10,20]}', '.a[1] |= (30,40)'),
        [{ a => [10,30] }], 'array slot updated once');
    is_deeply(results('{}', '.missing |= (3,4)'),
        [{ missing => 3 }], 'missing target uses first replacement');
    is_deeply(results('{"a":1}', '.a |= (null, empty)'),
        [{ a => undef }], 'null before empty is a real first result');
};

subtest 'empty RHS still deletes instead of selecting undefined' => sub {
    is_deeply(results('{"a":1}', '.a |= (empty)'),
        [{}], 'zero-result RHS still deletes target');
    is_deeply(results('[10,20]', '.[0] |= empty'),
        [[20]], 'zero-result RHS still splices array');
};

subtest 'unsupported update streams and invalid target types are explicit errors' => sub {
    for my $case (
        ['{"a":2}', '.a[0] |= . + 1', 'index on numeric leaf'],
        ['{"a":{}}', '.a[0] |= . + 1', 'numeric index on object'],
    ) {
        my ($json, $query, $label) = @$case;
        my $ok = eval { $jq->run_query($json, $query); 1 };
        my $err = $@;
        ok(!$ok, "$label: no silent success");
        isa_ok($err, 'JQ::Lite::Error::Evaluation', "$label: evaluation error")
            if !$ok;
    }
};


subtest 'fixed-index traversal preserves nested update and deletion contracts' => sub {
    my $input = '{"root":[{"detail":{"value":1,"keep":2}},{"detail":{"value":3,"keep":4}}]}';
    is_deeply(results($input, '.root[1].detail.value |= . + 7'),
        [{ root => [
            { detail => { value => 1, keep => 2 } },
            { detail => { value => 10, keep => 4 } },
        ] }], 'mixed key and index path updates only selected leaf');

    is_deeply(results($input, '.root[0].detail.value |= empty'),
        [{ root => [
            { detail => { keep => 2 } },
            { detail => { value => 3, keep => 4 } },
        ] }], 'nested key deletion retains sibling branches');

    is_deeply(results($input, '.root[1].detail.absent |= empty'),
        [{ root => [
            { detail => { value => 1, keep => 2 } },
            { detail => { value => 3, keep => 4 } },
        ] }], 'missing nested deletion does not create a new key');

    is_deeply(results('{"root":[{"items":[10,20,30]}]}',
        '.root[0].items[1] |= empty'),
        [{ root => [{ items => [10,30] }] }],
        'deep array deletion splices just its selected index');

    is_deeply(results('{"root":[{"items":[10,20]}]}',
        '.root[0].items[4] |= empty'),
        [{ root => [{ items => [10,20] }] }],
        'out-of-range deep deletion leaves array unchanged');

    is_deeply(results('{"root":[{"detail":null}]}',
        '.root[0].detail.value |= . + 1'),
        [{ root => [{ detail => { value => 1 } }] }],
        'null intermediate creates a container while RHS sees a null leaf');

    is_deeply(results('{"root":[{"detail":{"value":null}}]}',
        '.root[0].detail.value |= 9'),
        [{ root => [{ detail => { value => 9 } }] }],
        'explicit null deep leaf is replaced, not dropped');

    is_deeply(results('{"root":[{"detail":{"value":1}}]}',
        '.root[0].detail.value |= false'),
        [{ root => [{ detail => { value => JSON::PP::false } }] }],
        'false deep replacement preserves the JSON boolean');
};

done_testing;
