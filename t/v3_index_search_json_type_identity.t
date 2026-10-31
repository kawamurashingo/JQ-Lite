use strict;
use warnings;
use Test::More;
use JQ::Lite;

# jq 1.7 array search compares JSON types, not Perl numeric coercions.
# In particular numeric 1 and string "1" are distinct, even when they
# occur inside otherwise identical objects.
my $jq = JQ::Lite->new;
my $json = q({"items":["1",1,"1",1,true,false,null,{"n":"1"},{"n":1}]});

for my $case (
    ['index(1)', 1],
    ['index("1")', 0],
    ['rindex(1)', 3],
    ['rindex("1")', 2],
    ['index(true)', 4],
    ['index(false)', 5],
    ['index(null)', 6],
    ['index({"n":1})', 8],
    ['index({"n":"1"})', 7],
    ['rindex({"n":1})', 8],
) {
    my ($filter, $expected) = @$case;
    my @out = $jq->run_query($json, ".items | $filter");
    is_deeply(\@out, [$expected], "$filter preserves JSON value types");
}

for my $case (
    ['indices(1)', [1, 3]],
    ['indices("1")', [0, 2]],
    ['indices(true)', [4]],
    ['indices(false)', [5]],
    ['indices(null)', [6]],
    ['indices({"n":1})', [8]],
    ['indices({"n":"1"})', [7]],
) {
    my ($filter, $expected) = @$case;
    my @out = $jq->run_query($json, ".items | $filter");
    is_deeply(\@out, [$expected], "$filter preserves JSON value types");
}

# String searching still uses substring matching rather than array
# element equality; do not change that separate behavior.
is_deeply(
    [ $jq->run_query(q("11"), 'index("1")') ],
    [0],
    'string index still finds a substring'
);
is_deeply(
    [ $jq->run_query(q("11"), 'indices("1")') ],
    [[0, 1]],
    'string indices still finds all substrings'
);

done_testing;
