use strict;
use warnings;
use Test::More;
use JSON::PP ();
use Scalar::Util qw(refaddr);

use lib 'lib';
use JQ::Lite;
use JQ::Lite::Builtin ();

my $jq = JQ::Lite->new;

subtest 'rest on arrays' => sub {
    my $json = '[1,2,3,4]';
    my @res  = $jq->run_query($json, 'rest');
    is_deeply(\@res, [ [2,3,4] ], 'removes first element');
};

subtest 'rest on empty arrays yields empty array' => sub {
    my $json = '[]';
    my @res  = $jq->run_query($json, 'rest');
    is_deeply(\@res, [ [] ], 'empty array stays empty');
};

subtest 'rest passes through non-arrays' => sub {
    my $json = '{"foo":1}';
    my @res  = $jq->run_query($json, 'rest');
    is_deeply(\@res, [ { foo => 1 } ], 'non-arrays pass through untouched');
};


# One shallow copy, then removal of its first element, must preserve the
# existing slice-based rest behavior and JSON types for all array sizes.
my $json = JSON::PP->new->allow_nonref->canonical;
for my $case (
    ['[]', '[]', 'empty'],
    ['[1]', '[]', 'singleton'],
    ['[1,2]', '[2]', 'two elements'],
    ['[1,2,3,4,5]', '[2,3,4,5]', 'five elements'],
    ['[null,false,0,"",{"a":[2]},[3]]',
        '[false,0,"",{"a":[2]},[3]]',
        'mixed null, boolean, numeric, string, object and array'],
    ['[[],[1],[2,3]]', '[[1],[2,3]]', 'nested array references'],
    ['[[1,2]]', '[]', 'single nested array'],
) {
    my ($input, $expected, $label) = @$case;
    is_deeply([$jq->run_query($input, 'rest')],
        [$json->decode($expected)], "rest: $label");
}
for my $raw ('null', 'true', 'false', '"abc"', '42', '{}') {
    is_deeply([$jq->run_query($raw, 'rest')],
        [$json->decode($raw)], "rest passes through $raw");
}
is_deeply([$jq->run_query('[[1,2],[],[3],[4,5]]', '.[] | rest')],
    [[2],[],[],[5]],
    'rest keeps output order and exactly one result per upstream element');
is_deeply([$jq->run_query('null', 'empty | rest')],
    [], 'rest does not revive empty upstream streams');

my $child = { nested => [3] };
my $truth = JSON::PP::true;
my $falsity = JSON::PP::false;
my $source = [0, $child, $truth, undef];
my @inputs = ($source, [], [1], $falsity, undef, $child, 'text');
my $before = $json->encode(\@inputs);
my ($found, $outputs) =
    JQ::Lite::Builtin->dispatch($jq, 'rest', \@inputs);
ok($found, 'direct rest builtin remains registered');
is_deeply($outputs,
    [[$child,$truth,undef],[],[],$falsity,undef,$child,'text'],
    'direct rest preserves shallow values, empty arrays and passthrough');
isnt(refaddr($outputs->[0]), refaddr($source),
    'rest returns a new array, not the original source array');
is(refaddr($outputs->[0][0]), refaddr($child),
    'rest shares nested object reference, rather than deep-cloning');
is(refaddr($outputs->[0][1]), refaddr($truth),
    'rest preserves JSON boolean reference');
is(refaddr($outputs->[3]), refaddr($falsity),
    'rest passes through non-array boolean reference');
is(refaddr($outputs->[5]), refaddr($child),
    'rest passes through non-array object reference');
is($json->encode(\@inputs), $before,
    'rest does not mutate the original input stream');

my @many = (0 .. 256);
my @expected_tail = @many;
shift @expected_tail;
my ($large_found, $large_output) =
    JQ::Lite::Builtin->dispatch($jq, 'rest', [\@many]);
ok($large_found, 'rest remains registered for 257-element array');
is_deeply($large_output, [\@expected_tail],
    'rest preserves every element after the first in a long array');
is(scalar(@many), 257, 'rest leaves long source array length unchanged');

done_testing();
