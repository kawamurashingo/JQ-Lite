use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Error ();

my $jq = JQ::Lite->new;

sub results {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

subtest 'child comma branches stop when first descendant matches' => sub {
    is_deeply(results('{"a":1}',
            '.a |= (recurse((. + 1, 1 / 0)) | select(. > 1))'),
        [{ a => 2 }], 'unused second child filter branch never raises error');
    is_deeply(results('{"a":1}',
            '.a |= (recurse((. + 1, 1 / 0)) | select(. > 3))'),
        [{ a => 4 }], 'depth-first descendants precede unused sibling errors');
    is_deeply(results('{"a":1}',
            '.a |= (recurse((. + 1, 1 / 0)) | select(. == 5))'),
        [{ a => 5 }], 'custom child stream continues until matching descendant');
    is_deeply(results('{"a":1}',
            '.a |= (recurse((. + 1, 1 / 0)) | select(. > 1) | . + 10)'),
        [{ a => 12 }], 'stop after first complete downstream pipeline output');
    is_deeply(results('{"a":1}',
            '.a |= (recurse((. + 1, empty, 1 / 0)) | select(. > 1))'),
        [{ a => 2 }], 'empty sibling and error sibling remain unvisited');
};

subtest 'nested child filters produce a depth-first stream' => sub {
    is_deeply(results('{"a":1}',
            '.a |= (recurse(((. + 1, . + 2) | select(. < 4))) | select(. == 3))'),
        [{ a => 3 }], 'child pipeline is visited before later siblings');
    is_deeply(results('{"a":1}',
            '.a |= (recurse((range(2;1000000000), 1 / 0)) | select(. > 1))'),
        [{ a => 2 }], 'enormous child range and unused error do not materialize');
    is_deeply(results('{"a":1}',
            '.a |= (recurse(if . == 1 then (0, 2) else empty end) | select(. == 2))'),
        [{ a => 2 }], 'finite child stream visits second sibling after first subtree');
    is_deeply(results('{"a":1}',
            '.a |= (recurse(empty) | select(. > 2))'),
        [{}], 'empty recursive child stream still deletes unaccepted path');
};

subtest 'required child errors must still propagate' => sub {
    for my $case (
        ['.a |= (recurse((empty, 1 / 0)) | select(. > 1))',
            'empty first child requires error branch'],
        ['.a |= (recurse(1 / 0) | select(. > 1))',
            'single failing child filter is needed'],
    ) {
        my ($filter, $description) = @$case;
        my $ok = eval { $jq->run_query('{"a":1}', $filter); 1 };
        my $error = $@;
        ok(!$ok, "$description fails");
        isa_ok($error, 'JQ::Lite::Error::Evaluation',
            "$description is a structured evaluation failure") if !$ok;
    }
};

subtest 'nested array and object updates reuse streamed children' => sub {
    is_deeply(results('{"items":[1,2]}',
            '.items[] |= (recurse((. + 1, 1 / 0)) | select(. > 3))'),
        [{ items => [4,4] }], 'array iterator stops at first descendant match');
    is_deeply(results('{"items":{"x":1,"y":2}}',
            '.items[] |= (recurse((. + 1, 1 / 0)) | select(. > 3))'),
        [{ items => {x => 4,y => 4} }], 'object iterator skips error siblings');
    is_deeply(results('{"groups":[[1],[2]]}',
            '.groups[][] |= (recurse((. + 1, 1 / 0)) | select(. > 3))'),
        [{ groups => [[4],[4]] }], 'two nested iterators skip error siblings');
    is_deeply(results('{"items":{"a.b":1,"":2}}',
            '.items[] |= (recurse((. + 1, 1 / 0)) | select(. > 3))'),
        [{ items => {'a.b' => 4, '' => 4} }],
        'special object keys remain literal and untouched');
};

subtest 'ordinary finite recurse queries preserve all of their outputs' => sub {
    is_deeply(results('[1,[2]]', 'recurse(.[])'),
        [[1,[2]],1,[2],2], 'public recurse still emits every value for finite inputs');
};

done_testing;
