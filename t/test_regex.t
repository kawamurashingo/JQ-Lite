use strict;
use warnings;
use Test::More;
use JSON::PP;
use JQ::Lite;

my $json = q({
  "title": "Hello World!",
  "names": ["Alice", "bob", "Carol"],
  "misc": [null, 42, {"key": "value"}]
});

my $jq = JQ::Lite->new;

my @basic_match = $jq->run_query($json, '.title | test("World")');
ok($basic_match[0], 'test() returns true when the pattern matches');

my @case_sensitive = $jq->run_query($json, '.title | test("world")');
ok(!$case_sensitive[0], 'test() remains case-sensitive without flags');

my @case_insensitive = $jq->run_query($json, '.title | test("world"; "i")');
ok($case_insensitive[0], 'test() respects the case-insensitive flag');

my @array_projection = $jq->run_query($json, '.names | test("^A")');
is_deeply(
    $array_projection[0],
    [JSON::PP::true, JSON::PP::false, JSON::PP::false],
    'test() maps over arrays and returns JSON booleans'
);

my @multiple_flags = $jq->run_query($json, '.title | test("HELLO"; "im")');
ok($multiple_flags[0], 'test() accepts multiple regex flags');

my @non_strings = $jq->run_query($json, '.misc | test("val")');
is_deeply(
    $non_strings[0],
    [JSON::PP::false, JSON::PP::false, JSON::PP::false],
    'non-string inputs evaluate to false'
);

my @invalid_regex = $jq->run_query($json, '.title | test("(")');
ok(!$invalid_regex[0], 'test() returns false when regex compilation fails');

done_testing;
