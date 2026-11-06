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
        like("$err", qr/\Q$fragment\E/, "$label: strict failing stage");
    }
}

subtest 'root strict positive numeric index' => sub {
    is_deeply(results('[10,20,30]', '.[0]'), [10],
        'first root element');
    is_deeply(results('[10,20,30]', '.[1]'), [20],
        'second root element');
    is_deeply(results('[10,20,30]', '.[2]'), [30],
        'last root element');
    is_deeply(results('[10,20,30]', '.[3]'), [undef],
        'out-of-range root index yields one null');
    is_deeply(results('[]', '.[0]'), [undef],
        'empty root array yields one null');
    is_deeply(results('null', '.[0]'), [undef],
        'null root indexing yields one null');
    is_deeply(results('[null]', '.[0]'), [undef],
        'null element retained');
    is_deeply(results('[false]', '.[0]'),
        [JSON::PP::false], 'false element retained');
    runtime_error('{}', '.[0]', 'Cannot index object with number',
        'root object rejects numeric index');
    runtime_error('{"0":"x"}', '.[0]',
        'Cannot index object with number',
        'numeric-looking string key is not an array position');
    runtime_error('5', '.[0]', 'Cannot index number with number',
        'number rejects numeric indexing');
    runtime_error('true', '.[0]', 'Cannot index boolean with number',
        'boolean rejects numeric indexing');
    runtime_error('"abc"', '.[0]', 'Cannot index string with number',
        'string rejects numeric indexing');
};

subtest 'strict positive numeric index in named paths' => sub {
    is_deeply(results('{"items":[10,20]}', '.items[0]'), [10],
        'named field followed by strict zero index');
    is_deeply(results('{"items":[10,20]}', '.items[1]'), [20],
        'named field followed by strict positive index');
    is_deeply(results('{"items":[]}', '.items[0]'), [undef],
        'empty nested array yields null');
    is_deeply(results('{"items":null}', '.items[0]'), [undef],
        'null nested field yields null');
    is_deeply(results('{}', '.items[0]'), [undef],
        'missing parent field yields null');
    is_deeply(results('{"items":[{"name":"A"},{"name":"B"}]}',
        '.items[0].name'), ['A'], 'strict name after index');
    is_deeply(results('{"items":[{"name":"A"},{}]}',
        '.items[1].name'), [undef], 'missing suffix key yields null');
    is_deeply(results('{"items":[1]}',
        '.items[2].name'), [undef], 'out-of-range index then name');
    runtime_error('{"items":{}}', '.items[0]',
        'Cannot index object with number',
        'object nested target rejects numeric index');
    runtime_error('{"items":7}', '.items[0]',
        'Cannot index number with number',
        'number nested target rejects numeric index');
    runtime_error('{"items":[7]}', '.items[0].name',
        'Cannot index number with string "name"',
        'strict later name error retained');
    runtime_error('7', '.items[0]',
        'Cannot index number with string "items"',
        'strict earlier field error retained');
};

subtest 'strict composite numeric and quoted paths' => sub {
    is_deeply(results('[[1,2],[3,4]]', '.[0][1]'), [2],
        'two strict nonnegative numeric stages');
    is_deeply(results('{"groups":[[1,2],[3,4]]}',
        '.groups[1][0]'), [3],
        'nested strict numeric stages');
    is_deeply(results('{"groups":[[1,2],[3,4]]}',
        '.groups[0][-1]'), [2],
        'strict positive followed by prior signed negative');
    is_deeply(results('{"a.b":[4,5]}', '.["a.b"][0]'), [4],
        'strict bracket-quoted key and numeric suffix');
    is_deeply(results('{"a.b":[4,5]}', '."a.b"[1]'), [5],
        'strict dot-quoted key and numeric suffix');
    is_deeply(results('{"items":[[1,2]]}',
        '.items[0][]'), [1,2],
        'existing strict iterator after positive numeric');
    is_deeply(results('{"items":[1,2]}',
        '.items[0] | . + 1'), [2],
        'pipeline consumes positive indexed value');
    is_deeply(results('{"items":[1,2,3]}',
        '.items[0], .items[1]'), [1,2],
        'comma branch order preserved');
    is_deeply(results('{"items":[1,2,3]}',
        '0, .items[1], 9'), [0,2,9],
        'literal comma alternatives remain ordered');
    runtime_error('{"items":[1]}',
        '.items[3][]', 'Cannot iterate over null',
        'strict iterator rejects null after out-of-bounds index');
    is_deeply(results('{"items":[1]}',
        '.items[3][]?'), [],
        'optional iterator suppresses only final null iteration');
    is_deeply(results('{"items":7}',
        '.items[0]?'), [], 'optional numeric skips wrong-type target');
    runtime_error('{"items":7}', '.items[0]',
        'Cannot index number with number',
        'strict numeric keeps same error boundary');
};

subtest 'parser scope and prior regressions' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.[0]'), [['index',0]], 'standalone rooted zero index accepted');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[1]'), [['field','items'],['index',1]],
        'standalone named nonnegative index accepted');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[0].name'), [['field','items'],['index',0],['field','name']],
        'strict suffix after positive index retained');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.[0][1]'), [['index',0],['index',1]],
        'consecutive strict numeric steps');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items')), 'strict field-only path remains legacy');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items.name')), 'strict unquoted field chain remains legacy');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[1+2]')), 'arithmetic index stays outside literal parser');
    is_deeply(results('{"items":[[1],[2]]}', '.items[-1][]'), [2],
        'strict negative index and iterator unchanged');
    is_deeply(results('{"items":[10]}', '.items[0]?'), [10],
        'optional numeric stage unchanged');
    is_deeply(results('{"items":[{"name":7}]}',
        '.items[].name?'), [7],
        'optional iterator-field chain unchanged');
    is_deeply(results('{"name":"A"}', '.name'), ['A'],
        'direct strict unquoted field unchanged');
    is_deeply(results('{"a.b":5}', '."a.b"'), [5],
        'strict dot-quoted field unchanged');
};

done_testing;
