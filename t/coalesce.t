use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq = JQ::Lite->new;

# --- 1. Provide fallback string when field is missing
my $json_users = <<'JSON';
{
  "users": [
    { "name": "Alice", "nickname": "Al" },
    { "name": "Bob",   "nickname": null },
    { "name": "Carol" }
  ]
}
JSON

my @names = $jq->run_query($json_users, '.users[] | (.nickname // .name)');
is_deeply(\@names, [ 'Al', 'Bob', 'Carol' ], 'fallback picks existing nickname or name');

# --- 2. Literal fallback when key is absent
my $json_missing = '{"value":42}';
my @fallback = $jq->run_query($json_missing, '.missing // "default"');
is($fallback[0], 'default', 'literal fallback applied for missing key');

# --- 3. JSON false triggers fallback in v3 (unlike 2.x)
my $json_false = '{"active":false}';
my @bool = $jq->run_query($json_false, '.active // true');
ok(@bool && JSON::PP::is_bool($bool[0]) && $bool[0], 'false selects true fallback');

# --- 4. Nested alternative operator chains
my $json_nested = '{"foo":null,"bar":null}';
my @nested = $jq->run_query($json_nested, '.foo // .bar // 0');
is($nested[0], 0, 'nested fallbacks evaluate from left to right');


# jq treats zero, empty strings, and empty containers as truthy for //.
my @zero = $jq->run_query('0', '. // 9');
is_deeply(\@zero, [0], 'numeric zero does not trigger fallback');

my @empty_string = $jq->run_query('""', '. // 9');
is_deeply(\@empty_string, [''], 'empty string does not trigger fallback');

my @empty_array = $jq->run_query('[]', '. // 9');
is_deeply(\@empty_array, [[]], 'empty array does not trigger fallback');

my @false_text = $jq->run_query('"false"', '. // 9');
is_deeply(\@false_text, ['false'], 'string false is not JSON false');

my @false_rhs = $jq->run_query('null', '. // false');
ok(@false_rhs && JSON::PP::is_bool($false_rhs[0]) && !$false_rhs[0],
    'false remains a valid result from the fallback expression');

my @nested_false = $jq->run_query('null', 'false // null // 5');
is_deeply(\@nested_false, [5], 'nested alternative skips false and null');

done_testing;
