use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;

# Both path operations intentionally use the same coercion and negative-index
# normalization. A get bounds-checks; a set may extend the array afterwards.
my @index_cases = (
    [0, 3, 0, 'first position'],
    [-1, 3, 2, 'negative last position'],
    [-3, 3, 0, 'negative first position'],
    [-4, 3, undef, 'negative index before start'],
    [4, 3, 4, 'future positive index is not clamped'],
    ['1', 3, 1, 'numeric string retained as v2 extension'],
    ['bad', 3, undef, 'nonnumeric string is not an index'],
    [JSON::PP::false, 3, 0, 'JSON false maps to zero'],
    [JSON::PP::true, 3, 1, 'JSON true maps to one'],
    [undef, 3, undef, 'JSON null is not an index'],
    [[], 3, undef, 'container is not an index'],
);
for my $case (@index_cases) {
    my ($segment, $length, $expected, $label) = @$case;
    is(JQ::Lite::Util::_normalize_array_index_segment($segment, $length),
        $expected, "shared get/set segment normalizer: $label");
}

sub results {
    my ($json, $filter) = @_;
    return [$jq->run_query($json, $filter)];
}

my $array = '[10,20,30]';
is_deeply(results($array, 'getpath([0])'), [10],
    'getpath reads the first array element');
is_deeply(results($array, 'getpath([-1])'), [30],
    'getpath reads a negative index');
is_deeply(results($array, 'getpath([5])'), [undef],
    'out-of-bounds getpath returns one null');
is_deeply(results($array, 'getpath([-4])'), [undef],
    'negative out-of-bounds getpath returns one null');
is_deeply(results($array, 'setpath([-1]; 77)'), [[10,20,77]],
    'setpath replaces the last array member');
is_deeply(results($array, 'setpath([4]; 77)'), [[10,20,30,undef,77]],
    'setpath grows the array with null padding');
is_deeply(results($array, 'setpath([0]; 0)'), [[0,20,30]],
    'setpath replaces the first array member');
is_deeply(results($array, 'setpath([-4]; 77)'), [[10,20,30]],
    'setpath negative out-of-bounds leaves array unchanged');

# Compatibility extensions inherited from v2, not jq 1.7 promises:
# jq rejects boolean path elements, unlike this implementation.
is_deeply(results($array, 'getpath([false])'), [10],
    'v2 boolean-false index extension remains');
is_deeply(results($array, 'getpath([true])'), [20],
    'v2 boolean-true index extension remains');
is_deeply(results($array, 'setpath([true]; 77)'), [[10,77,30]],
    'v2 boolean index update extension remains');
is_deeply(results($array, 'getpath(["1"])'), [20],
    'v2 numeric-string path extension remains');

is_deeply(results($array, 'getpath([-3])'), [10],
    'negative index at first array slot remains valid');
is_deeply(results($array, 'setpath([-3]; 77)'), [[77,20,30]],
    'setpath writes the first slot with equivalent negative index');
is_deeply(results($array, 'setpath(["1"]; 77)'), [[10,77,30]],
    'numeric-looking string segment remains valid in setpath');
is_deeply(results('[[10,20],[30,40]]', 'getpath([-1,-2])'), [30],
    'nested negative indices retain getpath traversal');
is_deeply(results('[[10,20],[30,40]]', 'setpath([-1,-2]; 7)'),
    [[[10,20],[7,40]]], 'nested negative indices retain setpath update');
is_deeply(results('[10,20,30]', 'getpath([-5])'), [undef],
    'out-of-range negative index still yields null on get');
is_deeply(results('[10,20,30]', 'setpath([-5]; 7)'), [[10,20,30]],
    'out-of-range negative index is ignored by set');


# Direct private path helpers are exercised because getpath/setpath have
# separate public dispatch code; this specifically guards their index walks.
my $direct = {
    config => [
        { detail => { value => 2 }, keep => 'yes' },
        { detail => { value => undef } },
    ],
};
is(JQ::Lite::Util::_get_path_value($direct, 'config[0].detail.value'),
    2, 'private get reads a mixed nested path');
ok(!defined(JQ::Lite::Util::_get_path_value(
        $direct, 'config[1].detail.value')),
    'private get retains a defined null leaf');
ok(!defined(JQ::Lite::Util::_get_path_value(
        $direct, 'config[4].detail.value')),
    'private get retains out-of-range null semantics');
ok(!defined(JQ::Lite::Util::_get_path_value($direct, '')),
    'private get rejects an empty path');

JQ::Lite::Util::_set_path_value($direct, 'config[0].detail.value', 8);
is(JQ::Lite::Util::_get_path_value($direct, 'config[0].detail.value'),
    8, 'private set overwrites the selected mixed path');
is($direct->{config}[0]{keep}, 'yes',
    'private set leaves sibling fields unchanged');
JQ::Lite::Util::_set_path_value($direct, 'config[1].extra.flag', 1);
is_deeply($direct->{config}[1],
    { detail => { value => undef }, extra => { flag => 1 } },
    'private set creates a missing nested object field');
JQ::Lite::Util::_set_path_value($direct, '', 100);
is(scalar(@{ $direct->{config} }), 2,
    'private set with empty path leaves array length unchanged');
is(JQ::Lite::Util::_get_path_value($direct, 'config[1].extra.flag'),
    1, 'private set with empty path does not mutate existing nested values');

done_testing;
