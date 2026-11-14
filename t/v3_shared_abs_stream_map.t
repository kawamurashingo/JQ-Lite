use strict;
use warnings;
use Test::More;
use JSON::PP ();
use Scalar::Util qw(looks_like_number refaddr);
use FindBin ();
use File::Spec ();
use JQ::Lite;
use JQ::Lite::Builtin ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref->canonical;

sub output {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# abs preserves the v2 single-level array policy. Scalar booleans pass
# through as references, but booleans directly in arrays coerce to 1/0.
my @public_cases = (
    ['null', 'null', 'null'],
    ['0', '0', 'zero'],
    ['-12', '12', 'negative integer'],
    ['-3.75', '3.75', 'negative fraction'],
    ['12', '12', 'positive integer'],
    ['"-8"', '8', 'numeric-looking negative string'],
    ['"2e1"', '20', 'exponential numeric-looking string'],
    ['"bad"', '"bad"', 'nonnumeric string'],
    ['""', '""', 'empty string'],
    ['true', 'true', 'true scalar reference'],
    ['false', 'false', 'false scalar reference'],
    ['[]', '[]', 'empty array'],
    ['[-3,0,4]', '[3,0,4]', 'numeric array'],
    ['["-3","4","bad"]', '[3,4,"bad"]', 'mixed numeric strings'],
    ['[true,false]', '[1,0]', 'boolean array elements coerce'],
    ['[null,-2]', '[null,2]', 'null array element'],
    ['[[-2,-3],-4]', '[[-2,-3],4]', 'nested arrays are not recursed into'],
    ['[{"n":-3},-5]', '[{"n":-3},5]', 'objects inside arrays pass through'],
    ['{"n":-3}', '{"n":-3}', 'root object passes through'],
);
for my $case (@public_cases) {
    my ($input, $expected, $label) = @$case;
    is_deeply(output($input, 'abs'), [$json->decode($expected)],
        "abs preserves $label");
}

my @stream_cases = (
    ['[null,true,false,-4,"-5","bad"]',
     '[null,true,false,4,5,"bad"]',
     'mixed scalar types'],
    ['[[-3,2],[],[-1],{"n":-8}]',
     '[[3,2],[],[1],{"n":-8}]',
     'arrays and object within the input stream'],
    ['[{"a":-1},{"a":-2}]',
     '[{"a":-1},{"a":-2}]',
     'object stream remains unchanged'],
    ['[[-2],[-5],[-8]]',
     '[[2],[5],[8]]',
     'independent array stream elements'],
);
for my $case (@stream_cases) {
    my ($input, $expected, $label) = @$case;
    is_deeply(output($input, '.[] | abs'), $json->decode($expected),
        "abs preserves ordered outputs for $label");
}

# Compare the registered handler against the exact old scalar mapper.
# In particular, the nested array mapping must not become recursive.
sub old_abs {
    my ($inputs) = @_;
    return [ map {
        !defined($_) ? undef
            : !ref($_) ? (looks_like_number($_) ? abs($_) : $_)
            : ref($_) eq 'ARRAY'
                ? [ map { looks_like_number($_) ? abs($_) : $_ } @{$_} ]
                : $_
    } @$inputs ];
}
my $truth = JSON::PP::true;
my $falsity = JSON::PP::false;
my $hash = { k => -3 };
my $inner = [-6];
my $outer = [-2, '-3', $truth, $falsity, undef, 'word', $inner, $hash];
my @inputs = (undef, -8, '-4', 'bad', $truth, $falsity, $hash, $inner, $outer);
my ($matched, $actual) = JQ::Lite::Builtin->dispatch($jq, 'abs', \@inputs);
ok($matched, 'abs remains registered under its existing exact name');
is_deeply($actual, old_abs(\@inputs),
    'direct abs mapper matches the previous scalar coercion and array policy');
is(scalar(@$actual), scalar(@inputs), 'abs emits exactly one value per input');
is("$inputs[2]", '-4', 'abs preserves source numeric-string contents');
is("$outer->[1]", '-3', 'abs preserves source nested numeric-string contents');
is_deeply($hash, { k => -3 }, 'abs leaves the original object unchanged');
ok(!defined $actual->[0], 'null remains an explicit output slot');
is(refaddr($actual->[4]), refaddr($truth),
    'scalar true remains the same boolean reference');
is(refaddr($actual->[5]), refaddr($falsity),
    'scalar false remains the same boolean reference');
is(refaddr($actual->[6]), refaddr($hash),
    'root object is passed through by reference');
isnt(refaddr($actual->[7]), refaddr($inner),
    'array result is newly allocated');
is(refaddr($actual->[8][6]), refaddr($inner),
    'array nested inside array is passed through by reference');
is(refaddr($actual->[8][7]), refaddr($hash),
    'object nested inside array is passed through by reference');
my ($match_empty, $empty) =
    JQ::Lite::Builtin->dispatch($jq, 'abs', []);
ok($match_empty, 'abs still matches with an empty direct input stream');
is_deeply($empty, [], 'abs does not synthesize results from an empty stream');
is_deeply(output('null', 'empty | abs'), [],
    'abs does not synthesize results after empty upstream');

# The surrounding numeric registrations must remain unchanged.
for my $case (
    ['[-1.5,2.5]', 'ceil', '[[-1,3]]'],
    ['[-1.5,2.5]', 'floor', '[[-2,2]]'],
    ['["-3",null]', 'to_number', '[[-3,null]]'],
    ['"12"', 'tonumber', '[12]'],
    ['[-5,8]', 'clamp(0,3)', '[[0,3]]'],
) {
    my ($input, $filter, $expected) = @$case;
    is_deeply(output($input, $filter), $json->decode($expected),
        "$filter remains unaffected by abs stream mapping");
}

# Standalone child module registration must not depend on the parent
# Builtin registry having already been required.
my $lib = File::Spec->catdir($FindBin::Bin, '..', 'lib');
my $standalone = <<'PERL';
use strict;
use warnings;
use JSON::PP ();
require JQ::Lite::Builtin::Math;
die 'parent Builtin loaded' if exists $INC{'JQ/Lite/Builtin.pm'};
my ($input, $expected) = @ARGV;
my %handlers;
JQ::Lite::Builtin::Math->register(sub {
    my ($name, $handler) = @_;
    return if ref $name eq 'Regexp';
    my @names = ref($name) eq 'ARRAY' ? @$name : ($name);
    $handlers{$_} = $handler for @names;
});
die 'abs not registered' unless exists $handlers{abs};
my $json = JSON::PP->new->allow_nonref->canonical;
my $got = $handlers{abs}->(undef, [$json->decode($input)]);
die 'incorrect standalone abs'
    if $json->encode($got) ne $json->encode($json->decode($expected));
die 'parent Builtin loaded after register'
    if exists $INC{'JQ/Lite/Builtin.pm'};
PERL
for my $case (
    ['null', '[null]'],
    ['-5', '[5]'],
    ['"-6"', '[6]'],
    ['[-2,true,false]', '[[2,1,0]]'],
    ['{"n":-2}', '[{"n":-2}]'],
) {
    is(system($^X, "-I$lib", '-e', $standalone, '--', @$case), 0,
        "standalone Math registration preserves abs input $case->[0]");
}

done_testing;
