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

subtest 'completed comma-head alternatives survive later failure' => sub {
    my $head = '(0, (1 / 0), 9) | . + 1';
    is_deeply(results('null', "try ($head) catch 42"),
        [1,42], 'successful head value passes through tail before error');
    is_deeply(results('null', "try ($head)"),
        [1], 'no catch preserves completed head output');
    is_deeply(results('null', "try ($head) catch null"),
        [1,undef], 'explicit null is appended as a real value');
    is_deeply(results('null', "try ($head) catch empty"),
        [1], 'empty catch leaves completed head output');
    is_deeply(results('null', 'try ((0, (1 / 0), 9) | type) catch 42'),
        ['number',42], 'typed tail retains first completed head output');
    is_deeply(results('null', "try ($head) catch (42,43)"),
        [1,42,43], 'multi-result handler follows successful output');
    is_deeply(results('null',
        'try ((0, empty, 1, (1 / 0)) | . + 10) catch 42'),
        [10,11,42], 'an empty head alternative does not block later output');
};

subtest 'downstream errors stop before later alternatives' => sub {
    is_deeply(results('null',
        'try ((0, 1, 2) | if . == 1 then (1 / 0) else . end) catch 42'),
        [0,42], 'tail error stops remaining comma-head inputs');
    is_deeply(results('null',
        'try ((0, 1, 2) | .[]) catch 42'),
        [42], 'strict tail error on first head value is caught');
    is_deeply(results('null',
        'try ((0, (1 / 0), 9) | . + 1 | tostring) catch 42'),
        ['1',42], 'multi-stage tail preserves completed result');
    is_deeply(results('null',
        'try (((0, (1 / 0), 9) | . + 1), 8) catch 42'),
        [1,42], 'later try comma branch skipped on failure');
    is_deeply(results('null',
        '0, (try ((0, (1 / 0), 9) | . + 1) catch 42), 9'),
        [0,1,42,9], 'outer comma branches continue after caught error');
};

subtest 'successful comma heads preserve null/false, strings, empty' => sub {
    is_deeply(results('null',
        'try ((null, false, (1 / 0), 9) | .) catch 42'),
        [undef,JSON::PP::false,42],
        'null and false are outputs, not missing values');
    is_deeply(results('null',
        'try ((0, 1, 2) | . + 1)'),
        [1,2,3], 'fully successful head emits all values');
    is_deeply(results('null',
        'try ((null, 2) | .)'),
        [undef,2], 'successful null stays a visible result');
    is_deeply(results('null',
        'try ((empty, 2) | . + 1)'),
        [3], 'empty first alternative skips only itself');
    is_deeply(results('null',
        'try (("a,b", "c") | .)'),
        ['a,b','c'], 'commas in JSON strings do not split alternatives');
    is_deeply(results('null',
        'try (0, (1 / 0), 9) catch 42'),
        [0,42], 'bare comma in try remains on its previous code path');
};

done_testing;
