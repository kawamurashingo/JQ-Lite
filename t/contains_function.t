use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;
my @cases = (
    [ '[1,2,3]', 'contains([1,3])', '[true]', 'contains-array-subset' ],
    [ '[1,2]', 'contains([3])', '[false]', 'contains-array-missing' ],
    [ '[1,2]', 'contains([])', '[true]', 'contains-array-empty' ],
    [ '[]', 'contains([1])', '[false]', 'contains-array-empty-haystack' ],
    [ '[1]', 'contains([1,1])', '[true]', 'contains-array-repeated' ],
    [ '[[1,2,3]]', 'contains([[1,3]])', '[true]', 'contains-nested-array' ],
    [ '{"a":{"b":1,"c":2}}', 'contains({"a":{"b":1}})', '[true]', 'contains-object-partial' ],
    [ '{"a":null}', 'contains({"b":null})', '[false]', 'contains-object-missing' ],
    [ '{"a":null}', 'contains({"a":null})', '[true]', 'contains-object-null' ],
    [ '{"a":1}', 'contains({})', '[true]', 'contains-object-empty' ],
    [ '[{"id":1,"name":"A"}]', 'contains([{"id":1}])', '[true]', 'contains-array-object' ],
    [ '["1"]', 'contains([1])', '[false]', 'contains-array-string-number' ],
    [ '[true]', 'contains([1])', '[false]', 'contains-array-boolean-number' ],
    [ '{"a":1}', 'contains({"a":"1"})', '[false]', 'contains-object-string-number' ],
    [ '["foobar"]', 'contains(["bar"])', '[true]', 'contains-array-substring' ],
    [ '"\u65e5\u672c\u8a9e\u306eJSON"', 'contains("日本語")', '[true]', 'contains-unicode' ],
    [ '100', 'contains(100)', '[true]', 'contains-number-exact' ],
    [ '100', 'contains(1)', '[false]', 'contains-number-not-substring' ],
    [ 'true', 'contains(true)', '[true]', 'contains-boolean-equal' ],
    [ 'null', 'contains(null)', '[true]', 'contains-null' ],
    [ '[1,2]', 'select(contains([2]))', '[[1,2]]', 'contains-select-true' ],
    [ '[1,2]', 'select(contains([3]))', '[]', 'contains-select-false' ],
    [ '[1,2,3]', 'map(contains(1))', '[[true,false,false]]', 'contains-map' ],
    [ 'false', 'contains(false)', '[true]', 'contains-boolean-false-equal' ],
    [ '[true]', 'contains([false])', '[false]', 'contains-nested-boolean-mismatch' ],
 );
for my $case (@cases) {
    my ($input, $query, $expected, $name) = @$case;
    is_deeply([ $jq->run_query($input, $query) ], $json->decode($expected), $name);
}

my @errors = (
    [ 'true', 'contains(false)', 'contains-boolean-different' ],
    [ 'false', 'contains(true)', 'contains-boolean-reverse-error' ],
    [ '[1,2]', 'contains(1)', 'contains-array-scalar-error' ],
    [ '{"lang":"perl"}', 'contains("lang")', 'contains-object-key-error' ],
    [ 'null', 'contains("x")', 'contains-null-string-error' ],
    [ '"abc"', 'contains(null)', 'contains-string-null-error' ],
    [ '"1"', 'contains(1)', 'contains-string-number-error' ],
    [ '1', 'contains("1")', 'contains-number-string-error' ],
    [ 'true', 'contains(1)', 'contains-boolean-number-error' ],
    [ '[1,2]', 'select(contains(2))', 'contains-select-type-error' ],
 );
for my $case (@errors) {
    my ($input, $query, $name) = @$case;
    my $ok = eval { $jq->run_query($input, $query); 1 };
    ok(!$ok, $name);
    isa_ok($@, 'JQ::Lite::Error::Evaluation') unless $ok;
}

is_deeply([ $jq->run_query('["perl","json"]', 'index("perl") != null') ],
    [JSON::PP::true], 'exact array membership migration');
is_deeply([ $jq->run_query('{"lang":"perl"}', 'has("lang")') ],
    [JSON::PP::true], 'object key existence migration');

done_testing;
