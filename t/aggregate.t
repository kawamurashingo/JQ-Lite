use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $json = q([
  { "value": 10 },
  { "value": 30 },
  { "value": 20 }
]);

my $jq = JQ::Lite->new;

my ($add) = $jq->run_query($json, 'map(.value) | add');
is($add, 60, 'add = 60');

my ($sum) = $jq->run_query($json, 'map(.value) | sum');
is($sum, 60, 'sum = 60');

my ($min) = $jq->run_query($json, 'map(.value) | min');
is($min, 10, 'min = 10');

my ($max) = $jq->run_query($json, 'map(.value) | max');
is($max, 30, 'max = 30');

my ($avg) = $jq->run_query($json, 'map(.value) | avg');
is($avg, 20, 'avg = 20');

my ($variance) = $jq->run_query($json, 'map(.value) | variance');
ok(abs($variance - 66.6666667) < 1e-6, 'variance approx 66.6666667');

my ($stddev) = $jq->run_query($json, 'map(.value) | stddev');
ok(abs($stddev - 8.1649658) < 1e-6, 'stddev approx 8.1649658');

my ($product) = $jq->run_query($json, 'map(.value) | product');
is($product, 6000, 'product = 6000');

my ($variance_single) = $jq->run_query(q([{ "value": 42 }]), 'map(.value) | variance');
is($variance_single, 0, 'variance of single value = 0');

my ($stddev_single) = $jq->run_query(q([{ "value": 42 }]), 'map(.value) | stddev');
is($stddev_single, 0, 'stddev of single value = 0');

my ($variance_non_numeric) = $jq->run_query(q(["alpha", "beta", "gamma"]), 'variance');
ok(!defined $variance_non_numeric, 'variance returns undef when array has no numeric values');

my ($stddev_non_numeric) = $jq->run_query(q(["alpha", "beta", "gamma"]), 'stddev');
ok(!defined $stddev_non_numeric, 'stddev returns undef when array has no numeric values');


my $warned = 0;
{
    local $SIG{__WARN__} = sub { $warned = 1 };
    my ($min_mixed) = $jq->run_query(q(["x", 10, true, "5", null]), 'min');
    my ($max_mixed) = $jq->run_query(q(["x", 10, true, "5", null]), 'max');
    is($min_mixed, 1, 'min ignores non-numeric values and handles booleans numerically');
    is($max_mixed, 10, 'max ignores non-numeric values and keeps numeric candidates');
}
ok(!$warned, 'min/max with mixed arrays do not emit numeric warnings');

my ($min_none) = $jq->run_query(q(["alpha", "beta", null]), 'min');
my ($max_none) = $jq->run_query(q(["alpha", "beta", null]), 'max');
ok(!defined $min_none, 'min returns undef when no numeric values are present');
ok(!defined $max_none, 'max returns undef when no numeric values are present');

done_testing;
