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

subtest 'completed comma branches survive a later try error' => sub {
    is_deeply(results('null', 'try (0, (1 / 0), 9)'), [0],
        'try without catch preserves earlier completed output');
    is_deeply(results('null', 'try (0, (1 / 0), 9) catch 42'), [0,42],
        'explicit catch follows earlier output');
    is_deeply(results('null', 'try (0, (1 / 0), 9) catch type'),
        [0,'string'], 'catch receives the error message string');
    is_deeply(results('null', 'try (0, (1 / 0), 9) catch (42, 43)'),
        [0,42,43], 'multi-value handler follows retained output');
    is_deeply(results('null', 'try (0, .[])'), [0],
        'later strict iterator failure does not erase branch zero');
    is_deeply(results('null', 'try (0, .[]) catch 42'), [0,42],
        'later iterator error runs catch after earlier output');
};

subtest 'empty/successful alternatives remain independent' => sub {
    is_deeply(results('[1,2]', 'try (0, .[])'), [0,1,2],
        'successful iterator emits each element after literal output');
    is_deeply(results('null', 'try (0, empty, 9)'), [0,9],
        'empty alternative does not stop later alternatives');
    is_deeply(results('null', 'try (0, 1, 2)'), [0,1,2],
        'all successful comma branches retain order');
    is_deeply(results('null', 'try ([0, 1], (1 / 0)) catch 8'),
        [[0,1],8], 'array-constructor output is not flattened');
};

subtest 'explicit catches preserve null and false distinctly' => sub {
    is_deeply(results('null',
        'try (null, false, (1 / 0)) catch empty'),
        [undef, JSON::PP::false],
        'prior JSON null and false remain real outputs');
    is_deeply(results('null',
        'try (0, (1 / 0)) catch null'), [0,undef],
        'explicit null is appended after earlier success');
    is_deeply(results('null',
        'try (0, (1 / 0)) catch empty'), [0],
        'explicit empty retains only prior successful output');
    is_deeply(results('null',
        'try (0, (1 / 0)) catch (. | type)'), [0,'string'],
        'catch pipeline executes on the error string');
};

done_testing;
