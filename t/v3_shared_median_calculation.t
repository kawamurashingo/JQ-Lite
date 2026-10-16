use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;

sub output {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

my @cases = (
    ['[9,1,5]', 5, 'odd count'],
    ['[8,0,4,2]', 3, 'even count'],
    ['[0]', 0, 'single zero'],
    ['[-6,-2,-4]', -4, 'negative numbers'],
    ['[0.5,3.5,1.5,2.5]', 2, 'fractional values'],
    ['[true,false,3]', 1, 'boolean coercion'],
    ['[true,false]', 0.5, 'even boolean pair'],
    ['[1,"2",1e2]', 2, 'numeric strings and scientific notation'],
    ['[null,"bad",{},[],2,6]', 4, 'ignore nonnumeric values'],
    ['[null,"bad",{},[]]', undef, 'no eligible numeric values'],
);

for my $case (@cases) {
    my ($input, $expected, $label) = @$case;
    is_deeply(output($input, 'median'), [$expected],
        "median: $label");
    my $projected = $json->encode([ map { { n => $_ } }
        @{ $json->decode($input) } ]);
    is_deeply(output($projected, 'median_by(.n)'), [$expected],
        "median_by: $label");
}

is_deeply(output('[]', 'median'), [[]],
    'median retains the v2 empty-array passthrough');
is_deeply(output('[]', 'median_by(.)'), [undef],
    'median_by retains its distinct empty-array null result');

for my $input ('null', 'false', 'true', '0', '"text"', '{"n":2}') {
    for my $filter ('median', 'median_by(.n)') {
        is_deeply(output($input, $filter), [$json->decode($input)],
            "$filter passes through non-array $input");
    }
}

my $items = '[{"v":[9,1]},{"v":[5,3]},{"v":[]},{}]';
is_deeply(output($items, 'median_by(.v[])'), [4],
    'median_by includes every numeric result from a projected path');
for my $path ('.n', ' .n ', '".n"', "'n'") {
    is_deeply(output('[{"n":9},{"n":1},{"n":5}]', "median_by($path)"),
        [5], "median_by retains normalized path [$path]");
}
is_deeply(output('[{"meta":{"n":2}},{"meta":{"n":6}},{}]',
        'median_by(.meta.n)'), [4],
    'median_by ignores missing nested projections');
is_deeply(output('[9,"1",5]', 'median_by(.)'), [5],
    'median_by dot still uses each entire item');

my $stream = '[[9,1,5],[],[2,4],"text",null]';
is_deeply(output($stream, '.[] | median'), [5,[],3,'text',undef],
    'median preserves stream order and empty-array cardinality');
is_deeply(output($stream, '.[] | median_by(.)'), [5,undef,3,'text',undef],
    'median_by preserves stream order and null cardinality');
for my $filter ('median', 'median_by(.)') {
    is_deeply(output('null', "empty | $filter"), [],
        "$filter preserves an empty upstream stream");
}

done_testing;
