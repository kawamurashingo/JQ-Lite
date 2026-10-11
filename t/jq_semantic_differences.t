use strict;
use warnings;

use Test::More;
use JQ::Lite;
use JSON::PP ();

my $jq = JQ::Lite->new;

sub result_for {
    my ($json, $query) = @_;
    my @results = $jq->run_query($json, $query);
    return $results[0];
}

sub results_for {
    my ($json, $query) = @_;
    return [$jq->run_query($json, $query)];
}

subtest 'preserved 2.x compatibility semantics' => sub {
    ok(
        !result_for('[1,2,3]', 'contains([1,3])'),
        'contains does not treat its array argument as a jq-style subset',
    );

    ok(
        !result_for(
            '{"a":{"b":1,"c":2}}',
            'contains({"a":{"b":1}})',
        ),
        'contains requires equality for nested object values',
    );

    is_deeply(
        result_for('[[1,2],[3]]', 'transpose'),
        [[1, 3]],
        'transpose truncates jagged matrices to their shortest row',
    );
};

subtest 'v3 alternative semantics' => sub {
    is(result_for('false', '. // 9'), 9,
        'JSON false selects the fallback in v3');
    is(result_for('null', '. // 9'), 9,
        'null selects the fallback');
};

subtest 'strict arithmetic and preserved vectorised semantics' => sub {
    {
        my $ok = eval { result_for('"1e3"', '. * 1'); 1 };
        ok(!$ok, 'numeric-looking string arithmetic is rejected in v3');
        isa_ok($@, 'JQ::Lite::Error::Evaluation');
    }

    {
        my $ok = eval { result_for('true', '. + 1'); 1 };
        ok(!$ok, 'boolean arithmetic is rejected in v3');
        isa_ok($@, 'JQ::Lite::Error::Evaluation');
    }

    is_deeply(
        result_for('[1.2,"2.8","x"]', 'floor'),
        [1, 2, 'x'],
        'floor vectorises and passes non-numeric values through',
    );

    is_deeply(
        result_for('["1","true","bad"]', 'fromjson'),
        [1, JSON::PP::true, 'bad'],
        'fromjson vectorises and passes invalid JSON text through',
    );

    my $match = result_for('42', 'match("2")');
    is(ref($match), 'HASH', 'match accepts a non-string scalar');
    is($match->{string}, '2', 'match uses the scalar string representation');
    is($match->{offset}, 1, 'match reports the coerced-string offset');
};

subtest 'contains_subset extension limitations' => sub {
    ok(
        result_for('[1,2,3]', 'contains_subset([1,3])'),
        'contains_subset supports distinct same-type subset values',
    );
    ok(
        !result_for('[1]', 'contains_subset([1,1])'),
        'duplicate needles require distinct matches, unlike jq contains',
    );
    ok(
        result_for('["1"]', 'contains_subset([1])'),
        'scalar subset comparison coerces types, unlike jq contains',
    );
};

subtest 'comparison semantics' => sub {
    ok(result_for('{}', '"10" == 10'), 'numeric string equals number');
    ok(result_for('{}', 'false < 0'), 'cross-type ordering matches jq here');
    ok(!result_for('{}', '[1,2] < [1,3]'), 'arrays are not ordered lexicographically');
    ok(result_for('{}', '.missing == null'), 'missing compares equal to null');
};

subtest 'null, missing, and path semantics' => sub {
    is_deeply(results_for('{}', '.missing'), [undef], 'missing field emits JSON null');
    is_deeply(results_for('{}', '.missing.value'), [undef], 'path through missing field emits JSON null');
    is_deeply(results_for('{"a":[]}', '.a.value'), [], 'field access through array emits no result');
    my $ok = eval { results_for('{}', '.[5]'); 1 };
    ok(!$ok, 'numeric object index rejects object input in v3');
    isa_ok($@, 'JQ::Lite::Error::Evaluation');
};

