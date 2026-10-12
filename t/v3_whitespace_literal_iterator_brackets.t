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
        like("$err", qr/\Q$fragment\E/, "$label: failing strict stage");
    }
}

subtest 'strict whitespace iterator after named field' => sub {
    is_deeply(results('{"items":[1,2]}', '.items [ ]'), [1,2],
        'spaces before and inside iterator');
    is_deeply(results('{"items":[1,2]}', '.items[ ]'), [1,2],
        'space inside bracket only');
    is_deeply(results('{"items":[1,2]}', '.items []'), [1,2],
        'space before bracket only');
    is_deeply(results('{"items":[1,2]}', '.items [   ]'), [1,2],
        'multiple spaces in iterator');
    is_deeply(results('{"items":[null,false,3]}', '.items [ ]'),
        [undef,JSON::PP::false,3], 'iterator preserves null and false');
    is_deeply(results('{"items":[]}', '.items [ ]'), [],
        'empty array has no members');
    is_deeply(results('{"items":{"only":3}}', '.items [ ]'),
        [3], 'object with one member iterates value');
    is_deeply(results('{"items":{}}', '.items [ ]'), [],
        'empty object yields no members');
    is_deeply(results('{"items":[{"name":"A"},{}]}',
        '.items [ ].name'), ['A',undef],
        'strict name after whitespace iterator');
    is_deeply(results('{"items":[[1,2],[3]]}',
        '.items [ ] [ ]'), [1,2,3],
        'chained whitespace iterators flatten arrays');
    is_deeply(results('{"items":[[1,2],[3]]}',
        '.items[0] [ ]'), [1,2],
        'whitespace iterator after numeric index');
    is_deeply(results('{"a.b":[3,4]}',
        '.["a.b"] [ ]'), [3,4],
        'whitespace iterator after quoted bracket key');
    is_deeply(results('{"a.b":[3,4]}',
        '."a.b" [ ]'), [3,4],
        'whitespace iterator after dot-quoted key');
    runtime_error('{"items":null}', '.items [ ]',
        'Cannot iterate over null', 'strict null iteration fails');
    runtime_error('{"items":3}', '.items [ ]',
        'Cannot iterate over number', 'strict numeric iteration fails');
    runtime_error('{"items":true}', '.items [ ]',
        'Cannot iterate over boolean', 'strict boolean iteration fails');
    runtime_error('{"items":"abc"}', '.items [ ]',
        'Cannot iterate over string', 'strict string iteration fails');
    runtime_error('7', '.items [ ]',
        'Cannot index number with string "items"',
        'strict earlier field error remains');
    runtime_error('{"items":[2]}', '.items [ ].name',
        'Cannot index number with string "name"',
        'strict later field error remains');
};

subtest 'optional whitespace iterator after named field' => sub {
    is_deeply(results('{"items":[1,2]}', '.items [ ]?'), [1,2],
        'optional padded iterator emits values');
    is_deeply(results('{"items":[1,2]}', '.items[ ]?'), [1,2],
        'optional iterator with only inner spaces');
    is_deeply(results('{"items":[1,2]}', '.items []?'), [1,2],
        'optional iterator with only preceding spaces');
    is_deeply(results('{"items":[null,false]}', '.items [ ]?'),
        [undef,JSON::PP::false], 'optional iterator retains members');
    is_deeply(results('{"items":null}', '.items [ ]?'), [],
        'optional null iteration drops its value');
    is_deeply(results('{"items":3}', '.items [ ]?'), [],
        'optional numeric iteration drops value');
    is_deeply(results('{"items":{}}', '.items [ ]?'), [],
        'optional empty object yields empty stream');
    is_deeply(results('{}', '.items [ ]?'), [],
        'missing field then optional iterator yields empty stream');
    is_deeply(results('{"items":[[1,2],null]}',
        '.items [ ] [ ]?'), [1,2],
        'last optional iterator skips null nested member');
    is_deeply(results('{"items":[[1,2],null]}',
        '.items [ ]? [ ]?'), [1,2],
        'two independent optional iterator stages');
    runtime_error('{"items":[null]}',
        '.items [ ]? [ ]',
        'Cannot iterate over null',
        'later strict iterator error is not hidden');
    runtime_error('7', '.items [ ]?',
        'Cannot index number with string "items"',
        'earlier strict field error not hidden by optional');
    runtime_error('{"items":[2]}',
        '.items [ ]?.name',
        'Cannot index number with string "name"',
        'later strict named field error remains');
};

