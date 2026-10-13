use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;
my @cases = (
    [ '"banana"', '"an"', [1,3], 'repeated substring' ],
    [ '"aaaa"', '"aa"', [0,1,2], 'overlapping substring' ],
    [ '"banana"', '"x"', [], 'missing substring' ],
    [ '"banana"', '""', [], 'empty substring' ],
    [ '""', '""', [], 'empty input and substring' ],
    [ '""', '"x"', [], 'empty input string' ],
    [ '"a.b.a.b"', '"a.b"', [0,4], 'literal punctuation' ],
    [ '"\u65e5\u672c\u8a9e\u65e5\u672c"', '"\u672c"', [3,12], 'Unicode byte offsets' ],
    [ '"\u00e9b\u00e9b"', '"b"', [2,5], 'Latin-1 byte offsets' ],
    [ '[1,2,1]', '1', [0,2], 'repeated array scalar' ],
    [ '[1,2]', '9', [], 'missing array scalar' ],
    [ '[]', '1', [], 'empty array' ],
    [ '[false,true,false]', 'false', [0,2], 'false array value' ],
    [ '[null,1,null]', 'null', [0,2], 'null array value' ],
    [ '[{"a":1},{"a":2},{"a":1}]', '{"a":1}', [0,2], 'exact object element' ],
    [ '[{"a":1,"b":2}]', '{"a":1}', [], 'object search is exact' ],
    [ '["",1,""]', '""', [0,2], 'empty string array element' ],
    [ 'null', '"a"', undef, 'null haystack' ],
    [ 'null', '"1"', undef, 'null haystack with a numeric string needle' ],
);
for my $case (@cases) {
    my ($input, $needle, $positions, $name) = @$case;
    is_deeply([ $jq->run_query($input, "indices($needle)") ], [$positions], $name);
}

is_deeply([ $jq->run_query('"banana"', 'empty | indices("an")') ], [],
    'indices preserves an empty upstream stream');
is_deeply([ $jq->run_query('["banana","can","",null]', 'map(indices("an"))') ],
    [[[1,3],[1],[],undef]], 'map preserves order, empty arrays and null');
is_deeply([ $jq->run_query('{}', '.missing | indices("a")') ], [undef],
    'a missing field still emits one null');
is_deeply([ $jq->run_query('null', 'indices("a") | . // []') ], [[]],
    'an explicit fallback restores an empty result array');
is_deeply([ $jq->run_query('"banana"', 'indices("an") | . // []') ], [[1,3]],
    'the explicit fallback preserves non-null search results');

# Retained v2 extensions remain separate from the supported string correction.
is_deeply([ $jq->run_query('["1",1,"1"]', 'indices(1)') ], [[0,1,2]],
    'array scalar coercion remains unchanged');
is_deeply([ $jq->run_query('[[],1,[]]', 'indices([])') ], [[0,2]],
    'array needles keep exact-element lookup');
is_deeply([ $jq->run_query('"banana"', 'indices(null)') ], [[]],
    'legacy null-needle fallback remains unchanged');
is_deeply([ $jq->run_query('{}', 'indices("a")') ], [[]],
    'legacy invalid-target fallback remains unchanged');
is_deeply([ $jq->run_query('null', 'indices(null)') ], [[]],
    'an invalid null needle keeps its v2 fallback on a null input');
for my $needle ('1', 'true', '[]', '{}') {
    is_deeply([ $jq->run_query('null', "indices($needle)") ], [[]],
        "a non-string needle keeps its v2 fallback on a null input: $needle");
}

done_testing;
