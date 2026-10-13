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

my $compound_json = '{"a":1,"b":2,"label":"rock and roll"}';
my @compound_cases = (
    ['.a > 0 and .b > 0',          1],
    ['.a > 2 and .b > 0',          0],
    ['.a > 2 or .b > 0',           1],
    ['.a > 2 or .b < 0',           0],
    ['(.a > 0) and (.b > 0)',      1],
    ['.a > 0 and (.b > 0)',        1],
    ['(.a > 2) or (.b > 0)',       1],
    ['(.a > 0 or .b < 0) and (.b > 0)', 1],
    ['.a > 0 or .a > 2 and .b < 0',     1],
    ['.label == "rock and roll"',  1],
    ['.missing == 1',               0],
    ['.missing != 1',               1],
    ['.missing == null',            1],
    ['.missing > 1',                0],
    ['.missing < 1',                1],
    ['.a == .missing',              0],
    ['.missing == .also_missing',   1],
);

for my $case (@compound_cases) {
    my ($query, $expected) = @$case;
    my @results = $jq->run_query($compound_json, $query);
    is(scalar(@results), 1, "$query returns one result");
    is($results[0] ? 1 : 0, $expected, "$query preserves compound comparison semantics");
}

for my $operator (qw(== != < <= > >=)) {
    is_deeply([ $jq->run_query('null', "empty $operator null") ], [],
        "$operator preserves an empty left operand");
    is_deeply([ $jq->run_query('null', "null $operator empty") ], [],
        "$operator preserves an empty right operand");
}

my $decoder = JSON::PP->new->allow_nonref;
my @stream_cases = (
    [ 'null', 'select(false) == null', '[]', 'filtered left operand' ],
    [ 'null', 'null == select(false)', '[]', 'filtered right operand' ],
    [ '[]', '.[] == null', '[]', 'empty array iterator' ],
    [ '{}', '.[] == null', '[]', 'empty object iterator' ],
    [ '{}', '.missing[]? == null', '[]', 'optional empty iterator' ],
    [ '{"items":[]}', '.items[] == null', '[]', 'empty named iterator' ],
    [ '[1,2]', '(.[] | select(. > 9)) == null', '[]', 'filtered iterator' ],
    [ 'null', '(empty | type) == null', '[]', 'empty operand after type' ],
    [ 'null', 'null == null', '[true]', 'explicit null comparison' ],
    [ '{}', '.missing == null', '[true]', 'missing named field' ],
    [ '{}', '.missing.value == null', '[true]', 'missing field chain' ],
    [ '{}', '.missing? == null', '[true]', 'missing optional field' ],
    [ 'null', '.missing? == null', '[true]', 'optional field on null' ],
    [ '{}', '.["missing"] == null', '[true]', 'missing quoted field' ],
    [ 'null', '.["missing"] == null', '[true]', 'quoted field on null' ],
    [ '{}', '."missing" == null', '[true]', 'missing dot-quoted field' ],
    [ '{}', '.["a.b"] == null', '[true]', 'missing dotted quoted key' ],
    [ '[1]', '.[5] == null', '[true]', 'out-of-range index' ],
    [ '[null]', '.[] == null', '[true]', 'iterator emits explicit null' ],
    [ '{"items":[null]}', '.items[0] == null', '[true]', 'null array slot' ],
    [ 'null', '(empty // null) == null', '[true]', 'explicit null fallback' ],
    [ '{"null":7}', '.null == null', '[false]', 'literal-named field' ],
    [ '{"type":"vm"}', '.type == "vm"', '[true]', 'builtin-named field' ],
    [ '{"empty":null}', '.empty == null', '[true]', 'empty-named null field' ],
    [ 'null', '(1,3) < (2,4)', '[true,false,true,true]', 'right-operand output order' ],
    [ 'null', '(empty,1) == (null,1)', '[false,true]', 'empty comma branch adds no null' ],
    [ 'null', '(1 / 0) == empty', '[]', 'empty right operand skips left error' ],
    [ 'null', '[empty == null]', '[[]]', 'empty comparison in array constructor' ],
    [ 'null', '{x: (empty == null)}', '[]', 'empty comparison in object constructor' ],
    [ 'null', '(empty == null) | type', '[]', 'empty comparison through a pipe' ],
    [ '{}', '(.missing?) == null', '[true]', 'parenthesized optional field' ],
    [ '{}', '(.["missing"]) == null', '[true]', 'parenthesized quoted field' ],
    [ '[]', '(.[]) == null', '[]', 'parenthesized empty iterator' ],
    [ '{}', '(.missing[]?) == null', '[]', 'parenthesized optional iterator' ],
    [ '{}', '( .missing.value? ) == null', '[true]', 'parenthesized optional field chain' ],
);
for my $case (@stream_cases) {
    my ($input, $query, $expected, $name) = @$case;
    is_deeply([ $jq->run_query($input, $query) ], $decoder->decode($expected), $name);
}

my $error;
{
    local $@;
    eval { $jq->run_query('null', 'empty == (1 / 0)') };
    $error = $@;
}
isa_ok($error, 'JQ::Lite::Error::Evaluation', 'right operand error remains structured');
like("$error", qr/Division by zero/, 'empty left operand does not hide right error');

is_deeply([ $jq->run_query('[]', '.name == null') ], [],
    'existing empty array projection stays empty in a comparison');

done_testing;
