use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Error ();

my $jq = JQ::Lite->new;

sub results {
    my ($json, $query) = @_;
    return [ $jq->run_query($json, $query) ];
}

subtest 'updated root, not the updated leaf' => sub {
    is_deeply(results('{"a":1,"b":10}', '.a |= . + 1'),
        [{ a => 2, b => 10 }], 'updates a field and preserves siblings');
    is_deeply(results('{"a":{"b":2,"c":4}}', '.a.b |= . + 3'),
        [{ a => { b => 5, c => 4 } }], 'updates nested path');
    is_deeply(results('{"a":[1,2]}', '.a[1] |= . + 1'),
        [{ a => [1, 3] }], 'updates an indexed array element');
    is_deeply(results('[2]', '.[0] |= . + 1'),
        [[3]], 'updates root array element');
};

subtest 'missing and JSON null targets are evaluated as null' => sub {
    is_deeply(results('{}', '.missing |= . + 1'),
        [{ missing => 1 }], 'creates a missing field from null + 1');
    is_deeply(results('{"a":null}', '.a |= . + 1'),
        [{ a => 1 }], 'replaces an explicit null');
    is_deeply(results('{"a":{}}', '.a.b |= . + 1'),
        [{ a => { b => 1 } }], 'creates a missing nested field');
    is_deeply(results('null', '.x |= . + 1'),
        [{ x => 1 }], 'null root becomes an object');
    is_deeply(results('null', '.[0] |= . + 1'),
        [[1]], 'null root becomes an array');
};

subtest 'right hand filter receives the old target only' => sub {
    is_deeply(results('{"a":2,"b":99}', '.a |= . * 3'),
        [{ a => 6, b => 99 }], 'arithmetic uses old a, not root');
    is_deeply(results('{"a":{"b":2}}', '.a |= .b + 1'),
        [{ a => 3 }], 'RHS path is relative to the old a');
    is_deeply(results('{"a":1}', '.a |= .'),
        [{ a => 1 }], 'identity update');
    is_deeply(results('{"a":1}', '.a |= null'),
        [{ a => undef }], 'literal null replacement');
    is_deeply(results('{"a":1}', '.a |= 7'),
        [{ a => 7 }], 'constant replacement');
};

subtest 'unsupported update streams and invalid target types are explicit errors' => sub {
    for my $case (
        ['{"a":1}', '.a |= empty', 'empty RHS'],
        ['{"a":1}', '.a |= (1,2)', 'multiple RHS results'],
        ['{"a":2}', '.a[0] |= . + 1', 'index on numeric leaf'],
        ['{"a":{}}', '.a[0] |= . + 1', 'numeric index on object'],
    ) {
        my ($json, $query, $label) = @$case;
        my $ok = eval { $jq->run_query($json, $query); 1 };
        my $err = $@;
        ok(!$ok, "$label: no silent success");
        isa_ok($err, 'JQ::Lite::Error::Evaluation', "$label: evaluation error")
            if !$ok;
    }
};

done_testing;
