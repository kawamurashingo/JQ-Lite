use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;

# Check the shared dispatcher against each existing legacy implementation.
# First/last/all results must retain their own cardinality and fallback rules.
my @cases = (
    ['"banana"', '"an"', 1, 3, [1, 3], 'repeated substring'],
    ['"aaaa"', '"aa"', 0, 2, [0, 1, 2], 'overlapping substring'],
    ['"banana"', '"x"', undef, undef, [], 'missing substring'],
    ['"banana"', '""', undef, undef, [], 'empty string needle'],
    ['"\u65e5\u672c\u8a9e\u65e5\u672c"', '"\u672c"', 3, 12, [3, 12], 'Unicode byte positions'],
    ['"\u00e9b\u00e9b"', '"b"', 2, 5, [2, 5], 'Latin-1 byte positions'],
    ['[1,2,1]', '1', 0, 2, [0, 2], 'array numeric search'],
    ['[null,2,null]', 'null', 0, 2, [0, 2], 'array null search'],
    ['[false,true,false]', 'false', 0, 2, [0, 2], 'array boolean search'],
    ['["1",1,"1"]', '1', 0, 2, [0, 1, 2], 'v2 array numeric-string coercion'],
    ['[{"x":1},{"x":2},{"x":1}]', '{"x":1}', 0, 2, [0, 2], 'deep object matches'],
    ['[[],1,[]]', '[]', 0, 2, [0, 2], 'array-valued needle'],
    ['[]', '1', undef, undef, [], 'empty input array'],
    ['"banana"', 'null', undef, undef, [], 'v2 string null-needle fallback'],
    ['null', '"x"', undef, undef, undef, 'null haystack'],
    ['{}', '"x"', undef, undef, [], 'v2 object search fallback'],
);

for my $case (@cases) {
    my ($input, $needle, $first, $last, $all, $label) = @$case;
    is_deeply([ $jq->run_query($input, "index($needle)") ], [$first],
        "index: $label");
    is_deeply([ $jq->run_query($input, "rindex($needle)") ], [$last],
        "rindex: $label");
    is_deeply([ $jq->run_query($input, "indices($needle)") ], [$all],
        "indices: $label");
}

is_deeply([ $jq->run_query('[[1,2,1],[3,2,2]]', '.[] | index(2)') ],
    [1,1], 'index preserves ordered multi-array streams');
is_deeply([ $jq->run_query('[[1,2,1],[3,2,2]]', '.[] | rindex(2)') ],
    [1,2], 'rindex preserves ordered multi-array streams');
is_deeply([ $jq->run_query('[[1,2,1],[3,2,2]]', '.[] | indices(2)') ],
    [[1],[1,2]], 'indices preserves ordered multi-array streams');

for my $search (qw(index rindex indices)) {
    is_deeply([ $jq->run_query('"banana"', "empty | $search(\"an\")") ], [],
        "$search preserves empty upstream streams");
}

done_testing;
