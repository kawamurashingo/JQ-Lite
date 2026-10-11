use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Error ();
use JQ::Lite::Util ();
use JQ::Lite::Parser ();
use JQ::Lite::Filters ();

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
        like("$err", qr/\Q$fragment\E/, "$label: failing strict stage");
    }
}

subtest 'strict root dot-quoted fields' => sub {
    is_deeply(results('{"a.b":7}', '."a.b"'), [7],
        'dot in name is literal');
    is_deeply(results('{"full name":"Ada"}', '."full name"'), ['Ada'],
        'space in root name');
    is_deeply(results('{"":8}', '.""'), [8],
        'empty quoted field name');
    is_deeply(results('{"]":9}', '."]"'), [9],
        'bracket-shaped character stays a string key');
    is_deeply(results('{"[0]":10}', '."[0]"'), [10],
        'numeric bracket text stays a string key');
    is_deeply(results('{"a+b":11}', '."a+b"'), [11],
        'plus sign not arithmetic');
    is_deeply(results('{"a-b":12}', '."a-b"'), [12],
        'minus sign not arithmetic');
    is_deeply(results('{"a/b":13}', '."a/b"'), [13],
        'slash sign not arithmetic');
    is_deeply(results('{"a|=b":14}', '."a|=b"'), [14],
        'update assignment marker not an update');
    is_deeply(results('{"a,b":15}', '."a,b"'), [15],
        'comma inside key not a sequence');
    is_deeply(results('{"a\\"b":16}', '."a\\"b"'), [16],
        'escaped quote is decoded');
    is_deeply(results('{"a\\\\b":17}', '."a\\\\b"'), [17],
        'escaped backslash is decoded');
    is_deeply(results('{"a.b":18}', '."a\\u002eb"'), [18],
        'Unicode escape is decoded to dot');
    is_deeply(results('{}', '."a.b"'), [undef],
        'missing root key emits one null');
    is_deeply(results('null', '."a.b"'), [undef],
        'null input emits one null');
    is_deeply(results('{"a.b":false}', '."a.b"'),
        [JSON::PP::false], 'false member remains false');
    runtime_error('7', '."a.b"',
        'Cannot index number with string "a.b"',
        'numeric input rejected by strict named stage');
    runtime_error('true', '."a.b"',
        'Cannot index boolean with string "a.b"',
        'boolean input rejected');
    runtime_error('"abc"', '."a.b"',
        'Cannot index string with string "a.b"',
        'string input rejected');
    runtime_error('[]', '."a.b"',
        'Cannot index array with string "a.b"',
        'array input rejected');
};

subtest 'strict dot-quoted fields in composite paths' => sub {
    is_deeply(results('{"obj":{"a.b":{"name":"A"}}}',
        '.obj."a.b".name'), ['A'],
        'special quoted middle field');
    is_deeply(results('{"obj":{"a.b":{"full name":"Ada"}}}',
        '.obj."a.b"."full name"'), ['Ada'],
        'two consecutive strict dot-quoted fields');
    is_deeply(results('{"outer":{"a.b":7}}',
        '."outer"."a.b"'), [7],
        'strict quoted root and quoted suffix');
    is_deeply(results('{"a.b":{"name":"A"}}',
        '."a.b".name'), ['A'],
        'strict unquoted suffix');
    is_deeply(results('{"obj":{"a.b":[10,20]}}',
        '.obj."a.b"[1]'), [20],
        'strict numeric index after dot-quoted key');
    is_deeply(results('{"obj":{"a.b":[10,20]}}',
        '.obj."a.b"[-1]'), [20],
        'negative index after dot-quoted key');
    is_deeply(results('{"obj":{"a.b":null}}',
        '.obj."a.b".name'), [undef],
        'null through subsequent strict field');
    is_deeply(results('{"obj":{}}', '.obj."a.b".name'),
        [undef], 'missing field through strict suffix');
    is_deeply(results('{}', '.obj."a.b".name'),
        [undef], 'missing strict prefix yields null');
    runtime_error('{"obj":7', '.obj."a.b".name',
        'Cannot index number with string "a.b"',
        'bad quoted target fails');
    runtime_error('7', '.obj."a.b".name',
        'Cannot index number with string "obj"',
        'strict earlier unquoted field still errors');
    runtime_error('{"obj":{"a.b":7}}', '.obj."a.b".name',
        'Cannot index number with string "name"',
        'strict later unquoted field still errors');
    is_deeply(results('{"obj":{"a.b":7}}', '.obj."a.b".name?'),
        [], 'later optional field skips scalar target');
    is_deeply(results('{"obj":{"a.b":7}}',
        '.obj."a.b", .obj["a.b"]'), [7,7],
        'dot and bracket quoted alternatives preserve order');
    is_deeply(results('{"obj":{"a.b":7}}',
        '.obj."a.b" | . + 1'), [8],
        'piped result from strict dot-quoted field');
};

subtest 'bare string literal must not become field access' => sub {
    is_deeply(results('{"a.b":7}', '"a.b"'), ['a.b'],
        'bare JSON quoted text remains a literal');
    is_deeply(results('7', '"a.b"'), ['a.b'],
        'string literal independent of input type');
    is_deeply(results('{"a":7}', '"a"'), ['a'],
        'bare short string literal is not a field lookup');
    is_deeply(results('{"a.b":7}', '["a.b"]'), [['a.b']],
        'bare bracket array constructor stays an array');
    is_deeply(results('{"a.b":7}', '."a.b"'), [7],
        'adding root dot changes literal to lookup');
    is_deeply(results('{"a.b":7}', '.["a.b"]'), [7],
        'bracket-quoted field still works');
};

subtest 'parser and dispatch boundaries' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '."a.b"'), [['field','a.b']],
        'rooted strict dot-quoted parser recognition');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '"a.b"')), 'unrooted JSON literal is not a scoped path');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj."a.b"'), [['field','obj'],['field','a.b']],
        'strict quoted suffix in full path');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj."a.b".name'),
        [['field','obj'],['field','a.b'],['field','name']],
        'strict suffix after dot-quoted step');
    is_deeply([JQ::Lite::Parser::parse_query('."a.b"')],
        ['."a.b"'], 'parser keeps leading dot for strict quoted root');
    is_deeply([JQ::Lite::Parser::parse_query('"a.b"')],
        ['"a.b"'], 'bare quoted string stays literal');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj["a.b"]'),
        [['field','obj'],['field','a.b']],
        'prior strict bracket-quoted parsing unchanged');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj.name')), 'strict unquoted path remains outside scope');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[1]')), 'strict positive path remains outside scope');
    my @unused;
    ok(!JQ::Lite::Filters::apply($jq, '."a.b"',
        [{'a.b' => 7}], \@unused),
        'strict root dot-quoted field bypasses legacy filter shortcuts');
    is_deeply(results('{"a b":2}', '."a b"'), [2],
        'previous dot-quoted field access unchanged');
    is_deeply(results('{"items":[{"a.b":7}]}',
        '.items[]."a.b"'), [7],
        'previous quoted iterator path unchanged');
};

done_testing;