subtest 'iterator and pipeline semantics' => sub {
    is_deeply(
        results_for('[{"x":1},{"x":2}]', '.x'),
        [1, 2],
        'field access projects through array values',
    );
    is_deeply(
        results_for('{"a":[{"x":1}],"n":3}', '.[] | .x'),
        [1],
        'pipeline projection traverses nested array and drops missing scalar field',
    );
    is_deeply(results_for('{"b":2,"a":1}', 'keys[]'), ['a', 'b'], 'iterator suffix is stable');
    is_deeply(results_for('null', '0, [4,5][]'), [0, 4, 5], 'comma branches survive iterator suffix');
    is_deeply(results_for('null', '.[]?'), [],
        'optional iterator drops null rather than raising a type error');
    is_deeply(results_for('1', '.[]?'), [],
        'optional iterator drops numeric scalars');
    is_deeply(results_for('"abc"', '.[]?'), [],
        'optional iterator never splits string characters');
    is_deeply(results_for('[null,false,[2]]', '.[]?'),
        [undef, JSON::PP::false, [2]],
        'optional iterator preserves null/false array members');
    is_deeply(results_for('[null,false,[2]]', '.[]? | .[]?'),
        [2], 'chained optional iterators drop scalar leaves');
    is_deeply(results_for('{"a":null}', '.a[]?'), [],
        'optional literal path suffix discards non-iterable field');
    my $strict_field_ok = eval { results_for('{}', '.a[]'); 1 };
    ok(!$strict_field_ok, 'missing field followed by strict [] raises an error');
    isa_ok($@, 'JQ::Lite::Error::Evaluation') unless $strict_field_ok;
    is_deeply(results_for('{}', '.a[]?'), [],
        'missing field followed by []? has no outputs');
    my $bad_prefix_ok = eval { results_for('1', '.a[]?'); 1 };
    ok(!$bad_prefix_ok, 'optional []? does not suppress invalid field lookup');
    isa_ok($@, 'JQ::Lite::Error::Evaluation') unless $bad_prefix_ok;
    is_deeply(results_for('{"a":{"b":[1,2]}}', '.a.b[]?'), [1,2],
        'nested named-field optional iterator preserves array contents');
    is_deeply(results_for('{"items":[{"name":"A"},{}]}',
            '.items[].name'), ['A', undef],
        'intermediate strict iterator followed by named-field lookup');
    is_deeply(results_for('{"items":null}', '.items[]?.name'), [],
        'optional intermediate iterator suppresses null iteration only');
    is_deeply(results_for('{"items":[[1,2],[3]]}', '.items[][]'),
        [1, 2, 3], 'two strict iterators flatten consecutive arrays');
    is_deeply(results_for('{"items":[[{"name":"A"}]]}',
            '.items[0][].name'), ['A'],
        'numeric index before iterator and later field');
    is_deeply(results_for('{"items":[{"names":["A","B"]}]}',
            '.items[].names[0]'), ['A'],
        'numeric index after intermediate iterator');
    is_deeply(results_for('{"items":[[{"name":"A"}],[{"name":"B"}]]}',
            '.items[-1][].name'), ['B'],
        'negative numeric index in iterator path parses as indexing');
    is_deeply(results_for('{"items":[{"name":"A"},{"name":"B"}]}',
            '.["items"][].name'), ['A','B'],
        'quoted root field continues into strict iterator and named field');
    is_deeply(results_for('{"a.b":[[1,2]]}',
            '.["a.b"][0][]'), [1,2],
        'quoted key with dot survives numeric index and iteration');
    is_deeply(results_for('{"items":[{"full name":"Ada"}]}',
            '.items[].["full name"]'), ['Ada'],
        'quoted name after iterator remains literal');
    is_deeply(results_for('{"key":"a","a":7}', '.[.key]'), [7],
        'computed root field uses key string from current object');
    is_deeply(results_for('{"key":"missing"}', '.[.key]'), [undef],
        'computed root field emits null for a missing selected object key');
    is_deeply(results_for('{"key":"a","a":[1,2]}',
            '.[.key][]'), [1,2],
        'computed root selector can feed a strict iterator');
    is_deeply(results_for('{"key":"a","a":null}',
            '.[.key][]?'), [],
        'computed root selector can feed an optional iterator');
    is_deeply(results_for('{"items":[{"field":"x","x":2}]}',
            '.items[] | .[.field]'), [2],
        'each pipeline item evaluates its own computed selector');
    my $bad_dynamic_key = eval {
        results_for('{"key":null}', '.[.key]'); 1;
    };
    ok(!$bad_dynamic_key, 'computed key rejects null selector result');
    isa_ok($@, 'JQ::Lite::Error::Evaluation') unless $bad_dynamic_key;
    is_deeply(results_for('{"a.b":null}', '.["a.b"][]?'), [],
        'quoted optional iterator omits null field');
    my $quoted_strict_ok = eval {
        results_for('{"a.b":null}', '.["a.b"][]'); 1;
    };
    ok(!$quoted_strict_ok, 'quoted strict iterator errors on null field');
    isa_ok($@, 'JQ::Lite::Error::Evaluation') unless $quoted_strict_ok;
    my $quoted_member_ok = eval {
        results_for('{"items":[2]}', '.items[]?.["full name"]'); 1;
    };
    ok(!$quoted_member_ok,
        'optional iterator does not hide later quoted field indexing error');
    isa_ok($@, 'JQ::Lite::Error::Evaluation') unless $quoted_member_ok;
    is_deeply(results_for('{"items":[]}', '.items[0][]?'), [],
        'optional iterator skips null from out-of-bounds numeric index');
    my $invalid_numeric_index = eval {
        results_for('{"items":{}}', '.items[0][]?'); 1;
    };
    ok(!$invalid_numeric_index,
        'optional iterator cannot mask numeric indexing into object');
    isa_ok($@, 'JQ::Lite::Error::Evaluation')
        unless $invalid_numeric_index;
    is_deeply(results_for('{"items":[[1,2],null]}', '.items[][]?'),
        [1, 2], 'optional second iterator drops null leaf');
    my $bad_member_ok = eval {
        results_for('{"items":[2]}', '.items[]?.name'); 1;
    };
    ok(!$bad_member_ok,
        'optional intermediate iterator preserves later field-index error');
    isa_ok($@, 'JQ::Lite::Error::Evaluation') unless $bad_member_ok;
    my $bad_second_iter_ok = eval {
        results_for('{"items":[[1],null]}', '.items[][]'); 1;
    };
    ok(!$bad_second_iter_ok, 'strict second iterator rejects null element');
    isa_ok($@, 'JQ::Lite::Error::Evaluation')
        unless $bad_second_iter_ok;
    is_deeply(results_for('{"a":1}', 'keys[]?'), ['a'],
        'function-result optional suffix expands keys');
    is_deeply(results_for('null', 'recurse(.[]?)'), [undef],
        'optional recurse child iteration terminates at null');
    is_deeply(results_for('[1,[2]]', 'recurse'),
        [[1,[2]],1,[2],2],
        'default recurse still terminates safely at scalar leaves');
    my $strict_recurse_ok = eval {
        results_for('[1,[2]]', 'recurse(.[])');
        1;
    };
    ok(!$strict_recurse_ok, 'explicit recurse iterator rejects scalar leaves');
    isa_ok($@, 'JQ::Lite::Error::Evaluation')
        unless $strict_recurse_ok;

    is_deeply(results_for('[1,2]', '.[]'), [1,2],
        'standalone iterator still emits every array element');
    is_deeply(results_for('{}', '.[]'), [],
        'standalone iterator over empty object has no results');
    for my $scalar (qw(null 1 true false)) {
        my $ok = eval { results_for($scalar, '.[]'); 1 };
        ok(!$ok, "v3 standalone iterator rejects $scalar");
        isa_ok($@, 'JQ::Lite::Error::Evaluation') unless $ok;
    }
    my $string_ok = eval { results_for('"abc"', '.[]'); 1 };
    ok(!$string_ok, 'v3 standalone iterator rejects strings');
    isa_ok($@, 'JQ::Lite::Error::Evaluation')
        unless $string_ok;
};

