use strict;
use warnings;
use Test::More;
use JSON::PP ();
use List::Util qw(sum);
use Scalar::Util qw(refaddr);
use FindBin ();
use File::Spec ();
use JQ::Lite;
use JQ::Lite::Builtin ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;

sub run {
    my ($input, $query) = @_;
    return [ $jq->run_query($input, $query) ];
}

# Preserve the practical-v2 aggregation differences, including empty
# array behavior, numeric coercion, and the distinct non-array fallback.
my @cases = (
    ['[1,2,3]', 'add', '[6]', 'add alias'],
    ['[1,2,3]', 'sum', '[6]', 'sum'],
    ['["2",3,4]', 'sum', '[9]', 'numeric-looking string addition'],
    ['[1,2,3]', 'product', '[6]', 'product'],
    ['[null,2,3]', 'product', '[6]', 'product ignores null members'],
    ['[true,2,false]', 'product', '[0]', 'product bool numeric coercion'],
    ['[1,2,3]', 'min', '[1]', 'min'],
    ['[1,2,3]', 'max', '[3]', 'max'],
    ['["bad",3,"2",null]', 'min', '[2]', 'min extracts numeric values'],
    ['["bad",3,"2",null]', 'max', '[3]', 'max extracts numeric values'],
    ['[2,4,6]', 'avg', '[4]', 'avg'],
    ['[1,2,3,4]', 'avg', '[2.5]', 'avg fractional'],
    ['[1,2,3]', 'median', '[2]', 'odd median'],
    ['[1,2,3,4]', 'median', '[2.5]', 'even median'],
    ['[null,"bad",2,6]', 'median', '[4]', 'median ignores nonnumeric'],
    ['[]', 'add', '[null]', 'empty add'],
    ['[]', 'sum', '[null]', 'empty sum'],
    ['[]', 'product', '[1]', 'empty product identity'],
    ['[]', 'min', '[null]', 'empty min'],
    ['[]', 'max', '[null]', 'empty max'],
    ['[]', 'avg', '[0]', 'empty avg'],
    ['[]', 'median', '[[]]', 'empty median passes array through'],
    ['[null,"bad"]', 'min', '[null]', 'min with no numeric values'],
    ['[null,"bad"]', 'max', '[null]', 'max with no numeric values'],
    ['[null,"bad"]', 'median', '[null]', 'median with no numeric values'],
    ['[true,false]', 'median', '[0.5]', 'boolean median'],
);

for my $case (@cases) {
    my ($input, $filter, $expected, $label) = @$case;
    is_deeply(run($input, $filter), $json->decode($expected),
        "$filter retains $label");
}

my @streams = (
    ['[[1,2],[],[3,4]]', 'sum', '[3,null,7]'],
    ['[[1,2],[],[3,4]]', 'add', '[3,null,7]'],
    ['[[2,3],[],[4,5]]', 'product', '[6,1,20]'],
    ['[[3,1],[],[4,2]]', 'min', '[1,null,2]'],
    ['[[3,1],[],[4,2]]', 'max', '[3,null,4]'],
    ['[[2,4],[],[6,8]]', 'avg', '[3,0,7]'],
    ['[[2,4],[],[6,8]]', 'median', '[3,[],7]'],
);
for my $case (@streams) {
    my ($input, $filter, $expected) = @$case;
    is_deeply(run($input, ".[] | $filter"), $json->decode($expected),
        "$filter keeps ordered per-array stream and empty array slots");
}

my $object = { nested => [1,2] };
my $truth = JSON::PP::true;
for my $filter (qw(add sum product min max median)) {
    my ($matched, $outputs) =
        JQ::Lite::Builtin->dispatch($jq, $filter, [$object, $truth, undef]);
    ok($matched, "$filter is registered");
    is_deeply($outputs, [$object,$truth,undef],
        "$filter preserves non-array values in order");
    is(refaddr($outputs->[0]), refaddr($object),
        "$filter retains non-array object reference");
    is(refaddr($outputs->[1]), refaddr($truth),
        "$filter retains boolean reference");
}
my ($avg_found, $avg_outputs) =
    JQ::Lite::Builtin->dispatch($jq, 'avg', [$object, $truth, undef]);
ok($avg_found, 'avg remains registered');
is_deeply($avg_outputs, [0,0,0], 'avg preserves zero non-array fallback');

for my $filter (qw(add sum product min max avg median)) {
    my ($matched, $outputs) =
        JQ::Lite::Builtin->dispatch($jq, $filter, []);
    ok($matched, "$filter dispatches an empty input stream");
    is_deeply($outputs, [], "$filter creates no output from an empty stream");
    is_deeply(run('null', "empty | $filter"), [],
        "$filter does not revive an empty upstream stream");
}

