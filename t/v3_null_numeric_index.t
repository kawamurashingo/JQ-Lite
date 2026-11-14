use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Error ();

my $jq = JQ::Lite->new;

sub results {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

subtest 'numeric indexing into JSON null returns null' => sub {
    is_deeply(results('null', '.[5]'), [undef], 'null indexed directly');
    is_deeply(results('null', '.a[5]'), [undef], 'null field then numeric index');
    is_deeply(results('{"a":null}', '.a[5]'), [undef], 'nested null field');
    is_deeply(results('{"a":null}', '.a[5].b'), [undef], 'path continues through null');
    is_deeply(results('{}', '.missing[5]'), [undef], 'missing field before numeric index');
    is_deeply(results('{"a":null}', '.a | .[5]'), [undef], 'null input to piped index');
};

subtest 'array index of null element or missing slot returns null' => sub {
    is_deeply(results('[null]', '.[0]'), [undef], 'in-bounds null slot');
    is_deeply(results('[10]', '.[5]'), [undef], 'out of range array slot');
    is_deeply(results('[]', '.[0]'), [undef], 'empty array index returns null');
    is_deeply(results('{"a":[null]}', '.a[0]'), [undef], 'nested in-bounds null slot');
    is_deeply(results('{"a":[10]}', '.a[5]'), [undef], 'nested out of range slot');
    is_deeply(results('{"a":[null]}', '.a[0].b'), [undef], 'field through indexed null');
    is_deeply(results('{"a":[10]}', '.a[5].b'), [undef], 'field through out-of-range slot');
};

subtest 'normal array indexing and empty iteration still work' => sub {
    is_deeply(results('[10,20]', '.[1]'), [20], 'ordinary array index');
    is_deeply(results('{"a":[10,20]}', '.a[0]'), [10], 'nested array index');
    is_deeply(results('[]', '.[]'), [], 'empty array iteration remains empty stream');
    is_deeply(results('{"a":[]}', '.a[]'), [], 'nested empty array iterator remains empty stream');
    is_deeply(results('{}', '.missing'), [undef], 'missing object field still null');
};

subtest 'indexing an object with a number still fails' => sub {
    for my $case (
        ['{}', '.[5]'],
        ['{"a":{}}', '.a[5]'],
    ) {
        my ($input, $filter) = @$case;
        my $ok = eval { $jq->run_query($input, $filter); 1 };
        my $err = $@;
        ok(!$ok, "$filter rejects an object");
        isa_ok($err, 'JQ::Lite::Error::Evaluation') if !$ok;
    }
};

done_testing();
