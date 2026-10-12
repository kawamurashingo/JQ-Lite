use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Error ();
use JQ::Lite::Util ();
use JQ::Lite::Parser ();

my $jq = JQ::Lite->new;

sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

sub runtime_error {
    my ($json, $filter, $fragment, $label) = @_;
    my $ok = eval { $jq->run_query($json, $filter); 1 };
    my $error = $@;
    ok(!$ok, "$label: fails");
    if (!$ok) {
        isa_ok($error, 'JQ::Lite::Error::Evaluation',
            "$label: structured runtime error");
        like("$error", qr/\Q$fragment\E/,
            "$label: strict error identifies stage");
    }
}

subtest 'root quoted bracket after whitespace' => sub {
    is_deeply(results('{"a.b":3}', '. ["a.b"]'), [3],
        'space between dot and quoted bracket');
    is_deeply(results('{"a.b":3}', '. [ "a.b" ]'), [3],
        'space both outside and inside quoted bracket');
    is_deeply(results('{"a.b":3}', ".\t[\"a.b\"]"), [3],
        'tab after dot');
    is_deeply(results('{"full name":"Ada"}',
        '. [ "full name" ]'), ['Ada'], 'spaces in literal key');
    is_deeply(results('{"":8}', '. [""]'), [8],
        'empty JSON key');
    is_deeply(results('{"[0]":9}', '. [ "[0]" ]'), [9],
        'index-shaped text is still a field name');
    is_deeply(results('{"a+b":10}', '. [ "a+b" ]'), [10],
        'plus in field name is not arithmetic');
    is_deeply(results('{"a|=b":11}', '. [ "a|=b" ]'), [11],
        'update token inside quotes is not assignment');
    is_deeply(results('{"a,b":12}', '. [ "a,b" ]'), [12],
        'comma inside quotes is not a branch');
    is_deeply(results('{"a\\"b":13}', '. [ "a\\"b" ]'), [13],
        'escaped double quote decoded');
    is_deeply(results('{"a\\\\b":14}', '. [ "a\\\\b" ]'), [14],
        'escaped backslash decoded');
    is_deeply(results('{"a.b":15}', '. [ "a\\u002eb" ]'),
        [15], 'Unicode escape decoded');
    is_deeply(results('{}', '. ["a.b"]'), [undef],
        'missing root key produces one null');
    is_deeply(results('null', '. ["a.b"]'), [undef],
        'null root produces one null');
    is_deeply(results('{"a.b":false}', '. ["a.b"]'),
        [JSON::PP::false], 'false member preserved');
    runtime_error('7', '. ["a.b"]',
        'Cannot index number with string "a.b"',
        'strict quoted field rejects numeric root');
    runtime_error('true', '. ["a.b"]',
        'Cannot index boolean with string "a.b"',
        'strict quoted field rejects boolean root');
    runtime_error('[]', '. ["a.b"]',
        'Cannot index array with string "a.b"',
        'strict quoted field rejects array root');
};

subtest 'quoted bracket whitespace after intermediate stages' => sub {
    is_deeply(results('{"obj":{"a.b":5}}',
        '.obj ["a.b"]'), [5], 'quoted bracket after unquoted field');
    is_deeply(results('{"obj":{"a.b":5}}',
        '.obj [ "a.b" ]'), [5],
        'quoted bracket with spaces inside and before');
    is_deeply(results('{"obj":{"a.b":{"name":"A"}}}',
        '.obj [ "a.b" ].name'), ['A'],
        'later strict field stays ordered');
    is_deeply(results('{"outer":{"a.b":6}}',
        '. ["outer"] [ "a.b" ]'), [6],
        'two spaced bracket-quoted fields');
    is_deeply(results('{"obj":{"a.b":[3,4]}}',
        '.obj [ "a.b" ] [1]'), [4],
        'quoted field and spaced numeric bracket');
    is_deeply(results('{"obj":{"a.b":[3,4]}}',
        '.obj [ "a.b" ][ -1 ]'), [4],
        'quoted field and signed numeric bracket');
    is_deeply(results('{"obj":null}',
        '.obj [ "a.b" ]'), [undef],
        'null parent emits one null');
    is_deeply(results('{}', '.obj [ "a.b" ]'), [undef],
        'missing parent emits one null');
    is_deeply(results('{"obj":{}}',
        '.obj [ "a.b" ].name'), [undef],
        'missing intermediate key stays null through strict field');
    runtime_error('{"obj":7}', '.obj [ "a.b" ]',
        'Cannot index number with string "a.b"',
        'quoted field stage rejects numeric parent');
    runtime_error('7', '.obj [ "a.b" ]',
        'Cannot index number with string "obj"',
        'earlier strict field error not hidden');
    runtime_error('{"obj":{"a.b":7}}',
        '.obj [ "a.b" ].name',
        'Cannot index number with string "name"',
        'later strict field error not hidden');
    is_deeply(results('{"obj":{"a.b":5}}',
        '.obj [ "a.b" ] | . + 1'), [6],
        'pipeline receives quoted member');
    is_deeply(results('{"obj":{"a.b":5}}',
        '0, .obj [ "a.b" ], 9'), [0,5,9],
        'comma alternatives preserve order');
};

