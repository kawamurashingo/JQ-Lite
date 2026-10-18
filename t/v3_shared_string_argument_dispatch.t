use strict;
use warnings;
use Test::More;
use JSON::PP ();
use Scalar::Util qw(refaddr);
use JQ::Lite;
use JQ::Lite::Builtin ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;

sub run {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# The dispatcher is shared, but each string function keeps its original
# implementation, including v2 scalar/array behavior and JSON booleans.
my @cases = (
    ['"foobar"', 'ltrimstr("foo")', '["bar"]', 'matching prefix'],
    ['"foobar"', 'ltrimstr("bar")', '["foobar"]', 'nonmatching prefix'],
    ['"foo"', 'ltrimstr("foo")', '[""]', 'entire prefix'],
    ['"foobar"', 'ltrimstr("")', '["foobar"]', 'empty prefix'],
    ['""', 'ltrimstr("foo")', '[""]', 'empty input'],
    ['123', 'ltrimstr("1")', '[123]', 'number passthrough'],
    ['true', 'ltrimstr("t")', '[true]', 'boolean passthrough'],
    ['null', 'ltrimstr("n")', '[null]', 'null passthrough'],

    ['"foobar"', 'rtrimstr("bar")', '["foo"]', 'matching suffix'],
    ['"foobar"', 'rtrimstr("foo")', '["foobar"]', 'nonmatching suffix'],
    ['"bar"', 'rtrimstr("bar")', '[""]', 'entire suffix'],
    ['"foobar"', 'rtrimstr("")', '["foobar"]', 'empty suffix'],
    ['""', 'rtrimstr("bar")', '[""]', 'empty input'],
    ['123', 'rtrimstr("3")', '[123]', 'number passthrough'],
    ['false', 'rtrimstr("e")', '[false]', 'boolean passthrough'],
    ['null', 'rtrimstr("n")', '[null]', 'null passthrough'],

    ['"foobar"', 'startswith("foo")', '[true]', 'matching prefix'],
    ['"foobar"', 'startswith("bar")', '[false]', 'nonmatching prefix'],
    ['"foobar"', 'startswith("")', '[true]', 'empty prefix'],
    ['""', 'startswith("foo")', '[false]', 'empty input'],
    ['"123"', 'startswith("1")', '[true]', 'numeric-looking string'],
    ['"123"', 'startswith(1)', '[false]', 'numeric argument invalid'],
    ['123', 'startswith("1")', '[false]', 'numeric target invalid'],
    ['null', 'startswith("n")', '[false]', 'null target invalid'],

    ['"foobar"', 'endswith("bar")', '[true]', 'matching suffix'],
    ['"foobar"', 'endswith("foo")', '[false]', 'nonmatching suffix'],
    ['"foobar"', 'endswith("")', '[true]', 'empty suffix'],
    ['""', 'endswith("bar")', '[false]', 'empty input'],
    ['"123"', 'endswith("3")', '[true]', 'numeric-looking string'],
    ['"123"', 'endswith(3)', '[false]', 'numeric argument invalid'],
    ['123', 'endswith("3")', '[false]', 'numeric target invalid'],
    ['null', 'endswith("n")', '[false]', 'null target invalid'],

    ['["foobar","barfoo"]', 'ltrimstr("foo")', '["bar","barfoo"]', 'array prefix transform'],
    ['["foobar","barfoo"]', 'rtrimstr("foo")', '["foobar","bar"]', 'array suffix transform'],
    ['["foobar","barfoo"]', 'startswith("foo")', '[[true,false]]', 'array prefix predicate'],
    ['["foobar","barfoo"]', 'endswith("foo")', '[[false,true]]', 'array suffix predicate'],
);

for my $case (@cases) {
    my ($input, $filter, $expected, $label) = @$case;
    # The two trimming array cases return one array, not a value stream.
    $expected = '[' . $expected . ']' if $label =~ /^array (?:prefix|suffix) transform$/;
    is_deeply(run($input, $filter), $json->decode($expected),
        "$filter: $label");
}

# Nested arrays are recursively transformed by trims, not by predicates.
is_deeply(run('["foobar",["foo",null,42]]', 'ltrimstr("foo")'),
    [['bar', ['', undef, 42]]], 'nested trim keeps non-strings and depth');
is_deeply(run('["foobar",["foo",null,42]]', 'rtrimstr("foo")'),
    [['foobar', ['', undef, 42]]], 'nested suffix trim keeps depth');

# The builtins must continue to accept nonempty argument captures only.
for my $name (qw(ltrimstr rtrimstr startswith endswith)) {
    my ($matched) = JQ::Lite::Builtin->dispatch($jq, "$name(\"foo\")", ['foobar']);
    ok($matched, "$name keeps its registered argument pattern");
    my ($empty_match) = JQ::Lite::Builtin->dispatch($jq, "$name()", ['foobar']);
    ok(!$empty_match, "$name() is still not registered");
    is_deeply(run('"foobar"', "empty | $name(\"foo\")"), [],
        "$name preserves empty upstream streams");
}

is_deeply(run('["foobar","barfoo"]', '.[] | ltrimstr("foo")'),
    ['bar','barfoo'], 'prefix trim preserves multiple stream values');
is_deeply(run('["foobar","barfoo"]', '.[] | rtrimstr("foo")'),
    ['foobar','bar'], 'suffix trim preserves multiple stream values');
is_deeply(run('["foobar","barfoo"]', '.[] | startswith("foo")'),
    [JSON::PP::true,JSON::PP::false], 'prefix predicate preserves stream order');
is_deeply(run('["foobar","barfoo"]', '.[] | endswith("foo")'),
    [JSON::PP::false,JSON::PP::true], 'suffix predicate preserves stream order');


# Parameterized String builtins share the same unary stream-map adapter as
# their no-argument siblings. Changing captures between dispatches must not
# leak the old needle, substring bounds, or replacement to the next call.
my @capture_cases = (
    ['ltrimstr("foo")', '["bar",""]', 'prefix matches'],
    ['ltrimstr("bar")', '["foobar","foo"]', 'changed prefix'],
    ['rtrimstr("bar")', '["foo","foo"]', 'suffix matches'],
    ['rtrimstr("foo")', '["foobar",""]', 'changed suffix'],
    ['startswith("foo")', '[true,true]', 'prefix predicate'],
    ['startswith("bar")', '[false,false]', 'changed prefix predicate'],
    ['endswith("bar")', '[true,false]', 'suffix predicate'],
    ['endswith("foo")', '[false,true]', 'changed suffix predicate'],
    ['split("b")', '[["foo","ar"],["foo"]]', 'split separator'],
    ['split("z")', '[["foobar"],["foo"]]', 'changed split separator'],
    ['substr(1,3)', '["oob","oo"]', 'substring start and length'],
    ['substr(2,2)', '["ob","o"]', 'changed substring bounds'],
    ['substr()', '["foobar","foo"]', 'empty substring arguments'],
    ['replace("foo","bar")', '["barbar","bar"]', 'replacement'],
    ['replace("bar","baz")', '["foobaz","foo"]',
        'changed replacement'],
    ['replace("o","0")', '["f00bar","f00"]',
        'repeated replace captures'],
    ['ltrimstr("foo")', '["bar",""]', 'prefix after other handlers'],
    ['substr(1,3)', '["oob","oo"]', 'substring after other handlers'],
);
for my $case (@capture_cases) {
    my ($filter, $expected, $label) = @$case;
    my $wanted = $json->decode($expected);
    my ($found, $outputs) = JQ::Lite::Builtin->dispatch(
        $jq, $filter, ['foobar', 'foo']
    );
    ok($found, "$filter remains registered: $label");
    is_deeply($outputs, $wanted,
        "$filter keeps capture isolation and direct stream output: $label");
    is_deeply(run('["foobar","foo"]', ".[] | $filter"), $wanted,
        "$filter keeps public pipeline order: $label");
}

# No argument-taking mapper may fabricate values for an empty upstream
# stream. Non-arrays remain opaque and retain their original references.
my $opaque = { nested => ['foobar'] };
my $bool = JSON::PP::true;
for my $filter (
    'ltrimstr("foo")', 'rtrimstr("bar")',
    'split("o")', 'substr(1,2)', 'replace("foo","bar")'
) {
    my ($found, $outputs) = JQ::Lite::Builtin->dispatch(
        $jq, $filter, [$opaque, undef]
    );
    ok($found, "$filter handles a direct mixed stream");
    is_deeply($outputs, [$opaque, undef],
        "$filter keeps object and null in their original slots");
    is(refaddr($outputs->[0]), refaddr($opaque),
        "$filter preserves object identity");
    my ($empty_found, $empty_outputs) =
        JQ::Lite::Builtin->dispatch($jq, $filter, []);
    ok($empty_found, "$filter handles an empty stream");
    is_deeply($empty_outputs, [], "$filter emits no empty-stream values");
}

# A replace passthrough Boolean must not be converted to text by the
# mapper, and the original input list must not be modified.
my @original = ($opaque, $bool, undef, 'foobar');
my ($replace_found, $replaced) = JQ::Lite::Builtin->dispatch(
    $jq, 'replace("foo","bar")', \@original
);
ok($replace_found, 'replace remains registered for mixed input');
is_deeply($replaced, [$opaque,$bool,undef,'barbar'],
    'replace preserves Boolean and ordered stream slots');
is(refaddr($replaced->[1]), refaddr($bool),
    'replace preserves JSON Boolean reference identity');
is_deeply(\@original, [$opaque,$bool,undef,'foobar'],
    'replace mapper leaves caller input stream untouched');

done_testing;
