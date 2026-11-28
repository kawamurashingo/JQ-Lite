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
    my $error = $@;
    ok(!$ok, "$label: fails");
    if (!$ok) {
        isa_ok($error, 'JQ::Lite::Error::Evaluation',
            "$label: structured evaluation error");
        like("$error", qr/\Q$fragment\E/,
            "$label: error is from the strict stage");
    }
}

subtest 'root dot separated from numeric bracket' => sub {
    is_deeply(results('[10,20]', '. [0]'), [10],
        'one space after root dot');
    is_deeply(results('[10,20]', '.  [ 1 ]'), [20],
        'multiple spaces and inner spaces');
    is_deeply(results('[10,20]', ".\t[0]"), [10],
        'tab before a numeric bracket');
    is_deeply(results('[10,20]', '. [ -1 ]'), [20],
        'signed negative bracket with root gap');
    is_deeply(results('[10,20]', '. [4]'), [undef],
        'out-of-range index still yields one null');
    is_deeply(results('[]', '. [0]'), [undef],
        'empty array still yields one null');
    is_deeply(results('null', '. [0]'), [undef],
        'null numeric lookup still yields one null');
    is_deeply(results('[null]', '. [0]'), [undef],
        'null array member retained');
    is_deeply(results('[false]', '. [0]'), [JSON::PP::false],
        'false array member retained');
    runtime_error('{}', '. [0]', 'Cannot index object with number',
        'wrong-type object lookup stays strict');
    runtime_error('{"0":3}', '. [0]',
        'Cannot index object with number',
        'numeric-looking key is not an array index');
    runtime_error('3', '. [ -1 ]',
        'Cannot index number with number',
        'strict negative numeric stage rejects a number');
    runtime_error('"hi"', '. [0]',
        'Cannot index string with number',
        'strict numeric stage rejects a string');
};

subtest 'numeric brackets separated from preceding literal stages' => sub {
    is_deeply(results('{"items":[10,20]}', '.items [0]'), [10],
        'name and bracket separated by a space');
    is_deeply(results('{"items":[10,20]}', '.items [ -1 ]'), [20],
        'name and signed bracket separated');
    is_deeply(results('{"items":[{"name":"A"}]}',
        '.items [ 0 ].name'), ['A'],
        'strict named suffix after spaced bracket');
    is_deeply(results('{"items":[[1,2],[3,4]]}',
        '.items[0] [1]'), [2],
        'second numeric bracket separated');
    is_deeply(results('{"items":[[1,2],[3,4]]}',
        '.items [1] [ 0 ]'), [3],
        'both numeric brackets separated');
    is_deeply(results('[[1,2],[3,4]]',
        '. [0] [1]'), [2],
        'root gap and consecutive numeric gap');
    is_deeply(results('{"a.b":[4,5]}',
        '.["a.b"] [1]'), [5],
        'strict bracket-quoted key before spaced numeric index');
    is_deeply(results('{"a.b":[4,5]}',
        '."a.b" [0]'), [4],
        'strict dot-quoted key before spaced numeric index');
    is_deeply(results('{"items":null}', '.items [0]'), [undef],
        'null field followed by spaced index');
    is_deeply(results('{}', '.items [0]'), [undef],
        'missing field followed by spaced index');
    is_deeply(results('{"items":[1]}',
        '.items [3].name'), [undef],
        'out-of-range index then strict named lookup');
    runtime_error('{"items":{}}', '.items [0]',
        'Cannot index object with number',
        'wrong-type numeric target still fails');
    runtime_error('{"items":[7]}', '.items [0].name',
        'Cannot index number with string "name"',
        'later strict field error is not suppressed');
    runtime_error('7', '.items [0]',
        'Cannot index number with string "items"',
        'prior strict field error is not suppressed');
    is_deeply(results('{"items":[[1,2]]}',
        '.items [0][]'), [1,2],
        'unspaced iterator suffix works');
    is_deeply(results('{"items":[10,20]}',
        '.items [0] | . + 1'), [11],
        'numeric result enters pipeline');
    is_deeply(results('{"items":[10,20]}',
        '0, .items [1], 9'), [0,20,9],
        'comma branch keeps result order');
};

subtest 'stage-local optional numeric brackets with preceding whitespace' => sub {
    is_deeply(results('[10,20]', '. [0]?'), [10],
        'root optional spaced index reads array element');
    is_deeply(results('[10,20]', '. [ -1 ]?'), [20],
        'root optional signed spaced index');
    is_deeply(results('[10]', '. [4]?'), [undef],
        'optional out-of-bounds index retains null');
    is_deeply(results('null', '. [0]?'), [undef],
        'optional null index retains null');
    is_deeply(results('7', '. [0]?'), [],
        'optional invalid numeric root emits no results');
    is_deeply(results('{"items":7}', '.items [0]?'), [],
        'optional wrong-type numeric field emits no results');
    is_deeply(results('{"items":{}}', '.items [0]?'), [],
        'optional object numeric target emits no results');
    is_deeply(results('{"items":null}', '.items [0]?'), [undef],
        'optional index on null retains one null');
    is_deeply(results('{"items":[{"name":"A"}]}',
        '.items [0]?.name'), ['A'],
        'later strict suffix after valid optional numeric index');
    runtime_error('{"items":[7]}',
        '.items [0]?.name',
        'Cannot index number with string "name"',
        'optional numeric lookup cannot hide later strict field error');
    is_deeply(results('{"items":[[1,2]]}',
        '.items [0]? [1]'), [2],
        'strict spaced numeric suffix after optional spaced prefix');
    runtime_error('{"items":[7]}',
        '.items [0]? [1]',
        'Cannot index number with number',
        'later strict numeric suffix still fails');
    is_deeply(results('{"items":7}',
        '0, .items [0]?, 9'), [0,9],
        'empty optional comma branch omitted');
};

subtest 'parser limits and regression controls' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '. [0]'), [['index',0]],
        'root dot followed by spaced index');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items [ -1 ]'), [['field','items'],['index',-1]],
        'nested signed index with preceding whitespace');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items [0]?'), [['field','items'],['index',0,1]],
        'nested optional stage preserves shape');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[0] [1]'),
        [['field','items'],['index',0],['index',1]],
        'whitespace-separated consecutive numeric steps');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '[ 0 ]')), 'bare array constructor is not a rooted path');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items [ 0:1 ]')), 'slices remain outside literal numeric scanner');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items [ .key ]'),
        [['field','items'],['computed_context','.key']],
        'simple computed field with preceding whitespace now audited');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items [ "a.b" ]'),
        [['field','items'],['field','a.b']],
        'literal JSON-quoted bracket after a space now enters visitor');
    is_deeply(results('[10,20]', '.[0]'), [10],
        'previous unspaced root numeric unchanged');
    is_deeply(results('{"items":[10,20]}', '.items[ 0 ]'), [10],
        'previous inner-space numeric path unchanged');
    is_deeply(results('[10,20]', '.[-1]'), [20],
        'previous signed numeric unchanged');
    is_deeply(results('{"name":7}', '.name'), [7],
        'bare strict unquoted field unchanged');
    is_deeply(results('{"a.b":5}', '."a.b"'), [5],
        'strict dot-quoted field unchanged');
};

done_testing;
