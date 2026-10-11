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
    my ($input, $filter, $fragment, $description) = @_;
    my $ok = eval { $jq->run_query($input, $filter); 1 };
    my $error = $@;
    ok(!$ok, "$description: runtime error");
    if (!$ok) {
        isa_ok($error, 'JQ::Lite::Error::Evaluation',
            "$description: structured evaluation failure");
        like("$error", qr/\Q$fragment\E/,
            "$description: error identifies the failing stage");
    }
}

subtest 'quoted root field before strict or optional iteration' => sub {
    is_deeply(results('{"items":[{"name":"A"},{"name":"B"}]}',
            '.["items"][].name'), ['A','B'],
        'quoted root key followed by iterator and unquoted name');
    is_deeply(results('{"items":[{"name":"A"},{}]}',
            '.["items"][]?.name'), ['A',undef],
        'optional root iteration retains null for absent member name');
    is_deeply(results('{"a.b":[[1,2],[3]]}',
            '.["a.b"][0][]'), [1,2],
        'dot inside a JSON-quoted root key is not a path separator');
    is_deeply(results('{"a.b":[[1,2],[3]]}',
            '.["a.b"][-1][]'), [3],
        'negative array index after quoted dotted key');
    is_deeply(results('{"a.b":null}',
            '.["a.b"][]?'), [],
        'optional iterator skips JSON null in quoted field');
    is_deeply(results('{"a.b":[]}',
            '.["a.b"][]'), [],
        'strict iterator over empty array succeeds');
    is_deeply(results('{"items":[[1,2],[3]]}',
            '.["items"][][]'), [1,2,3],
        'consecutive iterators after quoted root key');
    is_deeply(results('{"items":[[1,2],null]}',
            '.["items"][][]?'), [1,2],
        'optional second iterator drops null inner item');
};

subtest 'quoted fields after an intermediate iterator and index' => sub {
    is_deeply(results('{"items":[{"full name":"Ada"},{"full name":"Bea"}]}',
            '.items[].["full name"]'), ['Ada','Bea'],
        'bracket-quoted name after iterator');
    is_deeply(results('{"items":[{"full name":"Ada"},{"full name":"Bea"}]}',
            '.items[]."full name"'), ['Ada','Bea'],
        'dot-quoted name after iterator');
    is_deeply(results('{"items":[{"full name":["A"]},{"full name":[]}]}',
            '.items[].["full name"][]'), ['A'],
        'strict iterator after quoted intermediate field');
    is_deeply(results('{"items":[{"a.b":[4,5]},{"a.b":[6]}]}',
            '.items[].["a.b"][0]'), [4,6],
        'numeric index after quoted field inside intermediate iteration');
    is_deeply(results('{"items":[{"a.b":[4,5]},{"a.b":[6]}]}',
            '.items[].["a.b"][-1]'), [5,6],
        'negative numeric index after quoted field');
    is_deeply(results('{"items":[[{"full name":"A"}],[{"full name":"B"}]]}',
            '.items[][0].["full name"]'), ['A','B'],
        'numeric index followed by quoted field after first iterator');
    is_deeply(results('{"outer":{"a.b":[{"full name":"A"}]}}',
            '.outer["a.b"][].["full name"]'), ['A'],
        'quoted dot key in the middle of a dotted name path');
    is_deeply(results('{"items":[{"full name":"A"},null]}',
            '.items[]?.["full name"]'), ['A',undef],
        'optional iterator emits null, which safely indexes to null');
};

