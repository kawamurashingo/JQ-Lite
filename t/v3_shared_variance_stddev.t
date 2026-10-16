use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;

sub output {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

sub close_to {
    my ($got, $expected, $label) = @_;
    ok(defined($got) && abs($got - $expected) < 1e-12, $label)
        or diag("got: " . (defined $got ? $got : 'null')
            . "; expected: $expected");
}

is_deeply(output('[1,2,3,4]', 'variance'), [1.25],
    'variance uses population rather than sample denominator');
close_to(output('[1,2,3,4]', 'stddev')->[0], sqrt(1.25),
    'stddev takes square root of same population variance');

is_deeply(output('[-2,0,2]', 'variance'), [8/3],
    'variance handles negative, zero and positive numbers');
close_to(output('[-2,0,2]', 'stddev')->[0], sqrt(8/3),
    'stddev handles negative, zero and positive numbers');

is_deeply(output('[5]', 'variance'), [0],
    'single number has zero variance');
is_deeply(output('[5]', 'stddev'), [0],
    'single number has zero standard deviation');
is_deeply(output('["2","4"]', 'variance'), [1],
    'numeric-looking strings are retained as numbers');
is_deeply(output('["2","4"]', 'stddev'), [1],
    'numeric-looking string standard deviation stays numeric');

close_to(output('[true,false,2]', 'variance')->[0], 2/3,
    'JSON booleans continue to participate as one and zero');
close_to(output('[true,false,2]', 'stddev')->[0], sqrt(2/3),
    'JSON booleans preserve standard-deviation semantics');

is_deeply(output('[null,"bad",{},[7],2,4]', 'variance'), [1],
    'invalid/null/container values are excluded from variance');
is_deeply(output('[null,"bad",{},[7],2,4]', 'stddev'), [1],
    'invalid/null/container values are excluded from standard deviation');

for my $filter ('variance', 'stddev') {
    is_deeply(output('[]', $filter), [undef],
        "$filter on an empty array is null");
    is_deeply(output('[null,"bad",{}]', $filter), [undef],
        "$filter with no numeric values is null");
    is_deeply(output('{"n":4}', $filter), [{n=>4}],
        "$filter preserves v2 object passthrough");
    is_deeply(output('42', $filter), [42],
        "$filter preserves v2 numeric scalar passthrough");
    is_deeply(output('null', $filter), [undef],
        "$filter preserves v2 null scalar passthrough");
}

is_deeply(output('[[1,3],[2,6]]', '.[] | variance'), [1,4],
    'variance preserves ordered results from multiple arrays');
is_deeply(output('[[1,3],[2,6]]', '.[] | stddev'), [1,2],
    'stddev preserves ordered results from multiple arrays');

done_testing();
