use strict;
use warnings;
use Test::More;
use JSON::PP;
use JQ::Lite;

my $json = q({
  "title": "JQ Lite",
  "tags": ["perl", "json", "cli"],
  "flags": [true, false, "true"],
  "multiline": "Line1\nline2"
});

my $jq = JQ::Lite->new;

my @basic = $jq->run_query($json, '.title | test("JQ")');
ok($basic[0], 'test() returns true when the pattern matches');

my @case_insensitive = $jq->run_query($json, '.title | test("jq"; "i")');
ok($case_insensitive[0], 'test() honors case-insensitive flag strings');

my @no_match = $jq->run_query($json, '.title | test("perl")');
ok(!$no_match[0], 'test() returns false when the pattern does not match');

my @array_match = $jq->run_query($json, '.tags | test("^j")');
is_deeply(
    $array_match[0],
    [JSON::PP::false, JSON::PP::true, JSON::PP::false],
    'test() maps across arrays and returns JSON booleans'
);

my @boolean_inputs = $jq->run_query($json, '.flags | test("^t")');
is_deeply(
    $boolean_inputs[0],
    [JSON::PP::true, JSON::PP::false, JSON::PP::true],
    'booleans are coerced to strings before testing'
);

my @flag_multi = $jq->run_query($json, '.multiline | test("^line"; "im")');
ok($flag_multi[0], 'test() accepts multiple regex flags');

my @invalid_regex = $jq->run_query($json, '.title | test("[")');
ok(!$invalid_regex[0], 'invalid regex patterns yield false');

done_testing;