subtest 'JSON-escaped and special-character field names stay literal' => sub {
    is_deeply(results('{"":[1,2]}', '.[""][]'), [1,2],
        'empty-string object key is accepted');
    is_deeply(results('{"a[]":[1]}', '.["a[]"][]'), [1],
        'iterator text inside a quoted field is not syntax');
    is_deeply(results('{"[0]":[2]}', '.["[0]"][]'), [2],
        'index text inside quoted field is not a numeric step');
    is_deeply(results('{"a.b":[3]}', '.["a.b"][]'), [3],
        'embedded period remains part of the key');
    is_deeply(results('{"x-y":[4]}', '.["x-y"][]'), [4],
        'hyphen inside quoted key is not subtraction');
    is_deeply(results('{"a+b":[5]}', '.["a+b"][]'), [5],
        'plus inside quoted key is not arithmetic');
    is_deeply(results('{"a/b":[6]}', '.["a/b"][]'), [6],
        'slash inside quoted key is not division');
    is_deeply(results('{"q|r":[7]}', '.["q|r"][]'), [7],
        'pipe inside quoted key is not a pipeline separator');
    is_deeply(results('{"a,b":[8]}', '.["a,b"][]'), [8],
        'comma inside quoted key is not a stream alternative');
    is_deeply(results('{"a\\"b":[9]}', '.["a\\"b"][]'), [9],
        'JSON-escaped quote is decoded inside the key');
    is_deeply(results('{"a\\\\b":[10]}', '.["a\\\\b"][]'), [10],
        'JSON-escaped backslash is decoded inside the key');
    is_deeply(results('{"日本語":[11]}', '.["\u65e5\u672c\u8a9e"][]'), [11],
        'JSON Unicode escapes identify the same UTF-8 key');
    is_deeply(results('{"a.b":[{"full name":[12]}]}',
            '.["a.b"][].["full name"][]'), [12],
        'different special keys compose with two iterators');
};

subtest 'strict and optional failures remain at their own stages' => sub {
    runtime_error('{"a.b":null}', '.["a.b"][]',
        'Cannot iterate over null', 'strict iterator on quoted null');
    runtime_error('{}', '.["missing"][]',
        'Cannot iterate over null', 'strict iterator on missing quoted key');
    is_deeply(results('{}', '.["missing"][]?'), [],
        'optional iterator on missing quoted key returns empty stream');
    runtime_error('{"a.b":3}', '.["a.b"][]',
        'Cannot iterate over number', 'strict iterator on quoted numeric field');
    is_deeply(results('{"a.b":3}', '.["a.b"][]?'), [],
        'optional iterator drops scalar quoted field');
    runtime_error('1', '.["items"][]?',
        'Cannot index number with string "items"',
        'optional iterator cannot mask invalid quoted field lookup');
    runtime_error('{"items":[2]}', '.["items"][]?.["full name"]',
        'Cannot index number with string "full name"',
        'optional iterator cannot mask later invalid quoted field lookup');
    runtime_error('{"items":[{"a.b":null}]}',
            '.items[].["a.b"][]',
        'Cannot iterate over null',
        'missing quoted field cannot be strictly iterated');
    is_deeply(results('{"items":[{"a.b":null}]}',
            '.items[].["a.b"][]?'), [],
        'optional last iterator drops quoted null');
    runtime_error('{"a.b":{}}', '.["a.b"][0][]?',
        'Cannot index object with number',
        'optional last iterator cannot mask invalid numeric index');
    is_deeply(results('{"a.b":[]}', '.["a.b"][0][]?'), [],
        'optional iterator drops out-of-bounds numeric index null');
    runtime_error('{"items":[true]}', '.items[].["full name"]',
        'Cannot index boolean with string "full name"',
        'quoted field lookup from boolean fails');
};

subtest 'pipeline and comma branch ordering is preserved' => sub {
    is_deeply(results('{"a.b":[1,2]}',
            '.["a.b"][] | . + 1'), [2,3],
        'quoted key iterator emits values for downstream arithmetic');
    is_deeply(results('{"a.b":[1]}',
            '0, .["a.b"][]'), [0,1],
        'quoted bracket path works in comma alternative');
    is_deeply(results('{"a.b":null}',
            '0, .["a.b"][]?'), [0],
        'optional quoted path does not remove earlier comma value');
    runtime_error('{"a.b":null}',
            '0, .["a.b"][]',
        'Cannot iterate over null', 'later strict quoted path still errors');
    is_deeply(results('null',
            'empty | .["items"][].name'), [],
        'empty upstream stream never evaluates strict quoted path');
};

subtest 'unquoted iterator paths and unquoted quoted access remain intact' => sub {
    is_deeply(results('{"items":[[{"name":"A"}]]}',
            '.items[0][].name'), ['A'],
        'previous numeric index plus iterator path still works');
    is_deeply(results('{"items":[{"name":"A"},{}]}',
            '.items[].name'), ['A',undef],
        'previous unquoted intermediate iterator path still works');
    is_deeply(results('{"a b":2}', '."a b"'), [2],
        'preexisting non-iterator quoted field access is unchanged');
    is_deeply(results('{"a":null}', '.a[]?'), [],
        'previous optional terminal iterator still works');
};

done_testing;
