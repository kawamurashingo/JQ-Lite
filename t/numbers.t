use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $json = <<'JSON';
{
  "items": [
    1,
    "2",
    {"nested": 3, "other": "string"},
    [4, "five", {"deep": 6}, true],
    false,
    null
  ],
  "scalar_number": 42,
  "scalar_string": "not-a-number"
}
JSON

my $jq = JQ::Lite->new;

my @results = $jq->run_query($json, '.items[] | numbers');
is_deeply(\@results, [1, 3, 4, 6], 'numbers emits numeric values recursively from arrays');

@results = $jq->run_query($json, '.items | numbers');
is_deeply(\@results, [1, 3, 4, 6], 'numbers traverses arrays when applied directly');

@results = $jq->run_query($json, '.scalar_number | numbers');
is_deeply(\@results, [42], 'numbers emits scalar numbers');

@results = $jq->run_query($json, '.scalar_string | numbers');
is_deeply(\@results, [], 'numbers skips non-numeric scalars');

@results = $jq->run_query($json, '.items[4] | numbers');
is_deeply(\@results, [], 'numbers skips booleans');

@results = $jq->run_query($json, '.items[5] | numbers');
is_deeply(\@results, [], 'numbers skips null values');

@results = $jq->run_query($json, '.items[1] | numbers');
is_deeply(\@results, [], 'numbers does not treat numeric strings as numbers');

done_testing();
