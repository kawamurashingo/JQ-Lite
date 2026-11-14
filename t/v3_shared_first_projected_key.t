use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;
sub output {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

my $items = '[{"k":2,"tag":"two-first"},'
          . '{"k":1,"tag":"one-first"},'
          . '{"k":2,"tag":"two-second"},'
          . '{"k":1,"tag":"one-second"}]';
my $unique = [
    {k=>2,tag=>'two-first'}, {k=>1,tag=>'one-first'},
];
my $grouped = [
    [{k=>1,tag=>'one-first'},{k=>1,tag=>'one-second'}],
    [{k=>2,tag=>'two-first'},{k=>2,tag=>'two-second'}],
];
is_deeply(output($items, 'unique_by(.k)'), [$unique],
    'unique_by retains first occurrence and original key order');
is_deeply(output($items, 'group_by(.k)'), [$grouped],
    'group_by sorts signature groups and keeps intra-group order');
is_deeply(output($items, 'group_count(.k)'), [{1=>2,2=>2}],
    'group_count tallies the same projected keys');

for my $path ('.k', ' .k ', '".k"', "'k'") {
    is_deeply(output($items, "unique_by($path)"), [$unique],
        "unique_by accepts normalized path [$path]");
    is_deeply(output($items, "group_by($path)"), [$grouped],
        "group_by accepts normalized path [$path]");
    is_deeply(output($items, "group_count($path)"), [{1=>2,2=>2}],
        "group_count accepts normalized path [$path]");
}

my $nested = '[{"data":{"k":"b"},"n":1},'
           . '{"data":{"k":"a"},"n":2},'
           . '{"data":{"k":"b"},"n":3}]';
is_deeply(output($nested, 'unique_by(.data.k)'), [[
    {data=>{k=>'b'},n=>1},{data=>{k=>'a'},n=>2},
]], 'unique_by selects first nested key');
is_deeply(output($nested, 'group_by(.data.k)'), [[
    [{data=>{k=>'a'},n=>2}],
    [{data=>{k=>'b'},n=>1},{data=>{k=>'b'},n=>3}],
]], 'group_by selects first nested key');
is_deeply(output($nested, 'group_count(.data.k)'),
    [{a=>1,b=>2}], 'group_count selects first nested key');

my $multiple = '[{"keys":[2,9],"n":1},'
             . '{"keys":[2,8],"n":2},'
             . '{"keys":[1,7],"n":3}]';
is_deeply(output($multiple, 'unique_by(.keys[])'), [[
    {keys=>[2,9],n=>1}, {keys=>[1,7],n=>3},
]], 'unique_by takes only first emitted key');
is_deeply(output($multiple, 'group_by(.keys[])'), [[
    [{keys=>[1,7],n=>3}],
    [{keys=>[2,9],n=>1},{keys=>[2,8],n=>2}],
]], 'group_by takes only first emitted key');
is_deeply(output($multiple, 'group_count(.keys[])'),
    [{1=>1,2=>2}], 'group_count takes only first emitted key');

is_deeply(output('[2,1,2]', 'unique_by(.)'), [[2,1]],
    'unique_by dot projects whole scalar');
is_deeply(output('[2,1,2]', 'group_by(.)'), [[[1],[2,2]]],
    'group_by dot projects whole scalar');
is_deeply(output('[2,1,2]', 'group_count(.)'), [{1=>1,2=>2}],
    'group_count dot projects whole scalar');

my $missing = '[{"tag":"first-absent"},'
            . '{"k":null,"tag":"null"},'
            . '{"k":"null","tag":"string-null"},'
            . '{"tag":"second-absent"}]';
is_deeply(output($missing, 'unique_by(.k)'), [[
    {tag=>'first-absent'},{k=>'null',tag=>'string-null'},
]], 'unique_by coalesces missing and null but not literal string null');
is_deeply(output($missing, 'group_by(.k)'), [[
    [{tag=>'first-absent'},{k=>undef,tag=>'null'},{tag=>'second-absent'}],
    [{k=>'null',tag=>'string-null'}],
]], 'group_by keeps missing/null distinct from the string null key');
is_deeply(output($missing, 'group_count(.k)'), [{null=>4}],
    'group_count retains legacy collision with string null');

for my $filter ('unique_by(.k)', 'group_by(.k)', 'group_count(.k)') {
    my $empty = $filter =~ /^group_count/ ? [{}] : [[]];
    is_deeply(output('[]', $filter), $empty,
        "$filter preserves empty-array result");
}

is_deeply(output('{"k":1}', 'unique_by(.k)'), [{k=>1}],
    'unique_by passes through non-array values');
is_deeply(output('{"k":1}', 'group_count(.k)'), [{}],
    'group_count maps non-array to empty hash');
my $ok = eval { $jq->run_query('{"k":1}', 'group_by(.k)'); 1 };
ok(!$ok, 'group_by rejects non-array input');
like("$@", qr/group_by\(\): input must be an array/,
    'group_by retains non-array error message');

is_deeply(output('[[2,1,2],[3,2,3]]', '.[] | unique_by(.)'),
    [[2,1],[3,2]], 'unique_by keeps ordered independent streams');
is_deeply(output('[[2,1,2],[3,2,3]]', '.[] | group_by(.)'),
    [[[1],[2,2]],[[2],[3,3]]],
    'group_by keeps ordered independent streams');
is_deeply(output('[[2,1,2],[3,2,3]]', '.[] | group_count(.)'),
    [{1=>1,2=>2},{2=>1,3=>2}],
    'group_count keeps ordered independent streams');

done_testing;
