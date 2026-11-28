use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref->canonical;

sub run {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# max_by/min_by now use the first-key projection already shared by
# group_by/group_count. The extrema still apply their original comparable
# conversion and skip absent/null keys; grouping retains its own policy.
my @cases = (
    ['[{"id":"a","k":3},{"id":"b","k":-5},{"id":"c","k":9}]',
     '.k', '{"id":"c","k":9}', '{"id":"b","k":-5}',
     'integer projected keys'],
    ['[{"id":"a","k":"zoe"},{"id":"b","k":"amy"},{"id":"c","k":"mike"}]',
     '.k', '{"id":"a","k":"zoe"}', '{"id":"b","k":"amy"}',
     'string projected keys'],
    ['[{"id":"a"},{"id":"b","k":5},{"id":"c","k":2}]',
     '.k', '{"id":"b","k":5}', '{"id":"c","k":2}',
     'missing keys skipped without ending selection'],
    ['[{"id":"a","k":null},{"id":"b","k":4},{"id":"c","k":1}]',
     '.k', '{"id":"b","k":4}', '{"id":"c","k":1}',
     'null keys skipped'],
    ['[{"id":"first","k":4},{"id":"second","k":4}]',
     '.k', '{"id":"first","k":4}', '{"id":"first","k":4}',
     'first candidate wins equal-key ties'],
    ['[{"id":"f","k":false},{"id":"t","k":true}]',
     '.k', '{"id":"t","k":true}', '{"id":"f","k":false}',
     'boolean keys retain numeric comparable values'],
    ['[{"id":"a","meta":{"score":3}},{"id":"b","meta":{"score":7}}]',
     '.meta.score', '{"id":"b","meta":{"score":7}}',
     '{"id":"a","meta":{"score":3}}', 'nested path'],
    ['[{"id":"a","k":[1,2]},{"id":"b","k":[2]}]',
     '.k', '{"id":"b","k":[2]}', '{"id":"a","k":[1,2]}',
     'array keys retain encoded comparison'],
    ['[3,-4,7,2]', '.', '7', '-4', 'entire numeric item'],
    ['["beta","alpha","omega"]', '.', '"omega"', '"alpha"',
     'entire string item'],
    ['[{"x":1},{"x":2}]', '.absent', 'null', 'null',
     'all missing keys'],
    ['[]', '.k', 'null', 'null', 'empty array'],
);

for my $case (@cases) {
    my ($input, $path, $max_json, $min_json, $label) = @$case;
    for my $spec (['max_by', $max_json], ['min_by', $min_json]) {
        my ($filter, $expected) = @$spec;
        is_deeply(run($input, "$filter($path)"),
            [ $json->decode($expected) ], "$filter: $label");
    }
}

# An absent projection and an explicitly null first result both represent
# undef for extrema, but group_count still buckets them as null.
my $row = $json->decode('{"k":[1,2],"meta":{"score":5}}');
is_deeply(JQ::Lite::Util::_first_projected_key($row, 'k', 0),
    [1,2], 'shared projection returns array-valued key unchanged');
is(JQ::Lite::Util::_first_projected_key($row, 'missing', 0),
    undef, 'shared projection returns undef for a missing key');
is(JQ::Lite::Util::_first_projected_key($row, 'meta.score', 0),
    5, 'shared projection supports nested keys');
is(JQ::Lite::Util::_first_projected_key('raw', '', 1),
    'raw', 'shared projection supports whole-item mode');

my $group_rows = '[{"k":"b"},{"k":"a"},{"k":"b"}]';
is_deeply(run($group_rows, 'group_by(.k)'),
    [ [ [{ k => 'a' }], [{ k => 'b' }, { k => 'b' }] ] ],
    'group_by still uses the shared first projection');
is_deeply(run($group_rows, 'group_count(.k)'),
    [ { a => 1, b => 2 } ],
    'group_count still uses the shared first projection');

is_deeply(run('[{"id":"x"},{"id":"y"}]', 'group_count(.k)'),
    [ { null => 2 } ], 'group_count retains missing-key bucket');
is_deeply(run('[{"id":"x"},{"id":"y"}]', 'max_by(.k)'),
    [ undef ], 'extrema retain absent-key null result');

is_deeply(run('{"k":7}', 'max_by(.k)'), [ { k => 7 } ],
    'non-array max_by keeps the existing v2 passthrough');
is_deeply(run('{"k":7}', 'min_by(.k)'), [ { k => 7 } ],
    'non-array min_by keeps the existing v2 passthrough');

is_deeply(
    run('[[{"k":2},{"k":5}],[{"k":-3},{"k":0}]]',
        '.[] | max_by(.k)'),
    [ {k => 5}, {k => 0} ],
    'max_by preserves multiple array input order'
);
is_deeply(
    run('[[{"k":2},{"k":5}],[{"k":-3},{"k":0}]]',
        '.[] | min_by(.k)'),
    [ {k => 2}, {k => -3} ],
    'min_by preserves multiple array input order'
);

is_deeply(run('null', 'empty | max_by(.)'), [],
    'max_by does not manufacture an output from empty');
is_deeply(run('null', 'empty | min_by(.)'), [],
    'min_by does not manufacture an output from empty');

done_testing;
