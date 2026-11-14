use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Error ();
use JSON::PP ();

my $jq = JQ::Lite->new;

sub results {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

sub assert_iterator_error {
    my ($input, $filter, $type, $description) = @_;
    my $ok = eval { $jq->run_query($input, $filter); 1 };
    my $error = $@;
    ok(!$ok, "$description: query fails");
    if (!$ok) {
        isa_ok($error, 'JQ::Lite::Error::Evaluation',
            "$description: structured runtime error");
        like("$error", qr/Cannot iterate over \Q$type\E\b/,
            "$description: type is reported");
    }
}

subtest 'bare .[] rejects every scalar JSON type' => sub {
    for my $case (
        ['null',    'null',    'JSON null'],
        ['0',       'number',  'numeric zero'],
        ['1',       'number',  'positive number'],
        ['-5',      'number',  'negative number'],
        ['1.5',     'number',  'fractional number'],
        ['true',    'boolean', 'JSON true'],
        ['false',   'boolean', 'JSON false'],
        ['"hello"', 'string',  'nonempty string'],
        ['""',      'string',  'empty string'],
        ['"42"',    'string',  'numeric-looking string'],
    ) {
        my ($input, $type, $description) = @$case;
        assert_iterator_error($input, '.[]', $type, $description);
    }
};

subtest 'arrays and objects still yield their members' => sub {
    is_deeply(results('[]', '.[]'), [], 'empty array gives no results');
    is_deeply(results('{}', '.[]'), [], 'empty object gives no results');
    is_deeply(results('[1,null,false,{"x":2}]', '.[]'),
        [1, undef, JSON::PP::false, {x => 2}],
        'array yields number/null/boolean/object without iterating each');
    is_deeply(results('{"only":42}', '.[]'), [42],
        'object with one member yields its value');
    my $many = results('{"first":1,"second":2}', '.[]');
    is_deeply([sort { $a <=> $b } @$many], [1,2],
        'object members still iterate regardless of hash order');
};

subtest 'pipeline iteration errors only on attempted scalar traversal' => sub {
    is_deeply(results('[[],[1,2]]', '.[] | .[]'), [1,2],
        'nested arrays flatten one level successfully');
    is_deeply(results('[{},{"only":3}]', '.[] | .[]'), [3],
        'empty object plus nonempty object work in pipelines');
    is_deeply(results('null', 'empty | .[]'), [],
        'empty preceding stage produces no input, so no error');
    assert_iterator_error('[[],1]', '.[] | .[]', 'number',
        'pipeline encounters a numeric member');
    assert_iterator_error('[null]', '.[] | .[]', 'null',
        'pipeline encounters a null member');
    assert_iterator_error('[true]', '.[] | .[]', 'boolean',
        'pipeline encounters a boolean member');
    assert_iterator_error('["ab"]', '.[] | .[]', 'string',
        'pipeline cannot iterate string characters');
    assert_iterator_error('1', '. | .[]', 'number',
        'identity pipeline does not suppress iterator errors');
};

subtest 'comma alternatives preserve strict errors and stream order' => sub {
    is_deeply(results('[]', '0, .[]'), [0],
        'empty array branch does not erase previous output');
    is_deeply(results('[1,2]', '0, .[]'), [0,1,2],
        'array branch still emits all members');
    assert_iterator_error('null', '0, .[]', 'null',
        'later invalid iterator branch must still fail');
    assert_iterator_error('1', 'range(2) | .[]', 'number',
        'scalar values from a generator are not implicitly iterable');
};

subtest 'recurse without explicit iteration still visits scalar leaves' => sub {
    is_deeply(results('[1,[2]]', 'recurse'),
        [[1,[2]], 1, [2], 2],
        'default recurse remains valid on mixed arrays');
    assert_iterator_error('[1,[2]]', 'recurse(.[])', 'number',
        'explicit recurse iterator remains strict');
};

done_testing;
