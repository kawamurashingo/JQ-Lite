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
        like("$err", qr/\Q$fragment\E/, "$label: error belongs to strict stage");
    }
}

subtest 'root strict negative numeric lookup' => sub {
    is_deeply(results('[10,20,30]', '.[-1]'), [30],
        'root last array member');
    is_deeply(results('[10,20,30]', '.[-2]'), [20],
        'root second from last');
    is_deeply(results('[10,20,30]', '.[-3]'), [10],
        'root negative index reaches first member');
    is_deeply(results('[10,20,30]', '.[-4]'), [undef],
        'root negative out of bounds yields one null');
    is_deeply(results('[]', '.[-1]'), [undef],
        'empty root array yields one null');
    is_deeply(results('null', '.[-1]'), [undef],
        'root JSON null yields one null');
    is_deeply(results('[null]', '.[-1]'), [undef],
        'explicit null element retained');
    is_deeply(results('[false]', '.[-1]'), [JSON::PP::false],
        'false element retained');
    runtime_error('{}', '.[-1]', 'Cannot index object with number',
        'object cannot be indexed with a signed number');
    runtime_error('{"-1":7}', '.[-1]', 'Cannot index object with number',
        'numeric-looking key is not an array index');
    runtime_error('5', '.[-1]', 'Cannot index number with number',
        'number cannot be indexed with a number');
    runtime_error('true', '.[-1]', 'Cannot index boolean with number',
        'boolean cannot be indexed with a number');
    runtime_error('"abc"', '.[-1]', 'Cannot index string with number',
        'string cannot be indexed with a number');
};

subtest 'strict negative index following a field' => sub {
    is_deeply(results('{"items":[10,20,30]}', '.items[-1]'), [30],
        'named field followed by last index');
    is_deeply(results('{"items":[10,20,30]}', '.items[-2]'), [20],
        'named field followed by second-last index');
    is_deeply(results('{"items":[10,20,30]}', '.items[-10]'),
        [undef], 'nested out of range yields null');
    is_deeply(results('{"items":[]}', '.items[-1]'),
        [undef], 'empty nested array yields null');
    is_deeply(results('{"items":null}', '.items[-1]'),
        [undef], 'null nested array yields null');
    is_deeply(results('{}', '.items[-1]'),
        [undef], 'missing parent yields null');
    is_deeply(results('{"items":[{"name":"A"},{"name":"B"}]}',
        '.items[-1].name'), ['B'], 'strict named suffix');
    is_deeply(results('{"items":[{"name":"A"},{}]}',
        '.items[-1].name'), [undef], 'missing suffix gives null');
    is_deeply(results('{"items":[1]}',
        '.items[-2].name'), [undef], 'out-of-range then strict field');
    runtime_error('{"items":{}}', '.items[-1]',
        'Cannot index object with number', 'nested object index error');
    runtime_error('{"items":7}', '.items[-1]',
        'Cannot index number with number', 'nested number index error');
    runtime_error('{"items":[7]}', '.items[-1].name',
        'Cannot index number with string "name"',
        'strict later field error not suppressed');
    runtime_error('7', '.items[-1]',
        'Cannot index number with string "items"',
        'strict earlier field error not suppressed');
};

subtest 'strict negative indices in composite paths' => sub {
    is_deeply(results('{"groups":[{"items":[1,2]},{"items":[3,4]}]}',
        '.groups[-1].items[-1]'), [4],
        'two signed negative stages');
    is_deeply(results('{"groups":[[1,2],[3,4]]}',
        '.groups[0][-1]'), [2],
        'strict positive prefix and negative suffix');
    is_deeply(results('[[1,2],[3,4]]',
        '.[-1][0]'), [3],
        'negative root index and strict positive suffix');
    is_deeply(results('{"a.b":[1,2]}',
        '.["a.b"][-1]'), [2],
        'quoted field with strict negative index');
    is_deeply(results('{"items":[{"a.b":[7,8]}]}',
        '.items[-1]["a.b"][-1]'), [8],
        'strict negative indices around quoted field');
    is_deeply(results('{"items":[[1,2],[3,4]]}',
        '.items[-1]?[-1]'), [4],
        'strict negative after optional negative index');
    is_deeply(results('{"items":[[1,2],[3,4]]}',
        '.items[-1][-1]?'), [4],
        'optional suffix after strict negative index');
    is_deeply(results('{"items":[1,2]}',
        '.items[-1] | . + 1'), [3],
        'pipeline consumes strict negative result');
    is_deeply(results('{"items":[1,2,3]}',
        '.items[-1], .items[-2]'), [3,2],
        'comma branches preserve negative numeric results');
    is_deeply(results('{"items":[1,2,3]}',
        '0, .items[-1], 9'), [0,3,9],
        'comma branch with literals remains ordered');
    runtime_error('{"items":[[1,2]]}',
        '.items[-2][]', 'Cannot iterate over null',
        'strict iterator suffix after out-of-range index');
    is_deeply(results('{"items":[[1,2]]}',
        '.items[-2][]?'), [],
        'optional iterator suffix skips out-of-range null');
};

subtest 'scope and earlier index regressions' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.[-1]'), [['index',-1]],
        'standalone root strict negative index now parsed');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[-1]'), [['field','items'],['index',-1]],
        'standalone nested strict negative parsed');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[0][-1]'),
        [['field','items'],['index',0],['index',-1]],
        'strict positive and negative stages parsed together');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.[-1].name'), [['index',-1],['field','name']],
        'negative root then strict field');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.[1]'), [['index',1]],
        'strict positive root now enters scoped visitor');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[0]'), [['field','items'],['index',0]],
        'strict positive nested now enters scoped visitor');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[1+2]')), 'arithmetic index is not misparsed');
    is_deeply(results('[10,20]', '.[1]'), [20],
        'legacy positive root index unchanged');
    is_deeply(results('{"items":[10,20]}', '.items[1]'), [20],
        'legacy positive nested index unchanged');
    is_deeply(results('{"items":[10,20]}', '.items[-1]?'),
        [20], 'previous standalone optional negative index unchanged');
    is_deeply(results('{"items":[[1],[2]]}', '.items[-1][]'),
        [2], 'previous negative-index iterator path unchanged');
    is_deeply(results('{"keys":["a"],"obj":{"a":7}}',
        '.obj[.keys[-1]]'), [7],
        'computed selector with signed negative field index unchanged');
};

done_testing;
