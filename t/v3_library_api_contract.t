use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Error ();

# Exercise documented public entry points only. Do not tie the Library
# compatibility contract to private parser, filter or runtime methods.
my $jq = JQ::Lite->new;
isa_ok($jq, 'JQ::Lite', 'default constructor');

my $configured = JQ::Lite->new(
    raw  => 1,
    vars => { greeting => 'hello', user => { name => 'Ada' } },
);
isa_ok($configured, 'JQ::Lite', 'documented constructor options');
is_deeply([ $configured->run_query('{}', '$greeting') ],
    ['hello'], 'predeclared scalar variable');
is_deeply([ $configured->run_query('{}', '$user.name') ],
    ['Ada'], 'predeclared object variable path');
is_deeply([ $configured->run_query('{}', '$greeting') ],
    ['hello'], 'constructor variables survive later queries');

my @identity_cases = (
    ['null', undef, 'null'],
    ['true', JSON::PP::true, 'true'],
    ['false', JSON::PP::false, 'false'],
    ['17', 17, 'integer'],
    ['-2.5', -2.5, 'fractional number'],
    ['"hello"', 'hello', 'string'],
    ['[1,null,false]', [1, undef, JSON::PP::false], 'array'],
    ['{"a":1,"b":[2]}', { a => 1, b => [2] }, 'object'],
);

for my $case (@identity_cases) {
    my ($input, $expected, $label) = @$case;
    my @values = $jq->run_query($input, '.');
    is(scalar @values, 1, "identity emits one value: $label");
    is_deeply([ @values ], [$expected], "identity preserves value: $label");
}

is_deeply([ $jq->run_query('{"a":2}', undef) ], [{ a => 2 }],
    'undefined query returns decoded input');
is_deeply([ $jq->run_query('[1,2]', '  .  ') ], [[1,2]],
    'whitespace around identity query preserves input');
is_deeply([ $jq->run_query('null', '.') ], [undef],
    'null identity is one undef, not zero outputs');

my @bool_true = $jq->run_query('true', '.');
my @bool_false = $jq->run_query('false', '.');
ok(JSON::PP::is_bool($bool_true[0]) && $bool_true[0],
    'true remains a JSON boolean Perl object');
ok(JSON::PP::is_bool($bool_false[0]) && !$bool_false[0],
    'false remains a JSON boolean Perl object');
my @object = $jq->run_query('{"a":1}', '.');
my @array = $jq->run_query('[1,2]', '.');
is(ref($object[0]), 'HASH', 'object result is a hash reference');
is(ref($array[0]), 'ARRAY', 'array result is an array reference');

my $stream_input =
    '{"items":["a",null,true,{"id":2},[1,2]],"empty":[]}';
my @stream = $jq->run_query($stream_input, '.items[]');
is(scalar @stream, 5, 'iterator preserves result count');
is($stream[0], 'a', 'iterator preserves first scalar');
ok(!defined $stream[1], 'iterator preserves null as undef');
ok(JSON::PP::is_bool($stream[2]) && $stream[2],
    'iterator preserves boolean representation');
is_deeply($stream[3], { id => 2 }, 'iterator preserves object result');
is_deeply($stream[4], [1,2], 'iterator preserves array result');

is_deeply([ $jq->run_query($stream_input, '.empty[]') ], [],
    'iterating an empty array yields no results');
is_deeply([ $jq->run_query('null', 'empty') ], [],
    'empty filter yields no results');
is_deeply([ $jq->run_query('{}', '.missing') ], [undef],
    'missing ordinary key yields exactly one null');

is_deeply([ $jq->run_query('{"a":1,"b":2}', '.a, .b') ],
    [1,2], 'comma results preserve their order');
is_deeply([ $jq->run_query('[{"n":1},{"n":3}]', '.[] | .n') ],
    [1,3], 'pipeline preserves ordered multiple results');
is_deeply([ $jq->run_query('{"a":1,"b":2}', '[(.a, .b)]') ],
    [[1,2]], 'array construction returns one array reference');
is_deeply([ $jq->run_query('{"a":1}', '.a') ],
    [1], 'normal query after multi-result query stays independent');

is_deeply([ $configured->run_query('{"value":4}', '. as $local | $local.value') ],
    [4], 'query-local binding is usable during its query');
is_deeply([ $configured->run_query('{}', '$local') ],
    [undef], 'query-local binding does not leak to next call');
is_deeply([ $configured->run_query('{}', '$greeting') ],
    ['hello'], 'predeclared variable survives query-local bindings');

sub check_error {
    my ($json, $filter, $class, $category, $label) = @_;
    local $@;
    my $ok = eval { my @discard = $jq->run_query($json, $filter); 1 };
    my $error = $@;
    ok(!$ok, "$label raises an exception");
    isa_ok($error, $class, "$label error class");
    if (ref $error) {
        is($error->category, $category, "$label stable error category");
        ok(length("$error") > 0, "$label has a readable diagnostic");
    }
}

check_error('{', '.', 'JQ::Lite::Error::Input', 'input',
    'invalid JSON input');
check_error('{}', '.a |', 'JQ::Lite::Error::Parse', 'parse',
    'invalid query syntax');
check_error('{"a":1}', '1/0', 'JQ::Lite::Error::Evaluation', 'evaluation',
    'numeric evaluation failure');

is_deeply([ $jq->run_query('{"a":9}', '.a') ],
    [9], 'library instance remains reusable after caught errors');
is_deeply([ $configured->run_query('{}', '$greeting') ],
    ['hello'], 'configured instance remains reusable after other calls');

done_testing;
