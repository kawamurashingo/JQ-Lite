use strict;
use warnings;
use Test::More;
use JSON::PP ();
use Scalar::Util ();
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


# The extractor previously filtered with grep and coerced with map.
# Compare with that exact legacy pipeline so coercion, ordering and numeric
# scalar flags remain consistent across supported Perl/JSON::PP versions.
my @extractor_cases = (
    ['[]', '[]', 'empty array'],
    ['[1,2,-4.5,0]', '[1,2,-4.5,0]', 'numeric primitives'],
    ['[true,false,true]', '[1,0,1]', 'boolean values'],
    ['[null,false,true,"bad",3,"2.5",{},[]]',
        '[0,1,3,2.5]', 'mixed types and original order'],
    ['["1","2e2","-3.5","0"]', '[1,200,-3.5,0]',
        'numeric-looking JSON strings'],
    ['[[],{},null,"bad",""]', '[]', 'no valid numeric entries'],
    ['[[1],[2],{"n":3},4]', '[4]', 'opaque containers ignored'],
    ['[0,0,0,1]', '[0,0,0,1]', 'duplicate and zero entries'],
    ['[1e-3,2e2,-5.5]', '[0.001,200,-5.5]',
        'scientific and fractional JSON numbers'],
    ['[false,null,false,true]', '[0,0,1]',
        'null skipped without dropping false'],
    ['null', '[]', 'non-array null fallback'],
    ['"12"', '[]', 'non-array numeric string fallback'],
    ['{"n":2}', '[]', 'non-array object fallback'],
);
for my $case (@extractor_cases) {
    my ($raw, $expected, $label) = @$case;
    my $before = $json->decode($raw);
    my $after = $json->decode($raw);
    my @legacy = ref($before) eq 'ARRAY'
        ? map {
            JSON::PP::is_bool($_) ? ($_ ? 1 : 0) : 0 + $_;
        } grep {
            defined $_ && (JSON::PP::is_bool($_)
                || (!ref $_ && Scalar::Util::looks_like_number($_)));
        } @$before
        : ();
    my @new = JQ::Lite::Util::_extract_numeric_values($after);
    is_deeply(\@new, \@legacy,
        "numeric extraction matches legacy projection: $label");
    is_deeply(\@new, $json->decode($expected),
        "numeric extraction retains eligible elements: $label");
    is($json->encode($after), $json->encode($before),
        "numeric extraction preserves legacy scalar flags: $label");
}

# Preserve the extractor's downstream consumers, whose empty and invalid
# input policies are intentionally different.
my @aggregate_cases = (
    ['[null,false,true,"bad",3,"2.5",{},[]]',
        'min', '[0]', 'minimum of mixed inputs'],
    ['[null,false,true,"bad",3,"2.5",{},[]]',
        'max', '[3]', 'maximum of mixed inputs'],
    ['[null,false,true,"bad",3,"2.5",{},[]]',
        'median', '[1.75]', 'even median of mixed inputs'],
    ['[null,false,true,"bad",3,"2.5",{},[]]',
        'percentile(50)', '[1.75]', 'midpoint percentile'],
    ['[null,"bad",{},[]]', 'min', '[null]',
        'no eligible numeric minimum'],
    ['[null,"bad",{},[]]', 'max', '[null]',
        'no eligible numeric maximum'],
    ['[null,"bad",{},[]]', 'median', '[null]',
        'no eligible numeric median'],
    ['[true,"2",null,false,4]', 'median', '[1]',
        'odd numeric count'],
    ['[{"n":"2"},{"n":false},{"n":4},{"n":null}]',
        'median_by(.n)', '[2]', 'projected numbers and booleans'],
);
for my $case (@aggregate_cases) {
    my ($raw, $filter, $expected, $label) = @$case;
    is_deeply(output($raw, $filter), $json->decode($expected),
        "$filter after single-pass extraction: $label");
}
is_deeply(output(
    '[[null,false,true,"bad",3,"2.5",{},[]],[],[5,"1",2]]',
    '.[] | min'
), [0,undef,1], 'minimum preserves stream order and empty-array null');
is_deeply(output(
    '[[null,false,true,"bad",3,"2.5",{},[]],[],[5,"1",2]]',
    '.[] | median'
), [1.75,[],2], 'median preserves stream order and empty-array passthrough');

my @long_numbers = (0 .. 256);
my @projected = JQ::Lite::Util::_extract_numeric_values(\@long_numbers);
is_deeply(\@projected, \@long_numbers,
    '257-element numeric extraction keeps every input value');

done_testing;
