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

subtest 'bracket-quoted selector looks up field in original input' => sub {
    is_deeply(results('{"key":"a","a":7}', '.[.["key"]]'),
        [7], 'computed root with bracket-quoted field');
    is_deeply(results('{"key":"a","obj":{"key":"b","a":7,"b":8}}',
        '.obj[.["key"]]'), [7], 'outer key wins over nested key');
    is_deeply(results('{"cfg":{"selected":"b"},"obj":{"b":8}}',
        '.obj[.cfg["selected"]]'), [8], 'bracket-quoted child');
    is_deeply(results('{"cfg":{"selected":"b"},"obj":{"b":8}}',
        '.obj[.cfg.["selected"]]'), [8], 'dot before bracket is valid');
    is_deeply(results('{"cfg":{"selected":"b"},"obj":{"b":8}}',
        '.obj[.["cfg"]["selected"]]'), [8],
        'multiple adjacent bracket-quoted stages');
    is_deeply(results('{"cfg":{"a.b":"v"},"obj":{"v":4}}',
        '.obj[.cfg["a.b"]]'), [4], 'embedded dot stays in key');
    is_deeply(results('{"cfg":{"full name":"v"},"obj":{"v":4}}',
        '.obj[.cfg["full name"]]'), [4], 'space stays in key');
    is_deeply(results('{"cfg":{"":"v"},"obj":{"v":4}}',
        '.obj[.cfg[""]]'), [4], 'empty field name');
    is_deeply(results('{"cfg":{"x]y":"v"},"obj":{"v":4}}',
        '.obj[.cfg["x]y"]]'), [4],
        'right bracket inside quoted key does not close selector');
    is_deeply(results('{"cfg":{"[x]":"v"},"obj":{"v":4}}',
        '.obj[.cfg["[x]"]]'), [4], 'brackets inside literal key');
    is_deeply(results('{"cfg":{"a\"b":"v"},"obj":{"v":4}}',
        '.obj[.cfg["a\"b"]]'), [4], 'escaped quote in key');
    is_deeply(results('{"cfg":{"name":"v"},"obj":{"v":4}}',
        '.obj[.cfg["n\u0061me"]]'), [4], 'Unicode escape in key');
    is_deeply(results('{"cfg":{"selected":"v"},"obj":{"v":4}}',
        '.obj[.cfg["selected"]]'), [4],
        'numeric-looking keys not coerced');
};

subtest 'composition and optional computed indexing' => sub {
    is_deeply(results('{"cfg":{"selected":"a"},"items":[{"a":1},{"a":2}]}',
        '.items[][.cfg["selected"]]'), [1,2],
        'same original selector used across item stream');
    is_deeply(results('{"cfg":{"selected":"a"},"items":[{"a":1},3,{"a":2}]}',
        '.items[][.cfg["selected"]]?'), [1,2],
        'optional lookup skips invalid intermediate target');
    is_deeply(results('{"key":null,"a":7}', '.[.["key"]]?'),
        [], 'bad root selector key is optional');
    is_deeply(results('{"cfg":{"selected":null},"obj":{"a":7}}',
        '.obj[.cfg["selected"]]?'), [],
        'bad nested selector key is optional');
    is_deeply(results('{"cfg":{"selected":"a"},"obj":{}}',
        '.obj[.cfg["selected"]]?'), [undef],
        'valid key missing from object emits JSON null');
    is_deeply(results('{"cfg":{"selected":"a"},"obj":{"a":null}}',
        '.obj[.cfg["selected"]]'), [undef],
        'explicit selected null preserved as a result');
    is_deeply(results('{"cfg":{"selected":"a"},"obj":{"a":false}}',
        '.obj[.cfg["selected"]]'), [JSON::PP::false],
        'false selected value preserved');
    is_deeply(results('{"cfg":{"selected":"a"},"obj":{"a":[1,2]}}',
        '.obj[.cfg["selected"]][]'), [1,2],
        'computed bracket selector feeds strict iterator');
    is_deeply(results('{"cfg":{"selected":"a"},"obj":{"a":3}}',
        '.obj[.cfg["selected"]][]?'), [],
        'optional trailing iterator skips selected scalar');
    is_deeply(results('{"cfg":{"selected":"a"},"obj":{"a":{"child":3}}}',
        '.obj[.cfg["selected"]].child'), [3],
        'literal field suffix');
    is_deeply(results('{"cfg":{"selected":"a"},"items":[{"a":9}]}',
        '.items[0][.cfg["selected"]]'), [9],
        'numeric index prefix');
    is_deeply(results('{"cfg":{"selected":"a"},"a.b":{"a":9}}',
        '.["a.b"][.cfg["selected"]]'), [9],
        'JSON-quoted literal prefix');
    is_deeply(results('{"first":{"a.b":"x"},"second":"y","obj":{"x":{"y":10}}}',
        '.obj[.first["a.b"]][.second]'), [10],
        'separate computed selector stages');
    is_deeply(results('{"items":[{"key":"a","obj":{"a":1}},{"key":"b","obj":{"b":2}}]}',
        '.items[] | .obj[.["key"]]'), [1,2],
        'pipeline resets computed-selector context');
    is_deeply(results('{"key":"a","obj":{"a":7}}',
        '0, .obj[.["key"]]'), [0,7],
        'computed bracket syntax in comma alternative');
    is_deeply(results('{"cfg":{"selected":"a"},"items":[]}',
        '.items[][.cfg["selected"]]'), [],
        'empty iterator yields no results');
};

