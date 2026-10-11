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

subtest 'pipeline follows the first complete RHS output' => sub {
    is_deeply(results('{"a":1}', '.a |= ((1,2) | . + 1)'),
        [{a => 2}], 'two upstream outputs produce only first downstream result');
    is_deeply(results('{"a":1}', '.a |= ((1,2) | (., 1 / 0))'),
        [{a => 1}], 'unused downstream alternative is never evaluated');
    is_deeply(results('{"a":1}', '.a |= ((1,0) | (1 / .))'),
        [{a => 1}], 'second upstream value cannot trigger division by zero');
    is_deeply(results('{"a":1}', '.a |= ((1,0) | (1 / .) | . + 5)'),
        [{a => 6}], 'three pipeline stages stop after the first completed output');
    is_deeply(results('{"a":1}', '.a |= (((1,2) | . + 1), 1 / 0)'),
        [{a => 2}], 'outer comma alternatives stop after nested pipeline output');
};

subtest 'empty downstream results continue with next upstream value' => sub {
    is_deeply(results('{"a":1}', '.a |= ((1,2) | select(. > 1) | . + 3)'),
        [{a => 5}], 'failed first predicate allows second upstream value');
    is_deeply(results('{"a":1}', '.a |= ((1,2) | (select(false), . + 1))'),
        [{a => 2}], 'empty alternative before a successful downstream filter');
    is_deeply(results('{"a":1}', '.a |= ((empty, 7) | . + 1)'),
        [{a => 8}], 'skip empty upstream alternative');
    is_deeply(results('{"a":1}', '.a |= ((1,2) | select(. > 1))'),
        [{a => 2}], 'skip rejected first upstream value');
};

subtest 'empty complete pipeline deletes instead of storing null' => sub {
    is_deeply(results('{"a":1,"b":4}', '.a |= ((1,2) | empty)'),
        [{b => 4}], 'both outputs filtered, so delete object key');
    is_deeply(results('{"a":1}', '.a |= ((1,2) | select(. > 7))'),
        [{}], 'no accepted output deletes object key');
    is_deeply(results('{"a":1}', '.a |= ((empty, empty) | . + 1)'),
        [{}], 'empty upstream never reaches downstream');
    is_deeply(results('{"a":[3,4]}', '.a[0] |= ((1,2) | empty)'),
        [{a => [4]}], 'deleting an indexed array element still splices');
    is_deeply(results('{"a":1}', '.a |= ((1,2) | null)'),
        [{a => undef}], 'JSON null downstream result is not deletion');
};

subtest 'later errors must still propagate if no earlier output succeeds' => sub {
    my $ok = eval {
        $jq->run_query('{"a":1}',
            '.a |= ((1,0) | select(. == 0) | (1 / .))');
        1;
    };
    ok(!$ok, 'error in first successful pipeline path is not swallowed');
    isa_ok($@, 'JQ::Lite::Error::Evaluation') unless $ok;
};

subtest 'existing update iterator paths reuse the pipeline first-value policy' => sub {
    is_deeply(results('{"items":[1,2]}', '.items[] |= ((1,2) | . + 1)'),
        [{items => [2,2]}], 'array iterator on each original leaf');
    is_deeply(results('{"items":{"a":1,"b":2}}',
            '.items[] |= ((1,2) | . + 1)'),
        [{items => {a => 2,b => 2}}], 'object iterator on each original leaf');
    is_deeply(results('{"items":[[1],[2]]}',
            '.items[][] |= ((1,2) | . + 1)'),
        [{items => [[2],[2]]}], 'nested iterator applies first-result pipeline');
    is_deeply(results('{"items":{"a.b":1,"":2}}',
            '.items[] |= ((1,2) | . + 1)'),
        [{items => {'a.b' => 2, '' => 2}}], 'special object keys remain literal');
};

subtest 'ordinary run_query still emits all values' => sub {
    is_deeply(results('null', '(1,2) | . + 1'),
        [2,3], 'public run_query retains full output stream');
    is_deeply(results('[1,2]', '.[] | . + 1'),
        [2,3], 'normal iterator pipeline remains eager and multi-output');
};

done_testing;
