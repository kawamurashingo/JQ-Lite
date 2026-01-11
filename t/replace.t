use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $json = q({
  "title": "Hello World",
  "tags": ["perl", "shell", "world"],
  "details": {
    "description": "perl world",
    "count": 2
  },
  "mixed": ["World", 42, null]
});

my $jq = JQ::Lite->new;

my @title = $jq->run_query($json, '.title | replace("World", "Perl")');
is($title[0], 'Hello Perl', 'replace updates simple scalar values');

my @tags = $jq->run_query($json, '.tags | replace("world", "globe")');
is_deeply(
    $tags[0],
    ['perl', 'shell', 'globe'],
    'replace processes array elements recursively'
);

my @description = $jq->run_query($json, '.details.description | replace("perl", "Perl")');
is($description[0], 'Perl world', 'replace respects case-sensitive search term');

my $count_ok = eval {
    $jq->run_query($json, '.details.count | replace("2", "three")');
    1;
};
my $count_err = $@;
ok(!$count_ok, 'replace errors on non-string scalar inputs');
like($count_err, qr/^replace\(\): argument must be a string/, 'replace error message mentions string');

my $mixed_ok = eval {
    $jq->run_query($json, '.mixed | replace("World", "Earth")');
    1;
};
my $mixed_err = $@;
ok(!$mixed_ok, 'replace errors when array contains non-string values');
like($mixed_err, qr/^replace\(\): argument must be a string/, 'replace array error mentions string');

my @empty_search = $jq->run_query($json, '.title | replace("", "no-op")');
is($empty_search[0], 'Hello World', 'replace is a no-op when search term is empty');

my @missing = $jq->run_query($json, '.missing? | replace("foo", "bar")');
ok(!defined $missing[0], 'replace leaves undef values as undef');

my @chained = $jq->run_query($json, '.title | replace("World", "Perl") | upper');
is($chained[0], 'HELLO PERL', 'replace result can be chained with other functions');

my @double = $jq->run_query($json, '.title | replace("l", "L")');
is($double[0], 'HeLLo WorLd', 'replace substitutes all occurrences of the search term');

my @numeric_string = $jq->run_query('null', '"v2" | replace("2", "two")');
is($numeric_string[0], 'vtwo', 'replace operates on string scalars even if they look numeric');

my @semicolon_args = $jq->run_query('null', '"123" | replace("1"; "9")');
is($semicolon_args[0], '923', 'replace supports semicolon-separated arguments');

done_testing;
