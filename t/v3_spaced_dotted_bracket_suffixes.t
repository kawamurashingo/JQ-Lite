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
    my ($json, $filter, $fragment, $description) = @_;
    my $ok = eval { $jq->run_query($json, $filter); 1 };
    my $err = $@;
    ok(!$ok, "$description: fails");
    if (!$ok) {
        isa_ok($err, 'JQ::Lite::Error::Evaluation',
            "$description: structured evaluation error");
        like("$err", qr/\Q$fragment\E/,
            "$description: expected strict lookup type");
    }
}

subtest 'numeric bracket after a whitespace-separated dot' => sub {
    is_deeply(results('{"items":[[2,3],[4,5]]}',
        '.items[0] . [1]'), [3],
        'spaces around an intermediate dot and numeric bracket');
    is_deeply(results('{"items":[[2,3],[4,5]]}',
        '.items[0]. [1]'), [3],
        'space only after the dot');
    is_deeply(results('{"items":[[2,3],[4,5]]}',
        '.items[0] . [ 0 ]'), [2],
        'whitespace inside numeric bracket also retained');
    is_deeply(results('{"items":[[2,3],[4,5]]}',
        '.items[-1] . [0]'), [4],
        'negative earlier index and numeric suffix');
    is_deeply(results('{"items":[[2,3],[4,5]]}',
        '.items[1] . [-1]'), [5],
        'negative suffix after spaced dot');
    is_deeply(results('{"items":[[2,3],[4,5]]}',
        '.items[0] . [8]'), [undef],
        'out-of-bounds suffix yields one null');
    is_deeply(results('{"items":[null]}',
        '.items[0] . [0]'), [undef],
        'null intermediate indexing yields null');
    is_deeply(results('{"items":[[1]]}',
        '.items[0] . [2] . [0]'), [undef],
        'additional strict step through null remains null');
    runtime_error('{"items":[{}]}',
        '.items[0] . [0]',
        'Cannot index object with number',
        'object is not a numeric array target');
    runtime_error('{"items":[7]}',
        '.items[0] . [0]',
        'Cannot index number with number',
        'number is not a numeric array target');
    runtime_error('7', '.items[0] . [1]',
        'Cannot index number with string "items"',
        'strict earlier field error still propagates');
    is_deeply(results('{"items":[7]}',
        '.items[0] . [0]?'), [],
        'optional wrong-type numeric suffix drops item');
    is_deeply(results('{"items":[[1,2]]}',
        '.items[0] . [0]?'), [1],
        'optional numeric suffix selects valid array item');
    is_deeply(results('{"items":[[]]}',
        '.items[0] . [0]?'), [undef],
        'optional out-of-bounds suffix retains null');
};

subtest 'quoted fields and iterators after separated dotted brackets' => sub {
    is_deeply(results('{"items":[{"a.b":7}]}',
        '.items[0] . ["a.b"]'), [7],
        'quoted field after spaced dot and bracket');
    is_deeply(results('{"items":[{"a.b":7}]}',
        '.items[0]. [ "a.b" ]'), [7],
        'quote has padding and dot has trailing space');
    is_deeply(results('{"items":[{"a.b":[2,4]}]}',
        '.items[0] . ["a.b"][1]'), [4],
        'numeric suffix after JSON-quoted field');
    is_deeply(results('{"items":[{"a|=b":3}]}',
        '.items[0] . ["a|=b"]'), [3],
        'update token inside literal key is not an operator');
    is_deeply(results('{"items":[{"a,b":4}]}',
        '.items[0] . ["a,b"]'), [4],
        'comma inside literal key is not an alternative');
    is_deeply(results('{"items":[{}]}',
        '.items[0] . ["a.b"]'), [undef],
        'missing quoted field emits one null');
    is_deeply(results('{"items":[null]}',
        '.items[0] . ["a.b"]'), [undef],
        'quoted field on null emits one null');
    runtime_error('{"items":[8]}',
        '.items[0] . ["a.b"]',
        'Cannot index number with string "a.b"',
        'strict quoted field rejects numeric target');
    is_deeply(results('{"items":[8]}',
        '.items[0] . ["a.b"]?'), [],
        'optional quoted field drops invalid target');
    is_deeply(results('{"items":[[3,4]]}',
        '.items[0] . [ ]'), [3,4],
        'iterator bracket after separated dot');
    is_deeply(results('{"items":[[3,4]]}',
        '.items[0] . [ ]?'), [3,4],
        'optional iterator bracket after separated dot');
    is_deeply(results('{"items":[null]}',
        '.items[0] . [ ]?'), [],
        'optional iterator on null skips');
    runtime_error('{"items":[null]}',
        '.items[0] . [ ]',
        'Cannot iterate over null',
        'strict iterator on null still errors');
    is_deeply(results('{"items":[[1,2]]}',
        '.items[0] . [1] | . + 1'), [3],
        'pipeline consumes indexed result');
    is_deeply(results('{"items":[[1,2]]}',
        '0, .items[0] . [1], 9'), [0,2,9],
        'comma alternatives keep source order');
};

subtest 'scanner/parser boundaries and existing controls' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[0] . [1]'),
        [['field','items'],['index',0],['index',1]],
        'numeric bracket after spaced dot parsed in order');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[0] . ["a.b"]'),
        [['field','items'],['index',0],['field','a.b']],
        'literal quoted field after spaced dot parsed in order');
    is_deeply([JQ::Lite::Parser::parse_query('.items[0] . [1]')],
        ['.items[0] . [1]'],
        'parser preserves rooted numeric bracket suffix');
    is_deeply([JQ::Lite::Parser::parse_query('.items[0] . ["a.b"]')],
        ['.items[0] . ["a.b"]'],
        'parser preserves rooted quoted field suffix');
    is_deeply([JQ::Lite::Parser::parse_query('.items[0] . [ ]?')],
        ['.items[0] . [ ]?'],
        'parser preserves rooted iterator suffix');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        'items[0] . [1]')),
        'dotless path with separated dot cannot claim rooted syntax');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[0] . [1+2]')),
        'arithmetic selector is outside literal scanner');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[0] . [0:1]')),
        'slice is outside literal scanner');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[0] . name')),
        'whitespace after dot before an unquoted name stays invalid');
    is_deeply(results('{"items":[[2,3]]}',
        '.items[0][1]'), [3],
        'compact literal numeric path unchanged');
    is_deeply(results('{"items":[[2,3]]}',
        '.items[0] .[1]'), [3],
        'previous spaced dot before adjacent bracket unchanged');
    is_deeply(results('{"a.b":5}', '["a.b"]'), [['a.b']],
        'bare quoted array constructor unchanged');
    is_deeply(results('null', 'try ["catch me"]'),
        [['catch me']], 'prior try array literal unchanged');
    is_deeply(results('null', 'try [ ]'), [[]],
        'previous try empty array literal unchanged');
};

done_testing;
