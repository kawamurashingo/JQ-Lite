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

# A numeric slice bound is still a value when written using JSON
# fractional, signed, or scientific notation. On null/missing sources it
# must not be mistaken for the empty output stream of the filter 'empty'.
subtest 'numeric literal slice spellings preserve value streams' => sub {
    my @cases = (
        ['0e0:1', [1]],
        ['2E+0:3', [3]],
        ['-1:2', []],
        ['0.5:2', [1,2]],
        ['1e-1:2', [1,2]],
    );
    for my $case (@cases) {
        my ($bounds, $expected) = @$case;
        my $named = ".a[$bounds]";
        my $root = ".[$bounds]";
        for my $input ('null', '{}', '{"a":null}') {
            is_deeply([$jq->run_query($input, "[$named]")], [[undef]],
                "named numeric spelling in null array: $input / $named");
            is_deeply([$jq->run_query($input, "{x:$named}")], [{x => undef}],
                "named numeric spelling in null object: $input / $named");
        }
        is_deeply([$jq->run_query('{"a":[1,2,3]}', "[$named]")],
            [[$expected]], "named numeric spelling present array: $named");
        is_deeply([$jq->run_query('{"a":[1,2,3]}', "{x:$named}")],
            [{x => $expected}], "named numeric spelling present object: $named");
        is_deeply([$jq->run_query('null', "[$root]")], [[undef]],
            "root numeric spelling null array: $root");
        is_deeply([$jq->run_query('null', "{x:$root}")], [{x => undef}],
            "root numeric spelling null object: $root");
        is_deeply([$jq->run_query('[1,2,3]', "[$root]")],
            [[$expected]], "root numeric spelling present array: $root");
        is_deeply([$jq->run_query('[1,2,3]', "{x:$root}")],
            [{x => $expected}], "root numeric spelling present object: $root");
    }
};

# jq uses floor for a fractional array slice start and ceil for its end.
# This differs from the legacy slice() builtin, whose rounding is unchanged.
subtest 'fractional slice upper bounds use jq rounding' => sub {
    my @cases = (
        ['0:1.5', [1,2]],
        ['0:1e-1', [1]],
        ['1.5:2.5', [2,3]],
        ['-2.5:-0.5', [1,2,3]],
        ['2.2:2.4', [3]],
        ['0:0.1', [1]],
        ['0:1.0', [1]],
        ['-1.5:-0.5', [2,3]],
    );
    for my $case (@cases) {
        my ($bounds, $expected) = @$case;
        for my $form ('.a', '.') {
            my $input = $form eq '.' ? '[1,2,3]' : '{"a":[1,2,3]}';
            my $slice = "$form\[$bounds]";
            is_deeply([$jq->run_query($input, "[$slice]")], [[$expected]],
                "fractional upper bound in array: $slice");
            is_deeply([$jq->run_query($input, "{x:$slice}")], [{x => $expected}],
                "fractional upper bound in object: $slice");
        }
    }
};

# Bracket-bound filters evaluate to streams. Parenthesized expressions
# returning null/number are not the zero-output stream emitted by empty.
subtest 'computed slice bounds distinguish null values from empty' => sub {
    for my $input ('null', '{}', '{"a":null}') {
        for my $bounds ('(null):1', '(0):1', '((null)):1',
                        '(1+1):3', 'null:(1+0)') {
            my $slice = ".a[$bounds]";
            is_deeply([$jq->run_query($input, "[$slice]")], [[undef]],
                "computed value bound in array: $input / $slice");
            is_deeply([$jq->run_query($input, "{x:$slice}")], [{x => undef}],
                "computed value bound in object: $input / $slice");
        }
        my $empty = '.a[(empty):1]';
        is_deeply([$jq->run_query($input, "[$empty]")], [[]],
            "computed empty bound in array: $input");
        is_deeply([$jq->run_query($input, "{x:$empty}")], [],
            "computed empty bound in object: $input");
    }
    my @present = (
        ['(null):1', [1]],
        ['(0):1', [1]],
        ['(1+1):3', [3]],
        ['(empty):1', undef],
        ['(.i):2', [2]],
    );
    for my $case (@present) {
        my ($bounds, $expected) = @$case;
        my $slice = ".a[$bounds]";
        my $array = [$jq->run_query('{"a":[1,2,3],"i":1}', "[$slice]")];
        my $object = [$jq->run_query('{"a":[1,2,3],"i":1}', "{x:$slice}")];
        is_deeply($array, defined($expected) ? [[$expected]] : [[]],
            "computed bound on populated array: $slice");
        is_deeply($object, defined($expected) ? [{x => $expected}] : [],
            "computed bound on populated object: $slice");
    }
    for my $bounds ('(null):1', '(0):1', '(empty):1') {
        my $slice = ".[$bounds]";
        my $emits = $bounds !~ /empty/;
        is_deeply([$jq->run_query('null', "[$slice]")],
            $emits ? [[undef]] : [[]],
            "computed root bound on null in array: $slice");
        is_deeply([$jq->run_query('null', "{x:$slice}")],
            $emits ? [{x => undef}] : [],
            "computed root bound on null in object: $slice");
    }
};

