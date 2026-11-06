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
        like("$err", qr/\Q$fragment\E/, "$label: error boundary");
    }
}

subtest 'successful optional field selectors' => sub {
    is_deeply(results('{"cfg":{"name":"a"},"obj":{"a":7}}',
        '.obj[.cfg.name?]'), [7], 'unquoted optional field');
    is_deeply(results('{"cfg":{"name":"a"},"obj":{"a":7}}',
        '.obj[.cfg."name"?]'), [7], 'dot-quoted optional field');
    is_deeply(results('{"cfg":{"name":"a"},"obj":{"a":7}}',
        '.obj[.cfg["name"]?]'), [7], 'bracket-quoted optional field');
    is_deeply(results('{"cfg":{"a.b":"a"},"obj":{"a":7}}',
        '.obj[.cfg["a.b"]?]'), [7], 'period in quoted field');
    is_deeply(results('{"cfg":{"]":"a"},"obj":{"a":7}}',
        '.obj[.cfg["]"]?]'), [7], 'closing bracket in quoted field');
    is_deeply(results('{"cfg":{"":"a"},"obj":{"a":7}}',
        '.obj[.cfg[""]?]'), [7], 'empty quoted field');
    is_deeply(results('{"cfg":{"name":"a"},"obj":{"a":7}}',
        '.obj[.cfg?.name]'), [7], 'optional prior field succeeds');
    is_deeply(results('{"cfg":{"name":"a"},"obj":{"a":7}}',
        '.obj[.cfg?.name?]'), [7], 'two optional field stages');
    is_deeply(results('{"cfg":{"name":["a"]},"obj":{"a":7}}',
        '.obj[.cfg["name"]?[0]?]'), [7],
        'optional quoted field and numeric selector');
    is_deeply(results('{"cfg":{"name":["a"]},"obj":{"a":7}}',
        '.obj[.cfg.name?[0]]'), [7],
        'optional named field with strict numeric selector');
    is_deeply(results('{"key":"a","a":7}',
        '.[.key?]'), [7], 'optional field computed root');
    is_deeply(results('{"cfg":{"name":"a"},"obj":{"a":false}}',
        '.obj[.cfg.name?]'), [JSON::PP::false],
        'false selected output retained');
    is_deeply(results('{"cfg":{"name":"a"},"obj":{"a":null}}',
        '.obj[.cfg.name?]'), [undef],
        'selected JSON null is one result');
};

subtest 'invalid optional field lookups skip, not emit null' => sub {
    is_deeply(results('{"cfg":3,"obj":{"a":7}}',
        '.obj[.cfg.name?]'), [], 'number cannot supply named field');
    is_deeply(results('{"cfg":true,"obj":{"a":7}}',
        '.obj[.cfg.name?]'), [], 'boolean is not an object');
    is_deeply(results('{"cfg":"abc","obj":{"a":7}}',
        '.obj[.cfg.name?]'), [], 'string is not an object');
    is_deeply(results('{"cfg":["a"],"obj":{"a":7}}',
        '.obj[.cfg.name?]'), [], 'array is not an object');
    is_deeply(results('{"cfg":3,"obj":{"a":7}}',
        '.obj[.cfg."name"?]'), [], 'dot-quoted optional type error');
    is_deeply(results('{"cfg":3,"obj":{"a":7}}',
        '.obj[.cfg["name"]?]'), [], 'bracket-quoted optional type error');
    is_deeply(results('{"cfg":3,"obj":{"a":7}}',
        '.obj[.cfg?.name?]'), [], 'last optional field suppresses error');
    is_deeply(results('{"cfg":3,"obj":{"a":7}}',
        '.obj[.cfg.name?]?'), [], 'outer optional cannot restore result');
    is_deeply(results('{"cfg":3,"obj":{"a":7}}',
        '.obj[.cfg.name?].child'), [], 'later strict stage is not evaluated');
    is_deeply(results('{"cfg":3,"items":[]}',
        '.items[][.cfg.name?]'), [], 'selector skips before empty iterator');
    is_deeply(results('{"cfg":3,"items":[{"a":1}]}',
        '.items[][.cfg.name?]'), [], 'selector skips before populated iterator');
    is_deeply(results('{"cfg":3,"obj":{"a":7}}',
        '0, .obj[.cfg.name?], 1'), [0,1],
        'comma branches preserve previous and next outputs');
    is_deeply(results('{"cfg":3,"obj":{"a":7}}',
        '.obj[.cfg["name"]?[0]]'), [],
        'empty optional field short-circuits strict numeric selector');
};

