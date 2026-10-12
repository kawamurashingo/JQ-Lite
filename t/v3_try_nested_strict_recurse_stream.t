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

my $input = '[1,[2],3]';
subtest 'strict nested recurse yields node before child expansion errors' => sub {
    my $body = '. | (recurse(.[]) | type)';
    is_deeply(results($input, "try ($body) catch 42"),
        ['array','number',42], 'scalar type is emitted before strict iteration fails');
    is_deeply(results($input, "try ($body)"),
        ['array','number'], 'bare try preserves completed values');
    is_deeply(results($input, "try ($body) catch null"),
        ['array','number',undef], 'null handler appends actual JSON null');
    is_deeply(results($input, "try ($body) catch empty"),
        ['array','number'], 'empty handler does not remove prior outputs');
    is_deeply(results($input, "try ($body) catch type"),
        ['array','number','string'], 'caught error is passed as string');
    is_deeply(results($input, "try ($body) catch (42,43)"),
        ['array','number',42,43], 'multi-result catch follows completed stream');
    is_deeply(results($input, 'try (. | (recurse(.[]) | .)) catch 42'),
        [[1,[2],3],1,42], 'strict subtree emits root and first scalar');
    is_deeply(results($input, 'try (. | ((recurse(.[]) | type))) catch 42'),
        ['array','number',42], 'extra parenthesis layers preserve semantics');
};

subtest 'downstream filters and comma alternatives retain source order' => sub {
    is_deeply(results($input,
        'try (. | (recurse(.[]) | type) | tostring) catch 42'),
        ['array','number',42], 'trailing tostring processes preceding outputs');
    is_deeply(results($input,
        'try (. | ((recurse(.[]) | type), 99)) catch 42'),
        ['array','number',42], 'later comma alternative is skipped');
    is_deeply(results($input,
        'try (. | (recurse(.[]) | (.,99))) catch 42'),
        [[1,[2],3],99,1,99,42], 'each node feeds comma tail before expansion');
    is_deeply(results($input,
        'try (. | (recurse(.[]) | if . == 1 then (1/0) else . end)) catch 42'),
        [[1,[2],3],42], 'tail error stops before the scalar is emitted');
    is_deeply(results($input,
        '0,(try (. | (recurse(.[]) | type)) catch 42),9'),
        [0,'array','number',42,9], 'surrounding comma branches continue');
    is_deeply(results($input,
        'try ((. | (recurse(.[]) | type)),99) catch 42'),
        ['array','number',42], 'try-internal comma branch stops on error');
};

subtest 'null, false, empty and controls' => sub {
    is_deeply(results('null', 'try (. | (recurse(.[]) | type)) catch 42'),
        ['null',42], 'null root is yielded before strict iteration fails');
    is_deeply(results('false', 'try (. | (recurse(.[]) | type)) catch 42'),
        ['boolean',42], 'false root is yielded before strict iteration fails');
    is_deeply(results('[]', 'try (. | (recurse(.[]) | type)) catch 42'),
        ['array'], 'empty array has no child iteration error');
    is_deeply(results('[[1,[2],3],[4]]',
        'try (.[] | (recurse(.[]) | type)) catch 42'),
        ['array','number',42], 'outer iterator stops before next member');
    is_deeply(results('{"items":[[1,[2],3],[4]]}',
        'try (.items[] | (recurse(.[]) | type)) catch 42'),
        ['array','number',42], 'named-field outer iterator behaves identically');
    is_deeply(results($input,
        'try (. | (recurse(.[]?) | type))'),
        ['array','number','array','number','number'],
        'optional child recurse still skips invalid leaves');
    is_deeply(results($input,
        'try (recurse(.[]) | type) catch 42'),
        ['array','number',42], 'unwrapped strict recurse behavior unchanged');
};

done_testing;
