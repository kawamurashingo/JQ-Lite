use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Error ();

my $jq = JQ::Lite->new;

sub results {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

subtest 'object values update and root is returned once' => sub {
    is_deeply(results('{"a":1,"b":2}', '.[] |= . + 1'),
        [{a => 2, b => 3}], 'root object values');
    is_deeply(results('{"items":{"a":1,"b":2},"other":9}', '.items[] |= . + 2'),
        [{items => {a => 3, b => 4}, other => 9}], 'nested object values and sibling');
    is_deeply(results('{}', '.[] |= . + 1'),
        [{}], 'empty root object');
    is_deeply(results('{"items":{}}', '.items[] |= . + 1'),
        [{items => {}}], 'empty nested object');
    is_deeply(results('{"items":{"a":5,"b":null}}', '.items[] |= . + 1'),
        [{items => {a => 6, b => 1}}], 'explicit null member');
    is_deeply(results('{"a":1,"b":2}', '.[] |= null'),
        [{a => undef, b => undef}], 'JSON null is a value, not deletion');
    is_deeply(results('{"a":1}', '.[] |= (5,6)'),
        [{a => 5}], 'first RHS value is selected');
};

subtest 'deletion and filtered update preserve unrelated object keys' => sub {
    is_deeply(results('{"a":1,"b":2}', '.[] |= empty'),
        [{}], 'delete all root object members');
    is_deeply(results('{"items":{"a":1,"b":2}}', '.items[] |= empty'),
        [{items => {}}], 'delete all nested object members');
    is_deeply(results('{"items":{"a":1,"b":2}}', '.items[] |= select(. > 1)'),
        [{items => {b => 2}}], 'filter out only failing object values');
    is_deeply(results('{"items":{"a":1,"b":2}}', '.items[] |= (empty, 9)'),
        [{items => {a => 9, b => 9}}], 'first output after empty branch');
    is_deeply(results('{"items":{"a":5,"b":null}}', '.items[] |= select(. > 1)'),
        [{items => {a => 5}}], 'null member deleted');
};

subtest 'nested update applies suffix relative to each object value' => sub {
    is_deeply(results('{"items":{"a":{"n":1,"k":4},"b":{"n":2,"k":5}}}',
            '.items[].n |= . + 2'),
        [{items => {a => {n => 3, k => 4}, b => {n => 4, k => 5}}}],
        'nested object fields');
    is_deeply(results('{"items":{"a":{},"b":{"n":2}}}', '.items[].n |= . + 1'),
        [{items => {a => {n => 1}, b => {n => 3}}}],
        'missing nested fields created');
    is_deeply(results('{"items":{"a":{"n":1,"k":4},"b":{"n":2,"k":5}}}',
            '.items[].n |= empty'),
        [{items => {a => {k => 4}, b => {k => 5}}}],
        'deleting fields does not delete parent entries');
    is_deeply(results('{"items":{"a":[1,2],"b":[3,4]}}',
            '.items[][0] |= . + 1'),
        [{items => {a => [2,2], b => [4,4]}}],
        'fixed array index following object iterator');
};

subtest 'keys are literal values, not interpolated into dotted paths' => sub {
    is_deeply(results('{"a-b":1,"space key":2,"":3}', '.[] |= . + 1'),
        [{'a-b' => 2, 'space key' => 3, '' => 4}],
        'unquoted special keys updated');
    is_deeply(results('{"items":{"a.b":{"n":1},"[]":{"n":2},"":{"n":3}}}',
            '.items[].n |= . + 1'),
        [{items => {'a.b' => {n => 2}, '[]' => {n => 3}, '' => {n => 4}}}],
        'nested updates through special object keys');
    is_deeply(results('{"items":{"a.b":1,"x y":2,"":3}}',
            '.items[] |= empty'),
        [{items => {}}], 'special keys deleted');
};

subtest 'arrays keep their original iterator behavior' => sub {
    is_deeply(results('[1,2,3]', '.[] |= . + 1'),
        [[2,3,4]], 'array values updated');
    is_deeply(results('{"items":[1,2,3]}', '.items[] |= select(. > 1)'),
        [{items => [2,3]}], 'array select still shifts safely');
    is_deeply(results('{"items":[1,2,3]}', '.items[] |= empty'),
        [{items => []}], 'array delete still splices');
};

subtest 'non-container iterators and invalid member paths stay explicit errors' => sub {
    for my $case (
        ['null', '.[] |= . + 1', 'null root'],
        ['{"items":null}', '.items[] |= . + 1', 'null member'],
        ['{"items":5}', '.items[] |= . + 1', 'numeric member'],
        ['{"items":{"a":1}}', '.items[].n |= . + 1', 'invalid nested scalar'],
    ) {
        my ($json, $filter, $label) = @$case;
        my $ok = eval { $jq->run_query($json, $filter); 1 };
        my $error = $@;
        ok(!$ok, "$label: iteration fails");
        isa_ok($error, 'JQ::Lite::Error::Evaluation', "$label: evaluation error")
            unless $ok;
    }
};

done_testing();