subtest 'optional quoted bracket gap remains stage-local' => sub {
    is_deeply(results('{"a.b":5}', '. [ "a.b" ]?'), [5],
        'valid optional quoted root with whitespace');
    is_deeply(results('{"obj":{"a.b":5}}',
        '.obj [ "a.b" ]?'), [5],
        'valid optional quoted nested field');
    is_deeply(results('{"obj":{}}',
        '.obj [ "a.b" ]?'), [undef],
        'optional missing key retains null');
    is_deeply(results('null',
        '. [ "a.b" ]?'), [undef],
        'optional quoted lookup on null retains null');
    is_deeply(results('7',
        '. [ "a.b" ]?'), [],
        'optional invalid root emits zero results');
    is_deeply(results('{"obj":7}',
        '.obj [ "a.b" ]?'), [],
        'optional invalid intermediate target emits zero');
    is_deeply(results('{"obj":{"a.b":7}}',
        '.obj [ "a.b" ]?.name?'), [],
        'later optional field drops numeric target separately');
    runtime_error('{"obj":{"a.b":7}}',
        '.obj [ "a.b" ]?.name',
        'Cannot index number with string "name"',
        'later strict field remains an error');
    runtime_error('7',
        '.obj [ "a.b" ]?',
        'Cannot index number with string "obj"',
        'earlier strict named field remains an error');
};

subtest 'syntax and existing regression boundaries' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '. ["a.b"]'), [['field','a.b']],
        'space after root dot parsed');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj [ "a.b" ]'), [['field','obj'],['field','a.b']],
        'spaced nested field path parsed');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj [ "a.b" ]?'),
        [['field','obj'],['field','a.b',1]],
        'optional quoted stage shape');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '. ["outer"] [ "a.b" ]'),
        [['field','outer'],['field','a.b']],
        'two spaced quoted stages parsed');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '[ "a.b" ]')),
        'bare array constructor never interpreted as field');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        'try ["catch me"]')),
        'try followed by array literal is not a rooted path');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        'obj ["a.b"]')),
        'unrooted whitespace-quoted stage cannot be a jq path');
    is_deeply([JQ::Lite::Parser::parse_query('.obj [ "a.b" ]')],
        ['.obj [ "a.b" ]'],
        'parser retains explicit dot for whitespace-quoted field path');
    is_deeply(results('null', 'try ["catch me"]'),
        [['catch me']], 'try array literal remains an array');
    is_deeply(results('null', 'try ["other"]'),
        [['other']], 'additional try array literal regression');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj [ 1:3 ]')),
        'slice bracket not reclassified as literal quoted field');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj [ .key ]')),
        'computed bracket with gap remains separate');
    is_deeply(results('{"a.b":5}', '[ "a.b" ]'),
        [['a.b']], 'bare quoted array constructor retained');
    is_deeply(results('{"a.b":5}', '.["a.b"]'), [5],
        'previous unspaced bracket-quoted access');
    is_deeply(results('{"items":[10,20]}', '.items [0]'),
        [10], 'previous numeric bracket gap unaffected');
    is_deeply(results('{"a.b":5}', '."a.b"'), [5],
        'previous strict dot-quoted access unaffected');
};

done_testing;
