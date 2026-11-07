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

subtest 'quoted paths retain nulls in constructors and resolve predicate keys' => sub {
    for my $path ('."a"', '.["a"]', '."a"?', '.["a"]?') {
        for my $input ('{}', 'null', '{"a":null}') {
            is_deeply([$jq->run_query($input, "[$path]")], [[undef]],
                "array keeps null: $input / $path");
            is_deeply([$jq->run_query($input, "{x:$path}")], [{ x => undef }],
                "object keeps null: $input / $path");
        }
        is_deeply([$jq->run_query('{"a":1}', "select($path == null)")], [],
            "existing numeric field is not null: $path");
        is_deeply([$jq->run_query('{"a":1}', "select($path == 1)")], [{ a => 1 }],
            "predicate resolves the real field: $path");
        is_deeply([$jq->run_query('{}', "select($path == null)")], [{}],
            "missing quoted field is null: $path");
        is_deeply([$jq->run_query('null', "select($path == null)")], [undef],
            "null root remains one null: $path");
    }
    is_deeply([$jq->run_query('{"a.b":2}', 'select(.["a.b"] == 2)')],
        [{ 'a.b' => 2 }], 'quoted key period remains literal');
    is_deeply([$jq->run_query('{"a":{"b":2}}', 'select(."a"."b" == 2)')],
        [{ a => { b => 2 } }], 'nested quoted predicate');
};


# A bracketed predicate is not a missing string key. Dispatch the same
# scoped paths as ordinary lookups before a null comparison.
subtest 'unquoted bracket selectors resolve real predicate values' => sub {
    my $input = '{"a":[1],"i":0}';
    for my $path ('.a[-1]', '.a[ 0 ]', '.a[.i]', '.a[0]') {
        is_deeply([$jq->run_query($input, "select($path == null)")],
            [], "existing indexed value is not null: $path");
        is_deeply([$jq->run_query($input, "select($path == 1)")],
            [{a => [1], i => 0}], "numeric selector resolves 1: $path");
    }
    is_deeply([$jq->run_query('{"a":[{}]}',
        'select(.a[0].b == null)')], [{a => [{}]}],
        'missing indexed field is one null');
    is_deeply([$jq->run_query('{"a":[{"b":2}]}',
        'select(.a[0].b == null)')], [],
        'indexed existing field is not a missing null');
    is_deeply([$jq->run_query('{"a":[]}',
        'select(.a[].b == null)')], [],
        'empty iterator does not fabricate a null predicate value');
};


# Promotion review: a missing/null named slice is one JSON null in
# comparison operands, just as in constructors. An empty array slice is
# an array value and a genuinely empty iterator is still no output.
subtest 'named slice comparisons retain null without inventing streams' => sub {
    for my $input ('{}', 'null', '{"a":null}') {
        is_deeply([$jq->run_query($input, '.a[0:1] == null')],
            [JSON::PP::true], "missing/null slice equals null: $input");
        is_deeply([$jq->run_query($input, '.a[0:1] != 0')],
            [JSON::PP::true], "missing/null slice differs from 0: $input");
        is_deeply([$jq->run_query($input, 'null == .a[0:1]')],
            [JSON::PP::true], "RHS missing/null slice equals null: $input");
        my $expected = JSON::PP->new->decode($input);
        is_deeply([$jq->run_query($input, 'select(.a[0:1] == null)')],
            [$expected], "select keeps null-valued named slice: $input");
    }

    is_deeply([$jq->run_query('{"a":{}}', '.a.b[0:1] == null')],
        [JSON::PP::true], 'nested missing named slice is null');
    is_deeply([$jq->run_query('{"a":{"b":null}}', '.a.b[0:1] == null')],
        [JSON::PP::true], 'nested explicit null slice is null');
    is_deeply([$jq->run_query('{}', '.a[:1] == null')],
        [JSON::PP::true], 'missing named slice with omitted start');
    is_deeply([$jq->run_query('{}', '.a[0:] == null')],
        [JSON::PP::true], 'missing named slice with omitted end');
    is_deeply([$jq->run_query('{"a":[]}', '.a[0:1] == null')],
        [JSON::PP::false], 'existing empty array slice is not null');
    is_deeply([$jq->run_query('{"a":[]}', '.a[0:1] == []')],
        [JSON::PP::true], 'existing empty array slice equals empty array');
    is_deeply([$jq->run_query('{"a":[3,4]}', '.a[0:1] == [3]')],
        [JSON::PP::true], 'existing array slice comparison unchanged');
    is_deeply([$jq->run_query('{"a":[]}', '.a[] == null')],
        [], 'empty iterator comparison remains zero results');
    is_deeply([$jq->run_query('{"a":[]}', 'select(.a[] == null)')],
        [], 'empty iterator predicate does not invent null');
    # A computed bound can itself be an empty stream: neither plain
    # comparison nor select() may reinterpret it as a missing-field null.
    for my $input ('{}', '{"a":[1,2]}') {
        for my $slice ('.a[empty:1]', '.a[0:empty]') {
            is_deeply([$jq->run_query($input, "$slice == null")], [],
                "computed empty slice bound gives no comparison: $input / $slice");
            is_deeply([$jq->run_query($input, "select($slice == null)")], [],
                "computed empty slice bound gives no selection: $input / $slice");
        }
    }
};


