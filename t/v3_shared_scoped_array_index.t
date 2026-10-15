use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;
my $array = [10, undef, 30];
for my $case (
    [0, 10, 'first member'],
    [1, undef, 'explicit null member'],
    [-1, 30, 'negative last member'],
    [-3, 10, 'negative first member'],
    [-4, undef, 'index before the array'],
    [3, undef, 'index just after the array'],
    [20, undef, 'far out-of-range member'],
) {
    my ($index, $expected, $label) = @$case;
    is(JQ::Lite::Util::_v3_array_index_or_null($array, $index),
        $expected, $label);
}

sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

for my $case (
    ['{"idx":-1,"items":[7,8]}', '.items[-1]', [8],
        'literal negative index'],
    ['{"idx":-1,"items":[7,8]}', '.items[.idx]', [8],
        'computed negative index'],
    ['{"idx":5,"items":[7,8]}', '.items[5]', [undef],
        'literal out-of-range produces one null'],
    ['{"idx":5,"items":[7,8]}', '.items[.idx]', [undef],
        'computed out-of-range produces one null'],
    ['{"idx":0,"items":[null,8]}', '.items[0]', [undef],
        'literal explicit null array slot'],
    ['{"idx":0,"items":[null,8]}', '.items[.idx]', [undef],
        'computed explicit null array slot'],
    ['{"idx":0,"items":[]}', '.items[.idx]', [undef],
        'computed index into empty array produces one null'],
    ['null', '.[0]', [undef],
        'strict numeric lookup against null yields null'],
    ['null', '.[0]?', [undef],
        'optional numeric lookup against null yields null'],
    ['null', '.name?', [undef],
        'optional named field against null yields null'],
    ['[1,2]', '.[]?', [1,2],
        'optional iterator retains the ordered stream'],
    ['[1,2]', '.[] | .missing?', [],
        'invalid optional field lookup emits no results'],
    ['{"idx":"0","items":[7,8]}', '.items[.idx]?', [],
        'optional computed wrong-type index emits no results'],
) {
    my ($input, $filter, $expected, $label) = @$case;
    is_deeply(results($input, $filter), $expected, $label);
}

for my $case (
    ['{"idx":"0","items":[7,8]}', '.items[.idx]',
        'computed string index against an array'],
    ['{"idx":0,"items":{}}', '.items[.idx]',
        'computed numeric index against an object'],
    ['{"items":{}}', '.items[0]',
        'literal numeric index against an object'],
) {
    my ($input, $filter, $label) = @$case;
    my $ok = eval { $jq->run_query($input, $filter); 1 };
    ok(!$ok, "$label raises an error");
    like("$@", qr/Cannot index/, "$label keeps an index error");
}
done_testing;
