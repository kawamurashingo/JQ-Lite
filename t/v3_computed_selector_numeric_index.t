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
            "$label: structured error category");
        like("$err", qr/\Q$fragment\E/, "$label: error identifies stage");
    }
}

subtest 'numeric array indices within computed selector' => sub {
    is_deeply(results('{"keys":["a","b"],"obj":{"a":1,"b":2}}',
        '.obj[.keys[0]]'), [1], 'first element supplies object key');
    is_deeply(results('{"keys":["a","b"],"obj":{"a":1,"b":2}}',
        '.obj[.keys[1]]'), [2], 'second element supplies object key');
    is_deeply(results('{"keys":["a","b"],"obj":{"a":1,"b":2}}',
        '.obj[.keys[-1]]'), [2], 'negative index reads from end');
    is_deeply(results('{"keys":["a","b"],"obj":{"a":1,"b":2}}',
        '.obj[.keys[ 0 ]]'), [1], 'whitespace around numeric index');
    is_deeply(results('{"cfg":{"names":["a","b"]},"obj":{"a":1,"b":2}}',
        '.obj[.cfg["names"][-1]]'), [2], 'bracket-quoted prefix');
    is_deeply(results('{"cfg":{"names":[["a"]]},"obj":{"a":7}}',
        '.obj[.cfg.names[0][0]]'), [7], 'two successive numeric stages');
    is_deeply(results('{"keys":[0,2],"obj":[5,6,7]}',
        '.obj[.keys[1]]'), [7], 'numeric selector indexes array target');
    is_deeply(results('[1,4,5]', '.[.[0]]'),
        [4], 'root array can supply its own numeric selector');
    is_deeply(results('{"keys":["a"],"obj":{"a":false}}',
        '.obj[.keys[0]]'), [JSON::PP::false], 'false output remains a value');
    is_deeply(results('{"keys":["a"],"obj":{"a":null}}',
        '.obj[.keys[0]]'), [undef], 'explicit null output remains a value');
    is_deeply(results('{"keys":[0.5],"obj":[5,6]}',
        '.obj[.keys[0]]'), [5], 'numeric fractional selector remains numeric');
};

subtest 'null, out of bounds and optional outer lookups' => sub {
    runtime_error('{"keys":[],"obj":{"a":1}}', '.obj[.keys[0]]',
        'Cannot index object with null', 'empty selector array is a null key');
    runtime_error('{"keys":["a"],"obj":{"a":1}}', '.obj[.keys[5]]',
        'Cannot index object with null', 'out of range is null key');
    is_deeply(results('{"keys":[],"obj":{"a":1}}',
        '.obj[.keys[0]]?'), [], 'optional computed lookup skips null key');
    is_deeply(results('{"keys":null,"obj":{"a":1}}',
        '.obj[.keys[0]]?'), [], 'numeric indexing null yields null key');
    is_deeply(results('{"keys":[],"items":[]}',
        '.items[][.keys[0]]'), [], 'empty iterator with null key no error');
    is_deeply(results('{"keys":["a"],"obj":{}}',
        '.obj[.keys[0]]?'), [undef], 'missing selected field emits null');
    is_deeply(results('{"keys":[0],"obj":null}',
        '.obj[.keys[0]]'), [undef], 'numeric lookup into null emits null');
    is_deeply(results('{"keys":["a"],"obj":null}',
        '.obj[.keys[0]]'), [undef], 'string lookup into null emits null');
};

