use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;
my $array = '[1,2,3,4]';

sub result {
    my ($input, $query) = @_;
    return [ $jq->run_query($input, $query) ];
}

my @examples = (
    ['limit',  [1,2],          [],            [1,2,3,4]],
    ['drop',   [3,4],          [1,2,3,4],     []],
    ['tail',   [3,4],          [],            [1,2,3,4]],
    ['chunks', [[1,2],[3,4]],  [[1],[2],[3],[4]], [[1,2,3,4]]],
);
for my $row (@examples) {
    my ($name, $two, $zero, $large) = @$row;
    is_deeply(result($array, "$name(2)"),  [$two],
        "$name(2) preserves existing array behavior");
    is_deeply(result($array, "$name(0)"),  [$zero],
        "$name(0) preserves existing zero-count behavior");
    is_deeply(result($array, "$name(20)"), [$large],
        "$name(20) preserves count exceeding array length");
    is_deeply(result($array, "$name( 02 )"), [$two],
        "$name accepts whitespace and leading zeros");
    is_deeply(result('[]', "$name(2)"), [[]],
        "$name preserves empty array result");
    is_deeply(result('{"k":1}', "$name(2)"), [{ k => 1 }],
        "$name preserves v2 object passthrough");
    is_deeply(result('null', "$name(2)"), [undef],
        "$name preserves v2 null passthrough");
}

my @invalid = ('-1', '+2', '2.5', '2e1', 'abc', '  ');
for my $name (qw(limit drop tail chunks)) {
    my $noun = $name eq 'chunks' ? 'size' : 'count';
    for my $bad (@invalid) {
        # A whitespace-only argument is accepted by the matcher but
        # rejected by the same validation as the other invalid arguments.
        my $filter = "$name($bad)";
        my $ok = eval { $jq->run_query($array, $filter); 1 };
        ok(!$ok, "$name rejects invalid argument [$bad]");
        like("$@", qr/\Q$name(): $noun must be a non-negative integer\E/,
            "$name preserves function-specific error for [$bad]");
    }
    my $ok = eval { $jq->run_query('null', "$name(-1)"); 1 };
    ok(!$ok, "$name validates before inspecting non-array input");
    like("$@", qr/\Q$name(): $noun must be a non-negative integer\E/,
        "$name keeps the exact non-array validation error");
}

is_deeply(result('[[1,2,3],[4,5,6]]', '.[] | limit(2)'), [[1,2],[4,5]],
    'limit keeps iterator output order');
is_deeply(result('[[1,2,3],[4,5,6]]', '.[] | drop(1)'), [[2,3],[5,6]],
    'drop keeps iterator output order');
is_deeply(result('[[1,2,3],[4,5,6]]', '.[] | tail(2)'), [[2,3],[5,6]],
    'tail keeps iterator output order');
is_deeply(result('[[1,2,3],[4,5,6]]', '.[] | chunks(2)'),
    [[[1,2],[3]],[[4,5],[6]]], 'chunks keeps iterator output order');

done_testing();
