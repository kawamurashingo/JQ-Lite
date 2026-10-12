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
            "$label: structured error");
        like("$err", qr/\Q$fragment\E/,
            "$label: stage-local error message");
    }
}

subtest 'strict numeric prefixes and whitespace dotted suffixes' => sub {
    is_deeply(results('{"items":[{"name":"A"},{"name":"B"}]}',
        '.items[0] .name'), ['A'],
        'first indexed object then spaced field suffix');
    is_deeply(results('{"items":[{"name":"A"},{"name":"B"}]}',
        '.items[1]  .name'), ['B'],
        'two spaces before dot');
    is_deeply(results('{"items":[{"name":"A"},{"name":"B"}]}',
        ".items[0]\t.name"), ['A'],
        'tab before dot');
    is_deeply(results('{"items":[{"name":"A"}]}',
        '.items[0] ."name"'), ['A'],
        'dot-quoted field after index and whitespace');
    is_deeply(results('{"items":[{"a.b":7}]}',
        '.items[0] ."a.b"'), [7],
        'literal dot inside quoted suffix');
    is_deeply(results('{"items":[{"a.b":7}]}',
        '.items[0] .["a.b"]'), [7],
        'bracket-quoted selector after separated dot');
    is_deeply(results('{"items":[{"a.b":[4,5]}]}',
        '.items[0] .["a.b"][1]'), [5],
        'additional numeric suffix in same path');
    is_deeply(results('{"items":[{"a.b":[4,5]}]}',
        '.items[0] . ["a.b"][0]'), [4],
        'space between suffix dot and quoted bracket');
    is_deeply(results('{"items":[[4,5]]}',
        '.items[0] .[1]'), [5],
        'numeric bracket after spaced dot');
    is_deeply(results('{"items":[[4,5]]}',
        '.items[0] . [ 0 ]'), [4],
        'numeric bracket with spaces after dot');
    is_deeply(results('{"items":[[4,5]]}',
        '.items[0] .[]'), [4,5],
        'strict iterator after spaced dot');
    is_deeply(results('{"items":[[4,5]]}',
        '.items[0] .[ ]?'), [4,5],
        'optional padded iterator after spaced dot');
    is_deeply(results('{"items":[{"name":"A"}]}',
        '.items[0] .name?'), ['A'],
        'optional named suffix keeps value');
    is_deeply(results('{"items":[{}]}',
        '.items[0] .name'), [undef],
        'missing name yields one null');
    is_deeply(results('{"items":[]}',
        '.items[0] .name'), [undef],
        'out-of-range index followed by strict field yields null');
    is_deeply(results('{"items":null}',
        '.items[0] .name'), [undef],
        'null index target followed by field yields null');
    is_deeply(results('{}',
        '.items[0] .name'), [undef],
        'missing prefix followed by field yields null');
    runtime_error('{"items":[7]}',
        '.items[0] .name', 'Cannot index number with string "name"',
        'later strict field error persists');
    runtime_error('{"items":7}',
        '.items[0] .name', 'Cannot index number with number',
        'earlier strict numeric error persists');
    runtime_error('7',
        '.items[0] .name', 'Cannot index number with string "items"',
        'earlier strict named field error persists');
    is_deeply(results('{"items":[7]}',
        '.items[0] .name?'), [],
        'optional named suffix drops invalid numeric target');
};

subtest 'iterator, quoted, and composite audited prefixes' => sub {
    is_deeply(results('{"items":[{"name":"A"},{}]}',
        '.items[] .name'), ['A',undef],
        'each emitted iterator object receives named suffix');
    is_deeply(results('{"items":[{"name":"A"},{}]}',
        '.items[ ] .name'), ['A',undef],
        'padded iterator followed by separated suffix');
    is_deeply(results('{"items":[{"name":"A"},{}]}',
        '.items []? .name'), ['A',undef],
        'optional iterator then strict suffix');
    is_deeply(results('{"obj":{"a.b":{"name":"V"}}}',
        '.obj["a.b"] .name'), ['V'],
        'bracket-quoted strict stage then spaced suffix');
    is_deeply(results('{"obj":{"a.b":{"name":"V"}}}',
        '.obj ["a.b"] .name'), ['V'],
        'whitespace bracket-quoted stage then spaced suffix');
    is_deeply(results('{"obj":{"a.b":{"name":"V"}}}',
        '.obj."a.b" .name'), ['V'],
        'dot-quoted strict stage then spaced suffix');
    is_deeply(results('{"items":[{"name":"A"},{"name":"B"}]}',
        '.[0] .name'), [undef],
        'root array index on object is not silently projected');
    is_deeply(results('[{"name":"A"},{"name":"B"}]',
        '.[0] .name'), ['A'],
        'root positive index then spaced suffix');
    is_deeply(results('{"items":[{"name":"A"},{"name":"B"}]}',
        '.items[-1] .name'), ['B'],
        'signed negative index then spaced suffix');
    is_deeply(results('{"items":[{"name":"A"},{"name":"B"}]}',
        '.items[0] .name, .items[1] .name'), ['A','B'],
        'comma alternatives keep result order');
    is_deeply(results('{"items":[{"name":"A"}]}',
        '.items[0] .name | . + "!"'), ['A!'],
        'pipeline consumes spaced path result');
    runtime_error('{"items":[1]}',
        '.items[] .name', 'Cannot index number with string "name"',
        'iterator member strict error is retained');
    is_deeply(results('{"items":[1]}',
        '.items[] .name?'), [],
        'optional named iterator suffix omits wrong-type item');
};

subtest 'parser boundaries and non-path controls' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[0] .name'),
        [['field','items'],['index',0],['field','name']],
        'parse dotted suffix after strict numeric index');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[] .name'),
        [['field','items'],['iterator',0],['field','name']],
        'parse dotted suffix after iterator');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj["a.b"] .name'),
        [['field','obj'],['field','a.b'],['field','name']],
        'parse quoted prefix and unquoted suffix');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[0] .[1]'),
        [['field','items'],['index',0],['index',1]],
        'parse bracket index after separated dot');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        'items[0] .name')),
        'dotless text is not a newly rooted literal path');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items[0]. name')),
        'whitespace after a dot before bare name not recognized');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.items .name')),
        'unquoted field-only chain stays on legacy path');
    is_deeply([JQ::Lite::Parser::parse_query('.items[0] .name')],
        ['.items[0] .name'],
        'main parser preserves root dot for new syntax');
    is_deeply([JQ::Lite::Parser::parse_query('.items[] .name')],
        ['.items[] .name'],
        'iterator prefix retains root dot');
    is_deeply(results('null', 'try ["catch me"]'),
        [['catch me']], 'try array literal still unchanged');
    is_deeply(results('null', '["a.b"]'),
        [['a.b']], 'bare quoted constructor remains an array');
    is_deeply(results('{"name":"A"}', '.name'), ['A'],
        'bare unquoted named field unchanged');
    is_deeply(results('{"items":[{"name":"A"}]}',
        '.items[0].name'), ['A'],
        'unspaced numeric dotted path remains supported');
};

done_testing;
