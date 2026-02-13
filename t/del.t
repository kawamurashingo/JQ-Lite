use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $json = <<'JSON';
{
  "profile": {
    "name": "Alice",
    "age": 30,
    "password": "secret"
  }
}
JSON

my $jq = JQ::Lite->new;

my @result = $jq->run_query($json, '.profile | del("password")');

is_deeply(
    $result[0],
    {
        "name" => "Alice",
        "age" => 30
    },
    'deleted password field'
);

my @result_with_spaces = $jq->run_query($json, '.profile | del( "password" )');
is_deeply(
    $result_with_spaces[0],
    {
        "name" => "Alice",
        "age" => 30
    },
    'del() accepts whitespace around key argument'
);

my @result_single_quote = $jq->run_query($json, ".profile | del('password')");
is_deeply(
    $result_single_quote[0],
    {
        "name" => "Alice",
        "age" => 30
    },
    'del() accepts single-quoted key'
);

my @missing_key = $jq->run_query($json, '.profile | del("missing")');
is_deeply(
    $missing_key[0],
    {
        "name"     => "Alice",
        "age"      => 30,
        "password" => "secret",
    },
    'del() leaves object unchanged for missing key'
);

my @scalar_passthrough = $jq->run_query('{"value": 10}', '.value | del("anything")');
is($scalar_passthrough[0], 10, 'del() leaves non-object inputs untouched');

done_testing();
