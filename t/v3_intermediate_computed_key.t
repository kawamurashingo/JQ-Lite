use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Error ();
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;

sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

sub runtime_error {
    my ($json, $filter, $fragment, $label) = @_;
    my $ok = eval { $jq->run_query($json, $filter); 1 };
    my $err = $@;
    ok(!$ok, "$label: fails");
    if (!$ok) {
        isa_ok($err, 'JQ::Lite::Error::Evaluation',
            "$label: structured evaluation error");
        like("$err", qr/\Q$fragment\E/, "$label: correct error boundary");
    }
}

subtest 'computed key after a field uses original input, not the target' => sub {
    is_deeply(results('{"key":"a","obj":{"key":"b","a":7,"b":8}}',
            '.obj[.key]'),
        [7], 'outer key a wins over target-local key b');
    is_deeply(results('{"key":"b","obj":{"key":"a","a":7,"b":8}}',
            '.obj[.key]'),
        [8], 'outer key b wins over target-local key a');
    is_deeply(results('{"key":"missing","obj":{"a":7}}',
            '.obj[.key]'),
        [undef], 'selected target field absent yields one null');
    is_deeply(results('{"key":"a","obj":null}',
            '.obj[.key]'),
        [undef], 'computed string indexing into null yields null');
    is_deeply(results('{"key":"a"}',
            '.obj[.key]'),
        [undef], 'missing target object with valid key yields null');
    is_deeply(results('{"key":"a","obj":{"a":false}}',
            '.obj[.key]'),
        [JSON::PP::false], 'selected false value is retained');
    is_deeply(results('{"key":"a","obj":{"a":null}}',
            '.obj[.key]'),
        [undef], 'selected explicit null is one result');
    is_deeply(results('{"key":"0","obj":{"0":"zero"}}',
            '.obj[.key]'),
        ['zero'], 'numeric-looking string remains an object key');
    is_deeply(results('{"key":"","obj":{"":"empty"}}',
            '.obj[.key]'),
        ['empty'], 'empty string remains a valid computed object key');
    is_deeply(results('{"key":"a.b","obj":{"a.b":12}}',
            '.obj[.key]'),
        [12], 'period in computed string is literal key content');
};

subtest 'dotted selectors and literal/indexed prefixes' => sub {
    is_deeply(results('{"cfg":{"selected":"b"},"obj":{"a":7,"b":8}}',
            '.obj[.cfg.selected]'),
        [8], 'dotted selector reads original root');
    is_deeply(results('{"key":"a","obj":{"a":7}}',
            '.["obj"][.key]'),
        [7], 'computed key after JSON-quoted prefix');
    is_deeply(results('{"key":"a","a.b":{"a":9}}',
            '.["a.b"][.key]'),
        [9], 'quoted prefix containing a period');
    is_deeply(results('{"key":"a","items":[{"a":7},{"a":8}]}',
            '.items[0][.key]'),
        [7], 'computed key after a numeric index');
    is_deeply(results('{"key":"a","items":[{"a":7},{"a":8}]}',
            '.items[-1][.key]'),
        [8], 'computed key after a negative numeric index');
    is_deeply(results('{"key":"a","items":[{"a":{}}]}',
            '.items[0][.key].child'),
        [undef], 'field access after missing property on selected object');
    is_deeply(results('{"first":"a","second":"b","obj":{"a":{"b":8}}}',
            '.obj[.first][.second]'),
        [8], 'two computed stages independently select from original input');
    is_deeply(results('{"key":0,"obj":[5,6]}',
            '.obj[.key]'),
        [5], 'numeric selector indexes a target array');
    is_deeply(results('{"key":-1,"obj":[5,6]}',
            '.obj[.key]'),
        [6], 'negative numeric selector indexes a target array');
    is_deeply(results('{"key":0.5,"obj":[5,6]}',
            '.obj[.key]'),
        [5], 'fractional numeric selector matches jq array indexing');
    is_deeply(results('{"key":"a","obj":{"a":[3,4]}}',
            '.obj[.key][-1]'),
        [4], 'numeric suffix indexes computed array result');
};

subtest 'iterator streams share selector from filter input' => sub {
    is_deeply(results(
        '{"key":"a","items":[{"key":"b","a":1,"b":9},{"a":2}]}',
        '.items[][.key]'
    ), [1,2], 'item-local key is not used inside the same path filter');
    is_deeply(results(
        '{"key":"a","items":[[{"a":1}],[{"a":2}]]}',
        '.items[][][.key]'
    ), [1,2], 'selector context survives two iterator stages');
    is_deeply(results(
        '{"key":"a","items":[{"a":1},{"a":2}]}',
        '.items[]?[.key]'
    ), [1,2], 'optional intermediate iteration preserves root selector');
    is_deeply(results(
        '{"key":"a","items":[{"a":1},{"a":2}]}',
        '.items[].[.key]'
    ), [1,2], 'same semantics with explicit dot before bracket selector');
    is_deeply(results('{"key":"a","items":[]}',
        '.items[][.key]'), [],
        'empty container stream yields no indexed outputs');
    is_deeply(results(
        '{"key":"a","items":[{"a":[1,2]},{"a":[3]}]}',
        '.items[][.key][]'
    ), [1,2,3], 'computed selector result can feed a strict iterator');
    is_deeply(results(
        '{"key":"a","items":[{"a":[1,2]},{"a":null}]}',
        '.items[][.key][]?'
    ), [1,2], 'optional final iterator skips a computed null value');
    is_deeply(results(
        '{"key":"a","items":[{"a":[1,2]},{"a":null}]}',
        '.items[][.key]'
    ), [[1,2],undef], 'computed arrays stay single values without iterator');
    is_deeply(results(
        '{"key":"a","items":[null]}',
        '.items[][.key]'
    ), [undef], 'computed string lookup on emitted null yields null');
};

