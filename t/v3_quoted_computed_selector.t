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
        like("$err", qr/\Q$fragment\E, "$label: correct error boundary");
    }
}

subtest 'quoted selectors read the original filter input' => sub {
    is_deeply(results('{"key":"a","a":7}', '.[."key"]'),
        [7], 'quoted computed selector at root');
    is_deeply(results('{"key":"a","obj":{"key":"b","a":7,"b":8}}',
        '.obj[."key"]'), [7], 'quoted selector reads outer key');
    is_deeply(results('{"cfg":{"selected":"b"},"obj":{"b":8}}',
        '.obj[.cfg."selected"]'), [8], 'mixed selector segments');
    is_deeply(results('{"cfg":{"a.b":"v"},"obj":{"v":4}}',
        '.obj[.cfg."a.b"]'), [4], 'period is one quoted field name');
    is_deeply(results('{"cfg":{"full name":"v"},"obj":{"v":4}}',
        '.obj[.cfg."full name"]'), [4], 'space in quoted field name');
    is_deeply(results('{"cfg":{"":"v"},"obj":{"v":4}}',
        '.obj[.cfg.""]'), [4], 'empty quoted field name');
    is_deeply(results('{"cfg":{"name\"q":"v"},"obj":{"v":4}}',
        '.obj[.cfg."name\"q"]'), [4], 'escaped quote in name');
    is_deeply(results('{"cfg":{"a\\b":"v"},"obj":{"v":4}}',
        '.obj[.cfg."a\\b"]'), [4], 'escaped backslash in name');
    is_deeply(results('{"cfg":{"selected":"v"},"obj":{"v":4}}',
        '.obj[.cfg."sel\u0065cted"]'), [4], 'Unicode escape in name');
    is_deeply(results('{"sel":{"name":"v"},"obj":{"v":4}}',
        '.obj[."sel"."name"]'), [4], 'two dot-quoted segments');
    is_deeply(results('{"cfg":{"selected":"v"},"obj":{"v":4}}',
        '.obj[.cfg."selected"]?'), [4], 'optional quoted computed key');
    is_deeply(results('{"cfg":{"selected":null},"obj":{"v":4}}',
        '.obj[.cfg."selected"]?'), [], 'optional bad selected type');
};

subtest 'quoted selectors compose with literal paths and streams' => sub {
    is_deeply(results('{"cfg":{"a.b":"v"},"a b":{"v":5}}',
        '.["a b"][.cfg."a.b"]'), [5], 'quoted literal prefix');
    is_deeply(results('{"cfg":{"a.b":"v"},"items":[{"v":1},{"v":2}]}',
        '.items[][.cfg."a.b"]'), [1,2], 'selector shared by all items');
    is_deeply(results('{"cfg":{"a.b":"v"},"items":[{"v":1},3,{"v":2}]}',
        '.items[][.cfg."a.b"]?'), [1,2],
        'optional selector drops only bad targets');
    is_deeply(results('{"cfg":{"a.b":"v"},"items":[]}',
        '.items[][.cfg."a.b"]'), [], 'empty iterator yields nothing');
    is_deeply(results('{"cfg":{"a.b":null},"items":[]}',
        '.items[][.cfg."a.b"]'), [], 'null selector with empty iterator');
    is_deeply(results('{"cfg":{"a.b":"v"},"obj":{"v":[1,2]}}',
        '.obj[.cfg."a.b"][]'), [1,2],
        'selected array feeds strict suffix');
    is_deeply(results('{"cfg":{"a.b":"v"},"obj":{"v":3}}',
        '.obj[.cfg."a.b"][]?'), [],
        'later optional iterator drops number');
    is_deeply(results('{"first":{"a.b":"x"},"second":"y","obj":{"x":{"y":10}}}',
        '.obj[.first."a.b"][.second]'), [10],
        'two computed selectors read original root');
    is_deeply(results('{"first":{"a.b":"x"},"second":null,"obj":{"x":{"y":10}}}',
        '.obj[.first."a.b"][.second]?'), [],
        'later optional selector drops invalid key');
    is_deeply(results('{"items":[{"key":"a","obj":{"a":3}},{"key":"b","obj":{"b":4}}]}',
        '.items[] | .obj[."key"]'), [3,4],
        'pipeline creates per-item original context');
    is_deeply(results('{"key":"a","obj":{"a":7}}',
        '0, .obj[."key"]'), [0,7],
        'comma before quoted selector');
    is_deeply(results('{"key":"a","obj":{"a":7}}',
        '.obj[."key"], 0'), [7,0],
        'comma after quoted selector');
    is_deeply(results('{"cfg":{"a.b":"v"},"obj":{"v":{"child":7}}}',
        '.obj[.cfg."a.b"].child'), [7],
        'literal suffix after quoted selector');
    is_deeply(results('{"cfg":{"a.b":"v"},"obj":{"v":[{"child":7}]}}',
        '.obj[.cfg."a.b"][].child'), [7],
        'iterator after quoted selector');
    is_deeply(results('{"cfg":{"a.b":"v"},"items":[{"v":3}]}',
        '.items[0][.cfg."a.b"]'), [3],
        'numeric prefix before quoted selector');
};

