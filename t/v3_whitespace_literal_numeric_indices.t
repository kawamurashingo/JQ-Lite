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
        like("$err", qr/\Q$fragment\E/, "$label: strict stage diagnostic");
    }
}

subtest 'root whitespace-padded numeric indices' => sub {
    is_deeply(results('[10,20,30]', '.[ 0 ]'), [10],
        'spaces on both sides of zero');
    is_deeply(results('[10,20,30]', '.[0 ]'), [10],
        'space after index');
    is_deeply(results('[10,20,30]', '.[ 1]'), [20],
        'space before index');
    is_deeply(results('[10,20,30]', '.[  -1  ]'), [30],
        'negative numeric index with surrounding spaces');
    is_deeply(results('[10,20,30]', '.[ -2 ]'), [20],
        'negative index counts from array end');
    is_deeply(results('[10,20,30]', '.[ 8 ]'), [undef],
        'out-of-bounds positive index yields null');
    is_deeply(results('[10,20,30]', '.[ -8 ]'), [undef],
        'out-of-bounds negative index yields null');
    is_deeply(results('[]', '.[ 0 ]'), [undef],
        'empty array yields null');
    is_deeply(results('null', '.[ 0 ]'), [undef],
        'null numeric index yields null');
    is_deeply(results('[null]', '.[ 0 ]'), [undef],
        'explicit null member retained');
    is_deeply(results('[false]', '.[ 0 ]'), [JSON::PP::false],
        'false member retained');
    runtime_error('{}', '.[ 0 ]', 'Cannot index object with number',
        'strict numeric lookup rejects an object');
    runtime_error('{"0":1}', '.[ 0 ]',
        'Cannot index object with number',
        'numeric-looking object key is still an invalid target');
    runtime_error('4', '.[ -1 ]', 'Cannot index number with number',
        'strict negative lookup rejects a number');
    runtime_error('true', '.[ 0 ]', 'Cannot index boolean with number',
        'strict positive lookup rejects a boolean');
    runtime_error('"text"', '.[ 0 ]',
        'Cannot index string with number',
        'strict positive lookup rejects a string');
};

subtest 'nested whitespace numeric indices and strict stage boundaries' => sub {
    is_deeply(results('{"items":[10,20]}', '.items[ 0 ]'), [10],
        'whitespace numeric stage after named field');
    is_deeply(results('{"items":[10,20]}', '.items[  -1  ]'), [20],
        'whitespace negative index after named field');
    is_deeply(results('{"items":[{"name":"A"},{"name":"B"}]}',
        '.items[ 1 ].name'), ['B'],
        'strict named suffix after whitespace index');
    is_deeply(results('{"items":[[1,2],[3,4]]}',
        '.items[ 0 ][ 1 ]'), [2],
        'two separate whitespace-padded numeric stages');
    is_deeply(results('{"items":null}', '.items[ 0 ]'), [undef],
        'null field indexed with spaces yields null');
    is_deeply(results('{}', '.items[ 0 ]'), [undef],
        'missing field indexed with spaces yields null');
    is_deeply(results('{"items":[1]}', '.items[ 4 ].name'),
        [undef], 'out-of-bounds index passes null to field');
    runtime_error('{"items":{}}', '.items[ 0 ]',
        'Cannot index object with number',
        'strict numeric lookup rejects nested object');
    runtime_error('{"items":[7]}', '.items[ 0 ].name',
        'Cannot index number with string "name"',
        'later strict name lookup remains an error');
    runtime_error('7', '.items[ 0 ]',
        'Cannot index number with string "items"',
        'earlier strict field lookup remains an error');
    is_deeply(results('{"a.b":[5,6]}', '.["a.b"][ 1 ]'), [6],
        'quoted literal field and whitespace numeric index');
    is_deeply(results('{"items":[[1,2]]}', '.items[ 0 ][]'),
        [1,2], 'existing strict iterator after spaced index');
    is_deeply(results('{"items":[1,2]}',
        '.items[ 0 ] | . + 1'), [2],
        'downstream pipeline consumes spaced lookup');
    is_deeply(results('{"items":[1,2]}',
        '0, .items[ 1 ], 9'), [0,2,9],
        'comma branch with spaced lookup remains ordered');
};

subtest 'optional whitespace numeric indices' => sub {
    is_deeply(results('[4,5]', '.[ 0 ]?'), [4],
        'optional spaced root index selects array member');
    is_deeply(results('[4,5]', '.[ -1 ]?'), [5],
        'optional spaced negative root index');
    is_deeply(results('null', '.[ 0 ]?'), [undef],
        'optional numeric index on null retains null');
    is_deeply(results('[4]', '.[ 9 ]?'), [undef],
        'optional out-of-bounds lookup retains null');
    is_deeply(results('4', '.[ 0 ]?'), [],
        'optional numeric index drops scalar root');
    is_deeply(results('{"items":4}', '.items[ 0 ]?'), [],
        'optional numeric stage drops nested number');
    is_deeply(results('{"items":{}}', '.items[ 0 ]?'), [],
        'optional numeric stage drops nested object');
    is_deeply(results('{"items":null}', '.items[ 0 ]?'),
        [undef], 'optional numeric stage retains null parent');
    is_deeply(results('{"items":[{"name":"A"}]}',
        '.items[ 0 ]?.name'), ['A'],
        'optional numeric stage with strict field suffix');
    runtime_error('{"items":[4]}', '.items[ 0 ]?.name',
        'Cannot index number with string "name"',
        'optional numeric stage does not hide later strict error');
    is_deeply(results('{"items":[4]}', '.items[ 0 ]?.name?'),
        [], 'later optional field independently drops wrong type');
    is_deeply(results('{"items":[[4,5]]}',
        '.items[ 0 ]?[ 1 ]'), [5],
        'optional numeric prefix then strict spaced numeric suffix');
    runtime_error('{"items":[4]}',
        '.items[ 0 ]?[ 1 ]', 'Cannot index number with number',
        'later strict spaced numeric stage remains an error');
    is_deeply(results('{"items":4}',
        '0, .items[ 0 ]?, 9'), [0,9],
        'empty optional branch is omitted in comma sequence');
};

subtest 'complete literal scanner and unrelated syntax boundaries' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.[ 0 ]'), [['index',0]], 'spaced root numeric step');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[ -1 ]'), [['field','items'],['index',-1]],
        'spaced signed numeric step');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[ 0 ]?'), [['field','items'],['index',0,1]],
        'spaced optional numeric step shape');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[ 0 ].name'),
        [['field','items'],['index',0],['field','name']],
        'spaced numeric step with field suffix');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.[ 0 ][ -1 ]'),
        [['index',0],['index',-1]], 'two spaced numeric steps');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '[ 0 ]')), 'bare bracket array constructor is not an index path');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[ 1 + 1 ]')), 'arithmetic selector remains out of scope');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[ 0:1 ]')), 'slice stays outside the literal numeric parser');
    is_deeply(results('[10,20]', '.[0]'), [10],
        'unspaced positive index unchanged');
    is_deeply(results('[10,20]', '.[-1]'), [20],
        'unspaced negative index unchanged');
    is_deeply(results('[10,20]', '.[0]?'), [10],
        'unspaced optional index unchanged');
    is_deeply(results('{"name":7}', '.name'), [7],
        'strict field-only path stays legacy');
};

done_testing;
