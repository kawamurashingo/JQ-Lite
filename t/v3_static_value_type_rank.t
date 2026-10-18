use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Value ();

my $decoder = JSON::PP->new->allow_nonref;
my $jq = JQ::Lite->new;

# The type ranking is fixed and shared by recursive comparisons. Protect
# every cross-type boundary, as well as comparisons of equal-type roots.
my @ranked = (
    ['null',     'null'],
    ['false',    'boolean'],
    ['0',        'number'],
    ['"0"',      'string'],
    ['[]',       'array'],
    ['{}',       'object'],
);

for my $i (0 .. $#ranked) {
    my ($raw, $kind) = @{ $ranked[$i] };
    is(JQ::Lite::Value::type_of($decoder->decode($raw)), $kind,
        "type rank $i belongs to $kind");
    for my $j (0 .. $#ranked) {
        my $left = $decoder->decode($raw);
        my $right = $decoder->decode($ranked[$j][0]);
        my $expected = $i <=> $j;
        my $got = JQ::Lite::Value::compare($left, $right);
        is($got <=> 0, $expected,
            "type rank comparison $kind against $ranked[$j][1]");
        is(JQ::Lite::Value::equal($left, $right) ? 1 : 0,
            $expected == 0 ? 1 : 0,
            "type equality $kind against $ranked[$j][1]");
    }
}

# Arrays compare recursively, with shorter equal prefixes sorting first.
# Objects compare sorted key lists first, then their values recursively.
my @nested = (
    ['[]',                    '[0]',                     -1, 'empty array sorts before nonempty'],
    ['[1]',                   '[1,0]',                   -1, 'array prefix comparison'],
    ['[1,2]',                 '[1,3]',                   -1, 'array numeric leaf'],
    ['["1"]',                 '[1]',                      1, 'string before numeric identity is distinct'],
    ['[false]',               '[true]',                  -1, 'nested boolean order'],
    ['[[1],[0]]',             '[[1],[1]]',               -1, 'nested arrays'],
    ['[[1,2]]',               '[[1,2],[]]',              -1, 'nested equal-prefix arrays'],
    ['["x",{}]',              '["x",[]]',                 1, 'nested object ranks above array'],
    ['{"a":99}',              '{"b":0}',                -1, 'object key comparison before value'],
    ['{"a":1}',               '{"a":1,"b":0}',           -1, 'object key prefix'],
    ['{"a":2}',               '{"a":10}',               -1, 'object numeric value'],
    ['{"a":1}',               '{"a":"1"}',              -1, 'object number and string values'],
    ['{"a":[false]}',         '{"a":[true]}',            -1, 'object containing boolean array'],
    ['{"a":[1,true]}',        '{"a":[1,0]}',             -1, 'mixed type recursive array'],
    ['{"a":{"x":[1,2]}}',     '{"a":{"x":[1,3]}}',      -1, 'multiple recursion levels'],
    ['{"a":1,"b":2}',         '{"b":2,"a":1}',            0, 'object literal key order irrelevant'],
    ['{"a":[1,2]}',           '{"a":[1,2]}',              0, 'deep object value equality'],
    ['{"a":[1,2]}',           '{"a":[1,2,3]}',           -1, 'object nested array prefix'],
    ['"\u65e5"',             '"\u672c"',                -1, 'Unicode string ordering'],
);

for my $case (@nested) {
    my ($left_json, $right_json, $expected, $label) = @$case;
    my $left = $decoder->decode($left_json);
    my $right = $decoder->decode($right_json);
    for my $iteration (1,2) {
        my $forward = JQ::Lite::Value::compare($left, $right);
        my $reverse = JQ::Lite::Value::compare($right, $left);
        is($forward <=> 0, $expected,
            "$label: forward comparison $iteration");
        is($reverse <=> 0, -$expected,
            "$label: reversed comparison $iteration");
    }
    is(JQ::Lite::Value::equal($left, $right) ? 1 : 0,
       $expected == 0 ? 1 : 0, "$label: equality");
}

# End-to-end jq-style operators and stream ordering stay independent of
# whether comparisons happen at the top level or deep inside containers.
for my $case (
    ['null < false',             'true'],
    ['false < 0',                'true'],
    ['0 < "0"',                 'true'],
    ['"0" < []',                'true'],
    ['[] < {}',                  'true'],
    ['[1,2] < [1,3]',           'true'],
    ['{"a":2} < {"a":10}',       'true'],
    ['{"b":2,"a":1} == {"a":1,"b":2}', 'true'],
    ['{"a":[1,2]} == {"a":[1,2]}',   'true'],
    ['[1] == [1,0]',            'false'],
    ['"10" == 10',              'false'],
) {
    my ($filter, $expected) = @$case;
    is_deeply([ $jq->run_query('null', $filter) ],
        [$decoder->decode($expected)], "public comparison: $filter");
}

is_deeply([ $jq->run_query(
    '[{"x":[1,2]},{"x":[1,3]},{"x":[1,2]}]',
    '.[] | .x == [1,2]'
) ], [JSON::PP::true, JSON::PP::false, JSON::PP::true],
    'ordered multi-result comparisons retain all outputs');

# Array comparisons should not need an intermediate index list. Include
# empty bounds, equal prefixes, early exits, and divergence at a late slot.
# Nest a long array within both arrays and objects to exercise recursion.
my @prefix = (0) x 256;
my $long_left  = [@prefix, 1];
my $long_right = [@prefix, 2];
my @index_cases = (
    [[], [], 0, 'two empty arrays'],
    [[], [0], -1, 'empty left array'],
    [[0], [], 1, 'empty right array'],
    [[0], [0], 0, 'equal singletons'],
    [[0,99], [1], -1, 'early differing array slot'],
    [\@prefix, $long_left, -1, 'long shared prefix then extra left slot'],
    [$long_left, \@prefix, 1, 'long shared prefix then extra right slot'],
    [$long_left, $long_right, -1, 'last element difference'],
    [[$long_left], [$long_right], -1, 'nested long array'],
    [{items=>$long_left}, {items=>$long_right}, -1,
        'long array nested in an object'],
    [$long_left, [@$long_left], 0, 'equal long arrays'],
);
for my $case (@index_cases) {
    my ($left, $right, $ordering, $label) = @$case;
    is(JQ::Lite::Value::compare($left, $right) <=> 0, $ordering,
        "$label: forward comparison");
    is(JQ::Lite::Value::compare($right, $left) <=> 0, -$ordering,
        "$label: reverse comparison");
    is(JQ::Lite::Value::equal($left, $right) ? 1 : 0,
       $ordering == 0 ? 1 : 0, "$label: equality");
}
is_deeply($long_left, [@prefix, 1],
    'long-array comparisons do not modify left input');
is_deeply($long_right, [@prefix, 2],
    'long-array comparisons do not modify right input');

done_testing;
