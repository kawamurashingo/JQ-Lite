use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $json = q({
  "meta": {
    "version": "1.0",
    "author": "you"
  },
  "items": [10, 20, 30]
});

my $jq = JQ::Lite->new;

my @result1 = $jq->run_query($json, 'select(.meta has "version")');
my @result2 = $jq->run_query($json, 'select(.meta has "missing")');
my @result3 = $jq->run_query($json, 'select(.items has 1)');
my @result4 = $jq->run_query($json, 'select(.items has 5)');
my @result5 = $jq->run_query($json, 'select(.items has "1")');
my @result6 = $jq->run_query($json, 'select(.items has null)');

ok(@result1, 'meta has version');
ok(!@result2, 'meta does not have missing key');
ok(@result3, 'items has numeric index 1');
ok(!@result4, 'items does not have index 5');
ok(!@result5, 'items does not coerce numeric strings to indices');
ok(!@result6, 'items does not accept null as an index');

done_testing;
