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

my $input = '[1,[2],3,4]';
my $child = 'recurse(.[]? | if . == 3 then (1 / 0) else . end)';
my $prior = [[1,[2],3,4],1,[2],2];

subtest 'bare custom recurse yields preceding nodes before child errors' => sub {
    is_deeply(results($input, "try $child catch 42"),
        [@$prior,42], 'bare custom recurse keeps completed nodes');
    is_deeply(results($input, "try $child"),
        $prior, 'no-catch suppresses the remaining stream');
    is_deeply(results($input, "try $child catch null"),
        [@$prior,undef], 'explicit null is appended');
    is_deeply(results($input, "try $child catch empty"),
        $prior, 'empty handler keeps earlier nodes');
    is_deeply(results($input, "try $child catch type"),
        [@$prior,'string'], 'handler receives error string');
};

subtest 'child and tail pipelines preserve source order' => sub {
    is_deeply(results($input, "try ($child | .) catch 42"),
        [@$prior,42], 'identity tail sees already completed nodes');
    is_deeply(results($input, "try ($child | type) catch 42"),
        ['array','number','array','number',42],
        'type tail observes nodes before child filter error');
    is_deeply(results($input, "try ($child | . | type) catch 42"),
        ['array','number','array','number',42],
        'multi-stage tail preserves completed outputs');
    is_deeply(results($input,
        "try ($child | if . == 2 then (1 / 0) else . end) catch 42"),
        [[1,[2],3,4],1,[2],42],
        'tail failure stops recursion before later child error');
    is_deeply(results($input, "try (($child | type), 99) catch 42"),
        ['array','number','array','number',42],
        'later comma alternatives are skipped');
    is_deeply(results($input, "0, (try ($child | .) catch 42), 9"),
        [0,@$prior,42,9], 'outside comma branches still continue');
    is_deeply(results($input, "try ($child | .) catch (42,43)"),
        [@$prior,42,43], 'multiple outputs from handler keep order');
};

subtest 'zero, multiple, and multi-stage custom children' => sub {
    is_deeply(results($input,
        'try (recurse(.[]? | if . == 3 then empty else . end) | .) catch 42'),
        [[1,[2],3,4],1,[2],2,4],
        'empty child result skips only that subtree');
    is_deeply(results($input,
        'try (recurse(.[]? | empty) | .) catch 42'),
        [[1,[2],3,4]],
        'empty custom child stream retains root once');
    is_deeply(results('[1,2]',
        'try (recurse(.[]? | (., .)) | .) catch 42'),
        [[1,2],1,1,2,2],
        'two child-filter outputs are each visited');
    is_deeply(results('[[[1],[2]],3]',
        'try (recurse(.[]? | .[]?) | .) catch 42'),
        [[[[1],[2]],3],[1],[2]],
        'multi-stage child filter runs before next sibling');
};

subtest 'unchanged default, strict and optional recurse controls' => sub {
    is_deeply(results('null', "try $child catch 42"),
        [undef], 'null root emits one real null');
    is_deeply(results('[]', "try ($child | .) catch 42"),
        [[]], 'empty root array emits only itself');
    is_deeply(results($input, 'try recurse'),
        [[1,[2],3,4],1,[2],2,3,4],
        'bare default recurse unchanged');
    is_deeply(results($input, 'try recurse(.[]) catch 42'),
        [[1,[2],3,4],1,42],
        'strict child iterator error remains caught');
    is_deeply(results($input, 'try (recurse(.[]?) | type) catch 42'),
        ['array','number','array','number','number','number'],
        'optional recurse still emits all subtree nodes');
};

done_testing;
