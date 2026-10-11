use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Error ();
use JSON::PP ();

my $jq = JQ::Lite->new;

sub results {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

subtest 'update every array element and return the root exactly once' => sub {
    is_deeply(results('{"items":[1,2,3],"other":9}', '.items[] |= . + 1'),
        [{ items => [2,3,4], other => 9 }], 'iterated array and siblings');
    is_deeply(results('[1,2,3]', '.[] |= . + 1'),
        [[2,3,4]], 'root array iterator');
    is_deeply(results('{"items":[]}', '.items[] |= . + 1'),
        [{ items => [] }], 'empty iterator leaves root unchanged');
    is_deeply(results('{"items":[1,null,3]}', '.items[] |= . + 1'),
        [{ items => [2,1,4] }], 'null-valued element uses jq null arithmetic');
};

subtest 'nested fields and fixed array prefixes' => sub {
    is_deeply(results('{"items":[{"n":1},{"n":2}]}', '.items[].n |= . + 2'),
        [{ items => [{ n => 3 }, { n => 4 }] }], 'nested object field updated per element');
    is_deeply(results('{"items":[{},{"n":2}]}', '.items[].n |= . + 1'),
        [{ items => [{ n => 1 }, { n => 3 }] }], 'creates missing field per element');
    is_deeply(results('{"groups":[[1,2],[3,4]]}', '.groups[0][] |= . + 1'),
        [{ groups => [[2,3],[3,4]] }], 'fixed numeric prefix');
    is_deeply(results('{"a":[{"x":[1,2]},{"x":[3,4]}]}', '.a[].x[0] |= . + 2'),
        [{ a => [{ x => [3,2] }, { x => [5,4] }] }], 'fixed numeric suffix');
};

subtest 'delete selected array members without index-shift errors' => sub {
    is_deeply(results('{"items":[1,2,3]}', '.items[] |= empty'),
        [{ items => [] }], 'remove all elements from array');
    is_deeply(results('[1,2,3]', '.[] |= empty'),
        [[]], 'delete all elements of root array');
    is_deeply(results('{"items":[1,2,3]}', '.items[] |= select(. > 1)'),
        [{ items => [2,3] }], 'selectively remove elements');
    is_deeply(results('{"items":[{"n":1,"k":2},{"n":3,"k":4}]}', '.items[].n |= empty'),
        [{ items => [{ k => 2 }, { k => 4 }] }], 'delete nested key in each element');
};

subtest 'multi-result RHS uses its first value for each selected element' => sub {
    is_deeply(results('{"items":[1,2,3]}', '.items[] |= (., . + 1)'),
        [{ items => [1,2,3] }], 'old element is first result');
    is_deeply(results('{"items":[1,2]}', '.items[] |= (empty, 9)'),
        [{ items => [9,9] }], 'skip empty branch before first result');
    is_deeply(results('{"items":[1,2]}', '.items[] |= (null, 9)'),
        [{ items => [undef,undef] }], 'null remains a value');
};

subtest 'no implicit iteration on missing or non-array values' => sub {
    for my $case (
        ['{}', '.items[] |= . + 1', 'missing array'],
        ['{"items":null}', '.items[] |= . + 1', 'null array'],
        ['{"items":5}', '.items[] |= . + 1', 'number'],
        ['{"items":[1]}', '.items[].n |= . + 1', 'non-object member'],
    ) {
        my ($input, $filter, $label) = @$case;
        my $ok = eval { $jq->run_query($input, $filter); 1 };
        ok(!$ok, "$label: invalid target rejected");
        isa_ok($@, 'JQ::Lite::Error::Evaluation', "$label: structured runtime error") if !$ok;
    }
    my $ok = eval { $jq->run_query('{"items":[[1]]}', '.items[][] |= . + 1'); 1 };
    ok(!$ok, 'multiple iterator path syntax rejected until specified');
    isa_ok($@, 'JQ::Lite::Error::Parse') if !$ok;
};

done_testing;