subtest 'strict and optional root whitespace iterators' => sub {
    is_deeply(results('[1,2]', '. [ ]'), [1,2],
        'root strict iterator with spaces before and inside');
    is_deeply(results('[1,2]', '.[ ]'), [1,2],
        'root iterator with whitespace inside');
    is_deeply(results('[1,2]', '. []'), [1,2],
        'root iterator with whitespace before');
    is_deeply(results('[null,false]', '. [ ]'),
        [undef,JSON::PP::false], 'root preserves null and false');
    is_deeply(results('[]', '. [ ]'), [],
        'root empty array yields no output');
    is_deeply(results('{"one":9}', '. [ ]'), [9],
        'root object emits member');
    runtime_error('null', '. [ ]',
        'Cannot iterate over null', 'root strict null fails');
    runtime_error('3', '. [ ]',
        'Cannot iterate over number', 'root strict number fails');
    is_deeply(results('null', '. [ ]?'), [],
        'optional root null iteration emits no result');
    is_deeply(results('3', '. [ ]?'), [],
        'optional root number iteration emits no result');
    is_deeply(results('[1,2]', '. [ ]?'), [1,2],
        'optional root iterator emits valid members');
    is_deeply(results('{"one":9}', '. [ ]?'), [9],
        'optional root object yields member');
    is_deeply(results('[1,2]', '0, . [ ], 9'), [0,1,2,9],
        'comma branch ordering retained');
    is_deeply(results('[1,2]', '. [ ] | . + 1'), [2,3],
        'pipeline consumes strict iterator stream');
};

subtest 'parser safety and existing syntax boundaries' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items [ ]'), [['field','items'],['iterator',0]],
        'named field plus spaced strict iterator');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[ ]?'), [['field','items'],['iterator',1]],
        'named field plus padded optional iterator');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '. [ ]'), [['iterator',0]],
        'root whitespace iterator parsed as a single stage');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '. [ ]?'), [['iterator',1]],
        'root whitespace optional iterator parsed');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items [ ] [ ]'),
        [['field','items'],['iterator',0],['iterator',0]],
        'two spaced iterator stages preserved');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '[ ]')), 'bare empty array constructor is not an iterator path');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        'try [ ]')), 'try with empty array literal is not a path');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        'try[ ]')), 'try with padded bracket is not a path');
    is_deeply([JQ::Lite::Parser::parse_query('.items [ ]')],
        ['.items [ ]'], 'parser retains root dot on new iterator form');
    is_deeply([JQ::Lite::Parser::parse_query('.items[ ]?')],
        ['.items[ ]?'], 'parser retains root dot on padded iterator');
    is_deeply(results('null', '[ ]'), [[]],
        'bare padded empty array constructor remains array');
    is_deeply(results('null', 'try ["catch me"]'),
        [['catch me']], 'earlier try array regression preserved');
    is_deeply(results('[1,2]', '.[]'), [1,2],
        'unspaced root iterator unchanged');
    is_deeply(results('null', '.[]?'), [],
        'unspaced root optional iterator unchanged');
    is_deeply(results('{"items":[1,2]}', '.items[]'), [1,2],
        'unspaced nested iterator unchanged');
    is_deeply(results('{"name":3}', '.name'), [3],
        'strict unquoted field unchanged');
};

done_testing;