subtest 'pipeline stages each establish their own original context' => sub {
    is_deeply(results(
        '{"items":[{"key":"a","obj":{"a":1}},{"key":"b","obj":{"b":2}}]}',
        '.items[] | .obj[.key]'
    ), [1,2], 'each item is the root input of its next pipeline filter');
    is_deeply(results(
        '{"items":[{"key":"a","obj":{"a":[1,2]}},{"key":"a","obj":{"a":null}}]}',
        '.items[] | .obj[.key][]?'
    ), [1,2], 'optional iterator after per-item computed key');
    is_deeply(results('{"key":"a","obj":{"a":7}}',
        '0, .obj[.key]'), [0,7], 'comma alternative preserves value order');
    is_deeply(results('{"key":"a","obj":{"a":7}}',
        '.obj[.key], .key'), [7,'a'],
        'computed then literal comma alternatives preserve order');
    is_deeply(results('null',
        'empty | .obj[.key]'), [],
        'empty upstream pipeline never evaluates computed key');
    is_deeply(results('{"key":"a","obj":{"a":7}}',
        '.obj[.key] | . + 1'), [8],
        'computed value participates in downstream arithmetic');
};

subtest 'selector and target errors remain distinct' => sub {
    runtime_error('{"obj":{"a":7}}', '.obj[.key]',
        'Cannot index object with null', 'missing root selector');
    runtime_error('{"key":null,"obj":{"a":7}}', '.obj[.key]',
        'Cannot index object with null', 'explicit null selector');
    runtime_error('{"key":true,"obj":{"a":7}}', '.obj[.key]',
        'Cannot index object with boolean', 'boolean selector');
    runtime_error('{"key":["a"],"obj":{"a":7}}', '.obj[.key]',
        'Cannot index object with array', 'array selector');
    runtime_error('{"key":{"a":1},"obj":{"a":7}}', '.obj[.key]',
        'Cannot index object with object', 'object selector');
    runtime_error('{"key":"0","obj":[5,6]}', '.obj[.key]',
        'Cannot index array with string "0"',
        'numeric-looking string cannot index array');
    runtime_error('{"key":"a","obj":true}', '.obj[.key]',
        'Cannot index boolean with string "a"',
        'wrong target type is not suppressed');
    runtime_error('{"key":"a","obj":3}', '.obj[.key]',
        'Cannot index number with string "a"',
        'numeric target cannot be indexed by a string');
    runtime_error('{"key":"a","obj":{"a":3}}', '.obj[.key][]',
        'Cannot iterate over number',
        'strict suffix fails on selected number');
    is_deeply(results('{"key":"a","obj":{"a":3}}',
        '.obj[.key][]?'), [],
        'optional suffix skips a selected scalar');
    is_deeply(results('{"key":"a","obj":{}}',
            '.obj[.key][0][]?'), [],
        'optional iterator drops null produced by numeric index');
    runtime_error('{"key":"a","obj":{}}', '.obj[.key][0][]',
        'Cannot iterate over null',
        'strict last iterator rejects null produced by numeric index');
    runtime_error('{"cfg":7,"obj":{"a":7}}', '.obj[.cfg.key]',
        'Cannot index number with string "key"',
        'dotted selector errors before targeting object');
    runtime_error('{"cfg":7,"items":[]}', '.items[][.cfg.key]',
        'Cannot index number with string "key"',
        'invalid computed selector is evaluated even for empty iterator');
    is_deeply(results('{"key":null,"items":[]}', '.items[][.key]'),
        [], 'null selector cannot cause indexing error with no target');
    runtime_error('null', '.obj[.key]',
        'Cannot index null with null',
        'null root produces null key and indexing fails');
    runtime_error('1', '.obj[.key]',
        'Cannot index number with string "key"',
        'invalid field read from numeric original root');
};

subtest 'scoped parser and previously covered filters' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path('.obj[.key]'),
        [['field','obj'],['computed_context','.key']],
        'computed selector after object field parses explicitly');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
            '.items[][.cfg.selected][]?'),
        [['field','items'],['iterator',0],
         ['computed_context','.cfg.selected'],['iterator',1]],
        'computed selector follows strict iterator and optional suffix');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
            '.[.key]'),
        [['computed_root','.key']],
        'previous root computed selector step remains intact');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.key + 1]')),
        'arithmetic expression in selector is outside scoped syntax');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.keys[]]')),
        'generator-backed computed selector stays outside scope');
    is_deeply(results('{"key":"a","a":7}', '.[.key]'),
        [7], 'previous root computed lookup still works');
    is_deeply(results('{"items":[{"name":"A"}]}',
            '.["items"][].name'), ['A'],
        'previous literal quoted iterator path still works');
    is_deeply(results('{"items":[[1,2]]}',
            '.items[0][]'), [1,2],
        'previous numeric index plus iterator path still works');
    is_deeply(results('{"items":[{"name":"A"}]}',
            '.items[].name'), ['A'],
        'previous named intermediate iteration still works');
};

done_testing;
