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
        like("$err", qr/\Q$fragment\E/, "$label: correct failing stage");
    }
}

subtest 'optional named fields in a literal iterator path' => sub {
    is_deeply(results('{"items":[{"name":"A"},3,{"name":"B"}]}',
        '.items[].name?'), ['A','B'], 'wrong-type member is skipped');
    is_deeply(results('{"items":[{"name":"A"},{},null]}',
        '.items[].name?'), ['A',undef,undef],
        'missing object field and null input yield null');
    is_deeply(results('{"items":[{"name":null},{"name":false}]}',
        '.items[].name?'), [undef,JSON::PP::false],
        'explicit null and false values preserved');
    is_deeply(results('{"items":[{"name":"A"},true,{"name":"B"}]}',
        '.items[].name?'), ['A','B'], 'boolean member skipped');
    is_deeply(results('{"items":[{"name":"A"},[],{"name":"B"}]}',
        '.items[].name?'), ['A','B'], 'array member skipped');
    is_deeply(results('{"items":[{"name":"A"},"abc",{"name":"B"}]}',
        '.items[].name?'), ['A','B'], 'string member skipped');
    is_deeply(results('{"items":[]}', '.items[].name?'), [],
        'empty iterator has no results');
    is_deeply(results('{"items":[{"name":"A"},3]}',
        '.items[]?.name?'), ['A'],
        'optional iterator and named-field stage are independent');
    is_deeply(results('{"items":[{"a.b":"A"},3]}',
        '.items[]["a.b"]?'), ['A'],
        'bracket-quoted optional field with a period');
    is_deeply(results('{"items":[{"a.b":"A"},3]}',
        '.items[]."a.b"?'), ['A'],
        'dot-quoted optional field with a period');
    is_deeply(results('{"items":[{"":"A"},3]}',
        '.items[][""]?'), ['A'],
        'empty quoted field name');
    is_deeply(results('{"items":[{"]":"A"},3]}',
        '.items[]["]"]?'), ['A'],
        'quoted name can contain a closing bracket');
};

subtest 'optional field after computed or numeric index' => sub {
    is_deeply(results('{"key":"a","obj":{"a":{"child":7}}}',
        '.obj[.key].child?'), [7],
        'computed selector followed by optional field');
    is_deeply(results('{"key":"a","obj":{"a":3}}',
        '.obj[.key].child?'), [],
        'computed selector followed by wrong-type field lookup');
    is_deeply(results('{"key":"a","obj":{"a":null}}',
        '.obj[.key].child?'), [undef],
        'computed-selected null retains one null output');
    is_deeply(results('{"key":"a","obj":{"a":{}}}',
        '.obj[.key].child?'), [undef],
        'computed-selected object missing field retains null');
    is_deeply(results('{"arr":[{"child":7}]}',
        '.arr[0]?.child?'), [7],
        'standalone optional numeric index followed by optional field');
    is_deeply(results('{"arr":[3]}',
        '.arr[0]?.child?'), [],
        'named lookup on selected scalar skipped');
    is_deeply(results('{"arr":[]}',
        '.arr[0]?.child?'), [undef],
        'missing array index emits null through optional field');
    is_deeply(results('{"arr":[{"a.b":7}]}',
        '.arr[0]?["a.b"]?'), [7],
        'optional numeric with quoted optional field');
    is_deeply(results('{"key":"a","obj":{"a":[{"x":9},3]}}',
        '.obj[.key][].x?'), [9],
        'computed selector then iterator then optional field');
    is_deeply(results('{"key":"a","obj":{"a":[{"x":9},3]}}',
        '.obj[.key][]?.x?'), [9],
        'computed selector and optional iterator');
};

subtest 'stage-local optionality and failures' => sub {
    runtime_error('{"items":[{"name":1}]}',
        '.items[].name?.child',
        'Cannot index number with string "child"',
        'later strict field is not made optional');
    is_deeply(results('{"items":[{"name":1}]}',
        '.items[].name?.child?'), [],
        'later optional field separately suppresses wrong type');
    runtime_error('{"items":7}',
        '.items[].name?', 'Cannot iterate over number',
        'optional field does not suppress earlier strict iterator');
    runtime_error('{"items":[{"name":1},3]}',
        '.items[].name',
        'Cannot index number with string "name"',
        'previous strict field behavior unchanged');
    runtime_error('{"items":[{"name":1},3]}',
        '.items[].name?.missing',
        'Cannot index number with string "missing"',
        'later strict suffix error is preserved');
    is_deeply(results('{"items":[3]}',
        '.items[].name?.child'), [],
        'no later strict error for empty optional output');
    is_deeply(results('{"items":[{"name":null}]}',
        '.items[].name?.child'), [undef],
        'null passes through strict field lookup');
    is_deeply(results('{"items":[{"name":1},3]}',
        '0, .items[].name?, 1'), [0,1,1],
        'comma branches preserve optional field outputs');
    is_deeply(results('{"items":[{"name":1},3]}',
        '.items[].name? | . + 1'), [2],
        'pipeline runs on retained output only');
};

subtest 'parser shape and existing regression controls' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[].name?'),
        [['field','items'],['iterator',0],['field','name',1]],
        'unquoted optional field step tagged');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[]["a.b"]?'),
        [['field','items'],['iterator',0],['field','a.b',1]],
        'bracket-quoted optional field step tagged');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[]."a.b"?'),
        [['field','items'],['iterator',0],['field','a.b',1]],
        'dot-quoted optional field step tagged');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.key].child?'),
        [['field','obj'],['computed_context','.key'],['field','child',1]],
        'computed selector uses original input and optional suffix');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.arr[0]?.child?'),
        [['field','arr'],['index',0,1],['field','child',1]],
        'optional numeric index plus optional field');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[].name'),
        [['field','items'],['iterator',0],['field','name']],
        'strict field step shape remains unchanged');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.name?')), 'bare field-only optional remains a separate audit');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.["name"]?')), 'bare quoted optional remains separate audit');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[].name + 1')), 'expression is not a simple field path');
    is_deeply(results('{"items":[{"name":"A"},{}]}',
        '.items[].name'), ['A',undef], 'old strict named fields work');
    is_deeply(results('{"key":"a","obj":{"a":7}}',
        '.obj[.key]'), [7], 'prior computed selector unchanged');
    is_deeply(results('{"items":[[1,2],3]}',
        '.items[][0]?'), [1], 'prior optional numeric unchanged');
};

done_testing;
