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
    my $err = $@;
    ok(!$ok, "$label: fails");
    if (!$ok) {
        isa_ok($err, 'JQ::Lite::Error::Evaluation',
            "$label: structured evaluation error");
        like("$err", qr/\Q$fragment\E/, "$label: strict stage error");
    }
}

subtest 'root strict bracket-quoted field' => sub {
    is_deeply(results('{"a.b":7}', '.["a.b"]'), [7],
        'literal dot key at root');
    is_deeply(results('{"full name":"Ada"}', '.["full name"]'),
        ['Ada'], 'spaces in a quoted field');
    is_deeply(results('{"":8}', '.[""]'), [8],
        'empty JSON key');
    is_deeply(results('{"]":9}', '.["]"]'), [9],
        'closing bracket in a quoted key');
    is_deeply(results('{"[0]":10}', '.["[0]"]'), [10],
        'numeric-looking bracket key is a string');
    is_deeply(results('{"a+b":11}', '.["a+b"]'), [11],
        'operator-like plus sign remains literal');
    is_deeply(results('{"a-b":12}', '.["a-b"]'), [12],
        'operator-like minus sign remains literal');
    is_deeply(results('{"a|=b":13}', '.["a|=b"]'), [13],
        'update-operator text is not an assignment');
    is_deeply(results('{"a,b":14}', '.["a,b"]'), [14],
        'comma inside JSON string does not branch');
    is_deeply(results('{"a\\"b":15}', '.["a\\"b"]'), [15],
        'JSON quote escape decoded');
    is_deeply(results('{"a\\\\b":16}', '.["a\\\\b"]'), [16],
        'JSON backslash escape decoded');
    is_deeply(results('{"a.b":17}', '.["a\\u002eb"]'), [17],
        'Unicode escape decoded to literal dot');
    is_deeply(results('{}', '.["a.b"]'), [undef],
        'missing strict quoted field is one null');
    is_deeply(results('null', '.["a.b"]'), [undef],
        'quoted field on JSON null yields null');
    is_deeply(results('{"a.b":false}', '.["a.b"]'),
        [JSON::PP::false], 'false value is preserved');
    runtime_error('7', '.["a.b"]',
        'Cannot index number with string "a.b"',
        'number root rejects a strict string field');
    runtime_error('true', '.["a.b"]',
        'Cannot index boolean with string "a.b"',
        'boolean root rejects a strict string field');
    runtime_error('"abc"', '.["a.b"]',
        'Cannot index string with string "a.b"',
        'string root rejects a strict string field');
    runtime_error('[]', '.["a.b"]',
        'Cannot index array with string "a.b"',
        'array root rejects a strict string field');
};

subtest 'nested and chained strict bracket-quoted fields' => sub {
    is_deeply(results('{"obj":{"a.b":{"name":"A"}}}',
        '.obj["a.b"].name'), ['A'],
        'quoted key in middle of strict path');
    is_deeply(results('{"obj":{"a.b":{"name":"A"}}}',
        '.obj["a.b"]["name"]'), ['A'],
        'two strict quoted stages');
    is_deeply(results('{"obj":{"a.b":{"full name":"Ada"}}}',
        '.obj["a.b"]["full name"]'), ['Ada'],
        'two special quoted names');
    is_deeply(results('{"outer":{"a.b":7}}',
        '.["outer"]["a.b"]'), [7],
        'root and nested bracket-quoted keys');
    is_deeply(results('{"obj":{"a.b":{"n":3}}}',
        '.obj["a.b"].n'), [3],
        'unquoted strict suffix');
    is_deeply(results('{"obj":{"a.b":null}}',
        '.obj["a.b"].name'), [undef],
        'null selected field continues as null');
    is_deeply(results('{"obj":{}}',
        '.obj["a.b"].name'), [undef],
        'missing inner key continues as null');
    is_deeply(results('{}', '.obj["a.b"].name'),
        [undef], 'missing parent continues as null');
    is_deeply(results('null', '.obj["a.b"].name'),
        [undef], 'null input continues as null');
    is_deeply(results('{"obj":{"a.b":[10,20]}}',
        '.obj["a.b"][1]'), [20],
        'strict numeric index after quoted name');
    is_deeply(results('{"obj":{"a.b":[10,20]}}',
        '.obj["a.b"][-1]'), [20],
        'strict negative index after quoted name');
    is_deeply(results('{"obj":{"a.b":[10,20]}}',
        '.obj["a.b"][9]'), [undef],
        'out of range numeric index remains null');
    runtime_error('{"obj":{"a.b":3}}',
        '.obj["a.b"].name',
        'Cannot index number with string "name"',
        'later strict field error not masked');
    runtime_error('{"obj":3}',
        '.obj["a.b"].name',
        'Cannot index number with string "a.b"',
        'strict quoted stage rejects numeric parent');
    runtime_error('7', '.obj["a.b"].name',
        'Cannot index number with string "obj"',
        'earlier strict field error remains');
    runtime_error('{"obj":{"a.b":{}}}',
        '.obj["a.b"][1]',
        'Cannot index object with number',
        'later strict numeric error not masked');
};

subtest 'quoted lookup with stream composition' => sub {
    is_deeply(results('{"a.b":3}',
        '.["a.b"] | . + 1'), [4],
        'quoted result feeds pipeline');
    is_deeply(results('{"a.b":3}',
        '.["a.b"], .["a.b"]'), [3,3],
        'quoted literal paths in comma alternatives');
    is_deeply(results('{"a.b":3}',
        '0, .["a.b"], 9'), [0,3,9],
        'quoted branch preserves input order');
    is_deeply(results('{"a.b":null}',
        '0, .["a.b"], 9'), [0,undef,9],
        'quoted null is a value, not an empty branch');
    is_deeply(results('{"a.b":[1,2]}',
        '.["a.b"][]'), [1,2],
        'existing quoted iterator path unchanged');
    is_deeply(results('{"a.b":7}',
        '.["a.b"]?'), [7],
        'previous optional quoted field unchanged');
    is_deeply(results('7', '.["a.b"]?'), [],
        'optional quoted field still skips wrong type');
};

subtest 'parser boundaries and legacy controls' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.["a.b"]'), [['field','a.b']],
        'standalone rooted strict bracket field accepted');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj["a.b"]'), [['field','obj'],['field','a.b']],
        'strict quoted suffix accepted');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj["a.b"].name'),
        [['field','obj'],['field','a.b'],['field','name']],
        'composite strict path accepted');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.["a.b"][0]'),
        [['field','a.b'],['index',0]],
        'strict numeric suffix shape preserved');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '["a.b"]')), 'bare JSON array constructor is not a path');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.name')), 'bare unquoted strict field stays legacy');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '."a.b"')), 'standalone dot-quoted strict field stays legacy');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj.name')), 'strict unquoted chain stays legacy');
    is_deeply(results('{"a.b":7}', '["a.b"]'), [['a.b']],
        'bare bracket expression remains an array constructor');
    is_deeply(results('{"a b":2}', '."a b"'), [2],
        'old dot-quoted field access remains unchanged');
    is_deeply(results('{"obj":{"name":"A"}}',
        '.obj.name'), ['A'],
        'old unquoted strict field path unchanged');
};

done_testing;
