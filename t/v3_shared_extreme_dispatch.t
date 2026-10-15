use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;

sub run {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

my $users = '[{"name":"Alice","score":3},'
          . '{"name":"Bob","score":9},'
          . '{"name":"Carol","score":5}]';

is_deeply(run($users, 'max_by(.score)'), [{name=>'Bob', score=>9}],
    'max_by selects greatest projected number');
is_deeply(run($users, 'min_by(.score)'), [{name=>'Alice', score=>3}],
    'min_by selects least projected number');

is_deeply(run($users, 'max_by(.name)'), [{name=>'Carol', score=>5}],
    'max_by compares projected string keys');
is_deeply(run($users, 'min_by(.name)'), [{name=>'Alice', score=>3}],
    'min_by compares projected string keys');

is_deeply(run('[3,-2,7,5]', 'max_by(.)'), [7],
    'max_by compares entire scalar elements');
is_deeply(run('[3,-2,7,5]', 'min_by(.)'), [-2],
    'min_by compares entire scalar elements');

is_deeply(run('[]', 'max_by(.)'), [undef],
    'max_by on empty array emits null');
is_deeply(run('[]', 'min_by(.)'), [undef],
    'min_by on empty array emits null');
is_deeply(run($users, 'max_by(.missing)'), [undef],
    'max_by on absent path yields null');
is_deeply(run($users, 'min_by(.missing)'), [undef],
    'min_by on absent path yields null');

my $ties = '[{"id":"first","score":4},'
         . '{"id":"second","score":4}]';
is_deeply(run($ties, 'max_by(.score)'),
    [{id=>'first', score=>4}], 'max_by keeps first tie');
is_deeply(run($ties, 'min_by(.score)'),
    [{id=>'first', score=>4}], 'min_by keeps first tie');

is_deeply(run('{"score":7}', 'max_by(.score)'), [{score=>7}],
    'max_by retains v2 object passthrough');
is_deeply(run('{"score":7}', 'min_by(.score)'), [{score=>7}],
    'min_by retains v2 object passthrough');
is_deeply(run('5', 'max_by(.)'), [5],
    'max_by retains v2 scalar passthrough');
is_deeply(run('5', 'min_by(.)'), [5],
    'min_by retains v2 scalar passthrough');
is_deeply(run('null', 'max_by(.)'), [undef],
    'max_by retains v2 null passthrough');
is_deeply(run('null', 'min_by(.)'), [undef],
    'min_by retains v2 null passthrough');

my $rows = '[[{"n":1},{"n":4}],[{"n":-3},{"n":2}]]';
is_deeply(run($rows, '.[] | max_by(.n)'), [{n=>4},{n=>2}],
    'max_by preserves ordered array streams');
is_deeply(run($rows, '.[] | min_by(.n)'), [{n=>1},{n=>-3}],
    'min_by preserves ordered array streams');

done_testing;