# The Aggregate child must register without loading the parent module:
# the shared mapper is defined in its preloaded JQ::Lite::Util dependency.
my $lib = File::Spec->catdir($FindBin::Bin, '..', 'lib');
my $standalone = <<'PERL';
use strict;
use warnings;
use JSON::PP ();
require JQ::Lite::Builtin::Aggregate;
die 'parent loaded' if exists $INC{'JQ/Lite/Builtin.pm'};
my ($name, $raw, $expected) = @ARGV;
my %handlers;
JQ::Lite::Builtin::Aggregate->register(sub {
    my ($names, $callback) = @_;
    my @names = ref($names) eq 'ARRAY' ? @$names : ($names);
    $handlers{$_} = $callback for @names;
});
die 'handler missing' unless $handlers{$name};
my $json = JSON::PP->new->allow_nonref->canonical;
my $got = $handlers{$name}->(undef, [$json->decode($raw)]);
die 'wrong result' if $json->encode($got) ne $expected;
die 'parent loaded after register' if exists $INC{'JQ/Lite/Builtin.pm'};
PERL
for my $case (
    ['sum', '[2,3]', '[5]'],
    ['product', '[]', '[1]'],
    ['min', '[3,1]', '[1]'],
    ['avg', '[]', '[0]'],
    ['median', '[]', '[[]]'],
) {
    is(system($^X, "-I$lib", '-e', $standalone, @$case), 0,
        "standalone Aggregate registration works for $case->[0]");
}


# Sum and average share a streaming numeric accumulator; jq and this
# practical-v2 subset intentionally have distinct empty/non-array behavior.
my @sum_avg_regressions = (
    ['[null]', 'sum', '[0]', 'null-only array contributes zero'],
    ['[true,false,"12",3]', 'sum', '[16]',
        'booleans and numeric-looking string sum'],
    ['[true,false,"12",3]', 'add', '[16]',
        'add alias shares numeric coercion'],
    ['[true,false,"12",3]', 'avg', '[4]',
        'average divides by all array elements'],
    ['[-2,0.5,1.5]', 'sum', '[0]',
        'negative and fractional members sum to zero'],
    ['[-2,0.5,1.5]', 'avg', '[0]',
        'negative and fractional members average to zero'],
    ['[null,4]', 'avg', '[2]',
        'null member still contributes to average denominator'],
    ['[]', 'sum', '[null]', 'empty sum remains JSON null'],
    ['[]', 'add', '[null]', 'empty add remains JSON null'],
    ['[]', 'avg', '[0]', 'empty average remains zero'],
    ['{"n":5}', 'sum', '[{"n":5}]', 'non-array sum passthrough'],
    ['"12"', 'avg', '[0]', 'non-array average stays zero'],
    ['[[1,2],[3,4]]', '.[] | avg', '[1.5,3.5]',
        'two streamed averages retain order'],
);
for my $case (@sum_avg_regressions) {
    my ($input, $filter, $expected, $description) = @$case;
    is_deeply(run($input, $filter), $json->decode($expected),
        "numeric accumulator: $description");
}

my $long_array = [0 .. 256];
my $long_json = $json->encode($long_array);
is_deeply(run($long_json, 'sum'), [32896],
    '257-element array sum is complete');
is_deeply(run($long_json, 'add'), [32896],
    '257-element array add retains alias behavior');
is_deeply(run($long_json, 'avg'), [128],
    '257-element array average uses every element');

# Verify numeric coercion never mutates an existing numeric-string SV:
# this is observable via the original array's JSON encoding.
my $typed_array = ['12', '3.5', JSON::PP::true, undef];
my $typed_before = $json->encode($typed_array);
for my $filter (qw(sum add avg)) {
    my ($found, $output) =
        JQ::Lite::Builtin->dispatch($jq, $filter, [$typed_array]);
    ok($found, "$filter direct dispatch retains registration");
    is_deeply($output, [$filter eq 'avg' ? 16.5 / 4 : 16.5],
        "$filter directly computes mixed numeric array");
    is($json->encode($typed_array), $typed_before,
        "$filter numeric coercion preserves input JSON string types");
}


# The previous List::Util::sum(map { 0 + $_ } ...) behavior is the oracle
# for integer overflow and signed/unsigned promotion on the running Perl.
# Numeric formatting in JSON distinguishes floating promotion from a
# retained integer; test this on 32-bit and 64-bit Perl without hardcoding
# either platform's boundary result.
for my $boundary (
    ['[9223372036854775807,1]', 'positive signed boundary'],
    ['[9223372036854775807,1,-9223372036854775807]',
        'mixed signs after positive overflow'],
    ['[9223372036854775808]', 'unsigned high singleton'],
    ['[18446744073709551615,1]', 'unsigned boundary'],
    ['[-9223372036854775808,-1]', 'negative signed boundary'],
    ['[2147483647,1,-2147483647]', '32-bit signed boundary'],
) {
    my ($input, $label) = @$boundary;
    my $old_array = $json->decode($input);
    my $legacy = sum(map { 0 + $_ } @$old_array);
    my $expected_avg = $legacy / @$old_array;

    for my $filter (qw(add sum avg)) {
        my $expected = $filter eq 'avg' ? $expected_avg : $legacy;
        my $old_json = $json->encode([$expected]);
        my $new_array = $json->decode($input);
        my ($found, $outputs) =
            JQ::Lite::Builtin->dispatch($jq, $filter, [$new_array]);
        ok($found, "$filter is registered: $label");
        is($json->encode($outputs), $old_json,
            "$filter preserves legacy List::Util overflow: $label");
    }
}

done_testing;
