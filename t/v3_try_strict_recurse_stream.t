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

subtest 'strict recurse yields completed values before child expansion errors' => sub {
    my $array = '[1,[2],3]';
    is_deeply(results($array, 'try recurse(.[]) catch 42'),
        [[1,[2],3],1,42],
        'first scalar is emitted before its strict child lookup fails');
    is_deeply(results($array, 'try recurse(.[])'),
        [[1,[2],3],1], 'no catch drops only the failing remainder');
    is_deeply(results($array, 'try recurse(.[]) catch null'),
        [[1,[2],3],1,undef], 'explicit null catch is a real value');
    is_deeply(results($array, 'try recurse(.[]) catch empty'),
        [[1,[2],3],1], 'empty catch does not drop prior outputs');
    is_deeply(results($array, 'try recurse(.[]) catch type'),
        [[1,[2],3],1,'string'], 'catch receives the error string');
    is_deeply(results($array, 'try (recurse(.[]) | type) catch 42'),
        ['array','number',42], 'pipeline tail runs before expansion error');
    is_deeply(results($array, 'try (recurse(.[]) | type) catch null'),
        ['array','number',undef], 'pipeline catch null remains one result');
    is_deeply(results($array, 'try (recurse(.[]) | type) catch empty'),
        ['array','number'], 'pipeline catch empty retains prior results');
    is_deeply(results($array, 'try (recurse(.[]) | type) catch type'),
        ['array','number','string'], 'error type is string in handler input');
    is_deeply(results($array, 'try (recurse(.[]) | type) catch (42,43)'),
        ['array','number',42,43], 'multiple handler outputs are appended');
};

subtest 'strict recursion catches errors on null and false leaves' => sub {
    is_deeply(results('null', 'try recurse(.[]) catch 42'),
        [undef,42], 'null root is emitted before failing to iterate it');
    is_deeply(results('null', 'try (recurse(.[]) | type) catch 42'),
        ['null',42], 'null root type is emitted before iterator error');
    is_deeply(results('false', 'try (recurse(.[]) | type) catch 42'),
        ['boolean',42], 'false root is emitted before iterator error');
    is_deeply(results('[]', 'try recurse(.[]) catch 42'),
        [[]], 'empty array emits itself and terminates normally');
    is_deeply(results('[[1],3,[4]]', 'try recurse(.[]) catch 42'),
        [[[1],3,[4]],[1],1,42],
        'depth-first strict traversal preserves earlier nested values');
    is_deeply(results('[null,7]', 'try (recurse(.[]) | .) catch 42'),
        [[undef,7],undef,42],
        'null member is visible before its own iterator fails');
};

subtest 'tail errors, comma branches and optional controls' => sub {
    is_deeply(results('[1,[2],3]',
        'try (recurse(.[]) | if . == 1 then (1 / 0) else . end) catch 42'),
        [[1,[2],3],42], 'tail failure stops before expanding the member');
    is_deeply(results('[1,[2],3]',
        '0, (try (recurse(.[]) | type) catch 42), 9'),
        [0,'array','number',42,9],
        'surrounding comma alternatives continue after catch');
    is_deeply(results('[1,[2],3]',
        'try ((recurse(.[]) | type), 9) catch 42'),
        ['array','number',42],
        'later comma alternatives are skipped by the first error');
    is_deeply(results('[1,[2],3]',
        'try (recurse(.[]?) | type)'),
        ['array','number','array','number','number'],
        'optional child recurse continues after scalar leaves');
    is_deeply(results('[1,[2],3]', 'try recurse'),
        [[1,[2],3],1,[2],2,3],
        'default bare recurse remains unchanged');
};

done_testing;
