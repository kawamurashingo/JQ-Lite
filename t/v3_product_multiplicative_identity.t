use strict;
use warnings;
use Test::More;
use JSON::PP ();
use Scalar::Util qw(refaddr);
use JQ::Lite;
use JQ::Lite::Builtin ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;

sub results {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# product starts at the multiplicative identity (1), so a second
# "have we seen a non-null factor" flag does not affect any result.
# Keep all v2 semantics, including null-element skipping, numeric
# coercion, array-only multiplication and non-array passthrough.
my @cases = (
    ['[]', '[1]', 'empty array identity'],
    ['[null]', '[1]', 'single null element'],
    ['[null,null,null]', '[1]', 'all null elements'],
    ['[1]', '[1]', 'unit factor'],
    ['[0]', '[0]', 'zero factor'],
    ['[0,null]', '[0]', 'zero with null'],
    ['[null,0]', '[0]', 'null before zero'],
    ['[2,3,4]', '[24]', 'several positive integers'],
    ['[null,2,null,3,null]', '[6]', 'interspersed null elements'],
    ['[-2,3]', '[-6]', 'negative factors'],
    ['[-2,-3,4]', '[24]', 'even number of negatives'],
    ['[0.5,8]', '[4]', 'fractional factors'],
    ['[2.5,-4]', '[-10]', 'fraction and negative factor'],
    ['["2","3"]', '[6]', 'numeric strings coerced'],
    ['[true,2,false]', '[0]', 'boolean factors'],
    ['[true,2]', '[2]', 'true factor is one'],
    ['[null,false]', '[0]', 'false factor is zero'],
    ['[false,null,true]', '[0]', 'zero survives null skipping'],
    ['[1,1,1,1]', '[1]', 'multiplicative identity remains one'],
    ['null', '[null]', 'null scalar passthrough'],
    ['true', '[true]', 'true scalar passthrough'],
    ['false', '[false]', 'false scalar passthrough'],
    ['42', '[42]', 'numeric scalar passthrough'],
    ['"42"', '["42"]', 'string scalar passthrough'],
    ['"text"', '["text"]', 'text scalar passthrough'],
    ['{"value":[2,3]}', '[{"value":[2,3]}]', 'object passthrough'],
);

for my $case (@cases) {
    my ($input, $expected, $name) = @$case;
    is_deeply(results($input, 'product'), $json->decode($expected),
        "product preserves $name");
}

# Arrays in an iterator become individual product calls; empty arrays
# must emit one value instead of an empty output stream.
is_deeply(results('[[],[null],[2,3],[0,null],[true,4],null]',
                  '.[] | product'),
    $json->decode('[1,1,6,0,4,null]'),
    'product preserves mixed upstream stream order and null slots');
is_deeply(results('[[2,3],[4,5]]', 'map(product)'),
    [ [6,20] ], 'product retains map composition');
is_deeply(results('[2,3]', 'empty | product'), [],
    'an empty upstream stream remains empty');
is_deeply(results('[2,3]', 'product | tostring'), ['6'],
    'product result remains available to downstream filters');

# Direct registration is a single bare name, not a new () alias. Check
# that the returned array keeps every input, including reference identity.
my $truth = JSON::PP::true;
my $falsity = JSON::PP::false;
my $object = { nested => [1,2] };
my @inputs = ([], [undef], [2,3], [0,undef], undef,
              $truth, $falsity, 7, 'text', $object);
my ($found, $outputs) = JQ::Lite::Builtin->dispatch(
    $jq, 'product', \@inputs
);
ok($found, 'product remains registered as an exact bare name');
is_deeply($outputs,
    [1, 1, 6, 0, undef, $truth, $falsity, 7, 'text', $object],
    'product keeps one direct output per input in the same order');
is(refaddr($outputs->[5]), refaddr($truth),
    'true scalar is passed through without converting reference');
is(refaddr($outputs->[6]), refaddr($falsity),
    'false scalar is passed through without converting reference');
is(refaddr($outputs->[9]), refaddr($object),
    'object scalar is passed through without cloning reference');
my ($empty_found, $empty_outputs) = JQ::Lite::Builtin->dispatch(
    $jq, 'product', []
);
ok($empty_found, 'product accepts an empty direct input stream');
is_deeply($empty_outputs, [], 'empty direct input stream emits nothing');
my ($alias_found) = JQ::Lite::Builtin->dispatch(
    $jq, 'product()', [[2,3]]
);
ok(!$alias_found, 'product() is not newly registered as an exact alias');

my %registered = map { $_ => 1 } JQ::Lite::Builtin->registered_names;
ok($registered{product}, 'product remains in exact registry');
ok(!$registered{'product()'}, 'no product() exact registry entry added');

# Other aggregate handlers are unaffected by this local simplification.
is_deeply(results('[1,2,3]', 'add'), [6], 'add unchanged');
is_deeply(results('[1,2,3]', 'sum'), [6], 'sum unchanged');
is_deeply(results('[1,2,3]', 'avg'), [2], 'avg unchanged');
is_deeply(results('[1,2,3]', 'min'), [1], 'min unchanged');
is_deeply(results('[1,2,3]', 'max'), [3], 'max unchanged');

done_testing;
