use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use JQ::Lite;

my $jq = JQ::Lite->new;

my $json = <<'JSON';
[
  { "name": "Alice", "team": "A" },
  { "name": "Bob",   "team": "B" },
  { "name": "Carol", "team": "A" }
]
JSON

my @res = $jq->run_query($json, 'group_by(team)');

is_deeply($res[0], [
  [
    { name => "Alice", team => "A" },
    { name => "Carol", team => "A" }
  ],
  [
    { name => "Bob", team => "B" }
  ]
], 'group_by(team) works as expected');

my $json_complex = <<'JSON';
[
  { "name": "Alpha", "tags": [1, 2] },
  { "name": "Beta",  "tags": [1, 2] },
  { "name": "Gamma", "tags": [2, 3] },
  { "name": "Delta", "tags": null }
]
JSON

my @complex_res = $jq->run_query($json_complex, 'group_by(tags)');

is_deeply($complex_res[0], [
  [
    { name => 'Delta', tags => undef }
  ],
  [
    { name => 'Alpha', tags => [1, 2] },
    { name => 'Beta',  tags => [1, 2] }
  ],
  [
    { name => 'Gamma', tags => [2, 3] }
  ]
], 'group_by(tags) groups by array keys and nulls');

my @scalar_res = $jq->run_query('"not an array"', 'group_by(.)');

is_deeply($scalar_res[0], [], 'group_by on scalar returns empty array');

done_testing;