subtest 'missing and null are values, not empty streams' => sub {
    runtime_error('{"cfg":{},"obj":{"a":7}}',
        '.obj[.cfg.name?]', 'Cannot index object with null',
        'missing object field gives a null selector key');
    runtime_error('{"cfg":null,"obj":{"a":7}}',
        '.obj[.cfg.name?]', 'Cannot index object with null',
        'field read through null gives a null key');
    is_deeply(results('{"cfg":{},"obj":{"a":7}}',
        '.obj[.cfg.name?]?'), [],
        'outer optional lookup suppresses missing null key');
    is_deeply(results('{"cfg":null,"obj":{"a":7}}',
        '.obj[.cfg["name"]?]?'), [],
        'outer optional lookup suppresses null key');
    is_deeply(results('{"cfg":{},"items":[]}',
        '.items[][.cfg.name?]'), [], 'preceding empty iterator yields nothing');
    is_deeply(results('{"cfg":3,"obj":{}}',
        '.obj[.cfg.name?]?'), [],
        'invalid selector still skips even with missing target');
    runtime_error('{"cfg":{},"obj":{"a":7}}',
        '.obj[.cfg["name"]?]', 'Cannot index object with null',
        'missing bracket-quoted field yields null key');
};

subtest 'optional lookup is restricted to its own stage' => sub {
    runtime_error('{"cfg":3,"obj":{"a":7}}',
        '.obj[.cfg?.name]',
        'Cannot index number with string "name"',
        'optional parent does not suppress strict child');
    runtime_error('{"cfg":3,"obj":{"a":7}}',
        '.obj[.cfg.name]?',
        'Cannot index number with string "name"',
        'outer optional lookup does not suppress strict selector');
    is_deeply(results('{"cfg":3,"obj":{"a":7}}',
        '.obj[.cfg.name?[0]]'), [],
        'empty optional field suppresses a later strict index');
    runtime_error('{"cfg":{"name":3},"obj":{"a":7}}',
        '.obj[.cfg.name?[0]]',
        'Cannot index number with number',
        'later strict numeric stage is independently strict');
    is_deeply(results('{"cfg":{"name":3},"obj":{"a":7}}',
        '.obj[.cfg.name?[0]?]'), [],
        'later optional numeric stage drops malformed scalar');
    runtime_error('{"cfg":{"name":"a"},"obj":{"a":7}}',
        '.obj[.cfg.name?][]', 'Cannot iterate over number',
        'suffix iterator remains strict');
    is_deeply(results('{"cfg":{"name":"a"},"obj":{"a":7}}',
        '.obj[.cfg.name?][]?'), [], 'suffix iterator can be optional');
};

subtest 'selector evaluation order with multiple computed keys' => sub {
    is_deeply(results('{"cfg":3,"other":9,"obj":{"a":7}}',
        '.obj[.other.field][.cfg.name?]'), [],
        'rightmost empty selector short-circuits earlier error');
    runtime_error('{"cfg":3,"other":9,"obj":{"a":7}}',
        '.obj[.cfg.name?][.other.field]',
        'Cannot index number with string "field"',
        'rightmost invalid strict selector still fails');
    is_deeply(results('{"first":{"name":"a"},"second":{"name":"b"},'
        . '"obj":{"a":{"b":7}}}',
        '.obj[.first.name?][.second.name?]'), [7],
        'two optional field selectors resolve original input');
    is_deeply(results('{"items":[{"cfg":{"name":"a"},"obj":{"a":1}},'
        . '{"cfg":{"name":"b"},"obj":{"b":2}}]}',
        '.items[] | .obj[.cfg.name?]'), [1,2],
        'pipeline resets selector context for each item');
};

subtest 'parser shape and compatibility' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_computed_selector_fields(
        '.cfg.name?'), ['cfg',['field','name',1]],
        'only optional field becomes a tagged step');
    is_deeply(JQ::Lite::Util::_parse_v3_computed_selector_fields(
        '.cfg."a.b"?'), ['cfg',['field','a.b',1]],
        'dot-quoted optional field decode');
    is_deeply(JQ::Lite::Util::_parse_v3_computed_selector_fields(
        '.cfg["a.b"]?'), ['cfg',['field','a.b',1]],
        'bracket-quoted optional field decode');
    is_deeply(JQ::Lite::Util::_parse_v3_computed_selector_fields(
        '.cfg?["a.b"]?'), [['field','cfg',1],['field','a.b',1]],
        'two independently optional field stages');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg["name"]?]?'),
        [['field','obj'],['computed_context','.cfg["name"]?',1]],
        'selector and outer optional flags remain distinct');
    is_deeply(JQ::Lite::Util::_parse_v3_computed_selector_fields(
        '.cfg.name'), ['cfg','name'], 'strict field shapes stay unchanged');
    is_deeply(JQ::Lite::Util::_parse_v3_computed_selector_fields(
        '.cfg["name"][0]?'), ['cfg','name',['index',0,1]],
        'existing optional numeric index shape preserved');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg["name" + 1]?]')),
        'arithmetic selector remains unsupported');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.cfg[]?]')), 'selector iterator remains unsupported');
    is_deeply(results('{"cfg":{"name":"a"},"obj":{"a":7}}',
        '.obj[.cfg.name]'), [7], 'strict plain fields unchanged');
    is_deeply(results('{"cfg":{"name":"a"},"obj":{"a":7}}',
        '.obj[.cfg["name"]]'), [7], 'strict bracket-quoted unchanged');
    is_deeply(results('{"keys":["a"],"obj":{"a":7}}',
        '.obj[.keys[0]?]'), [7], 'optional numeric selector unchanged');
};

done_testing;
