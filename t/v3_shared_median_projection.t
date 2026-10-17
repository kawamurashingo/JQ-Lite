use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref->canonical;

sub output {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# The median_by projection now delegates only numeric filtering/coercion to
# the extractor already shared by median, min/max, and percentile. Traversal,
# stream cardinality and the median calculation keep their existing policies.
my @projections = (
    ['null',                    '',             1, [],              'whole null'],
    ['true',                    '',             1, [1],             'whole true'],
    ['false',                   '',             1, [0],             'whole false'],
    ['2.5',                     '',             1, [2.5],           'whole decimal'],
    ['"1e2"',                  '',             1, [100],           'whole numeric string'],
    ['"bad"',                  '',             1, [],              'whole nonnumeric string'],
    ['[]',                      '',             1, [],              'whole array is opaque'],
    ['{"n":2}',                 '',             1, [],              'whole object is opaque'],
    ['{"n":7}',                 'n',            0, [7],             'number field'],
    ['{"n":"4"}',               'n',            0, [4],             'numeric-string field'],
    ['{"n":true}',              'n',            0, [1],             'true field'],
    ['{"n":false}',             'n',            0, [0],             'false field'],
    ['{"n":null}',              'n',            0, [],              'null field'],
    ['{"n":"bad"}',             'n',            0, [],              'nonnumeric field'],
    ['{"n":[1,2]}',             'n',            0, [],              'array field without iterator'],
    ['{"other":4}',             'n',            0, [],              'missing field'],
    ['{"meta":{"score":"8"}}',  'meta.score',   0, [8],             'nested field'],
    ['{"v":[true,"2",null,false,"bad",4,{}]}',
                                'v[]',          0, [1,2,0,4],       'mixed iterator values'],
    ['{"v":[]}',               'v[]',          0, [],              'empty iterator'],
    ['{"v":[[1,2],{"n":3}]}',   'v[]',          0, [],              'iterator skips containers'],
);

for my $case (@projections) {
    my ($raw, $path, $whole, $expected, $label) = @$case;
    my $input = $json->decode($raw);
    my $before = $json->encode($input);
    my @numbers = JQ::Lite::Util::_project_numeric_values($input, $path, $whole);
    is_deeply(\@numbers, $expected, "numeric projection: $label");
    is($json->encode($input), $before, "projection does not mutate input: $label");
}

my @medians = (
    ['[{"n":5},{"n":1},{"n":9}]', '.n', 5, 'odd projected count'],
    ['[{"n":2},{"n":8},{"n":4},{"n":6}]', '.n', 5, 'even projected count'],
    ['[{"n":true},{"n":false},{"n":true}]', '.n', 1, 'boolean values'],
    ['[{"n":true},{"n":false}]', '.n', 0.5, 'even boolean pair'],
    ['[{"n":"2e1"},{"n":"4.0"},{"n":6}]', '.n', 6, 'numeric strings and exponent'],
    ['[{"n":null},{"n":"bad"},{"n":4},{}]', '.n', 4, 'skip missing and nonnumeric'],
    ['[{"n":null},{"n":"bad"},{}]', '.n', undef, 'no eligible values'],
    ['[{"v":[1,"3",true,false]},{"v":[4,null,"bad"]}]',
     '.v[]', 1, 'iterator yields multiple mixed values'],
    ['[{"v":[2,"4"]},{"v":[6,true]}]',
     '.v[]', 3, 'iterator even numeric count'],
    ['[{"v":[]},{}]', '.v[]', undef, 'empty or missing iterators'],
    ['[1,"2",3,"bad"]', '.', 2, 'whole-item mode'],
    ['[]', '.', undef, 'empty root array'],
);

for my $case (@medians) {
    my ($input, $path, $expected, $label) = @$case;
    is_deeply(output($input, "median_by($path)"), [$expected],
        "public median_by: $label");
}

# The simplification does not alter adjacent statistics or stream shape.
is_deeply(output('[1,"3",true,null]', 'median'), [1],
    'plain median retains shared numeric extraction');
is_deeply(output('[1,"3",true,null]', 'min'), [1],
    'plain min retains shared numeric extraction');
is_deeply(output('[1,"3",true,null]', 'max'), [3],
    'plain max retains shared numeric extraction');
is_deeply(output('[1,"3",true,null]', 'percentile(50)'), [1],
    'percentile retains shared numeric extraction');
is_deeply(output('[true,false,3]', 'sum_by(.)'), [4],
    'sum_by retains its independent numeric policy');
is_deeply(output('[true,false,3]', 'avg_by(.)'), [4/3],
    'avg_by retains its independent numeric policy');
is_deeply(output(
    '[[{"n":1},{"n":5}],[],[{"n":"2"},{"n":false}],{"n":7},null]',
    '.[] | median_by(.n)'
), [3, undef, 1, {n=>7}, undef], 'ordered upstream streams and passthrough');
is_deeply(output('null', 'empty | median_by(.)'), [],
    'empty upstream produces no median_by output');

done_testing;