subtest 'assignment and update semantics' => sub {
    is_deeply(result_for('{"a":1}', '.a = 2'), {a => 2}, 'plain assignment emits updated root');
    is_deeply(results_for('{"a":1}', '.a |= . + 1'), [{a => 2}],
        'v3 update assignment emits the updated root');
    is_deeply(results_for('{"a":1}', '.missing |= . + 1'),
        [{a => 1, missing => 1}], 'v3 update creates missing key');
    is_deeply(results_for('{"a":1}', '.a |= (3, 4)'),
        [{a => 3}], 'v3 update selects the first RHS result');
    is_deeply(results_for('{"a":1}', '.a |= (3, 1 / 0)'),
        [{a => 3}], 'v3 update does not evaluate later unused RHS branch');
    is_deeply(results_for('{"a":1}', '.a |= ((1,2) | . + 1)'),
        [{a => 2}], 'v3 update takes the first complete pipeline output');
    is_deeply(results_for('{"a":1}', '.a |= ((1,0) | (1 / .))'),
        [{a => 1}], 'v3 update skips unused later upstream errors');
    is_deeply(results_for('{"a":1}', '.a |= recurse(. + 1)'),
        [{a => 1}], 'v3 update stops before unbounded recurse child expansion');
    is_deeply(results_for('{"a":1}', '.a |= (recurse(. + 1) | select(. > 3))'),
        [{a => 4}], 'v3 update expands only needed recurse descendants');
    is_deeply(results_for('{"a":1}',
            '.a |= (recurse((. + 1, 1 / 0)) | select(. > 1))'),
        [{a => 2}], 'v3 update skips unused recurse child branch error');
    is_deeply(results_for('{"a":1}',
            '.a |= (recurse((. + 1, 1 / 0)) | select(. > 3))'),
        [{a => 4}], 'v3 update searches custom children depth-first');
    is_deeply(results_for('{"a":17}', '.a |= range(1000000000)'),
        [{a => 0}], 'v3 update does not construct enormous range streams');
    is_deeply(results_for('{"a":17}', '.a |= (range(1000000000) | select(. > 3))'),
        [{a => 4}], 'v3 update consumes only required range values');
    is_deeply(results_for('{"a":17}', '.a |= range(0;0)'),
        [{}], 'v3 empty range deletes the update target');
    is_deeply(results_for('{"a":1}', '.a |= empty'),
        [{}], 'v3 update deletes when the entire RHS is empty');
    is_deeply(results_for('{"items":[1,2,3]}', '.items[] |= . + 1'),
        [{items => [2,3,4]}], 'v3 iterator update returns the updated root');
    is_deeply(results_for('{"items":[1,2,3]}', '.items[] |= empty'),
        [{items => []}], 'v3 iterator update deletes every array element');
    is_deeply(results_for('{"items":{"a":1,"b":2}}', '.items[] |= . + 1'),
        [{items => {a => 2, b => 3}}],
        'v3 object iterator updates values in the original object');
    is_deeply(results_for('{"items":{"a":1,"b":2}}', '.items[] |= empty'),
        [{items => {}}],
        'v3 object iterator deletes member keys on empty RHS');
    is_deeply(results_for('{"groups":[[1,2],[3,4]]}', '.groups[][] |= . + 1'),
        [{groups => [[2,3],[4,5]]}],
        'v3 nested iterators update multiple array dimensions');
    is_deeply(results_for('{"groups":{"x":[1,2],"y":[3,4]}}',
            '.groups[][] |= empty'),
        [{groups => {x => [], y => []}}],
        'v3 nested iterator deletion keeps outer object keys');
    is_deeply(results_for('{"a":0}', '.a = (1,2)'), [], 'multi-result assignment emits no result');
};

subtest 'unsupported jq syntax remains non-functional' => sub {
    is_deeply(
        results_for('1', 'def inc: . + 1; inc'),
        [undef],
        'user-defined jq function syntax currently evaluates to null',
    );
};

done_testing;
