use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Util ();
use JQ::Lite::Parser ();
use JQ::Lite::Error ();

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
        like("$err", qr/\Q$fragment\E/,
            "$label: strict stage diagnostic");
    }
}

subtest 'root computed selectors with whitespace before bracket' => sub {
    is_deeply(results('{"key":"name","name":"Ada"}',
        '. [.key]'), ['Ada'], 'root computed key with preceding space');
    is_deeply(results('{"key":"name","name":"Ada"}',
        '. [ .key ]'), ['Ada'], 'root computed key with surrounding spaces');
    is_deeply(results('{"key":"name","name":"Ada"}',
        ".\t[.key]"), ['Ada'], 'root with tab before bracket');
    is_deeply(results('{"key":"missing"}',
        '. [ .key ]'), [undef], 'missing selected root field yields null');
    is_deeply(results('{"key":"a.b","a.b":7}',
        '. [ .key ]'), [7], 'computed punctuation is one literal key');
    is_deeply(results('{"key":"name","name":false}',
        '. [.key]'), [JSON::PP::false], 'false member is not omitted');
    is_deeply(results('{"key":"name","name":null}',
        '. [.key]'), [undef], 'explicit null member is retained');
    is_deeply(results('{"key":"name","name":8}',
        '. [.key]?'), [8], 'optional spaced selector emits valid value');
    is_deeply(results('{"key":null}',
        '. [.key]?'), [], 'optional selector drops invalid null key');
    runtime_error('{"key":null}', '. [.key]',
        'Cannot index object with null', 'strict null key raises error');
    runtime_error('{"key":1}', '. [.key]',
        'Cannot index object with number', 'strict number key raises error');
};

subtest 'nested selector uses the original input, not intermediate value' => sub {
    is_deeply(results('{"obj":{"name":42},"key":"name"}',
        '.obj [.key]'), [42], 'root key selects nested object member');
    is_deeply(results('{"obj":{"name":42},"key":"name"}',
        '.obj [ .key ]'), [42], 'spaces inside and before nested bracket');
    is_deeply(results('{"obj":{"name":42},"key":"name"}',
        '.obj [.key]?'), [42], 'nested optional selector');
    is_deeply(results('{"obj":{"a":{"n":4}},"key":"a"}',
        '.obj [ .key ].n'), [4], 'strict suffix follows computed stage');
    is_deeply(results('{"obj":{"a":{"n":4}},"cfg":{"chosen":"a"}}',
        '.obj [ .cfg.chosen ].n'), [4],
        'dotted computed expression reads original input');
    is_deeply(results('{"obj":{"a":4},"key":"a"}',
        '.obj . [.key]'), [4], 'spaced dotted bracket suffix');
    is_deeply(results('{"outer":{"name":"X"},"key":"name"}',
        '.["outer"] [.key]'), ['X'], 'quoted previous stage');
    is_deeply(results('{"arr":[10,20],"idx":1}',
        '.arr [.idx]'), [20], 'numeric computed key indexes array');
    is_deeply(results('{"arr":[10,20],"idx":-1}',
        '.arr [ .idx ]'), [20], 'negative computed index reads last');
    is_deeply(results('{"arr":[10,20],"idx":9}',
        '.arr [.idx]'), [undef], 'out-of-bounds computed index is null');
    is_deeply(results('{"obj":null,"key":"a"}',
        '.obj [.key]'), [undef], 'null intermediate target yields null');
    runtime_error('{"obj":7,"key":"name"}', '.obj [.key]',
        'Cannot index number with string "name"',
        'strict computed lookup errors on wrong target');
    is_deeply(results('{"obj":7,"key":"name"}',
        '.obj [.key]?'), [], 'optional selector drops wrong-type target');
    runtime_error('{"arr":[10],"idx":"0"}',
        '.arr [.idx]', 'Cannot index array with string "0"',
        'array rejects computed string index');
    runtime_error('7', '.obj [.key]?',
        'Cannot index number with string "key"',
        'computed selector on original input fails before target indexing');
    is_deeply(results('{"obj":{"name":42},"key":"name"}',
        '0, .obj [.key], 9'), [0,42,9],
        'comma branches preserve order');
    is_deeply(results('{"obj":{"name":42},"key":"name"}',
        '.obj [.key] | . + 1'), [43],
        'pipeline operates on computed selector output');
};

subtest 'parse boundaries and regression controls' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '. [.key]'), [['computed_root','.key']],
        'spaced computed root step shape retained');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj [.key]'),
        [['field','obj'],['computed_context','.key']],
        'spaced computed context step shape retained');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj [ .key ]?'),
        [['field','obj'],['computed_context','.key',1]],
        'stage-local optional computed shape retained');
    is_deeply([JQ::Lite::Parser::parse_query('.obj [.key]')],
        ['.obj [.key]'], 'parser retains rooted spelling');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '[.key]')), 'bare selector bracket is array constructor');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        'try [.key]')), 'try array constructor is not rooted path');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj [ .key + 1 ]')), 'arbitrary computed expression excluded');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj [1:3]')), 'slice excluded');
    is_deeply(results('{"key":"name","name":"Ada"}',
        '[.key]'), [['name']], 'bare bracket remains constructor');
    is_deeply(results('{"key":"name","name":"Ada"}',
        'try [.key]'), [['name']], 'try remains array expression');
    is_deeply(results('{"obj":{"name":42},"key":"name"}',
        '.obj[.key]'), [42], 'unspaced nested computed unaffected');
    is_deeply(results('{"key":"name","name":"Ada"}',
        '.[.key]'), ['Ada'], 'unspaced root computed unaffected');
    is_deeply(results('{"items":[1,2]}',
        '.items [ ]'), [1,2], 'padded iterator unaffected');
};

done_testing;
