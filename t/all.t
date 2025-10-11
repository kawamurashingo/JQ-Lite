use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;

my @array_true = $jq->run_query('[true, 1, "non-empty"]', 'all');
ok($array_true[0], 'all returns true when every array element is truthy');

my @array_false = $jq->run_query('[true, false, 1]', 'all');
ok(!$array_false[0], 'all returns false when any array element is falsy');

my @array_empty = $jq->run_query('[]', 'all');
ok($array_empty[0], 'all returns true for an empty array (vacuous truth)');

my @filter_true = $jq->run_query('[{"active":true},{"active":1}]', 'all(.active)');
ok($filter_true[0], 'all(filter) returns true when filter is truthy for every element');

my @filter_false = $jq->run_query('[{"active":true},{}]', 'all(.active)');
ok(!$filter_false[0], 'all(filter) returns false when filter fails for any element');

my @scalar_true = $jq->run_query('true', 'all');
ok($scalar_true[0], 'all on a scalar truthy value returns true');

my @scalar_false = $jq->run_query('0', 'all');
ok(!$scalar_false[0], 'all on a scalar falsy value returns false');

done_testing;
