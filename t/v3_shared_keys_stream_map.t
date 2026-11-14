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

sub results {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# keys sorts hash members, while arrays always expose zero-based indices.
my @sorted = (
    ['{}', [], 'empty object'],
    ['[]', [], 'empty array'],
    ['[null]', [0], 'single-element array'],
    ['[true,false,0]', [0,1,2], 'mixed array values'],
    ['{"z":1,"a":2}', ['a','z'], 'hash key order'],
    ['{"2":1,"10":2}', ['10','2'], 'lexical numeric-looking keys'],
    ['{"a":[1],"b":{"x":2}}', ['a','b'], 'nested hash values ignored'],
    ['{"Z":1,"a":2,"A":3}', ['A','Z','a'], 'case-sensitive keys'],
);
for my $case (@sorted) {
    my ($input, $expected, $label) = @$case;
    is_deeply(results($input, 'keys'), [$expected],
        "keys preserves $label");
}

# keys_unsorted iterates the same members without promising any order.
# Only compare sets; Perl hash iteration may vary between runs.
for my $case (@sorted) {
    my ($input, $expected, $label) = @$case;
    my $output = results($input, 'keys_unsorted');
    is(scalar(@$output), 1,
        "keys_unsorted emits one result for $label");
    my @actual = sort @{ $output->[0] };
    is_deeply(\@actual, [sort @$expected],
        "keys_unsorted preserves the member set for $label");
}

for my $case (
    ['null', 'null'],
    ['true', 'boolean true'],
    ['false', 'boolean false'],
    ['7', 'numeric scalar'],
    ['"text"', 'text scalar'],
) {
    my ($raw, $label) = @$case;
    is_deeply(results($raw, 'keys_unsorted'), [undef],
        "keys_unsorted preserves undef output for $label");
    my $ok = eval { results($raw, 'keys'); 1 };
    ok(!$ok, "keys still rejects $label");
    like("$@", qr/^keys\(\): argument must be an object or array/,
        "keys retains exact error for $label");
}

my $stream_input = '[{"z":1,"a":2},[],[true,7],{"x":8}]';
is_deeply(results($stream_input, '.[] | keys'),
    [['a','z'],[],[0,1],['x']],
    'keys preserves multiple ordered outputs');
my $unsorted_stream = results(
    '[{"z":1,"a":2},null,[true,7],false,{"x":8}]',
    '.[] | keys_unsorted'
);
is(scalar(@$unsorted_stream), 5,
    'keys_unsorted keeps null and invalid slots in ordered output stream');
is_deeply([sort @{ $unsorted_stream->[0] }], ['a','z'],
    'first object output retains its unsorted set');
ok(!defined $unsorted_stream->[1], 'null stream slot becomes undef');
is_deeply($unsorted_stream->[2], [0,1],
    'array index output remains in the original stream position');
ok(!defined $unsorted_stream->[3], 'boolean stream slot becomes undef');
is_deeply($unsorted_stream->[4], ['x'],
    'last object output remains in the original stream position');

my $obj = { z => { nested => [-3] }, a => JSON::PP::true };
my $array = [undef, 9, JSON::PP::false];
my $empty_hash = {};
my @valid = ($obj, $array, [], $empty_hash);
my @all = (@valid, undef, JSON::PP::true, JSON::PP::false, 17, 'word');
my $before = $json->encode(\@all);

my ($found, $sorted_output) =
    JQ::Lite::Builtin->dispatch($jq, 'keys', \@valid);
ok($found, 'keys exact registration remains present');
is_deeply($sorted_output, [['a','z'],[0,1,2],[],[]],
    'direct keys maps every valid input once and in order');
is(scalar(@$sorted_output), scalar(@valid),
    'direct keys preserves stream cardinality');
my ($unsorted_found, $unsorted_output) =
    JQ::Lite::Builtin->dispatch($jq, 'keys_unsorted', \@all);
ok($unsorted_found, 'keys_unsorted exact registration remains present');
is(scalar(@$unsorted_output), scalar(@all),
    'keys_unsorted maps every valid and invalid input once');
is_deeply([sort @{ $unsorted_output->[0] }], ['a','z'],
    'direct keys_unsorted preserves original object key set');
is_deeply($unsorted_output->[1], [0,1,2],
    'direct keys_unsorted retains array index order');
is_deeply($unsorted_output->[2], [],
    'direct keys_unsorted retains empty array result');
is_deeply($unsorted_output->[3], [],
    'direct keys_unsorted retains empty object result');
for my $i (4 .. $#all) {
    ok(!defined $unsorted_output->[$i],
        "direct keys_unsorted preserves undefined invalid slot $i");
}
my ($alias_found, $alias_output) =
    JQ::Lite::Builtin->dispatch($jq, 'keys_unsorted()', \@all);
ok($alias_found, 'keys_unsorted() registry alias remains present');
is(scalar(@$alias_output), scalar(@all),
    'keys_unsorted() alias preserves stream cardinality');
is_deeply([sort @{ $alias_output->[0] }], ['a','z'],
    'keys_unsorted() alias retains unordered object membership');
is_deeply($alias_output->[1], [0,1,2],
    'keys_unsorted() alias retains numeric array offsets');
is($json->encode(\@all), $before,
    'keys builtins do not modify input values');
isnt(refaddr($sorted_output->[1]), refaddr($array),
    'keys array result is a new array and not the input');
isnt(refaddr($sorted_output->[0]), refaddr($obj),
    'keys object result is a new array and not the input');

for my $name ('keys', 'keys_unsorted', 'keys_unsorted()') {
    my ($matched, $empty) =
        JQ::Lite::Builtin->dispatch($jq, $name, []);
    ok($matched, "$name matches an empty upstream stream");
    is_deeply($empty, [], "$name produces no outputs from empty input");
}
is_deeply(results('null', 'empty | keys'), [],
    'keys does not create an output after empty');
is_deeply(results('null', 'empty | keys_unsorted'), [],
    'keys_unsorted does not create an output after empty');

my %names = map { $_ => 1 } JQ::Lite::Builtin->registered_names;
ok($names{keys}, 'keys spelling remains registered');
ok($names{keys_unsorted}, 'keys_unsorted spelling remains registered');
ok($names{'keys_unsorted()'}, 'keys_unsorted() spelling remains registered');
ok(!$names{'keys()'}, 'no new keys() registration is introduced');

# The standalone child registry can load Object without preloading parent
# Builtin.pm, and the mapper wrapper does not change registration order.
my $lib = File::Spec->catdir($FindBin::Bin, '..', 'lib');
my $standalone = <<'PERL';
use strict;
use warnings;
use JSON::PP ();
require JQ::Lite::Builtin::Object;
die 'parent Builtin loaded' if exists $INC{'JQ/Lite/Builtin.pm'};
my ($name, $input, $expected) = @ARGV;
my %handlers;
JQ::Lite::Builtin::Object->register(sub {
    my ($spec, $handler) = @_;
    return if ref($spec) eq 'Regexp';
    my @names = ref($spec) eq 'ARRAY' ? @$spec : ($spec);
    $handlers{$_} = $handler for @names;
});
die "missing handler $name" unless exists $handlers{$name};
my $json = JSON::PP->new->allow_nonref->canonical;
my $result = $handlers{$name}->(undef, [$json->decode($input)]);
die "wrong standalone handler $name"
    unless $json->encode($result) eq $json->encode($json->decode($expected));
die 'parent Builtin loaded after register'
    if exists $INC{'JQ/Lite/Builtin.pm'};
PERL
for my $case (
    ['keys', '{"b":2,"a":1}', '[["a","b"]]'],
    ['keys', '[5,4,3]', '[[0,1,2]]'],
    ['keys_unsorted', '[null,true]', '[[0,1]]'],
    ['keys_unsorted()', '"text"', '[null]'],
    ['keys_unsorted()', '[]', '[[]]'],
) {
    is(system($^X, "-I$lib", '-e', $standalone, '--', @$case), 0,
        "standalone Object preserves $case->[0] with $case->[1]");
}

done_testing;

