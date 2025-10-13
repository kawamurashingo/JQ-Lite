use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $json = <<'JSON';
{
  "items": [
    3,
    "4",
    -7.5,
    true,
    null,
    {"note": "object"},
    [1, 2]
  ],
  "score": 0,
  "flag": false
}
JSON

my $jq = JQ::Lite->new;
my @results = $jq->run_query($json, '.items[] | numbers');

is_deeply(\@results, [3, -7.5], 'numbers emits only numeric entries from arrays');

@results = $jq->run_query($json, '.items | numbers');
is_deeply(\@results, [], 'numbers yields no output for array containers');

@results = $jq->run_query($json, '.score | numbers');
is($results[0], 0, 'numbers passes through zero values');

@results = $jq->run_query($json, '.flag | numbers');
is_deeply(\@results, [], 'numbers skips booleans');

@results = $jq->run_query($json, '.items[1] | numbers');
is_deeply(\@results, [], 'numbers skips numeric-looking strings');

done_testing();
