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

done_testing;