# Computed bounds retain every value of comma/arithmetic streams and do
# not evaluate an end bound after the start yields an empty stream.
subtest 'computed arithmetic slice bounds preserve jq streams' => sub {
    my @cases = (
        ['{"a":[1,2,3]}', '[.a[((0,1)+1):3]]', [[[2,3],[3]]]],
        ['{"a":[1,2,3]}', '[.a[(empty+1):3]]', [[]]],
        ['{"a":[1,2,3]}', '[.a[0:(1,2)]]', [[[1],[1,2]]]],
        ['{"a":[1,2,3]}', '{x:.a[(0,1):3]}',
            [{x => [1,2,3]}, {x => [2,3]}]],
        ['null', '[.a[((0,1)+1):3]]', [[undef,undef]]],
        ['{}', '[.a[((0,1)+1):3]]', [[undef,undef]]],
        ['[1,2,3]', '[.[(empty):(1/0)]]', [[]]],
        ['[1,2,3]', '{x:.[(empty):(1/0)]}', []],
        ['{"a":[1,2,3]}', '[.a[(empty):(1/0)]]', [[]]],
        ['[1,2,3]', '[.[0:(1,2)]]', [[[1],[1,2]]]],
        ['{"a":[1,2,3]}', '[.a[(1+1):3]]', [[[3]]]],
        ['{"a":[1,2,3]}', '{x:.a[(empty+1):3]}', []],
        ['{"a":[1,2,3],"b":[7,8,9]}',
            '{x:.a[(0,1):3],y:.b[(0,1):3]}',
            [
                {x => [1,2,3], y => [7,8,9]},
                {x => [1,2,3], y => [8,9]},
                {x => [2,3], y => [7,8,9]},
                {x => [2,3], y => [8,9]},
            ]],
        ['{"a":[1,2,3]}', '{x:.a[(0,1):3],y:empty}', []],
    );
    for my $case (@cases) {
        my ($input, $filter, $expected) = @$case;
        is_deeply([$jq->run_query($input, $filter)], $expected,
            "computed-bound stream parity: $filter on $input");
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


# Codex review: computed addition bounds evaluate RHS first and preserve
# its stream-major order, including errors on reachable RHS expressions.
subtest 'slice-bound addition follows jq RHS-first stream order' => sub {
    my $input = '{"a":[0,1,2]}';
    is_deeply([$jq->run_query($input, '[.a[((0,1)+(0,2)):3]]')],
        [[[0,1,2], [1,2], [2], []]],
        'both operands emit values in right-major order');
    is_deeply([$jq->run_query($input, '{x:.a[((0,1)+(0,2)):3]}')],
        [
            {x => [0,1,2]}, {x => [1,2]},
            {x => [2]}, {x => []},
        ], 'right-major order retained in object constructor');
    is_deeply([$jq->run_query($input, '[.a[((1/0)+empty):3]]')],
        [[]], 'empty RHS suppresses evaluation of throwing LHS');
    runtime_error($input, '[.a[(empty+(1/0)):3]]',
        'Division by zero', 'throwing RHS evaluated before empty LHS');
};

# A fractional index cannot turn a bad opposite bound (including a
# numeric-looking JSON string) into an accepted numeric index.
subtest 'fractional slices validate both index types' => sub {
    my $input = '{"a":[0,1,2]}';
    # The legacy slice() path throws a plain Perl runtime error, whereas
    # strict quoted-field lookup wraps JQ::Lite::Error::Evaluation.
    # Preserve the slice error contract rather than changing production API.
    my $slice_error = sub {
        my ($filter, $fragment, $label) = @_;
        my $ok = eval { $jq->run_query($input, $filter); 1 };
        my $error = $@;
        ok(!$ok, "$label: fails");
        like("$error", qr/\Q$fragment\E/, "$label: numeric validation");
    };
    $slice_error->('[.a[5e-1:"x"]]',
        'slice(): length must be numeric', 'invalid end after fractional start');
    $slice_error->('{x:.a[5e-1:"x"]}',
        'slice(): length must be numeric', 'object constructor validates end');
    $slice_error->('[.a["0.5":2]]',
        'slice(): start must be numeric', 'numeric-looking string start rejected');
    $slice_error->('[.a[0.5:"2"]]',
        'slice(): length must be numeric', 'numeric-looking string end rejected');
    is_deeply([$jq->run_query($input, '[.a[0.5:2]]')],
        [[[0,1]]], 'valid fractional bounds still round as before');
};


# jq pipe binds after comma: each preceding bound value must flow through
# every following pipe stage. In particular, empty suppresses them all.
subtest 'computed slice-bound pipelines consume complete comma streams' => sub {
    my $input = '{"a":[0,1,2]}';
    my @cases = (
        ['[.a[(0,1 | empty):3]]', [[]]],
        ['{x:.a[(0,1 | empty):3]}', []],
        ['[.a[(0,1 | .+1):3]]', [[[1,2],[2]]]],
        ['{x:.a[(0,1 | .+1):3]}', [{x => [1,2]}, {x => [2]}]],
        ['[.a[(0,1 | empty,2):3]]', [[[2],[2]]]],
        ['[.a[(0,1 | .+1 | .+1):3]]', [[[2],[]]]],
        ['[.a[(0,1 | (empty,2)):3]]', [[[2],[2]]]],
    );
    for my $case (@cases) {
        my ($filter, $expected) = @$case;
        is_deeply([$jq->run_query($input, $filter)], $expected,
            "slice-bound pipeline: $filter");
    }
    is_deeply([$jq->run_query('{}', '[.a[(0,1 | empty):3]]')],
        [[]], 'missing named slice still respects empty pipeline');
    is_deeply([$jq->run_query('null', '[.[(0,1 | empty):3]]')],
        [[]], 'null root slice still respects empty pipeline');
};


# A pipeline must finish each input's downstream stages before evaluating
# the next input. Both error precedence and observable output order matter.
subtest 'computed slice pipelines are depth-first across stages' => sub {
    my $input = '{"a":[0,1,2]}';
    is_deeply([$jq->run_query($input, 'try [.a[(0,"x" | .+1 | 1/0):3]] catch contains("zero")')],
        [JSON::PP::true], 'first source reaches division before next input addition');
    is_deeply([$jq->run_query($input, 'try {x:.a[(0,"x" | .+1 | 1/0):3]} catch contains("zero")')],
        [JSON::PP::true], 'object constructor observes same early error');
    is_deeply([$jq->run_query($input, 'try [.a[(0,(1/0) | "x"+1):3]] catch contains("zero")')],
        [JSON::PP::false], 'later upstream division must not preempt first downstream type error');
    is_deeply([$jq->run_query($input, 'try [.a[(0,(1/0) | "x"+1):3]] catch contains("string")')],
        [JSON::PP::true], 'first downstream type error is handled');
    is_deeply([$jq->run_query($input, 'try [.a[(0,"x" | .+1 | 1/0):3]] catch contains("string")')],
        [JSON::PP::false], 'first downstream division preempts later input');
    is_deeply([$jq->run_query($input, '[.a[(0,1 | (.+1,.+2) | (.+0,.+1)):3]]')],
        [[[1,2],[2],[2],[],[2],[],[],[]]], 'nested alternatives preserve depth-first output order');
};


# Bound streams must feed their outputs into slice application immediately.
# A bad first index must beat a later start/end division under try/catch.
subtest 'computed slices apply bound pairs before reading later values' => sub {
    my $input = '{"a":[0,1,2]}';
    is_deeply([$jq->run_query($input, 'try [.a[("x",1/0):3]] catch contains("zero")')],
        [JSON::PP::false], 'start type failure precedes next start expression');
    is_deeply([$jq->run_query($input, 'try [.a[0:("x",1/0)]] catch contains("zero")')],
        [JSON::PP::false], 'end type failure precedes next end expression');
    is_deeply([$jq->run_query($input, 'try {x:.a[("x",1/0):3]} catch contains("zero")')],
        [JSON::PP::false], 'object constructor start ordering');
    is_deeply([$jq->run_query($input, 'try {x:.a[0:("x",1/0)]} catch contains("zero")')],
        [JSON::PP::false], 'object constructor end ordering');
    is_deeply([$jq->run_query($input, 'try [.a[(0,"x",1/0):3]] catch contains("zero")')],
        [JSON::PP::false], 'successful slice before failing start');
    is_deeply([$jq->run_query($input, 'try [.a[0:(0,"x",1/0)]] catch contains("zero")')],
        [JSON::PP::false], 'successful slice before failing end');
    is_deeply([$jq->run_query($input, '[.a[(0,1):(1,2)]]')],
        [[[0],[0,1],[],[1]]], 'start-major end-minor Cartesian ordering');
    is_deeply([$jq->run_query($input, '[.a[(0,1):empty]]')],
        [[]], 'end empty still emits no slices');
    is_deeply([$jq->run_query($input, '[.a[empty:(1/0)]]')],
        [[]], 'start empty still avoids evaluating end');
};



# Conditional branch streams must be consumed in lockstep with slice
# application; otherwise a later error incorrectly wins under try/catch.
subtest 'computed conditional bound streams emit before later errors' => sub {
    my $input = '{"a":[0,1,2]}';
    is_deeply([$jq->run_query($input, 'try [.a[(if true then ("x",1/0) else 0 end):3]] catch contains("zero")')],
        [JSON::PP::false], 'conditional start first type error beats later division');
    is_deeply([$jq->run_query($input, 'try [.a[0:(if true then ("x",1/0) else 3 end)]] catch contains("zero")')],
        [JSON::PP::false], 'conditional end first type error beats later division');
    is_deeply([$jq->run_query($input, 'try {x:.a[(if true then ("x",1/0) else 0 end):3]} catch contains("zero")')],
        [JSON::PP::false], 'conditional object start short circuits');
    is_deeply([$jq->run_query($input, 'try {x:.a[0:(if true then ("x",1/0) else 3 end)]} catch contains("zero")')],
        [JSON::PP::false], 'conditional object end short circuits');
    is_deeply([$jq->run_query($input, '[.a[(if true then (0,1) else 2 end):3]]')],
        [[[0,1,2],[1,2]]], 'then branch emits every start');
    is_deeply([$jq->run_query($input, '[.a[(if false then 0 else (1,2) end):3]]')],
        [[[1,2],[2]]], 'else branch emits every start');
    is_deeply([$jq->run_query($input, '[.a[(if true then (if false then 0 else (1,2) end) else 0 end):3]]')],
        [[[1,2],[2]]], 'nested conditional branches retain streams');
    is_deeply([$jq->run_query($input, '[.a[(if false then 0 elif true then (1,2) else 0 end):3]]')],
        [[[1,2],[2]]], 'elif conditional emits streams');
    is_deeply([$jq->run_query($input, 'try [.a[(if true then (0,"x",1/0) else 2 end):3]] catch contains("zero")')],
        [JSON::PP::false], 'valid initial slice followed by invalid index');
    is_deeply([$jq->run_query($input, '[.a[((if true then (0,1) else 2 end) | .+1):3]]')],
        [[[1,2],[2]]], 'conditional stream flows to downstream pipeline');
    is_deeply([$jq->run_query($input, '[.a[(if (true,false) then (0,1) else 2 end):3]]')],
        [[[0,1,2],[1,2],[2]]], 'each condition value selects branch independently');
    is_deeply([$jq->run_query($input, '[.a[(if empty then 0 else 2 end):3]]')],
        [[]], 'empty condition does not evaluate else');
};


# A streamed conditional test must retain jq operator precedence: '+' binds
# inside comparisons, and comparisons bind inside boolean and/or. Preserve
# both value results and their use as slice bounds (start and end).
subtest 'conditional bound comparisons keep arithmetic precedence' => sub {
    my $input = '{"a":[0,1,2]}';
    my @cases = (
        ['[.a[(if (1+1 == 2) then 0 else 1 end):3]]', '[[[0,1,2]]]', 'eq-start'],
        ['[.a[0:(if (1+1 == 2) then 2 else 1 end)]]', '[[[0,1]]]', 'eq-end'],
        ['{x:.a[(if (1+1 == 2) then 0 else 1 end):3]}', '[{"x":[0,1,2]}]', 'eq-object-start'],
        ['[.a[(if (1+1 != 2) then 0 else 1 end):3]]', '[[[1,2]]]', 'ne-false-start'],
        ['[.a[(if (1+1 <= 2 and 2+2 == 4) then 0 else 1 end):3]]', '[[[0,1,2]]]', 'compound-and'],
        ['[.a[(if (1+1 > 2 or 3+1 == 4) then 0 else 1 end):3]]', '[[[0,1,2]]]', 'compound-or'],
        ['[.a[(if (1+1 == 3 or 1+2 == 3) then 0 else 1 end):3]]', '[[[0,1,2]]]', 'compound-or-second'],
        ['[.a[(if (1+1 == 2 and 2+2 < 5) then 0 else 1 end):3]]', '[[[0,1,2]]]', 'compound-and-second'],
        ['[.a[(if (1+1 == 2) then (0,1) else 2 end):3]]', '[[[0,1,2],[1,2]]]', 'eq-then-stream'],
        ['[.a[(if (1+1 == 2) then (if (3+1 == 4) then 1 else 2 end) else 0 end):3]]', '[[[1,2]]]', 'eq-nested-if'],
        ['[.a[(if (3-1 >= 2) then 0 else 1 end):3]]', '[[[0,1,2]]]', 'ge-subtract'],
        ['[.a[(if (2+2 > 4) then 0 else 1 end):3]]', '[[[1,2]]]', 'gt-false'],
    );
    for my $case (@cases) {
        my ($filter, $expected_json, $label) = @$case;
        is_deeply([$jq->run_query($input, $filter)],
            JSON::PP->new->decode($expected_json),
            "comparison precedence: $label");
    }
};

# The alternative operator binds outside boolean or/and in slice-bound
# conditionals. A false/null/empty left stream triggers its RHS once,
# while valid values and first-error ordering are preserved.
subtest 'computed slice alternatives respect boolean precedence' => sub {
    my $input = '{"a":[0,1,2]}';
    my @cases = (
        ['[.a[(if (empty or true // false) then 0 else 1 end):3]]', '[[[1,2]]]', 'or-empty-fallback'],
        ['[.a[(if (empty and true // false) then 0 else 1 end):3]]', '[[[1,2]]]', 'and-empty-fallback'],
        ['[.a[0:(if (empty or true // false) then 2 else 1 end)]]', '[[[0]]]', 'end-empty-fallback'],
        ['{x:.a[(if (empty or true // false) then 0 else 1 end):3]}', '[{"x":[1,2]}]', 'object-empty-fallback'],
        ['[.a[(if (true and false // true) then 0 else 1 end):3]]', '[[[0,1,2]]]', 'and-false-fallback'],
        ['[.a[(if (false or false // true) then 0 else 1 end):3]]', '[[[0,1,2]]]', 'or-false-fallback'],
        ['[.a[(if (false or true // false) then 0 else 1 end):3]]', '[[[0,1,2]]]', 'or-true-no-fallback'],
        ['[.a[(if (null or true // 0) then 0 else 1 end):3]]', '[[[0,1,2]]]', 'or-null-left'],
        ['[.a[(if (false // true or false) then 0 else 1 end):3]]', '[[[0,1,2]]]', 'nested-bool-fallback'],
        ['[.a[((null,1) // 0):3]]', '[[[1,2]]]', 'null-and-value-stream'],
        ['[.a[((null,false) // 1):3]]', '[[[1,2]]]', 'only-false-null-stream'],
        ['[.a[(empty // 1 // 0):3]]', '[[[1,2]]]', 'nested-alternatives'],
        ['[.a[(0 // 2):3]]', '[[[0,1,2]]]', 'zero-valid'],
        ['[.a[(if ((null // true) and true) then 0 else 1 end):3]]', '[[[0,1,2]]]', 'inner-fallback-before-and'],
        ['[.a[(if ("a//b" == "a//b") then 0 else 1 end):3]]', '[[[0,1,2]]]', 'quoted-slashes'],
        ['[.a[(if (true, false // true) then 0 else 1 end):3]]', '[[[0,1,2],[0,1,2]]]', 'comma-with-fallback'],
        ['[.a[(if (empty or true // false) then (0,1) else 2 end):3]]', '[[[2]]]', 'multiple-if-values'],
        ['[.a[(if (empty and true // false) then 0 else 1 end):(if (empty or true // false) then 3 else 2 end)]]', '[[[1]]]', 'start-and-end-bools'],
        ['try [.a[(("x",1/0) // 0):3]] catch contains("zero")', '[false]', 'first-invalid-before-division'],
        ['try [.a[((null,"x",1/0) // 0):3]] catch contains("zero")', '[false]', 'null-first-invalid-before-division'],
    );
    for my $case (@cases) {
        my ($filter, $expected_json, $label) = @$case;
        is_deeply([$jq->run_query($input, $filter)],
            JSON::PP->new->decode($expected_json),
            "alternative precedence: $label");
    }
};


# Main-target review: complete computed slices are filter streams even when
# arithmetic appears in their bound expressions; preserve empty/multi-output.
subtest 'computed slice filters keep all emitted values' => sub {
    my @cases = (
        ['[0,1,2]', '.[(0+0):(empty)]', '[]'],
        ['[0,1,2]', '.[(0+0):(1,2)]', '[[0],[0,1]]'],
        ['{"a":[0,1,2]}', '.a[(0+0):(1,2)]', '[[0],[0,1]]'],
        ['[0,1,2]', '.[(0+0):(1,2)] | length', '[1,2]'],
        ['[0,1,2]', '.[(empty):1]', '[]'],
        ['[0,1,2]', '.[(0+0):1]', '[[0]]'],
    );
    for my $case (@cases) {
        my ($input, $filter, $expected_json) = @$case;
        is_deeply([$jq->run_query($input, $filter)],
            JSON::PP->new->decode($expected_json),
            "computed slice stream: $input / $filter");
    }
};

# Fractional and parenthesized bounds in comparison operands must use the
# same null-aware value route as constructor slices, never legacy traversal.
subtest 'comparison slices preserve null and zero-output bounds' => sub {
    my @cases = (
        ['{}', '.a[0.5:1] == null', '[true]'],
        ['{}', '.a[(0):1] == null', '[true]'],
        ['null', '.a[0.5:1] == null', '[true]'],
        ['{"a":null}', '.a[(0):1] == null', '[true]'],
        ['{"a":[0,1,2]}', '.a[0.5:1] == null', '[false]'],
        ['{}', '.a[(empty):1] == null', '[]'],
        ['{}', '.a[0:(empty)] == null', '[]'],
        ['{}', 'null == .a[(0):1]', '[true]'],
        ['{}', 'select(.a[(0):1] == null)', '[{}]'],
        ['{}', 'select(.a[0.5:1] == null)', '[{}]'],
        ['{}', 'select(.a[(empty):1] == null)', '[]'],
        ['{}', 'select(.a[0:(empty)] == null)', '[]'],
        ['{"a":[0,1,2]}', '.a[(0):(1,2)] == [0]', '[true,false]'],
    );
    for my $case (@cases) {
        my ($input, $filter, $expected_json) = @$case;
        is_deeply([$jq->run_query($input, $filter)],
            JSON::PP->new->decode($expected_json),
            "null-aware comparison slice: $input / $filter");
    }
};


# Main-target Codex follow-up: optional slices preserve null-valued
# constructor members; fallback precedence and nested control-flow bounds
# retain jq 1.7's empty/null/false stream distinctions.
subtest 'optional slice (main-target regressions)' => sub {
    my @cases = (
        ['{}', '[.a[0:1]?]', '[[null]]'],
        ['{}', '{x:.a[0:1]?}', '[{"x":null}]'],
        ['null', '[.a[0:1]?]', '[[null]]'],
        ['null', '{x:.a[0:1]?}', '[{"x":null}]'],
        ['{"a":null}', '[.a[0:1]?]', '[[null]]'],
        ['{"a":2}', '[.a[0:1]?]', '[[]]'],
        ['{"a":"abcdef"}', '[.a[1:3]?]', '[["bc"]]'],
        ['{"a":"123"}', '[.a[0:1]?]', '[["1"]]'],
        ['{"a":false}', '[.a[0:1]?]', '[[]]'],
        ['{"a":{}}', '[.a[0:1]?]', '[[]]'],
        ['0', '[.[0:1]?]', '[[]]'],
        ['"hello"', '[.[1:3]?]', '[["el"]]'],
        ['{"a":"abcdef"}', '[.a[(0+1):(2+1)]?]', '[["bc"]]'],
        ['{"a":"abcdef"}', '[.a[(1,2):4]?]', '[["bcd","cd"]]'],
        ['{"a":"abcdef"}', '[.a[1.2:3.4]?]', '[["bcd"]]'],
        ['{"a":"abcdef"}', '[.a[-3:-1]?]', '[["de"]]'],
        ['{"a":"abcdef"}', '[.a[empty:3]?]', '[[]]'],
        ['{"a":[1,2]}', '[.a[0:1]?]', '[[[1]]]'],
        ['{}', '[.a[empty:1]?]', '[[]]'],
        ['{}', '{x:.a[empty:1]?}', '[]'],
        ['null', '[.[0:1]?]', '[[null]]'],
        ['{}', '[.a[(0):1]?]', '[[null]]'],
        ['{}', '[.a[0.5:1]?]', '[[null]]'],
        ['{}', '[.a[(empty):1]?]', '[[]]'],
    );
    for my $case (@cases) {
        my ($input, $filter, $expected_json) = @$case;
        is_deeply([$jq->run_query($input, $filter)],
            JSON::PP->new->decode($expected_json),
            "optional-slice / $filter on $input");
    }
};

subtest 'fallback comparison (main-target regressions)' => sub {
    my @cases = (
        ['{"a":false}', '[.a == null // false]', '[[false]]'],
        ['{"a":false}', '{x:(.a == null // false)}', '[{"x":false}]'],
        ['{"a":null}', '[.a == null // false]', '[[true]]'],
        ['{"a":false}', '[.a == null // true]', '[[true]]'],
        ['{"a":false}', '[.a == false // null]', '[[true]]'],
        ['{"a":false}', '[.a == null // (1,2)]', '[[1,2]]'],
        ['{"a":null}', '[.a == null // (1,2)]', '[[true]]'],
        ['{"a":false}', '{x:(.a == null // true)}', '[{"x":true}]'],
    );
    for my $case (@cases) {
        my ($input, $filter, $expected_json) = @$case;
        is_deeply([$jq->run_query($input, $filter)],
            JSON::PP->new->decode($expected_json),
            "fallback-comparison / $filter on $input");
    }
};

subtest 'nested control slice (main-target regressions)' => sub {
    my @cases = (
        ['{"a":null}', 'select(.a[(if true then 0 else 1 end):(empty)] == null)', '[]'],
        ['{}', 'select(.a[(if true then 0 else 1 end):1] == null)', '[{}]'],
        ['{"a":null}', '[.a[(if true then 0 else 1 end):(empty)] == null]', '[[]]'],
        ['{"a":null}', 'select(.a[(if true then 0 else 1 end):null] == null)', '[{"a":null}]'],
        ['{"a":null}', 'select(.a[(if true then 0 else 1 end):(0,empty)] == null)', '[{"a":null}]'],
    );
    for my $case (@cases) {
        my ($input, $filter, $expected_json) = @$case;
        is_deeply([$jq->run_query($input, $filter)],
            JSON::PP->new->decode($expected_json),
            "nested-control-slice / $filter on $input");
    }
};


# Optional '?' suppresses each invalid slice application, not errors from
# computing its bounds. Earlier successful outputs survive later bad bounds.
subtest 'optional bound stream error and order' => sub {
    my @cases = (
        ['{"a":[1,2]}', '[.a[(0,"x"):1]?]', '[[[1]]]'],
        ['{"a":[1,2]}', '[.a[(0,1,"x",2):2]?]', '[[[1,2],[2],[]]]'],
        ['{"a":[1,2]}', '[.a[0:(1,"x",2)]?]', '[[[1],[1,2]]]'],
        ['{"a":2}', '[.a[(0,"x"):1]?]', '[[]]'],
    );
    for my $case (@cases) {
        my ($input, $filter, $expected_json) = @$case;
        is_deeply([$jq->run_query($input, $filter)],
            JSON::PP->new->decode($expected_json),
            "per-bound optional application: $filter on $input");
    }

    for my $input ('{"a":[1,2]}', '{"a":2}') {
        my $threw = !eval {
            $jq->run_query($input, '[.a[(1+"x"):1]?]');
            1;
        };
        ok($threw, "optional must propagate invalid bound addition: $input");
    }
};


# Exact-head main-target follow-up: reject boolean array bounds per
# optional application and preserve conditional comparison fallback streams.
subtest 'boolean optional bounds and conditional fallback review' => sub {
    my @cases = (
        ['boolean-start-dropped', '{"a":[1,2]}', '[.a[false:1.2]?]', '[[]]'],
        ['boolean-true-dropped', '{"a":[1,2]}', '[.a[true:2]?]', '[[]]'],
        ['boolean-end-dropped', '{"a":[1,2]}', '[.a[0:false]?]', '[[]]'],
        ['boolean-start-mixed', '{"a":[1,2]}', '[.a[(false,0):1.2]?]', '[[[1,2]]]'],
        ['boolean-end-mixed', '{"a":[1,2]}', '[.a[0:(false,1)]?]', '[[[1]]]'],
        ['conditional-right-null', '{"a":false}', '[.a == null // if true then .a else null end == null]', '[[false]]'],
        ['conditional-fallback-skipped', '{"a":null}', '[.a == null // if true then .a else null end == null]', '[[true]]'],
        ['conditional-right-object', '{"a":false}', '{x:(.a == null // if true then .a else null end == null)}', '[{"x":false}]'],
        ['conditional-right-comparison', '{"a":false}', '[.a == null // null == if true then .a else null end]', '[[false]]'],
        ['conditional-right-multivalue', '{"a":false}', '[.a == null // if true then 0 else 1 end == (0,1)]', '[[true,false]]'],
    );
    for my $case (@cases) {
        my ($name, $input, $filter, $expected_json) = @$case;
        is_deeply([$jq->run_query($input, $filter)],
            JSON::PP->new->decode($expected_json),
            "$name: $filter on $input");
    }
};


# Codex exact-head follow-up: null sources ignore invalid bound types,
# while full if bodies retain internal fallback/comma operators.
subtest 'null optional slices and conditional body precedence' => sub {
    my @cases = (
        ['null-boolean-start', '{"a":null}', '[.a[false:1]?]', '[[null]]'],
        ['null-string-start', '{"a":null}', '[.a["x":1]?]', '[[null]]'],
        ['null-string-end', '{"a":null}', '[.a[0:"x"]?]', '[[null]]'],
        ['null-booleans-both', '{"a":null}', '[.a[true:false]?]', '[[null]]'],
        ['conditional-body-fallback', '{"a":false}', '[.a == null // if true then false // 1 else null end == null]', '[[false]]'],
        ['conditional-nested-fallback', '{"a":false}', '[.a == null // if true then if true then false // 1 else null end else null end == null]', '[[false]]'],
        ['conditional-body-comma', '{"a":false}', '[.a == null // if true then (1,2) else null end == null]', '[[false,false]]'],
        ['conditional-body-fallback-object', '{"a":false}', '{x:(.a == null // if true then false // 1 else null end == null)}', '[{"x":false}]'],
    );
    for my $case (@cases) {
        my ($name, $input, $filter, $expected) = @$case;
        is_deeply([$jq->run_query($input, $filter)],
            JSON::PP->new->decode($expected),
            "$name: $filter");
    }
};


# Full conditional comparisons bind before a subsequent outer fallback.
subtest 'conditional comparison outer fallback precedence' => sub {
    my @cases = (
        [\'outer-true\', \'[.a[(if (if true then 1 else null end == null // true) then 0 else 1 end):2]]\', \'[[[0,1]]]\'],
        [\'outer-unused\', \'[.a[(if (if true then null else 1 end == null // false) then 0 else 1 end):2]]\', \'[[[0,1]]]\'],
        [\'inner-body\', \'[.a[(if (if true then false // 1 else null end == null // true) then 0 else 1 end):2]]\', \'[[[0,1]]]\'],
        [\'parenthesized-rhs\', \'[.a[(if (if true then 1 else null end == (null // true)) then 0 else 1 end):2]]\', \'[[[1]]]\'],
        [\'outer-multivalue\', \'[.a[(if true then 1 else null end == null // (0,1)):2]]\', \'[[[0,1],[1]]]\'],
        [\'outer-false\', \'[.a[(if (if true then 1 else null end == null // false) then 0 else 1 end):2]]\', \'[[[1]]]\'],
    );
    for my $case (@cases) {
        my ($name, $filter, $expected_json) = @$case;
        is_deeply([$jq->run_query(\'{\"a\":[0,1,2]}\', $filter)],
            JSON::PP->new->decode($expected_json),
            "$name: $filter");
    }
};

done_testing;
