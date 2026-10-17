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

# split now shares the string-argument decoder and stream mapper used by
# trimstr/startswith/endswith; its legacy split/flatten behavior is unchanged.
my @cases = (
    ['"a,b,c"', 'split(",")', '[["a","b","c"]]', 'simple delimiter'],
    ['"a,,b,"', 'split(",")', '[["a","","b",""]]', 'empty interior and trailing fields'],
    ['",a"', 'split(",")', '[["","a"]]', 'empty leading field'],
    ['"a::b::"', 'split("::")', '[["a","b",""]]', 'multichar delimiter'],
    ['"a.b.c"', 'split(".")', '[["a","b","c"]]', 'regex dot is literal'],
    ['"a$^b$^c"', 'split("$^")', '[["a","b","c"]]', 'regex metacharacters'],
    ['"foo bar"', 'split(" ")', '[["foo","bar"]]', 'space delimiter'],
    ['"abc"', 'split("")', '[["a","b","c"]]', 'empty delimiter'],
    ['"abc"', 'split(null)', '[["a","b","c"]]', 'null argument becomes empty delimiter'],
    ['"a1b1"', 'split(1)', '[["a","b",""]]', 'numeric delimiter stringifies'],
    ['"ababa"', 'split("aba")', '[["","ba"]]', 'nonoverlapping delimiter'],
    ['"a,b"', 'split(x)', '[["a,b"]]', 'unquoted literal argument fallback'],
    ['null', 'split(",")', '[null]', 'null input preserved'],
    ['true', 'split("")', '[["t","r","u","e"]]', 'true stringified'],
    ['false', 'split(",")', '[["false"]]', 'false stringified'],
    ['123', 'split("")', '[["1","2","3"]]', 'numeric input stringified'],
    ['{"x":[1,2]}', 'split(",")', '[{"x":[1,2]}]', 'object input passed through'],
    ['["a,b",null,"c,d"]', 'split(",")', '[["a","b",null,"c","d"]]', 'array flatten preserves null'],
    ['[true,false,"a,b"]', 'split(",")', '[["true","false","a","b"]]', 'array booleans stringified'],
    ['[["a,b"],["c,d"]]', 'split(",")', '[["a","b","c","d"]]', 'nested array flattened'],
);
for my $case (@cases) {
    my ($input, $filter, $expected, $label) = @$case;
    is_deeply(run($input, $filter), $json->decode($expected),
        "$filter: $label");
}

is_deeply(run('"\\u3042\\u3044"', 'split("")'),
    [$json->decode('["\\u3042","\\u3044"]')],
    'empty separator splits Unicode codepoints');
is_deeply(run('"x,y"', 'split("\\u002c")'),
    [['x','y']], 'separator is decoded as JSON before splitting');
is_deeply(run('["a,b","c,d"]', '.[] | split(",")'),
    [['a','b'],['c','d']],
    'split retains ordered multi-value output streams');
is_deeply(run('["a,b","c,d"]', 'map(split(","))'),
    [[['a','b'],['c','d']]],
    'split retains map composition');
is_deeply(run('null', 'empty | split(",")'), [],
    'empty upstream stream stays empty');

# Direct dispatch tests argument capture and one-to-one stream mapping.
my ($matched, $values) = JQ::Lite::Builtin->dispatch(
    $jq, 'split(",")', ['a,b', undef, ['c,d', JSON::PP::true], {k => 1}]
);
ok($matched, 'split still matches its nonempty argument pattern');
is_deeply($values, [['a','b'], undef, ['c','d','true'], {k => 1}],
    'split keeps one output per input and flattens only within arrays');
my ($empty_match) = JQ::Lite::Builtin->dispatch($jq, 'split()', ['a,b']);
ok(!$empty_match, 'split() without argument is still not registered');
my ($empty_sep_match, $empty_sep) = JQ::Lite::Builtin->dispatch(
    $jq, 'split("")', ['ab']
);
ok($empty_sep_match, 'quoted empty separator remains registered');
is_deeply($empty_sep, [['a','b']],
    'quoted empty separator splits into characters');
my ($null_sep_match, $null_sep) = JQ::Lite::Builtin->dispatch(
    $jq, 'split(null)', ['ab']
);
ok($null_sep_match, 'null literal argument remains registered');
is_deeply($null_sep, [['a','b']],
    'null literal is decoded as empty string');
my ($empty_stream_match, $empty_stream) = JQ::Lite::Builtin->dispatch(
    $jq, 'split(",")', []
);
ok($empty_stream_match, 'split matches on an empty direct input stream');
is_deeply($empty_stream, [], 'empty direct input stream has no outputs');

# The other callers of this helper must retain their distinct semantics.
is_deeply(run('"foobar"', 'ltrimstr("foo")'), ['bar'],
    'ltrimstr still handles its direction');
is_deeply(run('"foobar"', 'rtrimstr("bar")'), ['foo'],
    'rtrimstr still handles its direction');
is_deeply(run('"foobar"', 'startswith("foo")'), [JSON::PP::true],
    'startswith still emits a JSON boolean');
is_deeply(run('"foobar"', 'endswith("bar")'), [JSON::PP::true],
    'endswith still emits a JSON boolean');

done_testing;
