use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;

sub run {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

my $users = '[{"id":2,"name":"first-two"},'
          . '{"id":1,"name":"first-one"},'
          . '{"id":2,"name":"duplicate-two"},'
          . '{"id":3,"name":"three"},'
          . '{"id":1,"name":"duplicate-one"}]';
my $expected = [
    { id => 2, name => 'first-two' },
    { id => 1, name => 'first-one' },
    { id => 3, name => 'three' },
];

is_deeply(run($users, 'unique_by(.id)'), [$expected],
    'projected keys preserve first occurrence and input order');
is_deeply(run($users, 'unique_by( .id )'), [$expected],
    'whitespace-padded dot path keeps same projected keys');
is_deeply(run($users, 'unique_by(".id")'), [$expected],
    'quoted dot path preserves projected keys');
is_deeply(run($users, q{unique_by('.id')}), [$expected],
    'single-quoted dot path preserves projected keys');
is_deeply(run($users, 'unique_by(id)'), [$expected],
    'unprefixed path retains v2 projection behavior');

my $nested = '[{"meta":{"id":3},"tag":"A"},'
           . '{"meta":{"id":3},"tag":"B"},'
           . '{"meta":{"id":1},"tag":"C"}]';
my $nested_expected = [
    { meta => {id=>3}, tag=>'A' },
    { meta => {id=>1}, tag=>'C' },
];
is_deeply(run($nested, 'unique_by(.meta.id)'), [$nested_expected],
    'nested projected paths select the first matching key');
is_deeply(run($nested, 'unique_by( ".meta.id" )'), [$nested_expected],
    'quoted nested paths normalize identically');
is_deeply(run($nested, 'unique_by( meta.id )'), [$nested_expected],
    'undotted nested paths normalize identically');

is_deeply(run('[2,1,2,3,1]', 'unique_by(.)'), [[2,1,3]],
    'whole-item dot path preserves first scalar occurrences');
is_deeply(run('[2,1,2,3,1]', 'unique_by( . )'), [[2,1,3]],
    'whitespace-padded whole-item dot path');
is_deeply(run('[2,1,2,3,1]', 'unique_by(".")'), [[2,1,3]],
    'quoted whole-item dot path');
is_deeply(run('["a","b","a"]', 'unique_by(.)'), [['a','b']],
    'whole-item string deduplication');
is_deeply(run('[]', 'unique_by(.)'), [[]],
    'empty array remains empty');
is_deeply(run('[1]', 'unique_by(.)'), [[1]],
    'singleton array remains unchanged');

my $missing = '[{"name":"no-id-1"},'
            . '{"id":null,"name":"null-id"},'
            . '{"name":"no-id-2"},'
            . '{"id":1,"name":"one"}]';
is_deeply(run($missing, 'unique_by(.id)'),
    [[{name=>'no-id-1'}, {id=>1,name=>'one'}]],
    'missing and explicit-null keys share historical deduplication signature');

my $multi = '[{"numbers":[7,8],"tag":"one"},'
          . '{"numbers":[7,9],"tag":"two"},'
          . '{"numbers":[2],"tag":"three"}]';
is_deeply(run($multi, 'unique_by(.numbers[])'),
    [[{numbers=>[7,8],tag=>'one'}, {numbers=>[2],tag=>'three'}]],
    'v2 unique_by uses first traversal value as key');

for my $filter ('unique_by(.id)', 'unique_by( .id )',
                'unique_by(".id")') {
    is_deeply(run('{"id":1}', $filter), [{id=>1}],
        "$filter preserves object passthrough");
    is_deeply(run('42', $filter), [42],
        "$filter preserves number passthrough");
    is_deeply(run('null', $filter), [undef],
        "$filter preserves null passthrough");
}

is_deeply(run('[[{"id":2},{"id":2},{"id":1}],'
            . '[{"id":4},{"id":3},{"id":4}]]',
              '.[] | unique_by(.id)'),
    [[{id=>2},{id=>1}], [{id=>4},{id=>3}]],
    'array streams keep their ordering and deduplicate independently');

done_testing;
