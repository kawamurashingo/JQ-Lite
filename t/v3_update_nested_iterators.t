use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Error ();

my $jq = JQ::Lite->new;

sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

subtest 'two or three nested array iterators' => sub {
    is_deeply(results('{"groups":[[1,2],[3,4]]}', '.groups[][] |= . + 1'),
        [{groups => [[2,3],[4,5]]}], 'two levels of arrays');
    is_deeply(results('[[1,2],[3,4]]', '.[][] |= . + 1'),
        [[[2,3],[4,5]]], 'root arrays nested twice');
    is_deeply(results('[[[1],[2,3]],[[4]]]', '.[][][] |= . + 1'),
        [[[[2],[3,4]],[[5]]]], 'three nested array iterators');
    is_deeply(results('{"a":[[[1,2]],[[3,4]]]}', '.a[0][][] |= . + 1'),
        [{a => [[[2,3]],[[3,4]]]}], 'literal array index before two iterators');
    is_deeply(results('{"a":[[[1,2],[3,4]],[[5,6]]]}', '.a[][][0] |= . + 1'),
        [{a => [[[2,2],[4,4]],[[6,6]]]}],
        'literal array index after two iterators');
};

subtest 'mix array and object iterators without stringifying object keys' => sub {
    is_deeply(results('[{"a":1,"b":2},{"c":3}]', '.[][] |= . + 1'),
        [[{a => 2, b => 3},{c => 4}]], 'array of objects');
    is_deeply(results('{"a":{"x":[1,2],"y":[3,4]}}', '.a[][] |= . + 1'),
        [{a => {x => [2,3], y => [4,5]}}], 'object of arrays');
    is_deeply(results('{"groups":{"x":{"p":1},"y":{"q":2}}}', '.groups[][] |= . + 1'),
        [{groups => {x => {p => 2}, y => {q => 3}}}], 'object of objects');
    is_deeply(results('{"groups":[{"items":[1,2]},{"items":[3]}]}',
            '.groups[].items[] |= . + 1'),
        [{groups => [{items => [2,3]}, {items => [4]}]}],
        'object key between iterator steps');
    is_deeply(results('{"groups":{"a.b":{"a-b":1,"":2},"":{"space key":3}}}',
            '.groups[][] |= . + 1'),
        [{groups => {'a.b' => {'a-b' => 2, '' => 3},
                     '' => {'space key' => 4}}}],
        'special keys at both object iterator levels');
    is_deeply(results('{"groups":{"a.b":[{"n":1},{"n":2}],"":[{"n":3}]}}',
            '.groups[][].n |= . + 1'),
        [{groups => {'a.b' => [{n => 2}, {n => 3}], '' => [{n => 4}]}}],
        'object to array and nested scalar field');
};

subtest 'zero-result updates delete only innermost targets' => sub {
    is_deeply(results('[[1,2],[3,4]]', '.[][] |= empty'),
        [[[],[]]], 'outer array members are retained');
    is_deeply(results('{"a":{"x":[1,2],"y":[3,4]}}', '.a[][] |= empty'),
        [{a => {x => [], y => []}}], 'outer object keys are retained');
    is_deeply(results('{"groups":[[1,2],[3,4]]}', '.groups[][] |= select(. > 2)'),
        [{groups => [[],[3,4]]}], 'conditional deletion keeps original structure');
    is_deeply(results('{"groups":[{"items":[1,2]},{"items":[3]}]}',
            '.groups[].items[] |= empty'),
        [{groups => [{items => []}, {items => []}]}],
        'multiple array iterators with field in between');
    is_deeply(results('{"a":[[1,2],[3,4]]}', '.a[][] |= (empty, 9)'),
        [{a => [[9,9],[9,9]]}], 'first RHS value after empty branch');
    is_deeply(results('{"a":[[1,2],[3,4]]}', '.a[][] |= null'),
        [{a => [[undef,undef],[undef,undef]]}],
        'JSON null replaces selected leaves rather than deleting them');
};

subtest 'empty child containers retain one unchanged root' => sub {
    is_deeply(results('{"a":[]}', '.a[][] |= . + 1'),
        [{a => []}], 'empty outer array yields unchanged root');
    is_deeply(results('{"a":[[],[1]]}', '.a[][] |= . + 1'),
        [{a => [[],[2]]}], 'empty inner array is a no-op');
    is_deeply(results('{"groups":{"a":{},"b":{"x":1}}}',
            '.groups[][] |= . + 1'),
        [{groups => {a => {}, b => {x => 2}}}],
        'empty inner object is a no-op');
};

subtest 'non-container children produce a structured evaluation error' => sub {
    for my $case (
        ['{"groups":[[1],null]}', '.groups[][] |= . + 1',
            'null inner container'],
        ['{"groups":[1,[2]]}', '.groups[][] |= . + 1',
            'number inner container'],
        ['{"groups":{"a":1}}', '.groups[][] |= . + 1',
            'number inner object member'],
    ) {
        my ($input, $filter, $label) = @$case;
        my $ok = eval { $jq->run_query($input, $filter); 1 };
        my $error = $@;
        ok(!$ok, "$label is rejected");
        isa_ok($error, 'JQ::Lite::Error::Evaluation', "$label error category")
            unless $ok;
    }
};

done_testing();
