use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Util ();
use JQ::Lite::Error ();

my $jq = JQ::Lite->new;

sub outputs {
    my ($json, $filter) = @_;
    return [$jq->run_query($json, $filter)];
}

is_deeply([JQ::Lite::Util::_v3_iterate_values([1, undef, JSON::PP::false], 0)],
    [1, undef, JSON::PP::false],
    'shared iterator emits array values including null and false');
is_deeply([JQ::Lite::Util::_v3_iterate_values({only => undef}, 0)],
    [undef], 'shared iterator preserves a null object member');
is_deeply([JQ::Lite::Util::_v3_iterate_values([], 0)], [],
    'empty array emits no results');
is_deeply([JQ::Lite::Util::_v3_iterate_values({}, 1)], [],
    'empty object emits no results');
for my $value (undef, 3, 'hi', JSON::PP::false) {
    is_deeply([JQ::Lite::Util::_v3_iterate_values($value, 1)], [],
        'optional shared iterator suppresses non-container');
    my $ok = eval { JQ::Lite::Util::_v3_iterate_values($value, 0); 1 };
    ok(!$ok, 'strict shared iterator raises a scalar error');
    isa_ok($@, 'JQ::Lite::Error::Evaluation');
    like("$@", qr/Cannot iterate over/, 'strict error keeps iterator diagnostic');
}

for my $case (
    ['[1,null,false]', '.[]', [1, undef, JSON::PP::false],
        'standalone array iterator'],
    ['[1,null,false]', '.[]?', [1, undef, JSON::PP::false],
        'standalone optional array iterator'],
    ['{"items":[1,null,false]}', '.items[]',
        [1, undef, JSON::PP::false], 'path array iterator'],
    ['{"items":[1,null,false]}', '.items[]?',
        [1, undef, JSON::PP::false], 'path optional array iterator'],
    ['{"only":3}', '.[]', [3],
        'standalone object iterator'],
    ['{"items":{"only":3}}', '.items[]', [3],
        'path object iterator'],
    ['{"only":null}', '.[]?', [undef],
        'standalone object null is emitted, not skipped'],
    ['{"items":{"only":null}}', '.items[]?', [undef],
        'path object null is emitted, not skipped'],
    ['{"items":[]}', '.items[]', [],
        'empty array path emits no stream'],
    ['{"items":[]}', '.items[]?', [],
        'optional empty array path emits no stream'],
    ['{"items":3}', '.items[]?', [],
        'optional path suppresses scalar iteration'],
    ['3', '.[]?', [], 'standalone optional iterator suppresses scalar'],
    ['null', '.[]?', [], 'standalone optional iterator suppresses null'],
    ['[{"x":1},3,{"x":2}]', '.[] | .x?', [1,2],
        'optional field drops invalid input after iterator'],
    ['{"items":[{"x":1},3,{"x":2}]}', '.items[].x?', [1,2],
        'optional field drops invalid path-stream elements'],
    ['[1,2]', '0, .[]?', [0,1,2],
        'comma branch retains input before optional iterator'],
) {
    my ($input, $filter, $expected, $label) = @$case;
    is_deeply(outputs($input, $filter), $expected, $label);
}

for my $case (
    ['3', '.[]', 'strict standalone scalar iterator'],
    ['null', '.[]', 'strict standalone null iterator'],
    ['{"items":3}', '.items[]', 'strict scalar path iterator'],
    ['{"items":null}', '.items[]', 'strict null path iterator'],
) {
    my ($input, $filter, $label) = @$case;
    my $ok = eval { $jq->run_query($input, $filter); 1 };
    ok(!$ok, "$label fails");
    isa_ok($@, 'JQ::Lite::Error::Evaluation');
    like("$@", qr/Cannot iterate over/, "$label preserves error text");
}

done_testing;
