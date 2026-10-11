use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Error ();

my $jq = JQ::Lite->new;

sub results {
    my ($input, $query) = @_;
    return [ $jq->run_query($input, $query) ];
}

subtest 'skip later comma alternatives after first RHS result' => sub {
    is_deeply(results('{"a":1,"b":8}', '.a |= (7, 1 / 0)'),
        [{ a => 7, b => 8 }], 'unused division-by-zero branch is skipped');
    is_deeply(results('{"a":1}', '.a |= (. + 1, 1 / 0)'),
        [{ a => 2 }], 'computed first result is used before error branch');
    is_deeply(results('{"a":1}', '.a |= (empty, 7, 1 / 0)'),
        [{ a => 7 }], 'skip empty branch and stop after first value');
    is_deeply(results('{"a":1}', '.a |= ((empty), (7, 1 / 0))'),
        [{ a => 7 }], 'nested grouping short-circuits recursively');
    is_deeply(results('{"a":1}', '.a |= ((7, 8), 1 / 0)'),
        [{ a => 7 }], 'stop after first value of a grouped branch');
    is_deeply(results('{"a":1}', '.a |= (null, 1 / 0)'),
        [{ a => undef }], 'JSON null is a valid first result');
    is_deeply(results('{"a":1}', '.a |= (false, 1 / 0)'),
        [{ a => JSON::PP::false }], 'JSON false is a valid first result');
    is_deeply(results('{"a":1}', '.a |= (0, 1 / 0)'),
        [{ a => 0 }], 'numeric zero is a valid first result');
};

subtest 'no RHS values still deletes selected path' => sub {
    is_deeply(results('{"a":1,"b":3}', '.a |= (empty, empty)'),
        [{ b => 3 }], 'two empty alternatives delete field');
    is_deeply(results('{"a":[1,2]}', '.a[0] |= (empty, empty)'),
        [{ a => [2] }], 'two empty alternatives splice array slot');
    is_deeply(results('{"a":1}', '.a |= (empty, null, 1 / 0)'),
        [{ a => undef }], 'null after empty does not delete');
};

subtest 'later alternatives still run when all prior branches are empty' => sub {
    for my $case (
        ['{"a":1}', '.a |= (empty, 1 / 0)', 'later error after empty'],
        ['{"a":1}', '.a |= ((empty), 1 / 0)', 'later error after grouped empty'],
        ['{"a":1}', '.a |= (1 / 0, 7)', 'first error must propagate'],
    ) {
        my ($input, $query, $description) = @$case;
        my $ok = eval { $jq->run_query($input, $query); 1 };
        my $error = $@;
        ok(!$ok, "$description: query fails");
        isa_ok($error, 'JQ::Lite::Error::Evaluation',
            "$description: structured evaluation error") if !$ok;
    }
};

subtest 'single-path and nested iterator updates share the same policy' => sub {
    is_deeply(results('{"items":[1,2]}', '.items[] |= (., 1 / 0)'),
        [{ items => [1,2] }], 'array iterator skips unused later RHS branch');
    is_deeply(results('{"items":{"x":2,"y":3}}', '.items[] |= (., 1 / 0)'),
        [{ items => {x => 2, y => 3} }],
        'object iterator skips unused later RHS branch');
    is_deeply(results('{"items":[{"n":1},{"n":2}]}',
            '.items[].n |= (. + 1, 1 / 0)'),
        [{ items => [{n => 2},{n => 3}] }],
        'iterator with suffix skips unused later branch');
    is_deeply(results('{"groups":[[1],[2]]}', '.groups[][] |= (., 1 / 0)'),
        [{ groups => [[1],[2]] }],
        'nested iterator skips unused later RHS branch');
    is_deeply(results('{"items":{"a.b":1,"":2}}',
            '.items[] |= (. + 1, 1 / 0)'),
        [{ items => {'a.b' => 2, '' => 3} }],
        'object keys are preserved when evaluating lazily');
};

done_testing;