subtest 'selector expression errors and strict suffix boundaries' => sub {
    runtime_error('{"cfg":7,"obj":{"a":1}}',
        '.obj[.cfg["selected"]]',
        'Cannot index number with string "selected"',
        'invalid selector field');
    runtime_error('{"cfg":7,"items":[]}',
        '.items[][.cfg["selected"]]?',
        'Cannot index number with string "selected"',
        'selector errors persist with empty iterator and optional index');
    runtime_error('{"cfg":{"selected":null},"obj":{"a":1}}',
        '.obj[.cfg["selected"]]',
        'Cannot index object with null',
        'strict computed index rejects null key');
    runtime_error('{"cfg":{"selected":"a"},"obj":{"a":3}}',
        '.obj[.cfg["selected"]][]',
        'Cannot iterate over number',
        'later strict iterator error');
    runtime_error('{"cfg":{"selected":"a"},"obj":{"a":3}}',
        '.obj[.cfg["selected"]].child',
        'Cannot index number with string "child"',
        'later literal field error');
};

subtest 'restricted parser and strict regression checks' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.[.["key"]]'), [['computed_root','.["key"]']],
        'root computed selector has original step shape');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg["selected"]]'),
        [['field','obj'],['computed_context','.cfg["selected"]']],
        'computed intermediate key with bracket-quoted segment');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg["a.b"]]?[]'),
        [['field','obj'],['computed_context','.cfg["a.b"]',1],
         ['iterator',0]],
        'optional computed step composes with strict iterator');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg.selected]'),
        [['field','obj'],['computed_context','.cfg.selected']],
        'existing dotted selector step shape unchanged');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg."selected"]'),
        [['field','obj'],['computed_context','.cfg."selected"']],
        'existing dot-quoted selector step shape unchanged');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg[0]]'),
        [['field','obj'],['computed_context','.cfg[0]']],
        'numeric selector stage is now recognized');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg[]]')), 'iterator inside selector is not audited');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg["selected"] + 1]')), 'arithmetic selector not audited');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg["\q"]]')), 'invalid JSON escape rejected');
    is_deeply(results('{"key":"a","obj":{"a":7}}',
        '.obj[.key]'), [7], 'strict old computed selector still works');
    is_deeply(results('{"key":"a","obj":{"a":7}}',
        '.obj[.key]?'), [7], 'optional old computed selector still works');
    is_deeply(results('{"key":"a","obj":{"a":7}}',
        '.obj[."key"]'), [7], 'dot-quoted computed selector still works');
};

done_testing;
