use strict;
use warnings;

use Test::More;

use JQ::Lite;

my $jq = JQ::Lite->new;

my $json = <<'JSON';
[
  {"id": 1, "flags": [true, false, true]},
  {"id": 2, "flags": [false, false]},
  {"id": 3, "flags": [true, true]}
]
JSON

my @stream_results = $jq->run_query($json, '.[] | select(.flags[]) | .id');

is_deeply(
    \@stream_results,
    [1, 1, 3, 3],
    'select() emits the input once per truthy value produced by the predicate'
);

my @fallback_results = $jq->run_query($json, '.[] | select(.id > 1) | .id');

is_deeply(
    \@fallback_results,
    [2, 3],
    'select() still handles basic comparison predicates'
);

my @scalar_kept = $jq->run_query('2', 'select(. > 1)');
is_deeply(\@scalar_kept, [2],
    'select() compares the current numeric scalar using a dot-only LHS');

my @scalar_filtered = $jq->run_query('1', 'select(. > 1)');
is_deeply(\@scalar_filtered, [],
    'select() filters scalar that does not satisfy dot-only comparison');

my @null_filtered = $jq->run_query('null', 'select(. > 1)');
is_deeply(\@null_filtered, [],
    'select() applies jq type ordering to JSON null and numeric literal');

done_testing();