subtest 'selector expression errors do not become optional' => sub {
    runtime_error('{"keys":3,"obj":{"a":1}}',
        '.obj[.keys[0]]', 'Cannot index number with number',
        'scalar input to numeric selector');
    runtime_error('{"keys":{},"obj":{"a":1}}',
        '.obj[.keys[0]]', 'Cannot index object with number',
        'object input to numeric selector');
    runtime_error('{"keys":true,"obj":{"a":1}}',
        '.obj[.keys[0]]?', 'Cannot index boolean with number',
        'optional outer index does not hide boolean selector error');
    runtime_error('{"keys":3,"items":[]}',
        '.items[][.keys[0]]?', 'Cannot index number with number',
        'invalid selector still evaluated for empty iterator');
    runtime_error('{"keys":{},"items":[]}',
        '.items[][.keys[0]]', 'Cannot index object with number',
        'empty iterator cannot hide malformed selector data');
    runtime_error('{"keys":["a"],"obj":{"a":3}}',
        '.obj[.keys[0]][]', 'Cannot iterate over number',
        'later strict iterator still errors');
    is_deeply(results('{"keys":["a"],"obj":{"a":3}}',
        '.obj[.keys[0]][]?'), [],
        'later optional iterator still drops scalar');
};

subtest 'composed paths and stream context' => sub {
    is_deeply(results('{"keys":["a"],"items":[{"a":1},{"a":2}]}',
        '.items[][.keys[0]]'), [1,2],
        'one selector from original filter shared across items');
    is_deeply(results('{"keys":["a"],"items":[{"a":1},3,{"a":2}]}',
        '.items[][.keys[0]]?'), [1,2],
        'optional computed lookup skips only malformed item');
    is_deeply(results('{"cfg":{"names":["a"]},"a.b":{"a":7}}',
        '.["a.b"][.cfg["names"][0]]'), [7],
        'quoted literal prefix');
    is_deeply(results('{"keys":["a"],"items":[{"a":7}]}',
        '.items[0][.keys[-1]]'), [7],
        'numeric literal prefix and selector numeric stage');
    is_deeply(results('{"keys":["a"],"obj":{"a":{"child":7}}}',
        '.obj[.keys[0]].child'), [7],
        'literal suffix field lookup');
    is_deeply(results('{"first":["a"],"second":["b"],"obj":{"a":{"b":7}}}',
        '.obj[.first[0]][.second[0]]'), [7],
        'repeated computed selectors read original input');
    is_deeply(results('{"items":[{"keys":["a"],"obj":{"a":1}},{"keys":["b"],"obj":{"b":2}}]}',
        '.items[] | .obj[.keys[0]]'), [1,2],
        'each pipeline stage reestablishes selector input');
    is_deeply(results('{"keys":["a"],"obj":{"a":7}}',
        '0, .obj[.keys[0]]'), [0,7],
        'computed selector after comma alternative');
};

subtest 'parser shape and scope guardrails' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.keys[0]]'),
        [['field','obj'], ['computed_context','.keys[0]']],
        'numeric selector recognized without changing outer steps');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.[.[0]]'),
        [['computed_root','.[0]']],
        'root numeric selector recognized');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg["names"][-1]]?[]'),
        [['field','obj'],['computed_context','.cfg["names"][-1]',1],
         ['iterator',0]],
        'quoted-prefix index plus optional computed lookup');
    is_deeply(JQ::Lite::Util::_parse_v3_computed_selector_fields(
        '.cfg["names"][0]'),
        ['cfg','names',['index',0]],
        'numeric index has an explicit kind distinct from string field');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg["selected"]]'),
        [['field','obj'],['computed_context','.cfg["selected"]']],
        'previous bracket-quoted selector unchanged');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg."selected"]'),
        [['field','obj'],['computed_context','.cfg."selected"']],
        'previous dot-quoted selector unchanged');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.keys[]]')), 'iterator selector remains unsupported');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.keys[1 + 2]]')), 'computed arithmetic remains unsupported');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.keys[0:2]]')), 'slice selector remains unsupported');
    is_deeply(results('{"key":"a","obj":{"a":7}}',
        '.obj[.key]'), [7], 'previous strict computed selector unchanged');
    is_deeply(results('{"key":"a","obj":{"a":7}}',
        '.obj[.key]?'), [7], 'previous optional computed selector unchanged');
};

done_testing;
