use strict;
use warnings;
use Test::More;
use JSON::PP ();
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
    ['bar', ['', undef, 42]], 'nested trim keeps non-strings and depth');
is_deeply(run('["foobar",["foo",null,42]]', 'rtrimstr("foo")'),
    ['foobar', ['', undef, 42]], 'nested suffix trim keeps depth');

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

done_testing;
