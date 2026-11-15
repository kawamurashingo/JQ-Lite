use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;

sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

subtest 'first range result is generated without materializing large streams' => sub {
    is_deeply(results('{"a":17,"other":4}', '.a |= range(1000000000)'),
        [{a => 0, other => 4}], 'billion-item range stops at first number');
    is_deeply(results('{"a":17}', '.a |= (range(1000000000) | . + 5)'),
        [{a => 5}], 'downstream arithmetic stops early');
    is_deeply(results('{"a":17}', '.a |= (range(1000000000) | select(. > 3))'),
        [{a => 4}], 'downstream selector consumes only needed numbers');
    is_deeply(results('{"a":17}', '.a |= range(2;9)'),
        [{a => 2}], 'start/end form uses its first value');
    is_deeply(results('{"a":17}', '.a |= range(10;2;-3)'),
        [{a => 10}], 'negative-step range starts at its upper bound');
    is_deeply(results('{"a":17}', '.a |= (range(10;2;-3) | select(. < 9))'),
        [{a => 7}], 'negative step continues until first downstream success');
};

subtest 'empty sequences delete, while null is a result' => sub {
    is_deeply(results('{"a":17,"b":2}', '.a |= range(0;0)'),
        [{b => 2}], 'empty range removes selected object key');
    is_deeply(results('{"a":17}', '.a |= range(0;5;0)'),
        [{}], 'zero step emits no results');
    is_deeply(results('{"a":17}', '.a |= range(1;5;-1)'),
        [{}], 'wrong-direction step emits no results');
    is_deeply(results('{"a":17}', '.a |= (range(0;0), null)'),
        [{a => undef}], 'first output after empty range is JSON null');
    is_deeply(results('{"a":17}', '.a |= (range(0;3), 1 / 0)'),
        [{a => 0}], 'unused comma alternative is not evaluated');
    is_deeply(results('{"a":[2,3]}', '.a[0] |= range(0;0)'),
        [{a => [3]}], 'empty range splices array member');
    is_deeply(results('{"a":17}', '.a |= (range(0;4) | select(. > 8))'),
        [{}], 'empty downstream pipeline deletes target');
};

subtest 'range outputs flow one at a time through an RHS pipeline' => sub {
    is_deeply(results('{"a":17}', '.a |= (range(0;5) | select(. > 2) | . + 1)'),
        [{a => 4}], 'three stages stop at first complete output');
    is_deeply(results('{"a":17}', '.a |= (range(0;5) | select(. > 1) | (., 1 / 0))'),
        [{a => 2}], 'later downstream error branch is skipped');
    is_deeply(results('{"a":17}', '.a |= (range(0;3) | . + 1)'),
        [{a => 1}], 'simple downstream transformation');
    is_deeply(results('{"a":17}', '.a |= (range(0;0) | . + 1)'),
        [{}], 'empty upstream never evaluates downstream');
};

subtest 'errors on required range validation still propagate' => sub {
    for my $case (
        ['.a |= range("bad")', 'invalid end bound'],
        ['.a |= range(0; 2; "bad")', 'invalid step'],
    ) {
        my ($query, $label) = @$case;
        my $ok = eval { $jq->run_query('{"a":17}', $query); 1 };
        ok(!$ok, "$label raises an error");
        like("$@", qr/range\(\): (?:bounds|step) must be numeric/,
            "$label reports range argument failure") unless $ok;
    }
};

subtest 'array, object, and nested iterators inherit lazy range behavior' => sub {
    is_deeply(results('{"items":[1,2]}',
            '.items[] |= (range(1;10) | select(. > 3))'),
        [{items => [4,4]}], 'array iterator runs range on each old element');
    is_deeply(results('{"items":{"x":2,"y":3}}',
            '.items[] |= (range(1;10) | select(. > 3))'),
        [{items => {x => 4, y => 4}}], 'object values use first accepted number');
    is_deeply(results('{"groups":[[1],[2]]}', '.groups[][] |= range(20)'),
        [{groups => [[0],[0]]}], 'nested iterators each stop at range start');
    is_deeply(results('{"items":{"a.b":1,"":2}}', '.items[] |= range(5)'),
        [{items => {'a.b' => 0, '' => 0}}], 'special keys remain literal');
};

subtest 'normal run_query still emits complete finite range streams' => sub {
    is_deeply(results('null', 'range(5)'), [0,1,2,3,4],
        'ordinary one-argument range returns all numbers');
    is_deeply(results('null', 'range(10;2;-3)'), [10,7,4],
        'ordinary negative-step range preserves every number');
    is_deeply(results('null', 'range(0;3;0)'), [],
        'ordinary zero-step range produces an empty result stream');
};

done_testing;
