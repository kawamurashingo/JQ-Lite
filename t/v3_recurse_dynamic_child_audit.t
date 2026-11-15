use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;
sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

my $input = '{"items":[{"id":1},{"id":2},{"id":3}]}';
my $nested = '{"items":[{"id":1,"items":[{"id":4}]},{"id":2},{"id":3}]}';
my $child = 'recurse(.["items"][]? | if .id == 2 then (1/0) else . end)';
my $root = { items => [{id=>1},{id=>2},{id=>3}] };
my $prior = [$root, {id=>1}];

subtest 'quoted child iterator retains earlier outputs' => sub {
    is_deeply(results($input, "try (. | ($child | .)) catch 42"),
        [@$prior,42], 'completed root and sibling survive child failure');
    is_deeply(results($input, "try (. | ($child | .))"),
        $prior, 'unhandled error preserves earlier outputs');
    is_deeply(results($input, "try (. | ($child | .)) catch empty"),
        $prior, 'catch empty does not discard completed outputs');
    is_deeply(results($input, "try (. | ($child | .)) catch null"),
        [@$prior,undef], 'catch null appends one JSON null');
    is_deeply(results($input, "try (. | ($child | .)) catch (42,43)"),
        [@$prior,42,43], 'multiple catch results follow completed outputs');
    is_deeply(results($input, "try (. | ($child | type)) catch type"),
        ['object','object','string'], 'error reaches the type catch handler');
    is_deeply(results($nested, "try (. | ($child | .)) catch 42"),
        [{items=>[{id=>1,items=>[{id=>4}]},{id=>2},{id=>3}]},
            {id=>1,items=>[{id=>4}]},{id=>4},42],
        'nested descendants appear in depth-first order');
};

subtest 'pipeline ordering and branch termination' => sub {
    is_deeply(results($input, "try (. | ($child | (.,0))) catch 42"),
        [$root,0,{id=>1},0,42], 'tail alternatives are emitted per child');
    is_deeply(results($input, "try (. | (($child | .),99)) catch 42"),
        [@$prior,42], 'later comma alternative is not visited');
    is_deeply(results($input, "try (. | (($child | .))) catch 42"),
        [@$prior,42], 'additional balanced parentheses retain order');
    is_deeply(results($input,
        "try (. | ($child | if .id == 1 then (1/0) else . end)) catch 42"),
        [$root,42], 'tail error stops before later child expansion');
    is_deeply(results("[$input, " . '{"items":[{"id":4}]}' . "]",
        "try (.[] | ($child | type)) catch 42"),
        ['object','object',42], 'outer iterator stops on first error');
};

subtest 'empty, multiple, and control child streams' => sub {
    is_deeply(results($input,
        'try (. | (recurse(.["items"][]? | if .id == 2 then empty else . end) | .)) catch 42'),
        [$root,{id=>1},{id=>3}], 'empty child skips only that child');
    is_deeply(results($input,
        'try (. | (recurse(.["items"][]? | (.,.)) | type)) catch 42'),
        ['object','object','object','object','object','object','object'],
        'each duplicate child is traversed');
    is_deeply(results('null', "try (. | ($child | .)) catch 42"),
        [undef], 'null root terminates normally');
    is_deeply(results($input, "try ($child | type) catch 42"),
        ['object','object',42], 'unwrapped custom recurse remains correct');
    is_deeply(results($input,
        'try (. | (recurse(.items[]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [@$prior,42], 'named-field recurse control remains unchanged');
};

done_testing;
