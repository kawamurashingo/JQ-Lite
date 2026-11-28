use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq = JQ::Lite->new;
sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

subtest 'three nested iterators keep completed results' => sub {
    my $mixed = '[[[1]],[[2],3],[[4]]]';
    is_deeply(results('[[[1],[2]],[[3]]]', 'try .[][][]'), [1,2,3],
        'successful triple-root iterator emits in depth-first order');
    is_deeply(results($mixed, 'try .[][][] catch 42'), [1,2,42],
        'failed inner iterator stops later members but keeps earlier output');
    is_deeply(results($mixed, 'try .[][][]'), [1,2],
        'unhandled nested failure drops only the error');
    is_deeply(results($mixed, 'try .[][][] catch null'), [1,2,undef],
        'explicit null appended after successful output');
    is_deeply(results($mixed, 'try .[][][] catch empty'), [1,2],
        'explicit empty preserves earlier values');
    is_deeply(results($mixed, 'try .[][][] catch type'), [1,2,'string'],
        'catch still receives the error string');
    is_deeply(results('[[[1]],3,[[2]]]', 'try .[][][] catch 42'),
        [1,42], 'an intermediate strict iterator failure is caught');
    is_deeply(results('[[[null,false]],3]', 'try .[][][] catch 42'),
        [undef, JSON::PP::false,42],
        'completed JSON null and false remain real outputs');
};

subtest 'optional stages and pipelines keep their own boundaries' => sub {
    is_deeply(results('[[[1]],[3],[[2]]]', 'try .[][][]? catch 42'),
        [1,2], 'optional deepest iterator skips noniterable members');
    is_deeply(results('[[[1]],3,[[2]]]', 'try .[][]?[] catch 42'),
        [1,2], 'optional middle iterator skips scalar member');
    is_deeply(results('3', 'try .[]?[][] catch 42'), [],
        'optional outer iterator suppresses scalar-root errors');
    is_deeply(results('[[[1]],[[2],3],[[4]]]',
        'try (.[][][] | . + 10) catch 42'),
        [11,12,42], 'downstream tail retains successful earlier members');
    is_deeply(results('[[[1]],[[2],3],[[4]]]',
        'try (.[][][], 99) catch 42'), [1,2,42],
        'error stops later comma alternatives inside try');
    is_deeply(results('[[[1]],[[2],3],[[4]]]',
        '0, try .[][][], 9'), [0,1,2,9],
        'comma branches outside try continue after a caught error');
};

subtest 'named-field and four-level iterator chains' => sub {
    is_deeply(results('{"items":[[[1]],[[2]]]}', 'try .items[][][]'),
        [1,2], 'named triple iterator emits all members');
    is_deeply(results('{"items":[[[1]],[[2],3],[[4]]]}',
        'try .items[][][] catch 42'), [1,2,42],
        'named chain retains prior members before inner failure');
    is_deeply(results('{"items":[[[1]],[[2],3],[[4]]]}',
        'try .items[][][]'), [1,2],
        'unhandled named-chain error leaves completed values');
    is_deeply(results('{"items":[[[1]],[3],[[2]]]}',
        'try .items[][][]? catch 42'), [1,2],
        'named optional deepest step skips non-iterable value');
    is_deeply(results('{"items":[[[1]],3,[[2]]]}',
        'try .items[][]?[] catch 42'), [1,2],
        'named optional middle step skips scalar');
    is_deeply(results('{"items":null}',
        'try .items[]?[][] catch 42'), [],
        'optional named first iterator skips null');
    is_deeply(results('[[[[1]]],[[[2]]]]',
        'try .[][][][]'), [1,2],
        'four-level root iterator uses the same sequential traversal');
    is_deeply(results('{"items":[[[[1]]],[[[2]]]]}',
        'try .items[][][][]'), [1,2],
        'four-level named iterator uses the same visitor');
    is_deeply(results('[[[[1]]],[[2]],[[[3]]]]',
        'try .[][][][] catch 42'), [1,42],
        'fourth-level strict error retains earlier values');
};

subtest 'two-level and array-constructor controls' => sub {
    is_deeply(results('[[1],[2]]', 'try .[][]'), [1,2],
        'two-level iterator remains unchanged');
    is_deeply(results('null', 'try []'), [[]],
        'empty array constructor remains unchanged');
    is_deeply(results('[1,2]', 'try .[]'), [1,2],
        'bare one-level iterator remains unchanged');
};

done_testing;
