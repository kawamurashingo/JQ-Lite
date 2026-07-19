use Test::More;
use JQ::Lite;

my $json = q({
  "arr": [1, 2, 3],
  "obj": {"a": 1, "b": 2},
  "str": "hello",
  "num": 12345,
  "bool": true,
  "null": null
});

my $jq = JQ::Lite->new;

my @arr = $jq->run_query($json, '.arr | length');
my @obj = $jq->run_query($json, '.obj | length');
my @str = $jq->run_query($json, '.str | length');
my @num = $jq->run_query($json, '.num | length');
my @bool = $jq->run_query($json, '.bool | length');
my @null = $jq->run_query($json, '.null | length');

is($arr[0], 3, 'array length counts elements');
is($obj[0], 2, 'object length counts keys');
is($str[0], 5, 'string length counts characters');
is($num[0], 5, 'numeric length counts digits');
is($bool[0], 1, 'boolean length is treated as scalar');
is($null[0], 0, 'null length is zero');

my $comparison_json = q({"devices":[{"mac":"aa"}],"count":3,"s":"x"});
my @length_gt = $jq->run_query($comparison_json, '.devices | length > 0');
my @length_ge = $jq->run_query($comparison_json, '.devices | length >= 1');
my @length_eq = $jq->run_query($comparison_json, '.devices | length == 1');
my @length_ne = $jq->run_query($comparison_json, '.devices | length != 0');
my @count_gt  = $jq->run_query($comparison_json, '.count | . > 0');
my @count_eq  = $jq->run_query($comparison_json, '.count | . == 3');
my @string_eq = $jq->run_query($comparison_json, '.s | . == "x"');
my @parenthesized = $jq->run_query($comparison_json, '(.devices | length) > 0');

ok($length_gt[0], 'bare length result supports greater-than comparison');
ok($length_ge[0], 'bare length result supports greater-than-or-equal comparison');
ok($length_eq[0], 'bare length result supports equality comparison');
ok($length_ne[0], 'bare length result supports inequality comparison');
ok($count_gt[0], 'current numeric value supports comparison after a pipe');
ok($count_eq[0], 'current numeric value supports equality after a pipe');
ok($string_eq[0], 'current string value supports equality after a pipe');
ok($parenthesized[0], 'parenthesized pipeline result supports comparison');

done_testing;
