use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;

sub output {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

my @cases = (
    ['[1,2,3,4]', 'sum_by(.)', [10], 'sum entire numeric array'],
    ['[1,2,3,4]', 'avg_by(.)', [2.5], 'average entire numeric array'],
    ['[{"n":2},{"n":4},{"n":6}]', 'sum_by(.n)', [12], 'sum projected fields'],
    ['[{"n":2},{"n":4},{"n":6}]', 'avg_by(.n)', [4], 'average projected fields'],
    ['[{"n":2},{"n":4},{"n":6}]', 'sum_by( .n )', [12], 'trim whitespace in sum path'],
    ['[{"n":2},{"n":4},{"n":6}]', 'avg_by( .n )', [4], 'trim whitespace in average path'],
    ['[{"n":2},{"n":4},{"n":6}]', 'sum_by(".n")', [12], 'quoted sum path'],
    ['[{"n":2},{"n":4},{"n":6}]', 'avg_by(".n")', [4], 'quoted average path'],
    ['[1,"2",3,"bad",null,{},[20]]', 'sum_by(.)', [6], 'sum only numeric elements'],
    ['[1,"2",3,"bad",null,{},[20]]', 'avg_by(.)', [2], 'average counts numeric elements only'],
    ['[true,false,3]', 'sum_by(.)', [4], 'sum accepts JSON booleans as 1 and 0'],
    ['[true,false,3]', 'avg_by(.)', [4/3], 'average counts JSON booleans'],
    ['[-3,1,2]', 'sum_by(.)', [0], 'zero total retains numeric zero'],
    ['[-3,1,2]', 'avg_by(.)', [0], 'zero mean retains numeric zero'],
    ['[]', 'sum_by(.)', [0], 'empty array has sum zero'],
    ['[]', 'avg_by(.)', [0], 'empty array has mean zero'],
    ['[null,{},"bad"]', 'sum_by(.)', [0], 'no numeric projection sum is zero'],
    ['[null,{},"bad"]', 'avg_by(.)', [0], 'no numeric projection mean is zero'],
    ['[{"v":[1,2]},{"v":[3]}]', 'sum_by(.v[])', [6], 'sum multi-output path'],
    ['[{"v":[1,2]},{"v":[3]}]', 'avg_by(.v[])', [2], 'average multi-output path'],
    ['[{"v":[2,null,4]},{"v":[6,"bad"]}]', 'sum_by(.v[])', [12], 'sum mixed multi-output path'],
    ['[{"v":[2,null,4]},{"v":[6,"bad"]}]', 'avg_by(.v[])', [4], 'average mixed multi-output path'],
    ['{"n":10}', 'sum_by(.n)', [{n=>10}], 'sum preserves v2 object passthrough'],
    ['{"n":10}', 'avg_by(.n)', [{n=>10}], 'average preserves v2 object passthrough'],
    ['42', 'sum_by(.)', [42], 'sum preserves v2 scalar passthrough'],
    ['42', 'avg_by(.)', [42], 'average preserves v2 scalar passthrough'],
    ['null', 'sum_by(.)', [undef], 'sum preserves v2 null passthrough'],
    ['null', 'avg_by(.)', [undef], 'average preserves v2 null passthrough'],
    ['[[1,2],[3,4]]', '.[] | sum_by(.)', [3,7], 'sum keeps stream order'],
    ['[[1,2],[3,4]]', '.[] | avg_by(.)', [1.5,3.5], 'average keeps stream order'],
    ['[[{"n":1},{"n":3}],[{"n":5},{"n":7}]]', '.[] | sum_by(.n)', [4,12], 'sum of nested object streams stays ordered'],
    ['[[{"n":1},{"n":3}],[{"n":5},{"n":7}]]', '.[] | avg_by(.n)', [2,6], 'average of nested object streams stays ordered'],
    ['[{"values":[4,null,2]},{"values":[6,"bad"]}]', 'sum_by(.values[])', [12], 'sum of mixed projected multi-values'],
    ['[{"values":[4,null,2]},{"values":[6,"bad"]}]', 'avg_by(.values[])', [4], 'average of mixed projected multi-values'],
);

for my $case (@cases) {
    my ($json, $filter, $expected, $label) = @$case;
    is_deeply(output($json, $filter), $expected, $label);
}

done_testing();
