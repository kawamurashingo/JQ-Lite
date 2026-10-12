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

subtest 'completed pipeline members survive a later error' => sub {
    my $mixed = '[{"name":"Ada"},3,{"name":"Later"}]';
    is_deeply(results($mixed, 'try (.[] | .name)'), ['Ada'],
        'no-catch suppresses the error without losing the first output');
    is_deeply(results($mixed, 'try (.[] | .name) catch 42'), ['Ada', 42],
        'fallback follows the completed first element');
    is_deeply(results($mixed, 'try (.[] | .name) catch null'),
        ['Ada', undef], 'explicit null fallback is not dropped');
    is_deeply(results($mixed, 'try (.[] | .name) catch empty'), ['Ada'],
        'explicit empty fallback leaves completed output');
    is_deeply(results('[[1],[2],3,[4]]', 'try (.[] | .[]) catch 9'),
        [1,2,9], 'completed nested array elements precede the error');
    is_deeply(results('[[1],[2],3,[4]]', 'try (.[] | .[])'),
        [1,2], 'no-catch preserves completed nested array members');
    is_deeply(results('[1,2,"bad",4]', 'try (.[] | . + 1) catch 42'),
        [2,3,42], 'arithmetic errors retain earlier pipeline results');
};

subtest 'optional heads, multi-stage tails and comma alternatives' => sub {
    is_deeply(results('[{"name":"Ada"},3,{"name":"Later"}]',
        'try (.[]? | .name) catch 42'), ['Ada',42],
        'optional root iterator still catches later strict field error');
    is_deeply(results('[{"name":"Ada"},3]',
        'try (.[] | .name | tostring) catch 9'), ['Ada',9],
        'multi-stage tail retains prior completed element');
    is_deeply(results('[{"name":"Ada"},3]',
        'try ((.[] | .name), 88) catch 9'), ['Ada',9],
        'parenthesized comma alternatives skip later branch on error');
    is_deeply(results('[{"name":"Ada"},3]',
        'try (.[] | .name) catch type'), ['Ada','string'],
        'catch still receives the secondary evaluation error string');
};

subtest 'successful, missing and invalid heads are unchanged' => sub {
    is_deeply(results('[{"name":null},{"name":"Jane"}]',
        'try (.[] | .name)'), [undef, 'Jane'],
        'successful JSON null remains a real output');
    is_deeply(results('[]', 'try (.[] | .name) catch 9'), [],
        'empty array emits no values, not an error');
    is_deeply(results('3', 'try (.[] | .name) catch 9'), [9],
        'strict iterator error on the root still invokes catch');
    is_deeply(results('[{"name":"Ada"},{"name":"Bob"}]',
        'try (.[] | .name)'), ['Ada','Bob'],
        'all completed elements remain in order');
    is_deeply(results('[1,2]', 'try .[]'), [1,2],
        'bare try iterator remains unchanged');
};

done_testing;
