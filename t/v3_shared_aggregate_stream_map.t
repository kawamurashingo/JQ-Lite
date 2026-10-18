use strict;
use warnings;
use Test::More;
use JSON::PP ();
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

done_testing;