subtest 'error boundaries and optional indexes' => sub {
    runtime_error('{"cfg":7,"obj":{"a":7}}',
        '.obj[.cfg."selected"]',
        'Cannot index number with string "selected"',
        'bad selector field traversal');
    runtime_error('{"cfg":7,"items":[]}',
        '.items[][.cfg."selected"]?',
        'Cannot index number with string "selected"',
        'invalid selector checked despite empty iterator and ?');
    runtime_error('{"cfg":{"a.b":"v"},"obj":{"v":3}}',
        '.obj[.cfg."a.b"][]',
        'Cannot iterate over number',
        'later strict iterator error');
    runtime_error('{"cfg":{"a.b":"v"},"obj":{"v":3}}',
        '.obj[.cfg."a.b"].child',
        'Cannot index number with string "child"',
        'later field lookup error');
    runtime_error('{"cfg":{"a.b":null},"obj":{"v":3}}',
        '.obj[.cfg."a.b"]',
        'Cannot index object with null',
        'strict quoted selector rejects null key');
    is_deeply(results('{"cfg":{"a.b":null},"obj":{"v":3}}',
        '.obj[.cfg."a.b"]?'), [],
        'optional quoted selector suppresses invalid key');
    is_deeply(results('{"cfg":{"a.b":"v"},"obj":{}}',
        '.obj[.cfg."a.b"]?'), [undef],
        'optional missing target field still emits null');
    is_deeply(results('{"cfg":{"a.b":"v"},"obj":{"v":false}}',
        '.obj[.cfg."a.b"]'), [JSON::PP::false],
        'false output retained');
};

subtest 'scoped parser and earlier computed forms' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg."a.b"]'),
        [['field','obj'], ['computed_context','.cfg."a.b"']],
        'quoted computed selector gets original context step');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.[."key"]?'),
        [['computed_root','."key"',1]],
        'quoted root computed selector preserves optional flag');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg."full name"]?[]'),
        [['field','obj'], ['computed_context','.cfg."full name"',1],
         ['iterator',0]],
        'optional quoted computed selector composes with iterator');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg.selected]'),
        [['field','obj'],['computed_context','.cfg.selected']],
        'existing unquoted computed selector shape unchanged');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg["selected"]]')),
        'nested bracket-quoted selector is outside scope');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg."selected" + 1]')),
        'arithmetic in a selector is outside scope');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg."\q"]')),
        'invalid JSON escape cannot enter scoped selector');
    is_deeply(results('{"key":"a","obj":{"a":7}}',
        '.obj[.key]'), [7], 'previous strict unquoted selector');
    is_deeply(results('{"key":"a","obj":{"a":7}}',
        '.obj[.key]?'), [7], 'previous optional unquoted selector');
    is_deeply(results('{"key":"a","a":7}',
        '.[.key]'), [7], 'previous computed-root selector');
};

done_testing;
