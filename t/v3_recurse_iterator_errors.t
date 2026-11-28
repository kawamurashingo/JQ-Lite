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

subtest 'explicit recurse(.[]) rejects scalar and null roots' => sub {
    for my $case (
        ['null',   'null'],
        ['1',      'number'],
        ['true',   'boolean'],
        ['false',  'boolean'],
        ['"foo"',  'string'],
    ) {
        my ($json, $type) = @$case;
        my $ok = eval { $jq->run_query($json, 'recurse(.[])'); 1 };
        my $error = $@;
        ok(!$ok, "$json: explicit iteration fails");
        if (!$ok) {
            isa_ok($error, 'JQ::Lite::Error::Evaluation',
                "$json: structured evaluation error");
            like("$error", qr/Cannot iterate over \Q$type\E/,
                "$json: reported failing type");
        }
    }
};

subtest 'explicit iterator fails after reaching scalar descendants' => sub {
    for my $case (
        ['[1,[2]]', 'number'],
        ['[null]', 'null'],
        ['[true]', 'boolean'],
        ['["a"]', 'string'],
        ['{"x":1}', 'number'],
        ['{"x":null}', 'null'],
    ) {
        my ($json, $type) = @$case;
        my $ok = eval { $jq->run_query($json, 'recurse(.[])'); 1 };
        my $error = $@;
        ok(!$ok, "$json: scalar descendant rejected");
        if (!$ok) {
            isa_ok($error, 'JQ::Lite::Error::Evaluation',
                "$json: structured evaluation error");
            like("$error", qr/Cannot iterate over \Q$type\E/,
                "$json: error identifies descendant type");
        }
    }
};

subtest 'explicit iterator is still valid on all-container trees' => sub {
    is_deeply(results('[]', 'recurse(.[])'),
        [[]], 'empty array succeeds');
    is_deeply(results('{}', 'recurse(.[])'),
        [{}], 'empty object succeeds');
    is_deeply(results('[[],{}]', 'recurse(.[])'),
        [[[],{}], [], {}], 'empty container children succeed');
    is_deeply(results('[[[]]]', 'recurse(.[])'),
        [[[[]]], [[]], []], 'deep container-only tree succeeds');
    is_deeply(results('{"x":[]}', 'recurse(.[])'),
        [{x => []}, []], 'object containing empty array succeeds');
};

subtest 'recurse child pipeline still propagates explicit iterator errors' => sub {
    for my $case (
        ['1', 'recurse(.[] | .)', 'number'],
        ['null', 'recurse(.[] | empty)', 'null'],
        ['[1]', 'recurse(.[] | .)', 'number'],
    ) {
        my ($json, $filter, $type) = @$case;
        my $ok = eval { $jq->run_query($json, $filter); 1 };
        my $error = $@;
        ok(!$ok, "$filter on $json fails");
        if (!$ok) {
            isa_ok($error, 'JQ::Lite::Error::Evaluation',
                'child pipeline preserves structured evaluation error');
            like("$error", qr/Cannot iterate over \Q$type\E/,
                'child pipeline identifies invalid iterator input');
        }
    }
};

subtest 'plain recurse and optional children still terminate safely' => sub {
    is_deeply(results('null', 'recurse'),
        [undef], 'default recurse on null is valid');
    is_deeply(results('1', 'recurse'),
        [1], 'default recurse on a number is valid');
    is_deeply(results('"foo"', 'recurse'),
        ['foo'], 'default recurse on a string is valid');
    is_deeply(results('[1,[2]]', 'recurse'),
        [[1,[2]], 1, [2], 2], 'default recurse traverses scalar leaves');
    is_deeply(results('{"children":[{"name":"kid"}]}',
            'recurse(.children[]?) | .name'),
        [undef, 'kid'], 'optional children query remains non-throwing');
};

done_testing;
