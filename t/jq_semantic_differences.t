use strict;
use warnings;

use Test::More;
use JQ::Lite;
use JSON::PP ();

my $jq = JQ::Lite->new;

sub result_for {
    my ($json, $query) = @_;
    my @results = $jq->run_query($json, $query);
    return $results[0];
}

subtest 'preserved 2.x compatibility semantics' => sub {
    ok(
        !result_for('[1,2,3]', 'contains([1,3])'),
        'contains does not treat its array argument as a jq-style subset',
    );

    ok(
        !result_for(
            '{"a":{"b":1,"c":2}}',
            'contains({"a":{"b":1}})',
        ),
        'contains requires equality for nested object values',
    );

    ok(
        !result_for('false', '. // 9'),
        'alternative preserves false instead of selecting its fallback',
    );

    is_deeply(
        result_for('[[1,2],[3]]', 'transpose'),
        [[1, 3]],
        'transpose truncates jagged matrices to their shortest row',
    );
};

subtest 'permissive and vectorised semantics' => sub {
    is(
        result_for('"1e3"', '. * 1'),
        1000,
        'multiplication numerically coerces a numeric-looking string',
    );

    is(
        result_for('true', '. + 1'),
        2,
        'addition numerically coerces a boolean',
    );

    is_deeply(
        result_for('[1.2,"2.8","x"]', 'floor'),
        [1, 2, 'x'],
        'floor vectorises and passes non-numeric values through',
    );

    is_deeply(
        result_for('["1","true","bad"]', 'fromjson'),
        [1, JSON::PP::true, 'bad'],
        'fromjson vectorises and passes invalid JSON text through',
    );

    my $match = result_for('42', 'match("2")');
    is(ref($match), 'HASH', 'match accepts a non-string scalar');
    is($match->{string}, '2', 'match uses the scalar string representation');
    is($match->{offset}, 1, 'match reports the coerced-string offset');
};

subtest 'explicit jq-style migration aid' => sub {
    ok(
        result_for('[1,2,3]', 'contains_subset([1,3])'),
        'contains_subset opts in to jq-style array subset containment',
    );
};

done_testing;
