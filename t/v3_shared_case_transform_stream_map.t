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

# The five case transforms now use the same one-input/one-output mapping
# wrapper as trim/tojson/fromjson. They must keep their own modes and
# distinct Unicode-vs-ASCII handling.
my @cases = (
    ['titlecase', '"hELLO wORLD"', '"Hello World"', 'titlecased words'],
    ['titlecase', '"foo-bar 98 wORLD"', '"Foo-Bar 98 World"', 'punctuation and digits'],
    ['titlecase', '["aLICE","bOB"]', '["Alice","Bob"]', 'array of words'],
    ['upper', '"heLLo"', '"HELLO"', 'ASCII uppercase'],
    ['upper', '["a","MiXeD"]', '["A","MIXED"]', 'array uppercase'],
    ['upper', '"Ångström"', '"ÅNGSTRÖM"', 'Unicode uppercase'],
    ['lower', '"MiXeD"', '"mixed"', 'ASCII lowercase'],
    ['lower', '["H","W"]', '["h","w"]', 'array lowercase'],
    ['lower', '"ÅNGSTRÖM"', '"ångström"', 'Unicode lowercase'],
    ['ascii_upcase', '"az-By"', '"AZ-BY"', 'ASCII uppercase only'],
    ['ascii_upcase', '["abc","Çafé"]', '["ABC","ÇAFé"]',
        'ASCII mapping leaves accented letters unchanged'],
    ['ascii_upcase', '"Ångström"', '"ÅNGSTRöM"',
        'non-ASCII characters not uppercased'],
    ['ascii_downcase', '"AZ-By"', '"az-by"', 'ASCII lowercase only'],
    ['ascii_downcase', '["ABC","ÇAFé"]', '["abc","Çafé"]',
        'ASCII mapping leaves accented letters unchanged'],
    ['ascii_downcase', '"ÅNGSTRÖM"', '"ÅngstrÖm"',
        'non-ASCII characters not lowercased'],
);

for my $case (@cases) {
    my ($filter, $input, $expected, $label) = @$case;
    is_deeply(results($input, $filter), [$json->decode($expected)],
        "$filter: $label");
}

# Preserve pass-through identity and array nesting, including booleans.
my $mixed_json = '[null,true,false,{"keep":["MiXeD"]},["heLLo",null]]';
my %expected_nested = (
    titlecase      => '[null,true,false,{"keep":["MiXeD"]},["Hello",null]]',
    upper          => '[null,true,false,{"keep":["MiXeD"]},["HELLO",null]]',
    lower          => '[null,true,false,{"keep":["MiXeD"]},["hello",null]]',
    ascii_upcase   => '[null,true,false,{"keep":["MiXeD"]},["HELLO",null]]',
    ascii_downcase => '[null,true,false,{"keep":["MiXeD"]},["hello",null]]',
);
for my $name (sort keys %expected_nested) {
    is_deeply(results($mixed_json, $name),
        [$json->decode($expected_nested{$name})],
        "$name preserves booleans, objects, null and nested array shape");
    is_deeply(results('null', $name), [undef],
        "$name preserves scalar null");
    is_deeply(results('true', $name), [$json->decode('true')],
        "$name preserves scalar true");
    is_deeply(results('false', $name), [$json->decode('false')],
        "$name preserves scalar false");
}

# Registry captures must still include both bare and parenthesized names.
# In particular, a common mapper cannot stringify JSON boolean references
# or turn unmodified hash inputs into new containers.
my $object = { keep => ['MiXeD'] };
my $true = JSON::PP::true;
my $false = JSON::PP::false;
my @inputs = ($object, $true, $false, undef, 'hELLo', ['wOrLD', undef]);

for my $spec (
    ['titlecase',      'Hello', 'World'],
    ['upper',          'HELLO', 'WORLD'],
    ['lower',          'hello', 'world'],
    ['ascii_upcase',   'HELLO', 'WORLD'],
    ['ascii_downcase', 'hello', 'world'],
) {
    my ($name, $single, $nested) = @$spec;
    my ($matched, $values) =
        JQ::Lite::Builtin->dispatch($jq, $name, \@inputs);
    ok($matched, "$name remains registered");
    is_deeply($values, [$object, $true, $false, undef, $single,
                         [$nested, undef]],
        "$name keeps one-to-one dispatch and array nesting");

    my ($alias_matched, $alias_values) =
        JQ::Lite::Builtin->dispatch($jq, "$name()", \@inputs);
    ok($alias_matched, "$name() remains registered");
    is_deeply($alias_values, $values, "$name() retains bare-name semantics");
    is(refaddr($values->[0]), refaddr($object),
        "$name passes object by identity");
    is(refaddr($values->[1]), refaddr($true),
        "$name preserves true boolean identity");
    is(refaddr($values->[2]), refaddr($false),
        "$name preserves false boolean identity");
    my ($empty_matched, $empty) =
        JQ::Lite::Builtin->dispatch($jq, $name, []);
    ok($empty_matched, "$name matches the empty direct stream");
    is_deeply($empty, [], "$name does not generate values from empty");
    is_deeply(results('null', "empty | $name"), [],
        "$name keeps an empty upstream query stream");

    is_deeply(results('["hELLo","wOrLD"]', ".[] | $name"),
        [$single, $nested], "$name preserves ordered streaming values");
}

my %names = map { $_ => 1 } JQ::Lite::Builtin->registered_names;
for my $name (qw(titlecase upper lower ascii_upcase ascii_downcase)) {
    ok($names{$name}, "$name exact spelling remains in registry");
    ok($names{"$name()"}, "$name() exact alias remains in registry");
}

done_testing;
