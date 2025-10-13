use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $json = <<'JSON';
{
  "items": [
    1,
    "two",
    [3, "four", {"deep": 5}],
    {"nested": [6, "seven"]},
    true,
    null,
    8.5
  ]
}
JSON

my $jq = JQ::Lite->new;
my @results = $jq->run_query($json, '.items[] | numbers');

is_deeply(\@results, [1, 3, 5, 6, 8.5], 'numbers recursively emits numeric values');

@results = $jq->run_query($json, '.items | numbers');

is_deeply(\@results, [1, 3, 5, 6, 8.5], 'numbers traverses arrays when input is an array');

@results = $jq->run_query($json, '.items[1] | numbers');

is_deeply(\@results, [], 'numbers yields empty result for non-numeric scalar');

@results = $jq->run_query($json, '.items[4] | numbers');

is_deeply(\@results, [], 'numbers skips boolean values');

done_testing();
