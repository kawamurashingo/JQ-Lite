use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;

my $json = <<'JSON';
{
  "data": [1, null, 2, null, 3]
}
JSON

my @result = $jq->run_query($json, '.data | compact()');

is_deeply(
    $result[0],
    [1, 2, 3],
    'compact() removes nulls from arrays'
);

my $preserve_json = <<'JSON';
{
  "data": [0, false, "", null, "ok"]
}
JSON

my @preserved = $jq->run_query($preserve_json, '.data | compact');

is_deeply(
    $preserved[0],
    [0, JSON::PP::false, q{}, 'ok'],
    'compact preserves falsey non-null values and supports compact without parentheses'
);

my $scalar_json = <<'JSON';
{
  "data": "not an array"
}
JSON

my @scalar = $jq->run_query($scalar_json, '.data | compact()');

is(
    $scalar[0],
    'not an array',
    'compact() leaves non-array values unchanged'
);

done_testing();
