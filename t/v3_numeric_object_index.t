use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Error ();

my $jq = JQ::Lite->new;

sub errors_on {
    my ($json, $filter, $label) = @_;
    my $ok = eval { $jq->run_query($json, $filter); 1 };
    my $error = $@;
    ok(!$ok, "$label: index on an object fails");
    isa_ok($error, 'JQ::Lite::Error::Evaluation', "$label: structured error")
        if !$ok;
    if (ref($error) && eval { $error->isa('JQ::Lite::Error') }) {
        is($error->category, 'evaluation', "$label: runtime category");
        like("$error", qr/Cannot index object with number/, "$label: useful error message");
    }
}

sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

subtest 'numeric indices are invalid on JSON objects' => sub {
    errors_on('{}', '.[5]', 'root object');
    errors_on('{"5":"a"}', '.[5]', 'numeric-looking object key is not an array index');
    errors_on('{"a":{}}', '.a[5]', 'nested object');
    errors_on('{"a":{"5":"b"}}', '.a[5]', 'nested object with numeric key');
    errors_on('{"a":{}}', '.a | .[5]', 'index after pipe');
};

subtest 'numeric indices on arrays remain valid' => sub {
    is_deeply(results('[10,20]', '.[0]'), [10], 'root array index');
    is_deeply(results('{"a":[10,20]}', '.a[1]'), [20], 'nested array index');
    is_deeply(results('{"a":null}', '.a[5]'), [undef], 'null indexing remains null');
};

subtest 'missing fields and empty array iterators retain their v3 behavior' => sub {
    is_deeply(results('{}', '.missing'), [undef], 'missing field emits null');
    is_deeply(results('{}', '.missing.value'), [undef], 'missing field chain emits null');
    is_deeply(results('[]', '.[]'), [], 'empty array iteration emits nothing');
    is_deeply(results('{"a":[]}', '.a[]'), [], 'empty nested iterator emits nothing');
};

done_testing();
