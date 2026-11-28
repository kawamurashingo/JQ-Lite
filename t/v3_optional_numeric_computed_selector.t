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
        like("$err", qr/\Q$fragment\E/, "$label: right stage");
    }
}

subtest 'optional numeric selector index succeeds for arrays' => sub {
    is_deeply(results('{"keys":["a","b"],"obj":{"a":1,"b":2}}',
        '.obj[.keys[0]?]'), [1], 'first array key');
    is_deeply(results('{"keys":["a","b"],"obj":{"a":1,"b":2}}',
        '.obj[.keys[-1]?]'), [2], 'signed numeric selector');
    is_deeply(results('{"keys":["a","b"],"obj":{"a":1,"b":2}}',
        '.obj[.keys[ 1 ]?]'), [2], 'whitespace around index');
    is_deeply(results('{"cfg":{"names":["a"]},"obj":{"a":7}}',
        '.obj[.cfg["names"][0]?]'), [7], 'quoted field prefix');
    is_deeply(results('{"cfg":{"names":[["a"]]},"obj":{"a":7}}',
        '.obj[.cfg.names[0]?[0]?]'), [7],
        'two optional numeric selector stages');
    is_deeply(results('{"keys":[1],"obj":[4,5,6]}',
        '.obj[.keys[0]?]'), [5], 'numeric key indexes array target');
    is_deeply(results('[1,4,5]', '.[.[0]?]'),
        [4], 'root-array selector passes into root index');
    is_deeply(results('{"keys":["a"],"obj":{"a":null}}',
        '.obj[.keys[0]?]'), [undef], 'explicit null output');
    is_deeply(results('{"keys":["a"],"obj":{"a":false}}',
        '.obj[.keys[0]?]'), [JSON::PP::false], 'false output retained');
    is_deeply(results('{"keys":["a"],"obj":{}}',
        '.obj[.keys[0]?]'), [undef], 'missing valid outer field returns null');
};

subtest 'invalid numeric selector target emits no results' => sub {
    is_deeply(results('{"keys":3,"obj":{"a":7}}',
        '.obj[.keys[0]?]'), [], 'number is not an array');
    is_deeply(results('{"keys":{},"obj":{"a":7}}',
        '.obj[.keys[0]?]'), [], 'object is not an array');
    is_deeply(results('{"keys":"hello","obj":{"a":7}}',
        '.obj[.keys[1]?]'), [], 'string does not support numeric index');
    is_deeply(results('{"keys":true,"obj":{"a":7}}',
        '.obj[.keys[0]?]'), [], 'boolean does not support numeric index');
    is_deeply(results('{"cfg":{"names":3},"obj":{"a":7}}',
        '.obj[.cfg.names[0]?]'), [], 'optional deep numeric selector');
    is_deeply(results('{"keys":3,"items":[]}',
        '.items[][.keys[0]?]'), [], 'selector empty before empty iterator');
    is_deeply(results('{"keys":3,"items":[{"a":7}]}',
        '.items[][.keys[0]?]'), [], 'selector empty before populated iterator');
    is_deeply(results('{"keys":3,"obj":{"a":7}}',
        '.obj[.keys[0]?]?'), [], 'inner and outer optional lookups');
    is_deeply(results('{"keys":3,"obj":{"a":7}}',
        '0, .obj[.keys[0]?], 1'), [0,1],
        'comma alternatives remain independently evaluated');
    is_deeply(results('{"keys":3,"obj":{"a":7}}',
        '.obj[.keys[0]?].child'), [], 'later strict suffix cannot run');
};

subtest 'JSON null is not an empty selector result' => sub {
    runtime_error('{"keys":[],"obj":{"a":7}}',
        '.obj[.keys[0]?]', 'Cannot index object with null',
        'out of bounds on valid array yields null key');
    runtime_error('{"keys":null,"obj":{"a":7}}',
        '.obj[.keys[0]?]', 'Cannot index object with null',
        'numeric indexing null yields null key');
    is_deeply(results('{"keys":[],"obj":{"a":7}}',
        '.obj[.keys[0]?]?'), [], 'outer optional lookup skips null key');
    is_deeply(results('{"keys":null,"obj":{"a":7}}',
        '.obj[.keys[0]?]?'), [], 'null selector key skipped by outer ?');
    is_deeply(results('{"keys":[],"items":[]}',
        '.items[][.keys[0]?]'), [], 'empty earlier iterator with null key');
    is_deeply(results('{"keys":[null],"obj":null}',
        '.obj[.keys[0]?]?'), [], 'null key does not index null');
};

subtest 'earlier strict errors remain visible' => sub {
    runtime_error('{"cfg":7,"obj":{"a":7}}',
        '.obj[.cfg.names[0]?]',
        'Cannot index number with string "names"',
        'bad field before optional numeric index');
    runtime_error('{"cfg":7,"items":[]}',
        '.items[][.cfg.names[0]?]',
        'Cannot index number with string "names"',
        'bad selector prefix despite empty earlier iterator');
    runtime_error('{"keys":3,"obj":{"a":7}}',
        '.obj[.keys[0]]?',
        'Cannot index number with number',
        'optional outer lookup does not suppress strict numeric selector');
    runtime_error('{"keys":["a"],"obj":{"a":7}}',
        '.obj[.keys[0]?][]', 'Cannot iterate over number',
        'strict suffix still rejects selected scalar');
    is_deeply(results('{"keys":["a"],"obj":{"a":7}}',
        '.obj[.keys[0]?][]?'), [], 'later optional iterator skips scalar');
};

subtest 'multiple selectors honor jq nested evaluation order' => sub {
    is_deeply(results('{"keys":3,"cfg":9,"obj":{"a":1}}',
        '.obj[.cfg.x][.keys[0]?]'), [],
        'rightmost optional selector drops earlier selector error');
    runtime_error('{"keys":3,"cfg":9,"obj":{"a":1}}',
        '.obj[.keys[0]?][.cfg.x]',
        'Cannot index number with string "x"',
        'rightmost selector error remains visible');
    is_deeply(results('{"first":["a"],"second":["b"],"obj":{"a":{"b":7}}}',
        '.obj[.first[0]?][.second[0]?]'), [7],
        'two valid optional computed selectors');
};

subtest 'syntax and backwards compatibility' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_computed_selector_fields(
        '.keys[0]?'), ['keys',['index',0,1]],
        'optional numeric index has its own flag');
    is_deeply(JQ::Lite::Util::_parse_v3_computed_selector_fields(
        '.cfg["names"][-1]?'), ['cfg','names',['index',-1,1]],
        'quoted selector and optional signed numeric index');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.keys[0]?]?'),
        [['field','obj'],['computed_context','.keys[0]?',1]],
        'outer optional and selector optional remain distinct');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.keys[0]]'),
        [['field','obj'],['computed_context','.keys[0]']],
        'existing strict numeric selector unchanged');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.keys[]?]')), 'generator inside selector remains unsupported');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.keys[1+2]?]')), 'arithmetic inside selector not accepted');
    is_deeply(results('{"key":"a","obj":{"a":7}}',
        '.obj[.key]'), [7], 'plain computed selector unchanged');
    is_deeply(results('{"key":"a","obj":{"a":7}}',
        '.obj[.key]?'), [7], 'outer optional computed selector unchanged');
    is_deeply(results('{"keys":["a"],"obj":{"a":7}}',
        '.obj[.keys[0]]'), [7], 'strict numeric selector unchanged');
};

done_testing;