# Main-target Codex review: nonliteral bracket arrays used as comparison
# operands must be evaluated as filters rather than legacy index paths.
subtest 'array constructor comparison operands retain their values' => sub {
    my @cases = (
        ['{"a":1}', '[.a] == [1]', JSON::PP::true],
        ['{"a":1}', '[.a] == [.a]', JSON::PP::true],
        ['{"a":1}', '[.a] != [2]', JSON::PP::true],
        ['{"a":1}', '[.a] == []', JSON::PP::false],
        ['{"a":1}', 'null == [.a]', JSON::PP::false],
        ['{"a":1}', '[.a] == [.b]', JSON::PP::false],
        ['{"a":1,"b":2}', '[.a, .b] == [1, 2]', JSON::PP::true],
        ['{"a":null}', '[.a] == [null]', JSON::PP::true],
        ['{}', '[.a] == [.a]', JSON::PP::true],
        ['{}', '["literal"] == ["literal"]', JSON::PP::true],
        ['{}', '[1] == [1]', JSON::PP::true],
    );
    for my $case (@cases) {
        my ($input, $filter, $expected) = @$case;
        is_deeply([$jq->run_query($input, $filter)], [$expected],
            "comparison array constructor: $filter on $input");
    }
};

# Root slice on JSON null is one null result, including in constructors.
# The empty-bound variant must stay an empty stream, not a synthesized null.
subtest 'null root slice constructors retain null and empty streams' => sub {
    for my $slice ('.[0:1]', '.[:1]', '.[0:]', '.[1:1]') {
        is_deeply([$jq->run_query('null', "[$slice]")], [[undef]],
            "root slice array constructor: $slice");
        is_deeply([$jq->run_query('null', "{x:$slice}")], [{x => undef}],
            "root slice object constructor: $slice");
    }
    is_deeply([$jq->run_query('null', '[.[0:empty]]')], [[]],
        'empty upper-bound stream makes empty array constructor');
    is_deeply([$jq->run_query('null', '{x:.[empty:1]}')], [],
        'empty lower-bound stream makes no object constructor');
    is_deeply([$jq->run_query('[]', '[.[0:1]]')], [[[]]],
        'existing empty array root slice stays an empty array value');
    is_deeply([$jq->run_query('null', '.[0:1] == null')],
        [JSON::PP::true], 'direct null root slice comparison remains true');
    # Named slices with computed `empty` bounds also retain zero results
    # when their source is absent, an explicit null, or the root is null.
    for my $input ('null', '{}', '{"a":null}') {
        for my $slice ('.a[empty:1]', '.a[0:empty]') {
            is_deeply([$jq->run_query($input, "[$slice]")], [[]],
                "named computed empty bound in array: $input / $slice");
            is_deeply([$jq->run_query($input, "{x:$slice}")], [],
                "named computed empty bound in object: $input / $slice");
        }
    }
};

