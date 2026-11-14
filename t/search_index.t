use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq = JQ::Lite->new;
my @cases = (
    [ '"banana"', '"an"', 1, 3, 'repeated substring' ],
    [ '"aaaa"', '"aa"', 0, 2, 'overlapping substring' ],
    [ '"banana"', '"x"', undef, undef, 'missing substring' ],
    [ '"banana"', '""', undef, undef, 'empty substring' ],
    [ '""', '""', undef, undef, 'empty input and substring' ],
    [ '""', '"x"', undef, undef, 'empty input string' ],
    [ '"a.b.a.b"', '"a.b"', 0, 4, 'literal punctuation' ],
    [ '"\u65e5\u672c\u8a9e\u65e5\u672c"', '"\u672c"', 3, 12, 'Unicode byte offsets' ],
    [ '"\u00e9b"', '"b"', 2, 2, 'Latin-1 byte offsets' ],
    [ '[1,2,1]', '1', 0, 2, 'repeated array scalar' ],
    [ '[1,2]', '9', undef, undef, 'missing array scalar' ],
    [ '[]', '1', undef, undef, 'empty array' ],
    [ '[false,true,false]', 'false', 0, 2, 'false array value' ],
    [ '[null,1,null]', 'null', 0, 2, 'null array value' ],
    [ '[{"a":1},{"a":2},{"a":1}]', '{"a":1}', 0, 2, 'exact object element' ],
    [ '[{"a":1,"b":2}]', '{"a":1}', undef, undef, 'object search is exact' ],
    [ '["",1,""]', '""', 0, 2, 'empty string array element' ],
    [ 'null', '"a"', undef, undef, 'null haystack' ],
);
for my $case (@cases) {
    my ($input, $needle, $first, $last, $name) = @$case;
    is_deeply([ $jq->run_query($input, "index($needle)") ], [$first], "index: $name");
    is_deeply([ $jq->run_query($input, "rindex($needle)") ], [$last], "rindex: $name");
}

is_deeply([ $jq->run_query('"banana"', 'empty | index("an")') ], [],
    'index preserves an empty upstream stream');
is_deeply([ $jq->run_query('"banana"', 'empty | rindex("an")') ], [],
    'rindex preserves an empty upstream stream');
is_deeply([ $jq->run_query('["banana","can",""]', 'map(index("an"))') ], [[1,1,undef]],
    'map preserves first-match output order and null');
is_deeply([ $jq->run_query('["banana","can",""]', 'map(rindex("an"))') ], [[3,1,undef]],
    'map preserves last-match output order and null');

# These existing v2 extensions are separate from the substring correction.
is_deeply([ $jq->run_query('["1",1,"1"]', 'index(1), rindex(1)') ], [0,2],
    'array scalar coercion remains unchanged');
is_deeply([ $jq->run_query('[[],1,[]]', 'index([]), rindex([])') ], [0,2],
    'array needles keep exact-element lookup');
is_deeply([ $jq->run_query('"banana"', 'index(null), rindex(null)') ], [undef,undef],
    'legacy null-needle fallback remains unchanged');

done_testing;
