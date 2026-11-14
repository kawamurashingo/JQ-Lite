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

# The common argument parser handles undef/empty captures itself.
# The old flatten_depth wrapper normalized undef to '' and skipped
# parsing on empty text. Keep the exact argument sequence in both cases.
my @raw_arguments = (
    undef, '', ' ', '  ', '0', '1', '2', '-2', '2.7',
    'null', 'true', 'false', '"2"', '"bad"', '2, 100',
    '1e1', '[]', '{"depth":2}', '"a,b"',
);
for my $raw (@raw_arguments) {
    my $old_raw = defined($raw) ? $raw : '';
    my @old = length($old_raw) ? JQ::Lite::Util::_parse_arguments($old_raw) : ();
    my @new = JQ::Lite::Util::_parse_arguments($raw);
    is_deeply(\@new, \@old,
        'common argument parser retains prior result for '
            . (defined($raw) ? "[$raw]" : 'undefined capture'));
}

my $nested = '[[1,[2,[3]]],[],[4,[5]]]';
my %expected = (
    zero => '[[1,[2,[3]]],[],[4,[5]]]',
    one  => '[1,[2,[3]],4,[5]]',
    two  => '[1,2,[3],4,5]',
    all  => '[1,2,3,4,5]',
);
my @cases = (
    ['flatten_depth',          'one', 'no parentheses'],
    ['flatten_depth()',        'one', 'empty parentheses'],
    ['flatten_depth( )',       'one', 'whitespace only'],
    ['flatten_depth(null)',    'one', 'JSON null argument'],
    ['flatten_depth("bad")',   'one', 'non-numeric argument'],
    ['flatten_depth(1)',       'one', 'explicit one'],
    ['flatten_depth(2)',       'two', 'explicit two'],
    ['flatten_depth("2")',     'two', 'numeric string'],
    ['flatten_depth(2.8)',     'two', 'fraction truncated'],
    ['flatten_depth(2, 99)',   'two', 'extra argument ignored'],
    ['flatten_depth(0)',      'zero', 'zero depth'],
    ['flatten_depth(-1)',     'zero', 'negative depth clamps to zero'],
    ['flatten_depth(8)',       'all', 'depth above structure'],
    ['flatten_depth(1e1)',     'all', 'scientific notation'],
);

for my $case (@cases) {
    my ($filter, $key, $label) = @$case;
    my $wanted = $json->decode($expected{$key});
    is_deeply(run($nested, $filter), [$wanted], "$filter: $label");
    my ($matched, $values) = JQ::Lite::Builtin->dispatch(
        $jq, $filter, [$json->decode($nested)]
    );
    ok($matched, "$filter remains registered");
    is_deeply($values, [$wanted], "$filter direct dispatch: $label");
}

# The parser refactor must not affect array/non-array policy, stream
# cardinality, JSON booleans, or nested arrays inside opaque objects.
my $mixed = '[{"keep":[[1]]},null,true,false,[2,[3]]]';
my $mixed_expected = '[{"keep":[[1]]},null,true,false,2,[3]]';
for my $filter ('flatten_depth', 'flatten_depth()', 'flatten_depth(1)') {
    is_deeply(run($mixed, $filter), [$json->decode($mixed_expected)],
        "$filter preserves mixed JSON slots and object boundaries");
}
is_deeply(run('[[1,[2]],[3,[4]],null,42]', '.[] | flatten_depth()'),
    [[1,2],[3,4],undef,42], 'stream order and one output per input preserved');
is_deeply(run('null', 'empty | flatten_depth()'), [],
    'empty upstream stream stays empty');

my $object = { nested => [[1]], flag => JSON::PP::true };
my $truth = JSON::PP::true;
my $falsity = JSON::PP::false;
my @inputs = ($object, $truth, $falsity, undef, 42, 'text', [1,[2,[3]]]);
my ($found, $outputs) = JQ::Lite::Builtin->dispatch(
    $jq, 'flatten_depth()', \@inputs
);
ok($found, 'bare empty-argument capture registers for mixed direct streams');
is_deeply($outputs, [$object, $truth, $falsity, undef, 42, 'text', [1,2,[3]]],
    'direct dispatch preserves passthrough, order and depth');
is(refaddr($outputs->[0]), refaddr($object),
    'non-array object identity is unchanged');
is(refaddr($outputs->[1]), refaddr($truth),
    'true boolean identity is unchanged');
is(refaddr($outputs->[2]), refaddr($falsity),
    'false boolean identity is unchanged');
my ($empty_found, $empty_outputs) = JQ::Lite::Builtin->dispatch(
    $jq, 'flatten_depth', []
);
ok($empty_found, 'flatten_depth handles an empty direct stream');
is_deeply($empty_outputs, [], 'empty direct stream emits no values');

done_testing;
