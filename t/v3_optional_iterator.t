use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Error ();

my $jq = JQ::Lite->new;

sub results {
    my ($input, $query) = @_;
    return [ $jq->run_query($input, $query) ];
}

subtest 'optional iterator suppresses scalar iteration errors only' => sub {
    for my $json ('null', '0', '1', '-5', '1.5', 'true', 'false',
                  '"abc"', '""', '"42"') {
        is_deeply(results($json, '.[]?'), [],
            ".[]? drops non-container $json");
    }
    is_deeply(results('null', '0, .[]?'), [0],
        'later optional iterator never removes a prior comma result');
    is_deeply(results('null', '.[]? | (1 / 0)'), [],
        'downstream error is not evaluated for absent iterator output');
    is_deeply(results('1', '.[]? | . + 1'), [],
        'optional iterator emits no inputs to subsequent pipeline stages');
};

subtest 'arrays and objects retain their normal member streams' => sub {
    is_deeply(results('[]', '.[]?'), [], 'empty array emits nothing');
    is_deeply(results('{}', '.[]?'), [], 'empty object emits nothing');
    is_deeply(results('[1,null,false,{"x":2}]', '.[]?'),
        [1, undef, JSON::PP::false, {x => 2}],
        'optional array iterator retains all members including null and false');
    is_deeply(results('{"only":42}', '.[]?'), [42],
        'optional object iterator emits member value');
    is_deeply(results('{"a":null}', '.[]?'), [undef],
        'object null member is an emitted value, not an empty stream');
    is_deeply(results('[[],[1,2],null]', '.[]? | .[]?'),
        [1,2], 'optional nested iterators skip scalar leaves');
    is_deeply(results('{"only":[2,3]}', '.[]? | .[]?'),
        [2,3], 'optional object-to-array traversal');
};

subtest 'optional iterator does not swallow other evaluation errors' => sub {
    for my $filter ('1 / 0 | .[]?', '.[]? | .[]') {
        my $input = $filter =~ /^1/ ? 'null' : '[1]';
        my $ok = eval { $jq->run_query($input, $filter); 1 };
        my $err = $@;
        ok(!$ok, "$filter propagates a real upstream/downstream error");
        isa_ok($err, 'JQ::Lite::Error::Evaluation',
            "$filter returns a structured error") unless $ok;
    }
    is_deeply(results('null', 'empty | .[]?'), [],
        'empty upstream causes neither output nor an error');
    is_deeply(results('1', '.[]? | .[]'), [],
        'strict downstream iterator is never executed without input');
};

subtest 'optional literal field suffix preserves valid and empty paths' => sub {
    is_deeply(results('{"a":[1,2]}', '.a[]?'), [1,2],
        'array-valued field expands');
    is_deeply(results('{"a":{"only":3}}', '.a[]?'), [3],
        'object-valued field expands');
    for my $json ('{"a":null}', '{"a":0}', '{"a":"hey"}',
                  '{"a":true}', '{}', 'null') {
        is_deeply(results($json, '.a[]?'), [],
            ".a[]? skips non-iterable or missing field in $json");
    }
    is_deeply(results('{"a":[[1,2]]}', '.a[]? | .[]?'), [1,2],
        'optional path suffix composes with standalone optional iterator');
};

subtest 'optional suffixes of value-returning built-ins and constructors' => sub {
    is_deeply(results('{"b":2,"a":1}', 'keys[]?'), ['a','b'],
        'keys[]? expands sorted keys');
    is_deeply(results('{"b":2,"a":1}', 'keys []?'), ['a','b'],
        'space before optional suffix is accepted');
    is_deeply(results('"red,green"', 'split(",")[]?'), ['red','green'],
        'split() output can be iterated optionally');
    is_deeply(results('null', '[4,5][]?'), [4,5],
        'array constructor optional iterator');
    is_deeply(results('null', '0, [4,5][]?'), [0,4,5],
        'constructor optional suffix stays within its comma branch');
    is_deeply(results('null', '(range(3))[]?'), [],
        'number-valued generator results are dropped by the optional suffix');
};

subtest 'optional recurse children stop at leaves' => sub {
    is_deeply(results('[1,[2]]', 'recurse(.[]?)'),
        [[1,[2]],1,[2],2],
        'explicit optional children match default recurse on mixed arrays');
    is_deeply(results('null', 'recurse(.[]?)'), [undef],
        'optional recurse child iteration on null terminates');
    is_deeply(results('[null,false]', 'recurse(.[]?)'),
        [[undef,JSON::PP::false],undef,JSON::PP::false],
        'optional recurse preserves null/false leaves');
    is_deeply(results('[1,[2]]', 'recurse'),
        [[1,[2]],1,[2],2],
        'default recurse remains unchanged');
};

subtest 'bare strict .[] still rejects scalars' => sub {
    for my $json ('null', '1', 'true', '"abc"') {
        my $ok = eval { $jq->run_query($json, '.[]'); 1 };
        my $err = $@;
        ok(!$ok, "strict .[] continues rejecting $json");
        isa_ok($err, 'JQ::Lite::Error::Evaluation') unless $ok;
    }
};

done_testing;
