use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $json = q({
  "title": "Hello World",
  "tags": ["Perl", "JSON", "CLI"],
  "users": [
    {"name": "Alice"},
    {"name": "Bob"}
  ]
});

my $jq = JQ::Lite->new;

my @scalar_upper = $jq->run_query($json, '.title | upper');
is($scalar_upper[0], 'HELLO WORLD', 'upper converts scalar to uppercase');

my @scalar_lower = $jq->run_query($json, '.title | lower');
is($scalar_lower[0], 'hello world', 'lower converts scalar to lowercase');

my @array_upper = $jq->run_query($json, '.tags | upper');
is_deeply($array_upper[0], ['PERL', 'JSON', 'CLI'], 'upper converts array elements');

my @pipeline_lower = $jq->run_query($json, '.users[] | .name | lower');
is_deeply(\@pipeline_lower, ['alice', 'bob'], 'lower works in pipelines with flattened arrays');

done_testing;
