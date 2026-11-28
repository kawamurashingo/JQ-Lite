use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref->canonical;

sub output {
    my ($raw, $filter) = @_;
    return [ $jq->run_query($raw, $filter) ];
}

# Numeric conversion is now shared with median_by, but sum_by/avg_by still
# accumulate values in stream order and count every numeric projection.
my @projections = (
    ['null', '', 1, [], 'null whole item'],
    ['true', '', 1, [1], 'true whole item'],
    ['false', '', 1, [0], 'false whole item'],
    ['0', '', 1, [0], 'zero whole item'],
    ['-4.5', '', 1, [-4.5], 'fractional whole item'],
    ['"12"', '', 1, [12], 'numeric string'],
    ['"2e2"', '', 1, [200], 'scientific numeric string'],
    ['"bad"', '', 1, [], 'nonnumeric string'],
    ['[]', '', 1, [], 'array whole item is opaque'],
    ['{"n":3}', '', 1, [], 'object whole item is opaque'],
    ['{"n":4}', 'n', 0, [4], 'numeric projected field'],
    ['{"n":false}', 'n', 0, [0], 'false projected field'],
    ['{"n":null}', 'n', 0, [], 'null projected field'],
    ['{"other":4}', 'n', 0, [], 'missing projected field'],
    ['{"v":[1,2]}', 'v', 0, [], 'array value without iterator'],
    ['{"v":[1,true,"2",false,null,"bad",{},[],3]}',
     'v[]', 0, [1,1,2,0,3], 'mixed iterator results'],
    ['{"v":[]}', 'v[]', 0, [], 'empty iterator results'],
    ['{"meta":{"n":"7"}}', 'meta.n', 0, [7], 'nested numeric string'],
);

for my $case (@projections) {
    my ($raw, $path, $whole, $expected, $label) = @$case;
    my $value = $json->decode($raw);
    my $original = $json->encode($value);
    my @numbers = JQ::Lite::Util::_project_numeric_values($value, $path, $whole);
    is_deeply(\@numbers, $expected, "numeric projection: $label");
    is($json->encode($value), $original, "projection leaves input intact: $label");
}

# An unchanged practical-v2 contract: text numbers and booleans count, null
# and containers do not. Empty inputs sum to zero and average to zero.
my @statistics = (
    ['[1,2,3,4]', '.', 10, 2.5, 'direct numbers'],
    ['[true,false,3]', '.', 4, 4/3, 'JSON booleans count'],
    ['["4","2e1",true,false,null,"bad",{},[]]', '.', 25, 25/4,
     'mixed scalar and container values'],
    ['[null,{},[],"bad"]', '.', 0, 0, 'all nonnumeric items'],
    ['[]', '.', 0, 0, 'empty array'],
    ['[-3,1,2]', '.', 0, 0, 'zero-valued sum'],
    ['[{"n":2},{"n":null},{"n":"6"},{"n":false},{}]', '.n',
     8, 8/3, 'missing/null/boolean projections'],
    ['[{"n":2},{"n":8},{"n":4},{"n":6}]', '.n',
     20, 5, 'projected numeric object keys'],
    ['[{"v":[2,null,4]},{"v":[6,"bad"]}]', '.v[]',
     12, 4, 'multi-valued iterator'],
    ['[{"v":[1,true,"2"]},{"v":[3,false,null]}]', '.v[]',
     7, 7/5, 'mixed typed iterator'],
    ['[{"meta":{"n":"9"}},{"meta":{"n":3}}]', '.meta.n',
     12, 6, 'nested path'],
    ['[{"v":[]},{"v":[]},{}]', '.v[]',
     0, 0, 'no iterator outputs'],
    ['[{"n":5},{"n":7}]', ' .n ',
     12, 6, 'whitespace path'],
    ['[{"n":5},{"n":7}]', '".n"',
     12, 6, 'quoted path'],
    ['[{"n":true},{"n":false}]', '.n',
     1, 0.5, 'only boolean projections'],
);

for my $case (@statistics) {
    my ($raw, $path, $sum, $average, $label) = @$case;
    my $s = output($raw, "sum_by($path)");
    my $a = output($raw, "avg_by($path)");
    is(scalar(@$s), 1, "sum_by output cardinality: $label");
    is(scalar(@$a), 1, "avg_by output cardinality: $label");
    ok(abs($s->[0] - $sum) < 1e-10, "sum_by: $label");
    ok(abs($a->[0] - $average) < 1e-10, "avg_by: $label");
}

is_deeply(output('[[1,2],[3,5]]', '.[] | sum_by(.)'),
    [3,8], 'sum_by retains ordered multi-array stream');
is_deeply(output('[[1,2],[3,5]]', '.[] | avg_by(.)'),
    [1.5,4], 'avg_by retains ordered multi-array stream');
is_deeply(output('{"n":3}', 'sum_by(.n)'),
    [{n=>3}], 'sum_by retains non-array object passthrough');
is_deeply(output('{"n":3}', 'avg_by(.n)'),
    [{n=>3}], 'avg_by retains non-array object passthrough');
is_deeply(output('null', 'sum_by(.)'),
    [undef], 'sum_by preserves null passthrough');
is_deeply(output('null', 'avg_by(.)'),
    [undef], 'avg_by preserves null passthrough');
is_deeply(output('null', 'empty | sum_by(.)'),
    [], 'sum_by does not create values from empty');
is_deeply(output('null', 'empty | avg_by(.)'),
    [], 'avg_by does not create values from empty');

# Numeric projection is shared, not the output semantics of other builtins.
is_deeply(output('[true,false,3]', 'median_by(.)'),
    [1], 'median_by retains its independent median calculation');
is_deeply(output('[true,false,3]', 'median'),
    [1], 'median retains its numeric extractor');
is_deeply(output('[true,false,3]', 'min'),
    [0], 'min retains its numeric extractor');
is_deeply(output('[true,false,3]', 'max'),
    [3], 'max retains its numeric extractor');

done_testing;
