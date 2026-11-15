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
my $child = 'recurse(.[]? | if . == 3 then (1/0) else . end)';
my $prior = [[1,[2],3,4],1,[2],2];

subtest 'nested custom recurse keeps completed nodes before child errors' => sub {
    is_deeply(results($input, "try (. | ($child | .)) catch 42"),
        [@$prior,42], 'completed nodes precede the caught child error');
    is_deeply(results($input, "try (. | ($child | .))"),
        $prior, 'bare try preserves the completed stream');
    is_deeply(results($input, "try (. | ($child | .)) catch null"),
        [@$prior,undef], 'null catch produces one real output');
    is_deeply(results($input, "try (. | ($child | .)) catch empty"),
        $prior, 'empty catch does not discard prior results');
    is_deeply(results($input, "try (. | ($child | .)) catch type"),
        [@$prior,'string'], 'handler receives the error as a string');
    is_deeply(results($input, "try (. | ($child | .)) catch (42,43)"),
        [@$prior,42,43], 'multiple handler values follow earlier outputs');
};

subtest 'nested custom recurse feeds tails in depth-first order' => sub {
    is_deeply(results($input, "try (. | ($child | type)) catch 42"),
        ['array','number','array','number',42],
        'each completed node passes through type before later errors');
    is_deeply(results($input, "try (. | ($child | type | tostring)) catch 42"),
        ['array','number','array','number',42],
        'multiple downstream stages retain the completed output');
    is_deeply(results($input, "try (. | ($child | (.,0))) catch 42"),
        [[1,[2],3,4],0,1,0,[2],0,2,0,42],
        'downstream comma results preserve depth-first sequence');
    is_deeply(results($input, "try (. | (($child | type),99)) catch 42"),
        ['array','number','array','number',42],
        'later nested comma alternative is not visited');
    is_deeply(results($input, "try (. | (($child | .))) catch 42"),
        [@$prior,42], 'extra parentheses do not change result order');
    is_deeply(results($input,
        "try (. | ($child | if . == 2 then (1/0) else . end)) catch 42"),
        [[1,[2],3,4],1,[2],42],
        'early downstream failure stops before later child expansion');
};

subtest 'outer generators and comma branches stop at first error' => sub {
    is_deeply(results('[[1,[2],3,4],[4]]',
        "try (.[] | ($child | .)) catch 42"),
        [@$prior,42], 'second outer array is not visited');
    is_deeply(results('{"items":[[1,[2],3,4],[4]]}',
        "try (.items[] | ($child | .)) catch 42"),
        [@$prior,42], 'second named iterator member is not visited');
    is_deeply(results('{"items":[1,[2],3,4]}',
        "try (.items | ($child | .)) catch 42"),
        [@$prior,42], 'simple named field can feed nested recurse');
    is_deeply(results($input,
        "0,(try (. | ($child | .)) catch 42),9"),
        [0,@$prior,42,9], 'outer comma continues after caught error');
    is_deeply(results($input,
        "try ((. | ($child | .)),9) catch 42"),
        [@$prior,42], 'later inner comma branch is not evaluated');
};

subtest 'custom children can be empty, repeated, or skipped' => sub {
    is_deeply(results($input,
        'try (. | (recurse(.[]? | if . == 3 then empty else . end) | .)) catch 42'),
        [[1,[2],3,4],1,[2],2,4], 'a skipped child does not stop siblings');
    is_deeply(results($input,
        'try (. | (recurse(.[]? | empty) | .)) catch 42'),
        [[1,[2],3,4]], 'an empty child generator yields only its root');
    is_deeply(results('[1,2]',
        'try (. | (recurse(.[]? | (., .)) | type)) catch 42'),
        ['array','number','number','number','number'],
        'multiple child filter outputs are all visited');
    is_deeply(results('null', "try (. | ($child | .)) catch 42"),
        [undef], 'null root is one completed JSON null');
    is_deeply(results('false', "try (. | ($child | type)) catch 42"),
        ['boolean'], 'false root emits its boolean type');
    is_deeply(results('[]', "try (. | ($child | type)) catch 42"),
        ['array'], 'empty array emits only its root');
};

subtest 'previous unwrapped custom recurse remains unchanged' => sub {
    is_deeply(results($input, "try ($child | .) catch 42"),
        [@$prior,42], 'unwrapped custom child pipeline retains semantics');
};

done_testing;
