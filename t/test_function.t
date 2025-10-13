use strict;
use warnings;
use Test::More;
use JSON::PP;
use JQ::Lite;

my $json = q({
  "title": "Hello Perl",
  "tags": ["perl", "json", "jq"],
  "digits": 42,
  "items": [
    { "name": "Alice" },
    { "name": "Bob" }
  ]
});

my $jq = JQ::Lite->new;

my @title_match = $jq->run_query($json, '.title | test("Perl")');
ok($title_match[0], 'title matches substring');

my @case_insensitive = $jq->run_query($json, '.title | test("perl"; "i")');
ok($case_insensitive[0], 'flags enable case-insensitive matches');

my @array_results = $jq->run_query($json, '.tags | test("j")');
is_deeply(
    $array_results[0],
    [ JSON::PP::false, JSON::PP::true, JSON::PP::true ],
    'arrays yield element-wise booleans',
);

my @number_match = $jq->run_query($json, '.digits | tostring | test("\\\\d{2}")');
ok($number_match[0], 'numbers can match after tostring conversion');

my @number_raw = $jq->run_query($json, '.digits | test("\\\\d{2}")');
ok($number_raw[0], 'numbers are matched directly when they resemble the pattern');

my @no_match = $jq->run_query($json, '.title | test("^World")');
ok(!$no_match[0], 'non-matching pattern returns false');

my @invalid = $jq->run_query($json, '.title | test("(")');
ok(!$invalid[0], 'invalid regex falls back to false without dying');

my @non_scalar = $jq->run_query($json, '.items | test("Alice")');
is_deeply(
    $non_scalar[0],
    [ JSON::PP::false, JSON::PP::false ],
    'objects inside arrays yield false',
);

done_testing;
