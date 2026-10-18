use strict;
use warnings;
use Test::More;
use JSON::PP ();
use Scalar::Util qw(refaddr);
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;

sub output {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# The comparator has no per-call state. Reuse one CODE reference, while
# retaining numeric-only and lexical fallback rules from practical v2.
my $first = JQ::Lite::Util::_smart_cmp();
my $second = JQ::Lite::Util::_smart_cmp();
is(ref($first), 'CODE', 'the key comparator remains a callback');
is(refaddr($first), refaddr($second),
    'repeated lookup reuses exactly the same callback');

my @pairs = (
    ['2',      '10',     -1, 'numeric integers'],
    ['-5',     '2',      -1, 'signed numeric integers'],
    ['-1.5',   '-2',      1, 'numeric decimal negatives'],
    ['1.20',   '1.2',     0, 'equivalent decimals'],
    ['02',     '2',       0, 'leading zeros compare numerically'],
    ['10',     '2',       1, 'numeric order differs from lexical'],
    ['a',      'b',      -1, 'lexical alphabetic order'],
    ['10a',    '2a',     -1, 'nonnumeric strings compare lexically'],
    ['2e2',    '99',     -1, 'exponent notation falls back to lexical'],
    ['+2',     '10',     -1, 'plus signs fall back to lexical'],
    ['Alpha',  'alpha',  -1, 'case-sensitive strings'],
    ['x',      'x',       0, 'identical text'],
);
for my $case (@pairs) {
    my ($left, $right, $expected, $label) = @$case;
    is($first->($left, $right) <=> 0, $expected,
        "$label: forward ordering");
    is($second->($right, $left) <=> 0, -$expected,
        "$label: reverse ordering");
    is($first->($left, $right) <=> 0, $expected,
        "$label: repeated lookup does not accumulate state");
}

# Both users of _smart_cmp retain the same projected-key behavior.
my @filters = (
    ['[{"k":10,"id":"ten"},{"k":2,"id":"two"}]', 'min_by(.k)',
     '[{"k":2,"id":"two"}]', 'min_by numeric key'],
    ['[{"k":10,"id":"ten"},{"k":2,"id":"two"}]', 'max_by(.k)',
     '[{"k":10,"id":"ten"}]', 'max_by numeric key'],
    ['[{"k":"10","id":"ten"},{"k":"2","id":"two"}]', 'min_by(.k)',
     '[{"k":"2","id":"two"}]', 'min_by numeric-looking string'],
    ['[{"k":"10","id":"ten"},{"k":"2","id":"two"}]', 'max_by(.k)',
     '[{"k":"10","id":"ten"}]', 'max_by numeric-looking string'],
    ['[{"k":"2e2","id":"exponent"},{"k":"99","id":"ninety-nine"}]',
     'min_by(.k)', '[{"k":"2e2","id":"exponent"}]',
     'min_by retains lexical comparison for exponent strings'],
    ['[{"k":"2e2","id":"exponent"},{"k":"99","id":"ninety-nine"}]',
     'max_by(.k)', '[{"k":"99","id":"ninety-nine"}]',
     'max_by retains lexical comparison for exponent strings'],
    ['[{"k":2,"id":"first"},{"k":2,"id":"second"}]', 'min_by(.k)',
     '[{"k":2,"id":"first"}]', 'min_by keeps first tied item'],
    ['[{"k":2,"id":"first"},{"k":2,"id":"second"}]', 'max_by(.k)',
     '[{"k":2,"id":"first"}]', 'max_by keeps first tied item'],
    ['[{"k":10,"id":"ten-first"},{"k":2,"id":"two-first"},'
     . '{"k":10,"id":"ten-second"},{"k":2,"id":"two-second"}]',
     'group_by(.k)',
     '[[{"k":2,"id":"two-first"},{"k":2,"id":"two-second"}],'
     . '[{"k":10,"id":"ten-first"},{"k":10,"id":"ten-second"}]]',
     'group_by numeric group ordering and stable tie order'],
    ['[{"k":"b","id":"b-first"},{"k":"a","id":"a-first"},'
     . '{"k":"b","id":"b-second"}]',
     'group_by(.k)',
     '[[{"k":"a","id":"a-first"}],'
     . '[{"k":"b","id":"b-first"},{"k":"b","id":"b-second"}]]',
     'group_by lexical group ordering and stable tie order'],
    ['[]', 'group_by(.)', '[[]]', 'group_by empty array'],
    ['[]', 'min_by(.)', '[null]', 'min_by empty array'],
    ['[]', 'max_by(.)', '[null]', 'max_by empty array'],
);
for my $case (@filters) {
    my ($input, $filter, $expected, $label) = @$case;
    is_deeply(output($input, $filter), $json->decode($expected), $label);
}

is_deeply(output('[[2,10],[8,3]]', '.[] | min_by(.)'),
    [2,3], 'min_by preserves ordered multi-array stream');
is_deeply(output('[[2,10],[8,3]]', '.[] | max_by(.)'),
    [10,8], 'max_by preserves ordered multi-array stream');
is_deeply(output('[[2,10],[8,3]]', '.[] | group_by(.)'),
    [[[2],[10]],[[3],[8]]],
    'group_by preserves ordered independent groups');
for my $filter ('min_by(.)', 'max_by(.)', 'group_by(.)') {
    is_deeply(output('null', "empty | $filter"), [],
        "$filter does not create values from empty upstream");
}

is(refaddr(JQ::Lite::Util::_smart_cmp()), refaddr($first),
    'public filters do not replace or alter the shared comparator callback');

done_testing;
