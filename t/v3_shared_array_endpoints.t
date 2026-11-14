use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Builtin ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;

sub run {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# The first/last registry handlers still emit exactly one result per
# input, including null for empty arrays and non-array inputs.
my @cases = (
    ['[1,2,3]',          '[1]',            '[3]',            'numeric array'],
    ['[42]',             '[42]',           '[42]',           'single-item array'],
    ['[]',               '[null]',         '[null]',         'empty array'],
    ['[null,1,2]',       '[null]',         '[2]',            'leading null'],
    ['[1,2,null]',       '[1]',            '[null]',         'trailing null'],
    ['[null]',           '[null]',         '[null]',         'sole null element'],
    ['[false,true]',     '[false]',        '[true]',         'boolean array'],
    ['["a","b","c"]',   '["a"]',          '["c"]',          'string array'],
    ['[[1,2],[3,4]]',    '[[1,2]]',        '[[3,4]]',        'nested arrays are one value'],
    ['[{"id":1},{"id":2}]', '[{"id":1}]',  '[{"id":2}]',      'object elements'],
    ['null',             '[null]',         '[null]',         'null input passthrough'],
    ['123',              '[null]',         '[null]',         'number input fallback'],
    ['"abc"',           '[null]',         '[null]',         'string input fallback'],
    ['{"a":1}',          '[null]',         '[null]',         'object input fallback'],
    ['false',            '[null]',         '[null]',         'boolean input fallback'],
);

for my $case (@cases) {
    my ($input, $first, $last, $label) = @$case;
    is_deeply(run($input, 'first'), $json->decode($first),
        "first: $label");
    is_deeply(run($input, 'last'), $json->decode($last),
        "last: $label");
}

is_deeply(run('[[1,2,3],[],[4,5]]', '.[] | first'),
    [1,undef,4], 'first preserves stream order and null slots');
is_deeply(run('[[1,2,3],[],[4,5]]', '.[] | last'),
    [3,undef,5], 'last preserves stream order and null slots');
is_deeply(run('[[1,2,3],[],[4,5]]', 'map(first)'),
    [[1,undef,4]], 'first composes within map');
is_deeply(run('[[1,2,3],[],[4,5]]', 'map(last)'),
    [[3,undef,5]], 'last composes within map');

for my $name (qw(first last)) {
    my ($matched, $outputs) = JQ::Lite::Builtin->dispatch(
        $jq, $name, [ [7,9], [], undef, {a => 1} ]
    );
    ok($matched, "$name retains exact registry dispatch");
    is_deeply($outputs, [$name eq 'first' ? 7 : 9, undef, undef, undef],
        "$name preserves direct-dispatch cardinality");
    my ($with_parens) = JQ::Lite::Builtin->dispatch($jq, "$name()", [ [7,9] ]);
    ok(!$with_parens, "$name() remains unregistered");
    is_deeply(run('[1,2]', "empty | $name"), [],
        "$name does not restore empty upstream values");
}

done_testing;
