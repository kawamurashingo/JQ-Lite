use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Builtin ();

my $jq = JQ::Lite->new;

sub results {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# Hash order differs intentionally: keys sorts, keys_unsorted retains Perl
# hash iteration order, which is not a deterministic public contract.
is_deeply(results('{"z":3,"a":1,"m":2}', 'keys'),
    [['a', 'm', 'z']], 'keys returns lexically sorted object keys');
my ($raw) = @{ results('{"z":3,"a":1,"m":2}', 'keys_unsorted') };
is_deeply([ sort @$raw ], ['a', 'm', 'z'],
    'keys_unsorted keeps exactly the object key set');
my ($alias) = @{ results('{"z":3,"a":1,"m":2}', 'keys_unsorted()') };
is_deeply([ sort @$alias ], ['a', 'm', 'z'],
    'keys_unsorted() retains its registered spelling');

for my $case (
    ['[]', []],
    ['[9]', [0]],
    ['[3,1,4]', [0,1,2]],
) {
    my ($json, $expected) = @$case;
    for my $name ('keys', 'keys_unsorted', 'keys_unsorted()') {
        is_deeply(results($json, $name), [$expected],
            "$name returns array indexes for $json");
    }
}

for my $json ('null', '42', '"text"', 'false', 'true') {
    for my $name ('keys_unsorted', 'keys_unsorted()') {
        is_deeply(results($json, $name), [undef],
            "$name retains v2 null passthrough for $json");
    }
    my $ok = eval { $jq->run_query($json, 'keys'); 1 };
    ok(!$ok, "keys rejects unsupported input $json");
    like("$@", qr/^keys\(\): argument must be an object or array/,
        "keys retains its error message for $json");
}

is_deeply(results('[{"b":2,"a":1},[7,8],{}]', '.[] | keys'),
    [['a','b'],[0,1],[]], 'keys preserves stream order across containers');
my $mixed = results('[{"b":2,"a":1},[7,8],{}]', '.[] | keys_unsorted');
is_deeply([sort @{$mixed->[0]}], ['a','b'],
    'keys_unsorted retains first hash key set in a stream');
is_deeply([$mixed->[1], $mixed->[2]], [[0,1],[]],
    'keys_unsorted retains subsequent array and empty-object outputs');
is_deeply(results('[[5,6],[7]]', 'map(keys_unsorted())'),
    [[ [0,1], [0] ]], 'parenthesized spelling works inside map');
is_deeply(results('[1,2]', 'empty | keys_unsorted'),
    [], 'empty upstream stream produces no keys');

my %names = map { $_ => 1 } JQ::Lite::Builtin->registered_names;
ok($names{'keys'}, 'keys stays registered by its original name');
ok($names{'keys_unsorted'}, 'keys_unsorted stays registered');
ok($names{'keys_unsorted()'}, 'keys_unsorted() stays registered');
ok(!$names{'keys()'}, 'keys() is not added as an exact-name alias');

done_testing;
