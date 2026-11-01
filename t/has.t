use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $json = q({
  "meta": {
    "version": "1.0",
    "author": "you"
  }
});

my $jq = JQ::Lite->new;

my @result1 = $jq->run_query($json, 'select(.meta has "version")');
my @result2 = $jq->run_query($json, 'select(.meta has "missing")');

ok(@result1, 'meta has version');
ok(!@result2, 'meta does not have missing key');

# Retain the practical v2.59 has() contract. jq 1.7 raises for some
# mismatched key types, but these established fallbacks must not change
# implicitly while targeting jq compatibility in other filters.
my @object_string_key = $jq->run_query('{"1":true}', 'has("1")');
ok($object_string_key[0], 'string key lookup works for numeric-looking object keys');
my @object_numeric_key = $jq->run_query('{"1":true}', 'has(1)');
ok($object_numeric_key[0], 'legacy numeric object key is stringified');
my @object_missing = $jq->run_query('{"1":true}', 'has("missing")');
ok(!$object_missing[0], 'missing object key still returns false');

my @array_index = $jq->run_query('[10,20]', 'has(1)');
ok($array_index[0], 'numeric array index lookup still works');
my @array_fraction = $jq->run_query('[10,20]', 'has(1.5)');
ok($array_fraction[0], 'fractional numeric index retains truncation');
my @array_out_of_bounds = $jq->run_query('[10,20]', 'has(3)');
ok(!$array_out_of_bounds[0], 'out-of-range index remains false');
my @array_negative = $jq->run_query('[10,20]', 'has(-1)');
ok(!$array_negative[0], 'negative index remains false');
my @array_numeric_string = $jq->run_query('[10,20]', 'has("1")');
ok(!$array_numeric_string[0], 'numeric-looking string is not an array index');
my @array_text = $jq->run_query('[10,20]', 'has("value")');
ok(!$array_text[0], 'nonnumeric array key returns false, not an error');
my @array_boolean = $jq->run_query('[10,20]', 'has(true)');
ok(!$array_boolean[0], 'boolean array key retains false fallback');
my @null_needle = $jq->run_query('[10,20]', 'has(null)');
ok(!$null_needle[0], 'null needle retains false fallback');

done_testing;
