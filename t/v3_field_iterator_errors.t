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

sub evaluation_error {
    my ($input, $filter, $fragment, $description) = @_;
    my $ok = eval { $jq->run_query($input, $filter); 1 };
    my $error = $@;
    ok(!$ok, "$description: query fails");
    if (!$ok) {
        isa_ok($error, 'JQ::Lite::Error::Evaluation',
            "$description: structured evaluation error");
        like("$error", qr/\Q$fragment\E/,
            "$description: correct failing operation");
    }
}

subtest 'non-optional named-field iterator rejects invalid final values' => sub {
    for my $case (
        ['{}',             'null',    'missing key'],
        ['{"a":null}',     'null',    'explicit null'],
        ['{"a":0}',        'number',  'number zero'],
        ['{"a":2}',        'number',  'positive number'],
        ['{"a":true}',     'boolean', 'boolean true'],
        ['{"a":false}',    'boolean', 'boolean false'],
        ['{"a":"abc"}',    'string',  'nonempty string'],
        ['{"a":""}',       'string',  'empty string'],
    ) {
        my ($input, $type, $description) = @$case;
        evaluation_error($input, '.a[]', "Cannot iterate over $type",
            $description);
    }
    evaluation_error('null', '.a[]', 'Cannot iterate over null',
        'null root produces a null field');
};

subtest 'optional final iterator drops null and scalar field values' => sub {
    for my $input (
        '{}', '{"a":null}', '{"a":0}', '{"a":2}', '{"a":true}',
        '{"a":false}', '{"a":"abc"}', '{"a":""}', 'null'
    ) {
        is_deeply(results($input, '.a[]?'), [],
            "optional field iterator drops non-container value in $input");
    }
};

subtest 'valid array and object fields preserve each emitted value' => sub {
    is_deeply(results('{"a":[]}', '.a[]'), [],
        'empty array has no outputs');
    is_deeply(results('{"a":{}}', '.a[]'), [],
        'empty object has no outputs');
    is_deeply(results('{"a":[1,null,false,{"x":2}]}', '.a[]'),
        [1, undef, JSON::PP::false, {x => 2}],
        'non-optional iterator preserves all member types');
    is_deeply(results('{"a":[1,null,false]}', '.a[]?'),
        [1, undef, JSON::PP::false],
        'optional iterator also preserves emitted null and false members');
    is_deeply(results('{"a":{"only":42}}', '.a[]'),
        [42], 'object field produces its value');
    is_deeply(results('{"a":{"only":42}}', '.a[]?'),
        [42], 'optional object field produces its value');
    is_deeply(results('{"a":[[1,2],[]]}', '.a[] | .[]'),
        [1,2], 'literal path iterator composes with strict standalone iterator');
    is_deeply(results('{"a":[[1,2],null]}', '.a[] | .[]?'),
        [1,2], 'optional downstream iterator skips null array member');
};

subtest 'nested simple field lookups have strict final iteration' => sub {
    is_deeply(results('{"a":{"b":[1,null,2]}}', '.a.b[]'),
        [1,undef,2], 'nested strict iterator emits array members');
    is_deeply(results('{"a":{"b":[1,null,2]}}', '.a.b[]?'),
        [1,undef,2], 'nested optional iterator emits array members');
    is_deeply(results('{"a":{"b":{"only":3}}}', '.a.b[]?'),
        [3], 'nested optional iterator emits object values');
    for my $input ('{}', '{"a":{}}', '{"a":null}', '{"a":{"b":null}}',
                   '{"a":{"b":0}}', '{"a":{"b":"x"}}') {
        is_deeply(results($input, '.a.b[]?'), [],
            "nested optional iterator omits missing/scalar final value in $input");
    }
    evaluation_error('{"a":{}}', '.a.b[]', 'Cannot iterate over null',
        'strict nested iterator on missing final field');
    evaluation_error('{"a":null}', '.a.b[]', 'Cannot iterate over null',
        'strict nested iterator through null');
    evaluation_error('{"a":{"b":5}}', '.a.b[]', 'Cannot iterate over number',
        'strict nested iterator on number');
};

subtest 'optional iteration does not suppress a failed prefix field lookup' => sub {
    for my $case (
        ['1', '.a[]?', 'Cannot index number', 'numeric root'],
        ['true', '.a[]?', 'Cannot index boolean', 'boolean root'],
        ['"abc"', '.a[]?', 'Cannot index string', 'string root'],
        ['[]', '.a[]?', 'Cannot index array', 'array root'],
        ['{"a":1}', '.a.b[]?', 'Cannot index number', 'numeric intermediate'],
        ['{"a":true}', '.a.b[]?', 'Cannot index boolean', 'boolean intermediate'],
        ['{"a":"abc"}', '.a.b[]?', 'Cannot index string', 'string intermediate'],
        ['{"a":[]}', '.a.b[]?', 'Cannot index array', 'array intermediate'],
    ) {
        my ($input, $filter, $fragment, $description) = @$case;
        evaluation_error($input, $filter, $fragment, $description);
    }
    evaluation_error('1', '.a[]', 'Cannot index number',
        'strict field iterator also rejects invalid prefix');
};

subtest 'pipeline ordering and empty upstream remain unchanged' => sub {
    is_deeply(results('null', 'empty | .a[]'), [],
        'no input means strict path cannot raise');
    is_deeply(results('null', 'empty | .a[]?'), [],
        'no input means optional path remains empty');
    is_deeply(results('{"a":[1,2]}', '0, .a[]'),
        [0,1,2], 'comma branch retains first output before valid iteration');
    evaluation_error('{}', '0, .a[]', 'Cannot iterate over null',
        'later strict comma branch is evaluated and errors');
    is_deeply(results('{}', '0, .a[]?'), [0],
        'later optional comma branch is safely skipped');
    is_deeply(results('{"a":[{"b":[2]},{"b":[3]}]}',
            '.a[] | .b[]'), [2,3],
        'two named-field iterator pipeline stages work');
};

done_testing;
