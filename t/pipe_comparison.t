use strict;
use warnings;

use Test::More;
use JSON::PP ();
use lib 'lib';
use JQ::Lite;

my $jq = JQ::Lite->new;
my $json = '{"devices":[{"mac":"aa"}],"count":3,"s":"x"}';

my @cases = (
    ['.devices | length > 0',       1],
    ['(.devices | length) > 0',     1],
    ['.devices | length >= 1',      1],
    ['.devices | length == 1',      1],
    ['.devices | length != 0',      1],
    ['.count | . > 0',              1],
    ['.count | . == 3',             1],
    ['.s | . == "x"',               1],
    ['.devices | length == 0',      0],
    ['.count | . < 3',              0],
);

for my $case (@cases) {
    my ($query, $expected) = @$case;
    my @results = $jq->run_query($json, $query);
    is(scalar(@results), 1, "$query returns one result");
    is($results[0] ? 1 : 0, $expected, "$query compares the piped value");
}

done_testing;
