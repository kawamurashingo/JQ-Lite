use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use JQ::Lite;

my $object_json = <<'JSON';
{
  "users": [
    { "name": "Alice", "age": 30 },
    { "name": "Bob",   "age": 25 },
    { "name": "Carol", "age": 35 }
  ]
}
JSON

my $array_json = <<'JSON';
[
  { "name": "Ann" },
  { "name": "Bea" },
  { "name": "Cal" }
]
JSON

my $jq = JQ::Lite->new;

is_deeply([
    $jq->run_query($object_json, '.users[-1].name')
], ['Carol'], 'negative index fetches last object');

is_deeply([
    $jq->run_query($object_json, '.users[-2].age')
], [25], 'negative index fetches middle object');

is_deeply([
    $jq->run_query($object_json, '.users | nth(-1) | .name')
], ['Carol'], 'nth(-1) returns last element');

is_deeply([
    $jq->run_query($object_json, '.users | nth(-4)')
], [undef], 'nth(-4) returns undef when out of bounds');

is_deeply([
    $jq->run_query($array_json, '.[-1].name')
], ['Cal'], 'negative index works on top-level array');

is_deeply([
    $jq->run_query($array_json, 'nth(-2) | .name')
], ['Bea'], 'nth(-2) works on top-level array');

done_testing();

