use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;

sub run {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

is_deeply(run('[3,1,2,-4]', 'sort'), [[-4,1,2,3]],
    'sort preserves ascending numerical order');
is_deeply(run('[3,1,2,-4]', 'sort_desc'), [[3,2,1,-4]],
    'sort_desc preserves descending numerical order');

is_deeply(run('["pear","apple","banana"]', 'sort'),
    [['apple','banana','pear']], 'sort preserves lexical text order');
is_deeply(run('["pear","apple","banana"]', 'sort_desc'),
    [['pear','banana','apple']], 'sort_desc preserves reverse text order');

is_deeply(run('["10","2","30"]', 'sort'),
    [['2','10','30']], 'v2 sort retains numeric-looking string comparison');
is_deeply(run('["10","2","30"]', 'sort_desc'),
    [['30','10','2']], 'v2 sort_desc retains numeric-looking string comparison');

is_deeply(run('[2,1,2,1]', 'sort'), [[1,1,2,2]],
    'ascending sort keeps duplicate elements');
is_deeply(run('[2,1,2,1]', 'sort_desc'), [[2,2,1,1]],
    'descending sort keeps duplicate elements');

for my $filter ('sort', 'sort_desc') {
    is_deeply(run('[]', $filter), [[]],
        "$filter accepts an empty array");
    is_deeply(run('[42]', $filter), [[42]],
        "$filter accepts a one-item array");
    is_deeply(run('{"a":1}', $filter), [{a=>1}],
        "$filter retains v2 object passthrough");
    is_deeply(run('42', $filter), [42],
        "$filter retains v2 scalar passthrough");
    is_deeply(run('null', $filter), [undef],
        "$filter retains v2 null passthrough");
}

is_deeply(run('[[3,1],[5,2]]', '.[] | sort'),
    [[1,3],[2,5]], 'sort preserves multiple-array output order');
is_deeply(run('[[3,1],[5,2]]', '.[] | sort_desc'),
    [[3,1],[5,2]], 'sort_desc preserves multiple-array output order');

done_testing;