# Codex follow-up: a literal JSON null slice bound is a value, not
# the zero-output stream from the filter `empty`. Preserve both named
# missing-field and root-null slice values inside constructors.
subtest 'null-valued slice bounds remain values in constructors' => sub {
    for my $input ('null', '{}', '{"a":null}') {
        for my $bounds ('null:1', '0:null', 'null:null') {
            my $slice = ".a[$bounds]";
            is_deeply([$jq->run_query($input, "[$slice]")], [[undef]],
                "named null bound in array constructor: $input / $slice");
            is_deeply([$jq->run_query($input, "{x:$slice}")], [{x => undef}],
                "named null bound in object constructor: $input / $slice");
        }
    }
    my @present = (
        ['null:1', [1]],
        ['0:null', [1,2]],
        ['null:null', [1,2]],
    );
    for my $case (@present) {
        my ($bounds, $expected) = @$case;
        my $slice = ".a[$bounds]";
        is_deeply([$jq->run_query('{"a":[1,2]}', "[$slice]")],
            [[$expected]], "present named null bound array: $slice");
        is_deeply([$jq->run_query('{"a":[1,2]}', "{x:$slice}")],
            [{x => $expected}], "present named null bound object: $slice");
    }
    for my $bounds ('null:1', '0:null', 'null:null') {
        my $slice = ".[$bounds]";
        is_deeply([$jq->run_query('null', "[$slice]")], [[undef]],
            "root-null slice bound in array constructor: $slice");
        is_deeply([$jq->run_query('null', "{x:$slice}")], [{x => undef}],
            "root-null slice bound in object constructor: $slice");
    }
    for my $case (@present) {
        my ($bounds, $expected) = @$case;
        my $slice = ".[$bounds]";
        is_deeply([$jq->run_query('[1,2]', "[$slice]")], [[$expected]],
            "present root null bound array: $slice");
        is_deeply([$jq->run_query('[1,2]', "{x:$slice}")], [{x => $expected}],
            "present root null bound object: $slice");
    }
};

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

subtest 'strict root dot-quoted fields' => sub {
    is_deeply(results('{"a.b":7}', '."a.b"'), [7],
        'dot in name is literal');
    is_deeply(results('{"full name":"Ada"}', '."full name"'), ['Ada'],
        'space in root name');
    is_deeply(results('{"":8}', '.""'), [8],
        'empty quoted field name');
    is_deeply(results('{"]":9}', '."]"'), [9],
        'bracket-shaped character stays a string key');
    is_deeply(results('{"[0]":10}', '."[0]"'), [10],
        'numeric bracket text stays a string key');
    is_deeply(results('{"a+b":11}', '."a+b"'), [11],
        'plus sign not arithmetic');
    is_deeply(results('{"a-b":12}', '."a-b"'), [12],
        'minus sign not arithmetic');
    is_deeply(results('{"a/b":13}', '."a/b"'), [13],
        'slash sign not arithmetic');
    is_deeply(results('{"a|=b":14}', '."a|=b"'), [14],
        'update assignment marker not an update');
    is_deeply(results('{"a,b":15}', '."a,b"'), [15],
        'comma inside key not a sequence');
    is_deeply(results('{"a\\"b":16}', '."a\\"b"'), [16],
        'escaped quote is decoded');
    is_deeply(results('{"a\\\\b":17}', '."a\\\\b"'), [17],
        'escaped backslash is decoded');
    is_deeply(results('{"a.b":18}', '."a\\u002eb"'), [18],
        'Unicode escape is decoded to dot');
    is_deeply(results('{}', '."a.b"'), [undef],
        'missing root key emits one null');
    is_deeply(results('null', '."a.b"'), [undef],
        'null input emits one null');
    is_deeply(results('{"a.b":false}', '."a.b"'),
        [JSON::PP::false], 'false member remains false');
    runtime_error('7', '."a.b"',
        'Cannot index number with string "a.b"',
        'numeric input rejected by strict named stage');
    runtime_error('true', '."a.b"',
        'Cannot index boolean with string "a.b"',
        'boolean input rejected');
    runtime_error('"abc"', '."a.b"',
        'Cannot index string with string "a.b"',
        'string input rejected');
    runtime_error('[]', '."a.b"',
        'Cannot index array with string "a.b"',
        'array input rejected');
};

