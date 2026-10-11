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
    my ($input, $filter, $fragment, $label) = @_;
    my $ok = eval { $jq->run_query($input, $filter); 1 };
    my $error = $@;
    ok(!$ok, "$label: query fails");
    if (!$ok) {
        isa_ok($error, 'JQ::Lite::Error::Evaluation',
            "$label: structured evaluation error");
        like("$error", qr/\Q$fragment\E/, "$label: correct failing stage");
    }
}

subtest 'numeric index before iteration and later named fields' => sub {
    is_deeply(results('{"items":[[{"name":"A"},{"name":"B"}]]}',
            '.items[0][].name'),
        ['A', 'B'], 'index selects one nested array before iteration');
    is_deeply(results('{"items":[[{"name":"A"}]]}',
            '.items[0][]?.name'),
        ['A'], 'optional iteration after index preserves object fields');
    is_deeply(results('{"items":[[1,null,false]]}', '.items[0][]'),
        [1, undef, JSON::PP::false],
        'numeric index then iterator preserves JSON null and false');
    is_deeply(results('{"items":[[{"name":"A"}],[{"name":"B"}]]}',
            '.items[-1][].name'),
        ['B'], 'negative index selects the last array element');
    is_deeply(results('{"items":[[{"name":"A"}]]}',
            '.items[0][0].name'),
        ['A'], 'numeric-only path remains a normal field/index lookup');

    runtime_error('{"items":[]}', '.items[0][].name',
        'Cannot iterate over null', 'out-of-bounds index precedes strict iterator');
    is_deeply(results('{"items":[]}', '.items[0][]?.name'),
        [], 'out-of-bounds index precedes optional iterator');
    runtime_error('{"items":[[1]]}', '.items[3][].name',
        'Cannot iterate over null', 'larger out-of-bounds index is null');
    is_deeply(results('{"items":[[1]]}', '.items[3][]?.name'),
        [], 'optional iterator skips null from out-of-bounds index');
    runtime_error('{"items":{"0":[1,2]}}', '.items[0][]',
        'Cannot index object with number', 'numeric object key is not an array index');
    runtime_error('{"items":3}', '.items[0][]?',
        'Cannot index number with number', 'optional suffix cannot suppress invalid index');
    runtime_error('{"items":"abc"}', '.items[0][]?',
        'Cannot index string with number', 'string cannot be indexed numerically');
    runtime_error('{"items":false}', '.items[0][]?',
        'Cannot index boolean with number', 'boolean cannot be indexed numerically');
    is_deeply(results('{"items":null}', '.items[0][]?'), [],
        'numeric index on null produces null and optional iterator drops it');
};

subtest 'numeric index after an intermediate iterator' => sub {
    is_deeply(results('{"items":[{"names":["A","B"]},{"names":[]}]}',
            '.items[].names[0]'), ['A',undef],
        'numeric index reads each emitted nested array');
    is_deeply(results('{"items":[{"names":["A","B"]},{}]}',
            '.items[].names[0]'), ['A',undef],
        'missing array field indexes to null');
    is_deeply(results('{"items":[[1,2],null]}', '.items[][0]'),
        [1,undef], 'numeric indexing a null iterator member returns null');
    is_deeply(results('{"items":[[1],[2,3]]}', '.items[][-1]'),
        [1,3], 'negative numeric index after iterator');
    is_deeply(results('{"items":[[1],[2]]}', '.items[][4]'),
        [undef,undef], 'out-of-range per-member index emits null');
    is_deeply(results('{"items":[[{"name":"A"}],[{"name":"B"}]]}',
            '.items[][0].name'),
        ['A','B'], 'field read after indexing each iterated array');

    runtime_error('{"items":[1]}', '.items[][0]',
        'Cannot index number with number', 'numeric iterator member rejects index');
    runtime_error('{"items":[true]}', '.items[][0]',
        'Cannot index boolean with number', 'boolean iterator member rejects index');
    runtime_error('{"items":[{}]}', '.items[][0]',
        'Cannot index object with number', 'object member rejects numeric indexing');
    runtime_error('{"items":[{"names":["A"]},{"names":{"0":"B"}}]}',
        '.items[].names[0]',
        'Cannot index object with number', 'numeric object key does not convert to index');
    runtime_error('{"items":[1]}', '.items[]?[0]',
        'Cannot index number with number', 'optional first iterator does not hide later numeric index');
};

