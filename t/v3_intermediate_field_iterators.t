use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Error ();

my $jq = JQ::Lite->new;

sub results {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

sub runtime_error {
    my ($input, $filter, $message, $label) = @_;
    my $ok = eval { $jq->run_query($input, $filter); 1 };
    my $error = $@;
    ok(!$ok, "$label: runtime error");
    if (!$ok) {
        isa_ok($error, 'JQ::Lite::Error::Evaluation',
            "$label: structured evaluation failure");
        like("$error", qr/\Q$message\E/,
            "$label: failure identifies the affected stage");
    }
}

subtest 'strict intermediate iterator followed by a field' => sub {
    is_deeply(results('{"items":[{"name":"Ada"},{"name":"Bea"}]}',
            '.items[].name'), ['Ada','Bea'],
        'one field result per iterated object');
    is_deeply(results('{"items":[{"name":"Ada"},{}]}',
            '.items[].name'), ['Ada',undef],
        'missing member field emits jq null');
    is_deeply(results('{"items":[{"name":"Ada"},null]}',
            '.items[].name'), ['Ada',undef],
        'reading a named field through null emits null');
    is_deeply(results('{"items":[]}', '.items[].name'), [],
        'empty iterator does not evaluate later field access');
    is_deeply(results('{"items":[{"child":{"name":"x"}},{"child":{}}]}',
            '.items[].child.name'), ['x',undef],
        'two named-field accesses after intermediate iteration');

    runtime_error('{"items":null}', '.items[].name',
        'Cannot iterate over null', 'strict iterator over null field');
    runtime_error('{}', '.items[].name',
        'Cannot iterate over null', 'strict iterator over missing field');
    runtime_error('{"items":3}', '.items[].name',
        'Cannot iterate over number', 'strict iterator over numeric field');
    runtime_error('{"items":[{"name":"Ada"},2]}', '.items[].name',
        'Cannot index number with string "name"', 'number after iterator');
    runtime_error('{"items":[{"name":"Ada"},true]}', '.items[].name',
        'Cannot index boolean with string "name"', 'boolean after iterator');
    runtime_error('{"items":[[1,2]]}', '.items[].name',
        'Cannot index array with string "name"', 'array after iterator');
};

subtest 'optional intermediate iterator only omits non-iterable inputs' => sub {
    for my $input ('{}', 'null', '{"items":null}', '{"items":0}',
                   '{"items":true}', '{"items":"x"}', '{"items":[]}') {
        is_deeply(results($input, '.items[]?.name'), [],
            "optional intermediate iterator skips non-container field ($input)");
    }
    is_deeply(results('{"items":[{"name":"Ada"},{}]}',
            '.items[]?.name'), ['Ada',undef],
        'optional iterator still evaluates later field for emitted objects');
    is_deeply(results('{"items":[{"name":"Ada"},null]}',
            '.items[]?.name'), ['Ada',undef],
        'null member is an emitted value and supports null field lookup');
    runtime_error('{"items":[2]}', '.items[]?.name',
        'Cannot index number with string "name"',
        'optional iterator does not suppress later field-index error');
    runtime_error('{"items":[false]}', '.items[]?.name',
        'Cannot index boolean with string "name"',
        'optional iterator does not suppress boolean field error');
    runtime_error('1', '.items[]?.name',
        'Cannot index number with string "items"',
        'optional iterator does not suppress prefix field error');
    runtime_error('[]', '.items[]?.name',
        'Cannot index array with string "items"',
        'optional iterator does not suppress invalid array prefix');
};

subtest 'two iterators evaluate left-to-right and independently' => sub {
    is_deeply(results('{"items":[[1,2],[3]]}', '.items[][]'),
        [1,2,3], 'two strict iterators flatten nested arrays');
    is_deeply(results('{"items":[[],[1]]}', '.items[][]'),
        [1], 'empty intermediate stream is skipped');
    is_deeply(results('{"items":[[1,2],null]}', '.items[][]?'),
        [1,2], 'only the second iterator is optional');
    is_deeply(results('{"items":[[1,2],null]}', '.items[]?[]?'),
        [1,2], 'both iterators are optional');
    is_deeply(results('{"items":null}', '.items[]?[]'),
        [], 'optional first iterator avoids strict second iterator');
    is_deeply(results('{"items":[[1],2]}', '.items[][]?'),
        [1], 'optional second iterator drops numeric leaf');
    is_deeply(results('{"items":[{"only":[4,5]}]}', '.items[][]'),
        [[4,5]], 'second iterator emits the array-valued object member once');

    runtime_error('{"items":[[1],null]}', '.items[][]',
        'Cannot iterate over null', 'strict second iterator rejects null leaf');
    runtime_error('{"items":[[1],2]}', '.items[]?[]',
        'Cannot iterate over number', 'strict second iterator after optional first');
    runtime_error('{"items":null}', '.items[][]?',
        'Cannot iterate over null', 'strict first iterator fails before optional second');
    runtime_error('{"items":0}', '.items[][]?',
        'Cannot iterate over number', 'optional second iterator cannot hide first error');
};

subtest 'iterators interleaved with named fields' => sub {
    is_deeply(results('{"items":[[{"name":"A"}],[{"name":"B"}]]}',
            '.items[][].name'), ['A','B'],
        'two iterators before named field');
    is_deeply(results('{"items":[[{"name":"A"},{}],[]]}',
            '.items[][]?.name'), ['A',undef],
        'optional inner iterator followed by field');
    is_deeply(results('{"items":[{"children":[1,2]},{"children":[]}]}',
            '.items[].children[]'), [1,2],
        'strict named iterator after the first intermediate iterator');
    is_deeply(results('{"items":[{"children":[1,2]},{"children":null}]}',
            '.items[]?.children[]?'), [1,2],
        'two optional iterators around a later named field');
    is_deeply(results('{"outer":{"items":[{"name":"A"}]}}',
            '.outer.items[].name'), ['A'],
        'dotted named prefix before intermediate iterator');

    runtime_error('{"items":[{"children":[1]},{}]}',
            '.items[].children[]',
        'Cannot iterate over null', 'strict later iterator on missing field');
    runtime_error('{"items":[{"children":[1]},7]}',
            '.items[]?.children[]?',
        'Cannot index number with string "children"',
        'optional later iterator cannot hide a field-index error');
    runtime_error('{"items":[[{"name":"A"}],3]}',
            '.items[][].name',
        'Cannot iterate over number', 'intermediate strict iterator rejects scalar');
};

subtest 'empty streams and comma alternatives do not change errors' => sub {
    is_deeply(results('null', 'empty | .items[].name'), [],
        'no upstream input means no strict iterator attempt');
    is_deeply(results('null', 'empty | .items[][]'), [],
        'no upstream input means no nested iteration');
    is_deeply(results('{"items":[]}', '9, .items[].name'), [9],
        'empty second comma branch preserves first value');
    is_deeply(results('{"items":null}', '9, .items[]?.name'), [9],
        'optional second comma branch preserves first value');
    runtime_error('{"items":null}', '9, .items[].name',
        'Cannot iterate over null',
        'later strict comma branch still throws');

    is_deeply(results('{"items":[[1,2]]}', '.items[][] | . + 1'),
        [2,3], 'iterator outputs flow through ordinary pipeline');
};

subtest 'last-step iterator behavior from previous PR stays intact' => sub {
    is_deeply(results('{"a":[1,null,false]}', '.a[]'),
        [1,undef,JSON::PP::false],
        'strict terminal iterator preserves null and false output values');
    is_deeply(results('{"a":[1,2]}', '.a[]?'),
        [1,2], 'optional terminal iterator still emits all array members');
    is_deeply(results('{"a":{"b":[4]}}', '.a.b[]?'),
        [4], 'dotted optional terminal iterator still works');
    runtime_error('{"a":2}', '.a[]',
        'Cannot iterate over number', 'strict terminal iterator rejects scalar');
    is_deeply(results('{"a":2}', '.a[]?'), [],
        'optional terminal iterator skips scalar');
    runtime_error('1', '.a[]?',
        'Cannot index number with string "a"',
        'optional terminal iterator does not mask prefix error');
};

done_testing;