subtest 'strict dot-quoted fields in composite paths' => sub {
    is_deeply(results('{"obj":{"a.b":{"name":"A"}}}',
        '.obj."a.b".name'), ['A'],
        'special quoted middle field');
    is_deeply(results('{"obj":{"a.b":{"full name":"Ada"}}}',
        '.obj."a.b"."full name"'), ['Ada'],
        'two consecutive strict dot-quoted fields');
    is_deeply(results('{"outer":{"a.b":7}}',
        '."outer"."a.b"'), [7],
        'strict quoted root and quoted suffix');
    is_deeply(results('{"a.b":{"name":"A"}}',
        '."a.b".name'), ['A'],
        'strict unquoted suffix');
    is_deeply(results('{"obj":{"a.b":[10,20]}}',
        '.obj."a.b"[1]'), [20],
        'strict numeric index after dot-quoted key');
    is_deeply(results('{"obj":{"a.b":[10,20]}}',
        '.obj."a.b"[-1]'), [20],
        'negative index after dot-quoted key');
    is_deeply(results('{"obj":{"a.b":null}}',
        '.obj."a.b".name'), [undef],
        'null through subsequent strict field');
    is_deeply(results('{"obj":{}}', '.obj."a.b".name'),
        [undef], 'missing field through strict suffix');
    is_deeply(results('{}', '.obj."a.b".name'),
        [undef], 'missing strict prefix yields null');
    runtime_error('{"obj":7}', '.obj."a.b".name',
        'Cannot index number with string "a.b"',
        'bad quoted target fails');
    runtime_error('7', '.obj."a.b".name',
        'Cannot index number with string "obj"',
        'strict earlier unquoted field still errors');
    runtime_error('{"obj":{"a.b":7}}', '.obj."a.b".name',
        'Cannot index number with string "name"',
        'strict later unquoted field still errors');
    is_deeply(results('{"obj":{"a.b":7}}', '.obj."a.b".name?'),
        [], 'later optional field skips scalar target');
    is_deeply(results('{"obj":{"a.b":7}}',
        '.obj."a.b", .obj["a.b"]'), [7,7],
        'dot and bracket quoted alternatives preserve order');
    is_deeply(results('{"obj":{"a.b":7}}',
        '.obj."a.b" | . + 1'), [8],
        'piped result from strict dot-quoted field');
};

subtest 'bare string literal must not become field access' => sub {
    is_deeply(results('{"a.b":7}', '"a.b"'), ['a.b'],
        'bare JSON quoted text remains a literal');
    is_deeply(results('7', '"a.b"'), ['a.b'],
        'string literal independent of input type');
    is_deeply(results('{"a":7}', '"a"'), ['a'],
        'bare short string literal is not a field lookup');
    is_deeply(results('{"a.b":7}', '["a.b"]'), [['a.b']],
        'bare bracket array constructor stays an array');
    is_deeply(results('{"a.b":7}', '."a.b"'), [7],
        'adding root dot changes literal to lookup');
    is_deeply(results('{"a.b":7}', '.["a.b"]'), [7],
        'bracket-quoted field still works');
};

subtest 'parser and dispatch boundaries' => sub {
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '."a.b"'), [['field','a.b']],
        'rooted strict dot-quoted parser recognition');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '"a.b"')), 'unrooted JSON literal is not a scoped path');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj."a.b"'), [['field','obj'],['field','a.b']],
        'strict quoted suffix in full path');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj."a.b".name'),
        [['field','obj'],['field','a.b'],['field','name']],
        'strict suffix after dot-quoted step');
    is_deeply([JQ::Lite::Parser::parse_query('."a.b"')],
        ['."a.b"'], 'parser keeps leading dot for strict quoted root');
    is_deeply([JQ::Lite::Parser::parse_query('"a.b"')],
        ['"a.b"'], 'bare quoted string stays literal');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj["a.b"]'),
        [['field','obj'],['field','a.b']],
        'prior strict bracket-quoted parsing unchanged');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj.name')), 'strict unquoted path remains outside scope');
    is_deeply(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[1]'), [['field','obj'],['index',1]],
        'strict positive path now uses scoped visitor');
    my @unused;
    ok(!JQ::Lite::Filters::apply($jq, '."a.b"',
        [{'a.b' => 7}], \@unused),
        'strict root dot-quoted field bypasses legacy filter shortcuts');
    is_deeply(results('{"a b":2}', '."a b"'), [2],
        'previous dot-quoted field access unchanged');
    is_deeply(results('{"items":[{"a.b":7}]}',
        '.items[]."a.b"'), [7],
        'previous quoted iterator path unchanged');
};

done_testing;
