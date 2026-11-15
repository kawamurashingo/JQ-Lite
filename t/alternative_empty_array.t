use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq = JQ::Lite->new;
my @cases = (
    [ 'null', 'null // []', [[]], 'null chooses one empty array' ],
    [ 'null', 'false // []', [[]], 'false chooses one empty array' ],
    [ 'null', '0 // []', [0], 'zero is preserved' ],
    [ 'null', '"" // []', [''], 'empty string is preserved' ],
    [ 'null', 'true // []', [JSON::PP::true], 'true is preserved' ],
    [ 'null', 'null // [ ]', [[]], 'whitespace inside an empty array' ],
    [ 'null', '(null // [])', [[]], 'parenthesized alternative' ],
    [ 'null', 'null // [], 1', [[],1], 'comma retains an empty array before a scalar' ],
    [ 'null', '(null // [], false // [])', [[],[]], 'comma retains both empty arrays' ],
    [ 'null', 'empty // []', [[]], 'an empty left stream chooses the fallback' ],
    [ '{"value":null}', '.value // []', [[]], 'null named field' ],
    [ '{}', '.missing // []', [[]], 'missing named field' ],
    [ 'null', '. // []', [[]], 'null current value' ],
    [ '[]', '. // [1]', [[]], 'an empty input array remains a valid left value' ],
    [ 'null', '[null // []]', [[[]]], 'array constructor preserves the fallback value' ],
    [ 'null', '{x: (null // [])}', [{x=>[]}], 'object constructor preserves the fallback value' ],
    [ 'null', '(null // [])[]', [], 'explicit iteration consumes the empty array' ],
    [ 'null', 'null // [] | length', [0], 'length sees the empty array' ],
    [ 'null', 'null // [] | type', ['array'], 'type sees the empty array' ],
    [ 'null', '(true // [])[]?', [], 'optional boolean iteration emits nothing' ],
);
for my $case (@cases) {
    my ($input, $filter, $values, $name) = @$case;
    is_deeply([ $jq->run_query($input, $filter) ], $values, $name);
}

my $ok = eval { $jq->run_query('null', '(true // [])[]'); 1 };
my $error = $@;
ok(!$ok && ref($error) && $error->isa('JQ::Lite::Error::Evaluation'),
    'strict boolean iteration still raises a structured runtime error');

done_testing;
