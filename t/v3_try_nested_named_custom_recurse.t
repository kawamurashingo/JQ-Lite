use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq = JQ::Lite->new;
sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

my $input = '{"items":[{"id":1},{"id":2},{"id":3}]}';
my $nested = '{"items":[{"id":1,"items":[{"id":4}]},{"id":2},{"id":3}]}';
my $child = 'recurse(.items[]? | if .id == 2 then (1/0) else . end)';
my $root = { items => [{id=>1},{id=>2},{id=>3}] };
my $prior = [$root, {id=>1}];

subtest 'named child iterator retains completed recursive outputs' => sub {
    is_deeply(results($input, "try (. | ($child | .)) catch 42"),
        [@$prior,42], 'root and first child survive later error');
    is_deeply(results($input, "try (. | ($child | .))"),
        $prior, 'unhandled error does not erase earlier nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch null"),
        [@$prior,undef], 'null catch is one visible JSON null');
    is_deeply(results($input, "try (. | ($child | .)) catch empty"),
        $prior, 'empty catch keeps completed nodes');
    is_deeply(results($input, "try (. | ($child | type)) catch type"),
        ['object','object','string'], 'handler sees error as string');
    is_deeply(results($input, "try (. | ($child | .)) catch (42,43)"),
        [@$prior,42,43], 'multi-output catch follows prior nodes');
    is_deeply(results($nested, "try (. | ($child | .)) catch 42"),
        [{items=>[{id=>1,items=>[{id=>4}]},{id=>2},{id=>3}]},
            {id=>1,items=>[{id=>4}]},{id=>4},42],
        'nested children are emitted depth-first before later failure');
};

subtest 'downstream and outer pipeline boundaries' => sub {
    is_deeply(results($input, "try (. | ($child | (.,0))) catch 42"),
        [$root,0,{id=>1},0,42], 'comma tail preserves per-child output order');
    is_deeply(results($input, "try (. | (($child | .),99)) catch 42"),
        [@$prior,42], 'later comma branch is skipped after first error');
    is_deeply(results($input, "try (. | (($child | .))) catch 42"),
        [@$prior,42], 'extra parentheses retain semantics');
    is_deeply(results($input,
        "try (. | ($child | if .id == 1 then (1/0) else . end)) catch 42"),
        [$root,42], 'tail failure stops before later child expansion');
    is_deeply(results("[$input, " . '{"items":[{"id":4}]}' . "]",
        "try (.[] | ($child | type)) catch 42"),
        ['object','object',42], 'outer iterator stops at first failed child');
};

subtest 'zero, multiple and skipped named child values' => sub {
    is_deeply(results($input,
        'try (. | (recurse(.items[]? | if .id == 2 then empty else . end) | .)) catch 42'),
        [$root,{id=>1},{id=>3}], 'skipping one child preserves later siblings');
    is_deeply(results($input,
        'try (. | (recurse(.items[]? | empty) | .)) catch 42'),
        [$root], 'empty child filter leaves root only');
    is_deeply(results($input,
        'try (. | (recurse(.items[]? | (.,.)) | type)) catch 42'),
        ['object','object','object','object','object','object','object'],
        'two outputs per child are each visited once');
    is_deeply(results('null', "try (. | ($child | .)) catch 42"),
        [undef], 'null root is not an error');
    is_deeply(results($input, "try ($child | type) catch 42"),
        ['object','object',42], 'unwrapped named-child visitor unchanged');
};

done_testing;
