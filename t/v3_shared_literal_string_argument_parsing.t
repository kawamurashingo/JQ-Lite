use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Builtin ();
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;

sub run {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# Both helpers must decode valid JSON and retain the v2 plain-text
# fallback. Only JSON null and missing arguments differ: string-style
# arguments normalize them to "", while literal-style arguments keep undef.
my @parsing_cases = (
    [undef, undef, '', 'missing argument'],
    ['null', undef, '', 'JSON null'],
    ['""', '', '', 'empty JSON string'],
    ['"abc"', 'abc', 'abc', 'quoted JSON string'],
    ["'abc'", 'abc', 'abc', 'single-quoted fallback'],
    ['   abc   ', 'abc', 'abc', 'trimmed plain-text fallback'],
    ["   'abc'   ", 'abc', 'abc', 'trimmed single-quoted fallback'],
    ['true', JSON::PP::true, JSON::PP::true, 'true boolean'],
    ['false', JSON::PP::false, JSON::PP::false, 'false boolean'],
    ['0', 0, 0, 'zero number'],
    ['42', 42, 42, 'integer number'],
    ['-7.5', -7.5, -7.5, 'fractional number'],
    ['"42"', '42', '42', 'numeric-looking JSON string'],
    ['[]', [], [], 'JSON empty array'],
    ['{}', {}, {}, 'JSON empty object'],
    ['[1,"x"]', [1, 'x'], [1, 'x'], 'JSON array argument'],
    ['{"a":false}', {a => JSON::PP::false}, {a => JSON::PP::false},
        'JSON object argument'],
    ['"a\nb"', "a\nb", "a\nb", 'JSON escaped newline'],
    ['"\u3042"', "\x{3042}", "\x{3042}", 'JSON Unicode escape'],
    ['   "a"   ', 'a', 'a', 'whitespace around JSON string'],
    ['x', 'x', 'x', 'unquoted fallback'],
    ['"unterminated', 'unterminated', 'unterminated', 'malformed opening quote'],
    ['trailing"', 'trailing', 'trailing', 'malformed closing quote'],
    ["'null'", 'null', 'null', 'quoted literal null remains a string'],
);

for my $case (@parsing_cases) {
    my ($raw, $literal_expected, $string_expected, $label) = @$case;
    is_deeply(JQ::Lite::Util::_parse_literal_argument($raw), $literal_expected,
        "literal argument: $label");
    is_deeply(JQ::Lite::Util::_parse_string_argument($raw), $string_expected,
        "string argument: $label");
}

# Representative callers keep distinct semantics despite sharing the
# underlying decoder and legacy fallback path.
for my $case (
    ['"a,b,c"', 'split(",")', '[["a","b","c"]]', 'split quoted separator'],
    ['"abc"', 'split(null)', '[["a","b","c"]]', 'split null separator'],
    ['"abc"', 'split(x)', '[["abc"]]', 'split raw fallback'],
    ['"foobar"', 'ltrimstr("foo")', '["bar"]', 'prefix trim'],
    ['"foobar"', 'rtrimstr("bar")', '["foo"]', 'suffix trim'],
    ['"foobar"', 'ltrimstr(foo)', '["bar"]', 'unquoted trim argument'],
    ['"foobar"', 'startswith("foo")', '[true]', 'prefix predicate'],
    ['"foobar"', 'endswith("bar")', '[true]', 'suffix predicate'],
    ['"123"', 'startswith(1)', '[false]', 'non-string needle is rejected'],
    ['"banana"', 'contains("ana")', '[true]', 'string containment'],
    ['null', 'contains(null)', '[true]', 'null literal containment'],
    ['null', 'inside(null)', '[true]', 'legacy inside null containment'],
    ['[1,1]', 'contains_subset([1,1])', '[true]', 'literal array subset'],
    ['{"a":{"x":1}}', 'contains({"a":{"x":1}})', '[true]',
        'literal nested object subset'],
) {
    my ($input, $filter, $expected, $label) = @$case;
    is_deeply(run($input, $filter), $json->decode($expected),
        "$filter retains $label");
}

# Confirm registry capture is still exact; empty streams do not create
# values and string-versus-literal null normalization stays distinct.
for my $spec (
    ['split(null)', 'abc', ['a','b','c']],
    ['split(x)', 'abc', ['abc']],
    ['ltrimstr(foo)', 'foobar', 'bar'],
    ['startswith(1)', '123', JSON::PP::false],
    ['contains(null)', undef, JSON::PP::true],
) {
    my ($name, $input, $expected) = @$spec;
    my ($matched, $outputs) = JQ::Lite::Builtin->dispatch($jq, $name, [$input]);
    ok($matched, "$name retains its existing registered grammar");
    is_deeply($outputs, [$expected], "$name direct invocation keeps decoding");
}
for my $name ('split', 'ltrimstr', 'contains') {
    my ($matched, $out) = JQ::Lite::Builtin->dispatch(
        $jq, "$name(null)", []
    );
    ok($matched, "$name(null) accepts an empty upstream stream");
    is_deeply($out, [], "$name(null) does not synthesize an output");
}
my ($empty_split) = JQ::Lite::Builtin->dispatch($jq, 'split()', ['abc']);
ok(!$empty_split, 'split() remains unregistered without an argument');

my $ok = eval { $jq->run_query('[1,2]', 'contains(1)'); 1 };
ok(!$ok, 'contains keeps type mismatch errors with literal numeric arguments');
like("$@", qr/argument|cannot contain|number|array/i,
    'contains retains an informative type mismatch error');


# Parameterized object builtins use the unary stream mapper without
# changing each predicate's semantics. Decode arguments anew per dispatch,
# and verify the result/order both directly and in a public .[] stream.
my @object_stream_cases = (
    ['[{"x":1},{"y":2},[9,8],null,7]', 'has("x")',
        '[true,false,false,false,false]', 'object key'],
    ['[{"x":1},{"y":2},[9,8],null,7]', 'has("y")',
        '[false,true,false,false,false]', 'changed key'],
    ['[{"x":1},{"y":2},[9,8],null,7]', 'has(0)',
        '[false,false,true,false,false]', 'array numeric index'],
    ['[{"x":1},{"y":2},[9,8],null,7]', 'has("0")',
        '[false,false,false,false,false]', 'array numeric string not index'],
    ['[{"x":1},{"y":2},[9,8],null,7]', 'has(null)',
        '[false,false,false,false,false]', 'null key'],
    ['[[1,2,3],[1,2],[2],[]]', 'contains([2])',
        '[true,true,true,false]', 'jq array subset'],
    ['[[1,2,3],[1,2],[2],[]]', 'contains([1,1])',
        '[true,true,false,false]', 'jq array repeated-needle reuse'],
    ['[[1,1],[1,2],[1],[]]', 'contains_subset([1,1])',
        '[true,false,false,false]', 'multiset duplicate counting'],
    ['[[1,1],[1,2],[1],[]]', 'contains_subset([1])',
        '[true,true,true,false]', 'changed multiset needle'],
    ['[1,2,3]', 'inside([1,2])',
        '[true,true,false]', 'legacy inside membership direction'],
    ['[1,2,3]', 'inside([2,3])',
        '[false,true,true]', 'changed legacy container'],
    ['["ab","ba","zzz"]', 'contains("b")',
        '[true,true,false]', 'string literal containment'],
    ['["ab","ba","zzz"]', 'contains("a")',
        '[true,true,false]', 'changed string needle'],
    ['[{"a":1,"b":2},{"a":2},{}]', 'contains({"a":1})',
        '[true,false,false]', 'nested object containment'],
    ['[{"x":1},{"y":2},[9,8],null,7]', 'has("x")',
        '[true,false,false,false,false]', 'repeated key after other calls'],
    ['[[1,1],[1,2],[1],[]]', 'contains_subset([1,1])',
        '[true,false,false,false]', 'repeated multiset after other calls'],
);
for my $case (@object_stream_cases) {
    my ($input, $filter, $expected, $label) = @$case;
    my $decoded = $json->decode($input);
    my $before = $json->encode($decoded);
    my $wanted = $json->decode($expected);
    my ($matched, $outputs) = JQ::Lite::Builtin->dispatch(
        $jq, $filter, $decoded
    );
    ok($matched, "$filter registered for $label");
    is_deeply($outputs, $wanted, "$filter direct stream: $label");
    is_deeply(run($input, ".[] | $filter"), $wanted,
        "$filter public pipeline: $label");
    is($json->encode($decoded), $before,
        "$filter leaves input unchanged: $label");
}

for my $filter (
    'has("a")', 'has(0)', 'contains([1])',
    'contains_subset([1])', 'inside([1,2])'
) {
    my ($matched, $outputs) =
        JQ::Lite::Builtin->dispatch($jq, $filter, []);
    ok($matched, "$filter registered for empty stream");
    is_deeply($outputs, [], "$filter does not create empty-stream outputs");
}

# Preserve the jq-style type error; the common mapper must not swallow
# exceptions raised by the containment implementation.
my $type_ok = eval {
    JQ::Lite::Builtin->dispatch($jq, 'contains("x")', [[1], [2]]);
    1;
};
ok(!$type_ok, 'contains still rejects mismatched array/string types');
like("$@", qr/Cannot check whether array contains string/,
    'contains preserves existing type mismatch error wording');

done_testing;
