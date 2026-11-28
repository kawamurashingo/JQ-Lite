use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;

sub run {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

my $users = '[{"k":"B","v":1},{"k":"A","v":2},'
          . '{"k":"B","v":3},{"k":"A","v":4}]';
my $groups = [
    [{k=>'A', v=>2},{k=>'A', v=>4}],
    [{k=>'B', v=>1},{k=>'B', v=>3}],
];

is_deeply(run($users, 'group_by(.k)'), [$groups],
    'group_by sorts by signature but retains input order within a key');
is_deeply(run($users, 'group_by( .k )'), [$groups],
    'group_by supports whitespace around a path');
is_deeply(run($users, 'group_by(".k")'), [$groups],
    'group_by supports quoted dotted paths');
is_deeply(run($users, 'group_by(k)'), [$groups],
    'group_by supports unprefixed key paths');

my $counts = {A=>2, B=>2};
is_deeply(run($users, 'group_count(.k)'), [$counts],
    'group_count counts projected keys');
is_deeply(run($users, 'group_count( .k )'), [$counts],
    'group_count supports whitespace around a path');
is_deeply(run($users, 'group_count(".k")'), [$counts],
    'group_count supports quoted dotted paths');
is_deeply(run($users, 'group_count(k)'), [$counts],
    'group_count supports unprefixed key paths');

my $nested = '[{"meta":{"k":2},"v":"a"},'
           . '{"meta":{"k":1},"v":"b"},'
           . '{"meta":{"k":2},"v":"c"}]';
is_deeply(run($nested, 'group_by(.meta.k)'), [[
    [{meta=>{k=>1},v=>'b'}],
    [{meta=>{k=>2},v=>'a'},{meta=>{k=>2},v=>'c'}],
]], 'group_by normalizes nested paths');
is_deeply(run($nested, 'group_count(.meta.k)'), [{1=>1,2=>2}],
    'group_count normalizes nested paths');

is_deeply(run('[2,1,2,3]', 'group_by(.)'), [[[1],[2,2],[3]]],
    'group_by(.) compares entire scalar values');
is_deeply(run('[2,1,2,3]', 'group_count(.)'), [{1=>1,2=>2,3=>1}],
    'group_count(.) compares entire scalar values');

is_deeply(run('[]', 'group_by(.)'), [[]],
    'group_by on empty array returns empty groups');
is_deeply(run('[]', 'group_count(.)'), [{}],
    'group_count on empty array returns empty counts');

my $multi = '[{"keys":[2,1],"v":"a"},'
          . '{"keys":[2,9],"v":"b"},'
          . '{"keys":[1,2],"v":"c"}]';
is_deeply(run($multi, 'group_by(.keys[])'), [[
    [{keys=>[1,2],v=>'c'}],
    [{keys=>[2,1],v=>'a'},{keys=>[2,9],v=>'b'}],
]], 'group_by uses only the first traversal result');
is_deeply(run($multi, 'group_count(.keys[])'), [{1=>1,2=>2}],
    'group_count uses only the first traversal result');

my $missing = '[{"k":null,"v":"null"},'
            . '{"v":"missing"},{"k":"null","v":"string"},'
            . '{"k":2,"v":"number"}]';
is_deeply(run($missing, 'group_count(.k)'), [{null=>3,2=>1}],
    'group_count retains literal null bucket collision');
is_deeply(run($missing, 'group_by(.k)'), [[
    [{k=>undef,v=>'null'},{v=>'missing'}],
    [{k=>2,v=>'number'}],
    [{k=>'null',v=>'string'}],
]], 'group_by keeps missing/null separate from literal null text');

is_deeply(run('{"k":"x"}', 'group_count(.k)'), [{}],
    'group_count retains v2 non-array empty-hash behavior');
is_deeply(run('null', 'group_count(.)'), [{}],
    'group_count retains v2 null empty-hash behavior');
is_deeply(run('23', 'group_count(.)'), [{}],
    'group_count retains v2 scalar empty-hash behavior');

for my $input ('{"k":"x"}', 'null', '23') {
    my $ok = eval { $jq->run_query($input, 'group_by(.k)'); 1 };
    ok(!$ok, 'group_by non-array input throws an error');
    like("$@", qr/group_by\(\): input must be an array/,
        'group_by preserves its specific non-array error');
}

is_deeply(run('[[2,1,2],[3,3,2]]', '.[] | group_by(.)'),
    [[[1],[2,2]],[[2],[3,3]]],
    'group_by preserves ordered array streams');
is_deeply(run('[[2,1,2],[3,3,2]]', '.[] | group_count(.)'),
    [{1=>1,2=>2},{2=>1,3=>2}],
    'group_count preserves ordered array streams');

done_testing;
