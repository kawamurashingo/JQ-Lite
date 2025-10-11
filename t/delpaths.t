use strict;
use warnings;
use Test::More tests => 3;
use JQ::Lite;

my $jq = JQ::Lite->new;

# --- 1. Delete multiple paths from an object
my $json_object = <<'JSON';
{
  "profile": {
    "name": "Alice",
    "password": "secret",
    "tokens": ["abc", "def"]
  }
}
JSON

my @result_object = $jq->run_query(
    $json_object,
    '.profile | delpaths([["password"], ["tokens", 0]])'
);

is_deeply(
    $result_object[0],
    {
        "name"   => "Alice",
        "tokens" => ["def"],
    },
    'delpaths removes multiple keys and array entries from objects'
);

# --- 2. Delete array entries by index
my $json_array = <<'JSON';
{
  "items": [
    {"id": 1},
    {"id": 2},
    {"id": 3}
  ]
}
JSON

my @result_array = $jq->run_query($json_array, '.items | delpaths([[1]])');

is_deeply(
    $result_array[0],
    [
        {"id" => 1},
        {"id" => 3},
    ],
    'delpaths removes array elements by index'
);

# --- 3. Removing the root path yields null
my $json_scalar = '{"keep": true}';
my @result_null = $jq->run_query($json_scalar, '. | delpaths([[]])');

ok(!defined $result_null[0], 'delpaths with empty path removes the entire value');

