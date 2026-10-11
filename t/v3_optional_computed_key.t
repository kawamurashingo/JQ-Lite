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
            "$label: structured runtime error");
        like("$err", qr/\Q$fragment\E/, "$label: correct error boundary");
    }
}

subtest 'optional computed-root indexing' => sub {
    is_deeply(results('{"key":"a","a":7}', '.[.key]?'),
        [7], 'valid root key');
    is_deeply(results('{"key":"a","a":null}', '.[.key]?'),
        [undef], 'explicit null remains one output');
    is_deeply(results('{"key":"missing"}', '.[.key]?'),
        [undef], 'missing target key yields null, not empty');
    for my $json (
        '{"key":null}', '{"key":true}', '{"key":0}',
        '{"key":["a"]}', '{"key":{"a":1}}'
    ) {
        is_deeply(results($json, '.[.key]?'), [],
            'invalid selected key is dropped at root');
    }
    runtime_error('1', '.[.key]?',
        'Cannot index number with string "key"',
        'selector evaluation still fails on scalar root');
};

subtest 'optional intermediate indexing and types' => sub {
    is_deeply(results('{"key":"a","obj":{"a":7}}',
        '.obj[.key]?'), [7], 'valid intermediate key');
    is_deeply(results('{"key":"a","obj":{"a":false}}',
        '.obj[.key]?'), [JSON::PP::false], 'false is a valid result');
    is_deeply(results('{"key":"a","obj":{}}',
        '.obj[.key]?'), [undef], 'missing target field is null');
    is_deeply(results('{"key":"a","obj":null}',
        '.obj[.key]?'), [undef], 'null target with valid key is null');
    is_deeply(results('{"key":0,"obj":[7,8]}',
        '.obj[.key]?'), [7], 'numeric array selector');
    is_deeply(results('{"key":-1,"obj":[7,8]}',
        '.obj[.key]?'), [8], 'negative array selector');
    is_deeply(results('{"key":"0","obj":[7,8]}',
        '.obj[.key]?'), [], 'string cannot index array');
    is_deeply(results('{"key":0,"obj":{"0":7}}',
        '.obj[.key]?'), [], 'number cannot index object');
    is_deeply(results('{"key":"a","obj":3}',
        '.obj[.key]?'), [], 'number target is skipped');
    is_deeply(results('{"key":"a","obj":true}',
        '.obj[.key]?'), [], 'boolean target is skipped');
    is_deeply(results('{"key":null,"obj":{"a":7}}',
        '.obj[.key]?'), [], 'null computed key is skipped');
    is_deeply(results('{"cfg":{"selected":"b"},"obj":{"b":8}}',
        '.obj[.cfg.selected]?'), [8], 'dotted selector uses root input');
    is_deeply(results('{"key":"a","a.b":{"a":5}}',
        '.["a.b"][.key]?'), [5], 'quoted literal path prefix');
    is_deeply(results('{"key":"a","items":[{"a":5}]}',
        '.items[0][.key]?'), [5], 'numeric path prefix');
};

subtest 'streams, suffixes, alternatives and pipelines' => sub {
    is_deeply(results('{"key":"a","items":[{"a":1},3,{"a":2}]}',
        '.items[][.key]?'), [1,2], 'skip invalid item, retain others');
    is_deeply(results('{"key":"a","items":[null,{"a":2}]}',
        '.items[][.key]?'), [undef,2], 'null item remains one output');
    is_deeply(results('{"key":null,"items":[]}',
        '.items[][.key]?'), [], 'empty iterator stays empty');
    is_deeply(results('{"key":"a","obj":{"a":[1,2]}}',
        '.obj[.key]?[]'), [1,2], 'later strict iterator succeeds');
    is_deeply(results('{"key":null,"obj":{"a":[1,2]}}',
        '.obj[.key]?[]'), [], 'later iterator sees no suppressed value');
    is_deeply(results('{"first":"a","second":null,"obj":{"a":{"b":7}}}',
        '.obj[.first][.second]?'), [], 'second optional selector');
    is_deeply(results('{"first":null,"second":"b","obj":{"a":{"b":7}}}',
        '.obj[.first]?[.second]'), [], 'first optional selector');
    is_deeply(results('{"items":[{"key":"a","obj":{"a":3}},{"key":null,"obj":{"a":1}}]}',
        '.items[] | .obj[.key]?'), [3], 'pipeline resets selector context');
    is_deeply(results('{"key":null,"obj":{"a":7}}',
        '1, .obj[.key]?, 2'), [1,2], 'suppressed comma alternative');
    runtime_error('{"key":"a","obj":{"a":7}}',
        '.obj[.key]?[]', 'Cannot iterate over number',
        'strict iterator remains strict after optional lookup');
    runtime_error('{"key":"a","obj":{"a":7}}',
        '.obj[.key]?.field', 'Cannot index number with string "field"',
        'later invalid field access remains strict');
};

subtest 'selector errors are not suppressed by optional indexing' => sub {
    runtime_error('{"cfg":7,"obj":{"a":1}}',
        '.obj[.cfg.selected]?',
        'Cannot index number with string "selected"',
        'bad selector path before ordinary lookup');
    runtime_error('{"cfg":7,"items":[]}',
        '.items[][.cfg.selected]?',
        'Cannot index number with string "selected"',
        'bad selector path even with empty iterator');
    runtime_error('{"cfg":7,"items":[3]}',
        '.items[][.cfg.selected]?',
        'Cannot index number with string "selected"',
        'bad selector path before invalid target');
};

subtest 'scoped parser and strict regression' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.[.key]?'), [['computed_root','.key',1]],
        'root optionality is a separate step flag');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[][.cfg.selected]?[]'),
        [['field','items'],['iterator',0],
         ['computed_context','.cfg.selected',1],['iterator',0]],
        'intermediate optionality follows iterator');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.key]'), [['field','obj'],['computed_context','.key']],
        'existing nonoptional parsed shape unchanged');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.key + 1]?')), 'arithmetic selector still outside scope');
    runtime_error('{"key":null,"obj":{"a":7}}',
        '.obj[.key]', 'Cannot index object with null',
        'strict computed lookup continues to fail');
    is_deeply(results('{"key":"a","obj":{"a":[1,2]}}',
        '.obj[.key][]?'), [1,2], 'previous optional iterator unchanged');
};

done_testing;
