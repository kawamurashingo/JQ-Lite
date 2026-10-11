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
        like("$err", qr/\Q$fragment\E/, "$label: failing stage");
    }
}

subtest 'standalone unquoted optional field' => sub {
    is_deeply(results('{"name":"A"}', '.name?'), ['A'],
        'existing object field succeeds');
    is_deeply(results('{}', '.name?'), [undef],
        'missing object field yields one null');
    is_deeply(results('{"name":null}', '.name?'), [undef],
        'explicit null field retained');
    is_deeply(results('{"name":false}', '.name?'),
        [JSON::PP::false], 'false field retained');
    is_deeply(results('null', '.name?'), [undef],
        'null root yields one null');
    is_deeply(results('7', '.name?'), [],
        'number root skips invalid field lookup');
    is_deeply(results('true', '.name?'), [],
        'boolean root skips invalid field lookup');
    is_deeply(results('"text"', '.name?'), [],
        'string root skips invalid field lookup');
    is_deeply(results('[1,2]', '.name?'), [],
        'array root skips invalid field lookup');
    is_deeply(results('{"name":5}', '.name? | . + 1'), [6],
        'pipeline consumes optional field value');
    is_deeply(results('7', '.name? | . + 1'), [],
        'empty selector stream stays empty under pipeline');
};

subtest 'standalone JSON-quoted optional field' => sub {
    is_deeply(results('{"a.b":7}', '.["a.b"]?'), [7],
        'bracket-quoted key with literal period');
    is_deeply(results('{"a.b":7}', '."a.b"?'), [7],
        'dot-quoted key with literal period');
    is_deeply(results('{"":7}', '.[""]?'), [7],
        'empty JSON-quoted field');
    is_deeply(results('{"]":7}', '.["]"]?'), [7],
        'closing bracket within JSON string');
    is_deeply(results('{"a\\"b":7}', '.["a\\"b"]?'), [7],
        'escaped quote in field name');
    is_deeply(results('{"a\\u002eb":7}', '.["a\\u002eb"]?'), [7],
        'Unicode escape in JSON field name');
    is_deeply(results('{}', '.["a.b"]?'), [undef],
        'missing quoted field yields one null');
    is_deeply(results('null', '.["a.b"]?'), [undef],
        'quoted field on null yields one null');
    is_deeply(results('3', '.["a.b"]?'), [],
        'number root skipped by bracket-quoted optional field');
    is_deeply(results('[]', '."a.b"?'), [],
        'array root skipped by dot-quoted optional field');
    is_deeply(results('{"cfg":{"x.y":4}}', '.cfg["x.y"]?'), [4],
        'nested bracket-quoted optional field');
    is_deeply(results('{"cfg":3}', '.cfg["x.y"]?'), [],
        'nested quoted optional field skips scalar parent');
};

subtest 'standalone optional and strict chains' => sub {
    is_deeply(results('{"cfg":{"name":"A"}}',
        '.cfg?.name'), ['A'], 'optional parent then strict field');
    is_deeply(results('{"cfg":null}',
        '.cfg?.name'), [undef], 'null through strict child field');
    is_deeply(results('{}',
        '.cfg?.name'), [undef], 'missing parent yields null');
    is_deeply(results('5',
        '.cfg?.name'), [], 'optional parent skips malformed root');
    runtime_error('{"cfg":3}', '.cfg?.name',
        'Cannot index number with string "name"',
        'strict child failure after optional parent');
    runtime_error('5', '.cfg.name?',
        'Cannot index number with string "cfg"',
        'strict parent error before optional child');
    is_deeply(results('{"cfg":3}', '.cfg.name?'), [],
        'optional child suppresses invalid field target');
    is_deeply(results('{"cfg":3}', '.cfg?.name?'), [],
        'both optional fields independently suppress own error');
    is_deeply(results('{"cfg":{"name":3}}',
        '.cfg?.name?'), [3], 'two successful optional field steps');
    is_deeply(results('{"cfg":{"name":3}}',
        '.cfg?.name?.child?'), [],
        'third optional field skips selected number');
    runtime_error('{"cfg":{"name":3}}', '.cfg?.name?.child',
        'Cannot index number with string "child"',
        'trailing strict field still raises error');
    is_deeply(results('{"cfg":{}}',
        '.cfg?.name?.child'), [undef],
        'missing field yields null through later strict field');
    is_deeply(results('{"cfg":3}',
        '.cfg?["name"]?'), [],
        'bracket-quoted optional child skips number');
    runtime_error('{"cfg":3}', '.cfg?["name"]',
        'Cannot index number with string "name"',
        'bracket-quoted strict child still errors');
};

subtest 'interaction with literal indices and stream control' => sub {
    is_deeply(results('{"a":[10,20]}', '.a?[1]'), [20],
        'strict numeric index after optional named field');
    runtime_error('{"a":3}', '.a?[0]',
        'Cannot index number with number',
        'optional field does not suppress strict numeric lookup');
    is_deeply(results('{"a":3}', '.a?[0]?'), [],
        'later optional index independently skips invalid target');
    is_deeply(results('{"a":null}', '.a?[0]?'), [undef],
        'null through optional numeric index retains null');
    is_deeply(results('{"a":[{"x":2}]}',
        '.a?[0]?.x?'), [2],
        'optional field composes with numeric/field stages');
    is_deeply(results('{"a":[{"x":2}]}',
        '.a?[0]?.x? | . + 1'), [3],
        'pipeline preserves a successful optional branch');
    is_deeply(results('{"a":3}', '0, .a?, 9'), [0,3,9],
        'comma alternative with successful optional lookup');
    is_deeply(results('3', '0, .a?, 9'), [0,9],
        'comma alternative drops empty optional branch');
    is_deeply(results('null', '0, .a?, 9'), [0,undef,9],
        'comma alternative keeps explicit null output');
    is_deeply(results('{"items":[{"name":"A"},3]}',
        '.items[].name?'), ['A'],
        'prior optional field after iterator unchanged');
    is_deeply(results('{"keys":["a"],"obj":{"a":2}}',
        '.obj[.keys[0]?]'), [2],
        'prior optional selector numeric stage unchanged');
};

subtest 'parser boundaries and strict compatibility' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.name?'), [['field','name',1]],
        'root optional named field accepted');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        'name?'), [['field','name',1]],
        'normalized optional named field accepted');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.["a.b"]?'), [['field','a.b',1]],
        'root bracket-quoted optional accepted');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '."a.b"?'), [['field','a.b',1]],
        'root dot-quoted optional accepted');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.cfg?.name'), [['field','cfg',1],['field','name']],
        'optional prefix and strict suffix remain separate');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.cfg.name?'), [['field','cfg'],['field','name',1]],
        'strict prefix and optional suffix remain separate');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.name')), 'strict standalone field stays on legacy path');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.["a.b"]'), [['field','a.b']],
        'strict standalone bracket-quoted field uses scoped visitor');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.cfg.name')), 'strict field-only chain stays on legacy path');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.name + 1')), 'arithmetic expression is not parsed as a path');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.name | .')), 'pipeline expression is not parsed as one path');
    is_deeply(results('{"name":"A"}', '.name'), ['A'],
        'strict unquoted field unchanged');
    is_deeply(results('{"cfg":{"name":"A"}}', '.cfg.name'), ['A'],
        'strict nested field unchanged');
    is_deeply(results('{"a":[10,20]}', '.a[1]?'), [20],
        'previous standalone numeric optional unchanged');
    is_deeply([JQ::Lite::Parser::parse_query('.name?')],
        ['name?'], 'parser normalizes simple optional named field');
};

done_testing;
