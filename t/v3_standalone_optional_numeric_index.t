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
    ok(!$ok, "$label fails");
    if (!$ok) {
        isa_ok($err, 'JQ::Lite::Error::Evaluation',
            "$label returns structured evaluation error");
        like("$err", qr/\Q$fragment\E/, "$label correct error stage");
    }
}

subtest 'standalone root optional numeric index' => sub {
    is_deeply(results('[10,20]', '.[0]?'), [10], 'first root element');
    is_deeply(results('[10,20]', '.[-1]?'), [20], 'last root element');
    is_deeply(results('[]', '.[0]?'), [undef],
        'empty array returns one null');
    is_deeply(results('[10]', '.[8]?'), [undef],
        'out of bounds returns one null');
    is_deeply(results('null', '.[0]?'), [undef],
        'null root returns one null');
    is_deeply(results('{}', '.[0]?'), [],
        'object root yields no result');
    is_deeply(results('{"0":9}', '.[0]?'), [],
        'numeric object key cannot substitute for array index');
    is_deeply(results('7', '.[0]?'), [],
        'number root yields no result');
    is_deeply(results('"abc"', '.[0]?'), [],
        'string root yields no result');
    is_deeply(results('false', '.[0]?'), [],
        'boolean root yields no result');
    is_deeply(results('[false]', '.[0]?'), [JSON::PP::false],
        'false array element remains an output');
    is_deeply(results('[null]', '.[0]?'), [undef],
        'null array element remains an output');
    is_deeply(results('[{"name":"A"}]', '.[0]?.name'), ['A'],
        'literal suffix field reads array member');
    runtime_error('[5]', '.[0]?.name',
        'Cannot index number with string "name"',
        'strict suffix not suppressed');
    is_deeply(results('[]', '.[0]?.name'), [undef],
        'out of range then field remains one null');
};

subtest 'standalone nested optional numeric path' => sub {
    is_deeply(results('{"a":[10,20]}', '.a[0]?'), [10],
        'first nested array element');
    is_deeply(results('{"a":[10,20]}', '.a[-1]?'), [20],
        'negative nested index');
    is_deeply(results('{"a":[]}', '.a[0]?'), [undef],
        'empty array returns null');
    is_deeply(results('{"a":null}', '.a[0]?'), [undef],
        'null parent returns null');
    is_deeply(results('{}', '.a[0]?'), [undef],
        'missing parent returns null');
    is_deeply(results('{"a":7}', '.a[0]?'), [],
        'number parent produces no output');
    is_deeply(results('{"a":true}', '.a[0]?'), [],
        'boolean parent produces no output');
    is_deeply(results('{"a":"abc"}', '.a[0]?'), [],
        'string parent produces no output');
    is_deeply(results('{"a":{"0":7}}', '.a[0]?'), [],
        'object parent produces no output');
    is_deeply(results('{"a":[{"name":"A"}]}',
        '.a[0]?.name'), ['A'], 'field suffix succeeds');
    is_deeply(results('{"a":[7]}', '.a[0]? | . + 1'), [8],
        'pipeline consumes optional numeric result');
    is_deeply(results('{"a":7}', '.a[0]? | . + 1'), [],
        'pipeline preserves empty result');
    runtime_error('{"a":[7]}', '.a[0]?.name',
        'Cannot index number with string "name"',
        'bad suffix remains strict');
    runtime_error('{"a":7}', '.a[0].name',
        'Cannot index number with number',
        'strict numeric parent error remains');
    runtime_error('7', '.a[0]?',
        'Cannot index number with string "a"',
        'bad earlier field remains strict');
};

subtest 'mixed literal path stages' => sub {
    is_deeply(results('{"a":[[1,2],[3,4]]}',
        '.a[1]?[0]?'), [3],
        'consecutive optional numeric lookups');
    is_deeply(results('{"a":[3,4]}', '.a[0]?[0]?'), [],
        'second optional numeric lookup skips scalar');
    is_deeply(results('{"a":[[1,2]]}', '.a[0]?[1]'),
        [2], 'later strict numeric step succeeds');
    runtime_error('{"a":[5]}', '.a[0]?[1]',
        'Cannot index number with number',
        'later strict numeric index still errors');
    is_deeply(results('{"a":[5]}', '.a[0]?[1]?'), [],
        'later optional numeric index drops invalid type');
    is_deeply(results('{"a":[{"x":[9]}]}',
        '.a[0]?.x[0]?'), [9],
        'field stage between independent optional indices');
    is_deeply(results('{"a":[{"x":null}]}',
        '.a[0]?.x[0]?'), [undef],
        'numeric lookup through null still yields null');
    is_deeply(results('{"a":[{"x":5}]}',
        '.a[0]?.x[0]?'), [],
        'second optional numeric index drops scalar');
    is_deeply(results('{"a":[[1,2],[3,4]]}',
        '0, .a[1]?[0]?, 9'), [0,3,9],
        'comma alternatives preserve stream order');
    is_deeply(results('{"a":7}',
        '0, .a[0]?, 9'), [0,9],
        'empty optional comma branch is omitted');
    is_deeply(results('{"a":null}',
        '0, .a[0]?, 9'), [0,undef,9],
        'null optional comma branch is retained');
};

subtest 'legacy strict paths and scoped visitor boundaries' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.[0]?'), [['index',0,1]],
        'root optional numeric lookup audited');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.a[0]?'), [['field','a'],['index',0,1]],
        'nested optional numeric lookup audited');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.a[0]?.b'), [['field','a'],['index',0,1],['field','b']],
        'literal suffix parsed in source order');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.[0][1]?'), [['index',0],['index',1,1]],
        'strict root index before optional index');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.[0]')), 'standalone strict root index keeps old path');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.a[0]')), 'standalone strict nested index keeps old path');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.a[0].name')), 'strict-only composite keeps old path');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.a[0+1]?')), 'arithmetic index not intercepted');
    is_deeply(results('[10,20]', '.[0]'), [10],
        'existing strict root numeric unchanged');
    is_deeply(results('{"a":[10,20]}', '.a[1]'), [20],
        'existing strict nested numeric unchanged');
    is_deeply(results('{"items":[[1,2],3]}',
        '.items[][0]?'), [1], 'prior iterator optional index unchanged');
    is_deeply(results('{"key":"a","obj":{"a":[5,6]}}',
        '.obj[.key][0]?'), [5], 'prior computed optional index unchanged');
};

done_testing;
