use strict;
use warnings;
use Test::More;
use JSON::PP ();
use Scalar::Util qw(refaddr);
use JQ::Lite;
use JQ::Lite::Builtin ();
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;

sub run {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# Previously substr normalized a missing capture to "" before calling
# _parse_arguments. The common parser already handles both undefined
# and empty captures, so the argument lists must remain identical.
for my $raw (
    undef, '', ' ', '  ', '0', '1', '2', '-2', '1,2',
    'null', 'null,2', '"2"', '2.9', '1e1', 'true',
    'false', '"bad"', '[1]', '{"x":1}', '"a,b"',
) {
    my $old_raw = defined($raw) ? $raw : '';
    my @old_args = JQ::Lite::Util::_parse_arguments($old_raw);
    my @new_args = JQ::Lite::Util::_parse_arguments($raw);
    is_deeply(\@new_args, \@old_args,
        'substr parser preserves argument list for '
            . (defined($raw) ? "[$raw]" : 'missing argument'));
}

# The non-argument portions of substr are unchanged: positional slicing,
# numeric-string coercion, optional length and legacy error behavior.
my @cases = (
    ['substr',             '"abcdef"', '"abcdef"', 'missing capture'],
    ['substr()',           '"abcdef"', '"abcdef"', 'empty capture'],
    ['substr( )',          '"abcdef"', '"abcdef"', 'whitespace capture'],
    ['substr(null)',       '"abcdef"', '"abcdef"', 'null start'],
    ['substr(null,null)',  '"abcdef"', '"abcdef"', 'null start and length'],
    ['substr(0)',          '"abcdef"', '"abcdef"', 'explicit zero start'],
    ['substr(1)',          '"abcdef"', '"bcdef"',  'one-based offset'],
    ['substr(1,2)',        '"abcdef"', '"bc"',     'start and length'],
    ['substr(2,2)',        '"abcdef"', '"cd"',     'middle substring'],
    ['substr(-2)',         '"abcdef"', '"ef"',     'negative start'],
    ['substr(2,0)',        '"abcdef"', '""',       'zero length'],
    ['substr(1,-1)',       '"abcdef"', '"bcde"',   'negative length'],
    ['substr("2")',        '"abcdef"', '"cdef"',   'numeric string'],
    ['substr(2.9,2.9)',    '"abcdef"', '"cd"',     'fractional bounds truncated'],
    ['substr(0,null)',     '"abcdef"', '"abcdef"', 'null length'],
    ['substr(2,99)',       '"abcdef"', '"cdef"',   'length beyond input'],
    ['substr(1,2,99)',     '"abcdef"', '"bc"',     'unused extra argument'],
    ['substr(1e0,2)',     '"abcdef"', '"bc"',     'scientific notation'],
    ['substr(0,2)',        'true',     '"tr"',     'boolean stringification'],
    ['substr(1,2)',        'false',    '"al"',     'false stringification'],
    ['substr(0,2)',        'null',     'null',     'null pass-through'],
    ['substr(1,2)',        '{"a":[1]}', '{"a":[1]}',
        'opaque object pass-through'],
);

for my $case (@cases) {
    my ($filter, $input, $expected, $label) = @$case;
    my $want = $json->decode($expected);
    is_deeply(run($input, $filter), [$want],
        "$filter keeps $label");
    my ($matched, $outputs) = JQ::Lite::Builtin->dispatch(
        $jq, $filter, [$json->decode($input)]
    );
    ok($matched, "$filter remains registered ($label)");
    is_deeply($outputs, [$want],
        "$filter direct dispatch retains $label");
}

# Every input produces exactly one value. Arrays are processed recursively
# while objects remain opaque, including their nested string values.
my @array_cases = (
    ['["abcdef","xyz"]', 'substr(1,2)', '["bc","yz"]'],
    ['["a",null,true,false]', 'substr(0,2)',
        '["a",null,"tr","fa"]'],
    ['[["hello"],["world"]]', 'substr(1,2)',
        '[["el"],["or"]]'],
    ['[{"keep":"abcdef"},["abcdef"],null]', 'substr(1,2)',
        '[{"keep":"abcdef"},["bc"],null]'],
    ['[]', 'substr()', '[]'],
);
for my $case (@array_cases) {
    my ($input, $filter, $expected) = @$case;
    is_deeply(run($input, $filter), [$json->decode($expected)],
        "$filter retains array nesting and JSON types for $input");
}
is_deeply(run('["abcdef","xyz",null]', '.[] | substr(1,2)'),
    ['bc','yz',undef], 'ordered streams preserve null slots');
is_deeply(run('null', 'empty | substr'), [],
    'empty upstream stream produces no output');

my $object = { keep => ['abcdef'] };
my $true = JSON::PP::true;
my $false = JSON::PP::false;
my @inputs = ($object, $true, $false, undef, 'abcdef', ['xyz',undef]);
my ($found, $values) = JQ::Lite::Builtin->dispatch(
    $jq, 'substr', \@inputs
);
ok($found, 'substr matches direct stream without parentheses');
is_deeply($values,
    [$object, 'true', 'false', undef, 'abcdef', ['xyz',undef]],
    'missing arguments preserve mixed-input stream cardinality');
is(refaddr($values->[0]), refaddr($object),
    'object passthrough preserves reference identity');
is(refaddr($values->[0]{keep}), refaddr($object->{keep}),
    'nested object value is unchanged');
my ($empty_found, $empty_out) =
    JQ::Lite::Builtin->dispatch($jq, 'substr()', []);
ok($empty_found, 'substr() matches an empty direct stream');
is_deeply($empty_out, [], 'empty direct stream stays empty');

for my $case (
    ['substr("bad")', qr/substr\(\): start index must be numeric/,
        'non-numeric start'],
    ['substr(0,"bad")', qr/substr\(\): length must be numeric/,
        'non-numeric length'],
) {
    my ($filter, $error, $label) = @$case;
    my $ok = eval { $jq->run_query('"abcdef"', $filter); 1 };
    ok(!$ok, "$label remains an error");
    like("$@", $error, "$label keeps its old error text");
}

done_testing;
