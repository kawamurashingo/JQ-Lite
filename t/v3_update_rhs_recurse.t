use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Error ();
use JSON::PP ();

my $jq = JQ::Lite->new;

sub results {
    my ($input, $query) = @_;
    return [ $jq->run_query($input, $query) ];
}

subtest 'stop recurse before traversing unused descendants' => sub {
    is_deeply(results('{"a":1}', '.a |= recurse(. + 1)'),
        [{a => 1}], 'unbounded recursion returns current leaf immediately');
    is_deeply(results('{"a":1}', '.a |= (recurse(. + 1) | . + 2)'),
        [{a => 3}], 'downstream pipeline accepts first generated value');
    is_deeply(results('{"a":1}', '.a |= recurse(1 / 0)'),
        [{a => 1}], 'unused child division-by-zero never runs');
    is_deeply(results('{"a":1}', '.a |= (recurse(1 / 0) | . + 3)'),
        [{a => 4}], 'unused child error skipped after pipeline result');
    is_deeply(results('{"a":null}', '.a |= recurse(empty)'),
        [{a => undef}], 'JSON null is a result even with empty child filter');
    is_deeply(results('{"a":false}', '.a |= recurse(empty)'),
        [{a => JSON::PP::false}], 'JSON false is a result');
};

subtest 'only expand the recursion tree until a downstream match' => sub {
    is_deeply(results('{"a":1}',
            '.a |= (recurse(. + 1) | select(. > 3))'),
        [{a => 4}], 'unbounded recursion stops at first accepted descendant');
    is_deeply(results('{"a":1}',
            '.a |= (recurse(. + 1) | select(. > 3) | . + 1)'),
        [{a => 5}], 'multiple pipeline stages see accepted descendant');
    is_deeply(results('{"a":[1,4]}',
            '.a |= (recurse | select(. == 4))'),
        [{a => 4}], 'default recursion descends into arrays as needed');
    is_deeply(results('{"a":{"x":1,"y":4}}',
            '.a |= (recurse | select(. == 4))'),
        [{a => 4}], 'default recursion descends through object members');
    is_deeply(results('{"a":[[1],[4]]}',
            '.a |= (recurse | select(. == 4))'),
        [{a => 4}], 'default recursion traverses nested arrays');
    is_deeply(results('{"a":1}',
            '.a |= (recurse(empty) | select(. > 2))'),
        [{}], 'no accepted recursion output deletes the selected path');
};

subtest 'errors on required child expansion still propagate' => sub {
    my $ok = eval {
        $jq->run_query('{"a":1}',
            '.a |= (recurse(1 / 0) | select(false))');
        1;
    };
    ok(!$ok, 'rejecting initial value forces erroneous child filter to run');
    isa_ok($@, 'JQ::Lite::Error::Evaluation') unless $ok;
};

subtest 'array, object and nested update iterators share lazy recurse' => sub {
    is_deeply(results('{"items":[1,2]}',
            '.items[] |= recurse(. + 1)'),
        [{items => [1,2]}], 'array elements use current result');
    is_deeply(results('{"items":[1,2]}',
            '.items[] |= (recurse(. + 1) | select(. > 3))'),
        [{items => [4,4]}], 'each array element stops at its first descendant match');
    is_deeply(results('{"items":{"x":1,"y":2}}',
            '.items[] |= (recurse(. + 1) | select(. > 3))'),
        [{items => {x => 4,y => 4}}], 'object iterator delegates to lazy recurse');
    is_deeply(results('{"groups":[[1],[2]]}',
            '.groups[][] |= recurse(. + 1)'),
        [{groups => [[1],[2]]}], 'nested array iterators avoid infinite recursion');
    is_deeply(results('{"items":{"a.b":1,"":2}}',
            '.items[] |= recurse(. + 1)'),
        [{items => {'a.b' => 1, '' => 2}}], 'object keys remain literal');
};

subtest 'ordinary finite recurse still emits its complete stream' => sub {
    is_deeply(results('[1,[2]]', 'recurse'),
        [[1,[2]],1,[2],2], 'public run_query still computes all recurse outputs');
};

done_testing;
