use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JSON::PP ();
use Scalar::Util qw(refaddr);
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;

sub run_query {
    my ($json, $query) = @_;
    return [ $jq->run_query($json, $query) ];
}

subtest 'pick on single object' => sub {
    my $json    = '{"name":"Alice","age":30,"city":"Paris"}';
    my $results = run_query($json, 'pick("name", "age")');

    is_deeply(
        $results->[0],
        { name => 'Alice', age => 30 },
        'returns subset of keys'
    );
};

subtest 'pick on array of objects' => sub {
    my $json    = '{"users":[{"name":"Alice","age":30,"email":"alice@example.com"},{"name":"Bob","age":27}]}';
    my $results = run_query($json, '.users | pick("name", "email")');

    is_deeply(
        $results->[0],
        [
            { name => 'Alice', email => 'alice@example.com' },
            { name => 'Bob' },
        ],
        'applies selection to each array element'
    );
};

subtest 'pick leaves non-objects unchanged' => sub {
    my $json    = '{"value":"hello"}';
    my $results = run_query($json, '.value | pick("anything")');

    is($results->[0], 'hello', 'non-object value is passed through');
};


# pick() now filters and stringifies parsed arguments in one pass, rather
# than constructing a map list and filtering it with grep. Verify that JSON
# null is omitted, while false, zero, numeric strings and fallback raw
# identifiers preserve their v2 key interpretation.
my $decoder = JSON::PP->new->allow_nonref->canonical;
my @argument_cases = (
    ['{"name":"Alice","age":30,"city":"Paris"}',
        'pick("name","age")', '{"name":"Alice","age":30}',
        'ordinary string keys'],
    ['{"a":1,"b":2}', 'pick("b","a","b")', '{"a":1,"b":2}',
        'duplicate keys and argument order'],
    ['{"a":1,"b":2}', 'pick("missing","b")', '{"b":2}',
        'missing key omitted'],
    ['{"a":1,"b":2}', 'pick()', '{"a":1,"b":2}',
        'no arguments retain original object'],
    ['{"a":1,"b":2}', 'pick(null)', '{"a":1,"b":2}',
        'null-only arguments retain original object'],
    ['{"a":1,"b":2}', 'pick(null,"b",null)', '{"b":2}',
        'nulls dropped before and after key'],
    ['{"0":"zero","1":"one","2":"two"}', 'pick(0,1)',
        '{"0":"zero","1":"one"}', 'numeric keys stringified'],
    ['{"0":"zero","1":"one","2":"two"}', 'pick(true,false)',
        '{"0":"zero","1":"one"}', 'boolean keys stringify to one and zero'],
    ['{"0":"zero","1":"one","2":"two"}', 'pick("0","2")',
        '{"0":"zero","2":"two"}', 'quoted numeric-looking string keys'],
    ['{"":"blank","a":1}', 'pick("")', '{"":"blank"}',
        'empty string remains a valid key'],
    ['{" spaced ":3,"x":4}', 'pick(" spaced ")', '{" spaced ":3}',
        'spaces inside a quoted key preserved'],
    ['[{"a":1,"b":2},{"a":3},null,"str",5]', 'pick("a")',
        '[{"a":1},{"a":3},null,"str",5]',
        'recursive array selection and scalar passthrough'],
    ['[{"a":1},[{"a":2},{"b":3}],{"b":4}]', 'pick("a")',
        '[{"a":1},[{"a":2},{}],{}]', 'nested arrays and absent keys'],
    ['"text"', 'pick("a")', '"text"', 'string scalar passthrough'],
    ['null', 'pick("a")', 'null', 'null scalar passthrough'],
    ['true', 'pick("a")', 'true', 'Boolean scalar passthrough'],
    ['{"a":1}', 'pick(a)', '{"a":1}',
        'fallback argument parser bare identifier'],
    ['{"a":1,"b":2}', 'pick(a,b)', '{"a":1,"b":2}',
        'fallback comma-separated identifiers'],
    ['{"a":1}', 'pick(null,false)', '{"a":1}',
        'false key is retained even without a match'],
    ['{"a":1}', 'pick(1.0)', '{}',
        'numeric JSON argument coercion'],
    ['{"a":1}', 'pick("a",true,null)', '{"a":1}',
        'mixed string, Boolean and null arguments'],
    ['[1,[2],{}]', 'pick(null)', '[1,[2],{}]',
        'null-only keys preserve nested source'],
    ['{"a":1,"b":2}', 'pick("a","none","b")', '{"a":1,"b":2}',
        'multiple selected keys around absent key'],
);
for my $case (@argument_cases) {
    my ($raw, $filter, $expected, $label) = @$case;
    my $wanted = $decoder->decode($expected);
    is_deeply(run_query($raw, $filter), [$wanted],
        "pick argument normalization: $label");
    is_deeply(run_query("[$raw]", ".[] | $filter"), [$wanted],
        "pick ordered one-element pipeline: $label");
}

# Internal helper remains independent of argument parsing. Its distinct
# empty-key passthrough and shallow-copy semantics must not be changed.
my $nested = [1,'2',JSON::PP::true];
my $source = { a => $nested, b => undef, c => 3 };
my $before = $decoder->encode($source);
my $selected = JQ::Lite::Util::_apply_pick($source, ['a','b','missing']);
is_deeply($selected, {a=>$nested,b=>undef},
    'pick helper retains selected null and nested values');
is(refaddr($selected->{a}), refaddr($nested),
    'pick helper still shares nested references with input');
isnt(refaddr($selected), refaddr($source),
    'nonempty pick returns a new top-level object');
is($decoder->encode($source), $before,
    'pick helper does not modify original input types');
my $passthrough = JQ::Lite::Util::_apply_pick($source, []);
is(refaddr($passthrough), refaddr($source),
    'empty key set returns original object reference');

is_deeply(run_query('{"a":1}', 'empty | pick("a")'), [],
    'pick does not revive empty upstream stream');
is_deeply(run_query('[{"a":1},{"a":2}]', '.[] | pick(null,"a")'),
    [{a=>1},{a=>2}], 'pick preserves multiple ordered input objects');

done_testing();
