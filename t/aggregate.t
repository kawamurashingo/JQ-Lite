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

my ($product) = $jq->run_query($json, 'map(.value) | product');
is($product, 6000, 'product = 6000');

done_testing;
