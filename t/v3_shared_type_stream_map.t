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
my $json = JSON::PP->new->allow_nonref->canonical;

sub run {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# Fixed Type builtins transform one input to one output, unlike
# arrays/objects/scalars (grep) and empty (zero outputs).
my @public_cases = (
    ['null', 'length', '[0]', 'null length'],
    ['false', 'length', '[1]', 'false scalar length'],
    ['true', 'length', '[1]', 'true scalar length'],
    ['123', 'length', '[3]', 'numeric decimal digits'],
    ['-25', 'length', '[3]', 'negative numeric digits'],
    ['"42"', 'length', '[2]', 'numeric-looking string length'],
    ['""', 'length', '[0]', 'empty text length'],
    ['"abc"', 'length', '[3]', 'ASCII string length'],
    ['"\u65e5\u672c"', 'length', '[2]', 'UTF-8 character count'],
    ['[1,null,true]', 'length', '[3]', 'array length'],
    ['{"a":1,"b":2}', 'length', '[2]', 'object key count'],
    ['null', 'type', '["null"]', 'null type'],
    ['false', 'type', '["boolean"]', 'false type'],
    ['true', 'type()', '["boolean"]', 'true type alias'],
    ['123', 'type', '["number"]', 'number type'],
    ['"123"', 'type()', '["string"]', 'numeric-looking string type alias'],
    ['[]', 'type', '["array"]', 'array type'],
    ['{}', 'type()', '["object"]', 'object type alias'],
    ['null', 'count', '[0]', 'null count'],
    ['false', 'count', '[1]', 'false count'],
    ['true', 'count', '[1]', 'true count'],
    ['0', 'count', '[1]', 'zero count'],
    ['"0"', 'count', '[1]', 'string count'],
    ['[]', 'count', '[0]', 'empty array count'],
    ['[1,2,3]', 'count', '[3]', 'array element count'],
    ['{}', 'count', '[1]', 'empty object count'],
    ['[1,2]', 'values', '[[1,2]]', 'array values passthrough'],
    ['"text"', 'values', '["text"]', 'string values passthrough'],
    ['null', 'values', '[null]', 'null values passthrough'],
    ['false', 'values', '[false]', 'boolean values passthrough'],
);

for my $case (@public_cases) {
    my ($input, $filter, $expected, $label) = @$case;
    is_deeply(run($input, $filter), $json->decode($expected),
        "$filter preserves $label");
}

my @stream_cases = (
    ['[null,true,"ab",[1,2],{"a":1}]', 'length', '[0,1,2,2,1]'],
    ['[null,true,4,"4",[],{}]', 'type',
     '["null","boolean","number","string","array","object"]'],
    ['[null,true,4,"4",[],{}]', 'type()',
     '["null","boolean","number","string","array","object"]'],
    ['[null,true,4,"4",[],{}]', 'count', '[0,1,1,1,0,1]'],
    ['[null,true,4,"4",[1,2]]', 'values',
     '[null,true,4,"4",[1,2]]'],
);
for my $case (@stream_cases) {
    my ($input, $filter, $expected) = @$case;
    is_deeply(run($input, ".[] | $filter"), $json->decode($expected),
        "$filter maps each streamed value in order");
}

# Object values iterate in Perl hash order; compare members without
# imposing any new ordering promise.
my ($object_values) = @{ run('{"a":4,"b":2,"c":7}', 'values') };
is(ref($object_values), 'ARRAY', 'values maps an object to one array');
is_deeply([ sort { $a <=> $b } @$object_values ], [2,4,7],
    'object values are preserved regardless of hash key iteration order');

my $obj = { a => 3 };
my $arr = [1,2];
my $truth = JSON::PP::true;
my $falsity = JSON::PP::false;
my @inputs = (undef, $truth, $falsity, 12, '12', $arr, $obj);
my @contracts = (
    ['type',   ['null','boolean','boolean','number','string','array','object']],
    ['type()', ['null','boolean','boolean','number','string','array','object']],
    ['length', [0,1,1,2,2,2,1]],
    ['count',  [0,1,1,1,1,2,1]],
    ['values', [undef,$truth,$falsity,12,'12',$arr,[3]]],
);
for my $contract (@contracts) {
    my ($name, $expected) = @$contract;
    my ($found, $output) = JQ::Lite::Builtin->dispatch($jq, $name, \@inputs);
    ok($found, "$name remains registered");
    is_deeply($output, $expected, "$name has one result per input");
    is(scalar(@$output), scalar(@inputs), "$name does not drop values");
    my ($matched_empty, $empty) =
        JQ::Lite::Builtin->dispatch($jq, $name, []);
    ok($matched_empty, "$name accepts empty direct input stream");
    is_deeply($empty, [], "$name produces no output from empty input stream");
}
my (undef, $pass_through) = JQ::Lite::Builtin->dispatch($jq, 'values', \@inputs);
is(refaddr($pass_through->[1]), refaddr($truth),
    'values preserves the true boolean reference');
is(refaddr($pass_through->[2]), refaddr($falsity),
    'values preserves the false boolean reference');
is(refaddr($pass_through->[5]), refaddr($arr),
    'values passes through array reference unchanged');
is_deeply(\@inputs, [undef,$truth,$falsity,12,'12',$arr,$obj],
    'type callbacks never modify the source stream');

for my $name (qw(length type type() values count)) {
    is_deeply(run('null', "empty | $name"), [],
        "$name does not synthesize a value from an empty upstream stream");
}
for my $case (
    ['[[],3,{}]', 'arrays', '[[]]'],
    ['[[],3,{}]', 'objects', '[{}]'],
    ['[null,false,3,[]]', 'scalars', '[null,false,3]'],
    ['[1,2]', 'empty', '[]'],
) {
    my ($input, $filter, $expected) = @$case;
    is_deeply(run($input, ".[] | $filter"), $json->decode($expected),
        "$filter retains distinct filtering/empty cardinality");
}

# Type previously required only Value. Loading Util for the shared mapper
# must not introduce a dependency on loading the parent Builtin registry.
my $lib = File::Spec->catdir($FindBin::Bin, '..', 'lib');
my $standalone = <<'PERL';
use strict;
use warnings;
use JSON::PP ();
require JQ::Lite::Builtin::Type;
die 'parent loaded' if exists $INC{'JQ/Lite/Builtin.pm'};
my ($name, $input, $expected) = @ARGV;
my %handlers;
JQ::Lite::Builtin::Type->register(sub {
    my ($names, $handler) = @_;
    return if ref $names eq 'Regexp';
    my @names = ref $names eq 'ARRAY' ? @$names : ($names);
    $handlers{$_} = $handler for @names;
});
die "missing $name" unless $handlers{$name};
my $json = JSON::PP->new->allow_nonref->canonical;
my $got = $handlers{$name}->(undef, [$json->decode($input)]);
die 'incorrect standalone handler result'
    if $json->encode($got) ne $json->encode($json->decode($expected));
die 'parent loaded after register' if exists $INC{'JQ/Lite/Builtin.pm'};
PERL
for my $case (
    ['length','[1,null]','[2]'],
    ['type','true','["boolean"]'],
    ['type()','"42"','["string"]'],
    ['values','[1,2]','[[1,2]]'],
    ['count','null','[0]'],
    ['scalars','false','[false]'],
    ['empty','true','[]'],
) {
    is(system($^X, "-I$lib", '-e', $standalone, @$case), 0,
        "standalone Type registration: $case->[0]");
}

done_testing;