subtest 'strict/optional iteration after numeric index' => sub {
    is_deeply(results('{"items":[[[1,2]],[[3]]]}', '.items[][0][]'),
        [1,2,3], 'numeric index between strict iterators');
    is_deeply(results('{"items":[[[1,2]],null]}', '.items[][0][]?'),
        [1,2], 'last optional iterator omits null from numeric index');
    is_deeply(results('{"items":[[[1]],null]}', '.items[]?[0][]?'),
        [1], 'optional first and last iterators both preserve their bounds');
    is_deeply(results('{"items":[[1],null]}', '.items[][0][]?'),
        [], 'scalar indexed values are dropped only by optional final iteration');
    runtime_error('{"items":[[1],null]}', '.items[][0][]',
        'Cannot iterate over number', 'strict iterator rejects indexed number');
    runtime_error('{"items":null}', '.items[][0][]?',
        'Cannot iterate over null', 'last optional iterator cannot hide first strict error');
    runtime_error('{"items":[[[1]],2]}', '.items[]?[0][]?',
        'Cannot index number with number',
        'numeric index error survives optional iterators on either side');
};

subtest 'numeric path and field interleaving' => sub {
    is_deeply(results('{"groups":[{"items":[[{"name":"A"}]]}]}',
            '.groups[0].items[0][].name'),
        ['A'], 'multiple named fields and numeric indices before iterator');
    is_deeply(results('{"groups":[{"items":[{"name":"A"}]}]}',
            '.groups[].items[0].name'),
        ['A'], 'numeric index after first intermediate iterator');
    is_deeply(results('{"items":[{"names":["A","B"]},{"names":["C"]}]}',
            '.items[]?.names[-1]'),
        ['B','C'], 'optional iterator feeds negative index and field');
    is_deeply(results('{"items":[{"names":null},{"names":["A"]}]}',
            '.items[]?.names[0]'),
        [undef,'A'], 'numeric index from JSON null emits null');
    is_deeply(results('{"items":[[{"name":"A"}],[]]}',
            '.items[][0].name'),
        ['A',undef], 'out-of-bounds numeric index is still one null result');
    runtime_error('{"groups":[{"items":{}}]}',
            '.groups[0].items[0][]?',
        'Cannot index object with number',
        'bad numeric lookup cannot be masked by optional trailing iterator');
};

subtest 'comma and pipeline ordering, plus previously audited paths' => sub {
    is_deeply(results('null', 'empty | .items[0][].name'), [],
        'empty prior pipeline never evaluates strict numeric iterator');
    is_deeply(results('{"items":[]}', '9, .items[0][]?.name'), [9],
        'comma branch with optional iterator preserves earlier output');
    runtime_error('{"items":[]}', '9, .items[0][].name',
        'Cannot iterate over null', 'comma branch with strict iterator still errors');
    is_deeply(results('{"items":[[1,2]]}', '.items[0][] | . + 1'),
        [2,3], 'pipeline applies to every indexed iterator value');
    is_deeply(results('{"items":[{"name":"A"},{}]}', '.items[].name'),
        ['A',undef], 'earlier intermediate iterator path unchanged');
    is_deeply(results('{"items":[[1,2],[3]]}', '.items[][]'),
        [1,2,3], 'earlier adjacent iterators unchanged');
    is_deeply(results('{"a":null}', '.a[5]'), [undef],
        'numeric-only path still returns null from JSON null');
    is_deeply(results('[10,20]', '.[1]'), [20],
        'direct numeric index is not intercepted by scoped iterator logic');
    runtime_error('{"a":{}}', '.a[0]',
        'Cannot index object with number',
        'numeric-only indexed object remains a runtime error');
};

done_testing;
