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
            "$label: structured error");
        like("$err", qr/\Q$fragment\E/, "$label: correct stage");
    }
}

subtest 'optional literal numeric index after iterator' => sub {
    is_deeply(results('{"items":[[1,2],[3]]}',
        '.items[][0]?'), [1,3], 'first elements from arrays');
    is_deeply(results('{"items":[[1,2],[3]]}',
        '.items[][-1]?'), [2,3], 'negative indices from each array');
    is_deeply(results('{"items":[[1,2],3,[4]]}',
        '.items[][0]?'), [1,4], 'number member is skipped');
    is_deeply(results('{"items":[[1],{},[2]]}',
        '.items[][0]?'), [1,2], 'object member is skipped');
    is_deeply(results('{"items":[[1],false,[2]]}',
        '.items[][0]?'), [1,2], 'boolean member is skipped');
    is_deeply(results('{"items":[[1],"abc",[2]]}',
        '.items[][0]?'), [1,2], 'string member is skipped');
    is_deeply(results('{"items":[[],[2],null]}',
        '.items[][0]?'), [undef,2,undef],
        'empty array and null produce a value');
    is_deeply(results('{"items":[[1],[2,3]]}',
        '.items[][9]?'), [undef,undef],
        'out-of-range valid arrays produce null');
    is_deeply(results('{"items":[[1],[2,3]]}',
        '.items[][-9]?'), [undef,undef],
        'out-of-range negative index produces null');
    is_deeply(results('{"items":[]}',
        '.items[][0]?'), [], 'empty source iterator stays empty');
    is_deeply(results('{"items":[[1,2],[3,4]]}',
        '.items[][0]?, .items[][1]?'), [1,3,2,4],
        'comma alternatives preserve output order');
};

subtest 'optional numeric index before and between iterators' => sub {
    is_deeply(results('{"items":[[1,2]]}',
        '.items[0]?[]'), [1,2], 'selected nested array iterated');
    is_deeply(results('{"items":[[1,2]]}',
        '.items[-1]?[]'), [1,2], 'negative index before iterator');
    is_deeply(results('{"items":3}',
        '.items[0]?[]'), [], 'invalid numeric step short-circuits suffix');
    is_deeply(results('{"items":{}}',
        '.items[0]?[]'), [], 'object numeric step skips iterator');
    is_deeply(results('{"items":[]}',
        '.items[0]?[]?'), [],
        'optional suffix drops null from out-of-range index');
    is_deeply(results('{"items":null}',
        '.items[0]?[]?'), [],
        'optional suffix drops null after null index');
    is_deeply(results('{"items":[[[1,2]],3,[[4]]]}',
        '.items[][0]?[]'), [1,2,4],
        'invalid member skipped before second iterator');
    is_deeply(results('{"items":[[[1]],3,[[2]]]}',
        '.items[]?[0]?[]?'), [1,2],
        'independent optional iterator and numeric index stages');
    is_deeply(results('{"items":[[],[1]]}',
        '.items[][0]?[]?'), [],
        'null and scalar outputs both dropped by optional iterator');
};

subtest 'computed selectors and optional literal numeric index' => sub {
    is_deeply(results('{"key":"a","obj":{"a":[1,2]}}',
        '.obj[.key][0]?'), [1], 'index after computed key');
    is_deeply(results('{"key":"a","obj":{"a":[1,2]}}',
        '.obj[.key][-1]?'), [2], 'negative index after computed key');
    is_deeply(results('{"key":"a","obj":{"a":3}}',
        '.obj[.key][0]?'), [], 'bad selected type skipped');
    is_deeply(results('{"key":"a","obj":{"a":{}}}',
        '.obj[.key][0]?'), [], 'selected object skipped');
    is_deeply(results('{"key":"a","obj":{"a":null}}',
        '.obj[.key][0]?'), [undef], 'null selected target yields null');
    is_deeply(results('{"key":"a","obj":{"a":[]}}',
        '.obj[.key][0]?'), [undef], 'empty selected array yields null');
    is_deeply(results('{"key":"a","obj":{"a":[1,2]}}',
        '.obj[.key][0]? | . + 1'), [2],
        'pipeline consumes indexed value');
    is_deeply(results('{"keys":["a"],"obj":{"a":[1,2]}}',
        '.obj[.keys[0]?][1]?'), [2],
        'inner optional selector and later literal optional index');
    is_deeply(results('{"key":null,"obj":{"a":3}}',
        '.obj[.key]?[0]?'), [],
        'outer computed optional lookup still skips invalid key');
    runtime_error('{"key":null,"obj":{"a":[1]}}',
        '.obj[.key][0]?', 'Cannot index object with null',
        'invalid earlier computed selector remains strict');
    runtime_error('{"cfg":7,"obj":{"a":[1]}}',
        '.obj[.cfg.name][0]?',
        'Cannot index number with string "name"',
        'bad selector evaluation is not suppressed');
};

subtest 'strict numeric index and iterator errors remain intact' => sub {
    runtime_error('{"items":[[1],3]}',
        '.items[][0]', 'Cannot index number with number',
        'strict numeric index still fails');
    runtime_error('{"items":[[1],3]}',
        '.items[][0][]?', 'Cannot index number with number',
        'later optional iterator cannot mask strict index');
    runtime_error('{"items":3}',
        '.items[][0]?', 'Cannot iterate over number',
        'optional index cannot mask previous strict iterator');
    runtime_error('{"items":[]}',
        '.items[0]?[]', 'Cannot iterate over null',
        'later strict iterator still errors');
    runtime_error('{"items":[1]}',
        '.items[0]?[]', 'Cannot iterate over number',
        'strict iterator on scalar still errors');
    is_deeply(results('{"items":[3]}',
        '.items[][0]?.child'), [],
        'later strict field cannot run on skipped stream');
};

subtest 'parser representation and older behavior' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[][0]?'),
        [['field','items'],['iterator',0],['index',0,1]],
        'optional numeric stage has its own marker');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.key][-1]?'),
        [['field','obj'],['computed_context','.key'],['index',-1,1]],
        'optional index following computed key');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[0]?[]'),
        [['field','items'],['index',0,1],['iterator',0]],
        'optional index preceding iterator');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[][0]'),
        [['field','items'],['iterator',0],['index',0]],
        'old strict numeric step shape unchanged');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.key][0]'),
        [['field','obj'],['computed_context','.key'],['index',0]],
        'old strict numeric after computed key unchanged');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[0]?'),
        [['field','items'],['index',0,1]],
        'standalone optional numeric index now enters scoped visitor');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[1+2]?[]')), 'numeric expression remains out of scope');
    is_deeply(results('{"items":[[1,2]]}', '.items[0][]'),
        [1,2], 'previous strict index then iterator unchanged');
    is_deeply(results('{"key":"a","obj":{"a":[1,2]}}',
        '.obj[.key][]'), [1,2], 'previous computed + iterator unchanged');
};

done_testing;
