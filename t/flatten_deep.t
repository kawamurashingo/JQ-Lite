use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $json = <<'JSON';
{
  "items": [
    1,
    [2, [3, 4], []],
    [[5], [[6, 7]]],
    [{"foo": "bar"}],
    null
  ],
  "value": 42
}
JSON

my $jq = JQ::Lite->new;
my @results = $jq->run_query($json, '.items | flatten_deep');

is(scalar @results, 1, 'flatten_deep returns a single flattened array');

is_deeply(
    $results[0],
    [1, 2, 3, 4, 5, 6, 7, { foo => 'bar' }, undef],
    'flatten_deep recursively flattens nested arrays and preserves other values',
);

my @scalar = $jq->run_query($json, '.value | flatten_deep');

is_deeply(\@scalar, [42], 'flatten_deep leaves non-array values unchanged');

done_testing();
