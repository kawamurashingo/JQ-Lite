use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;

# Direct checks preserve the v2 range parser's empty slots, JSON decoding,
# quoted semicolons and first comma-separated value per argument.
my @parse = (
    [ '4', [4], 'single argument' ],
    [ ' 1 ; 7 ; 2 ', [1, 7, 2], 'whitespace and positive step' ],
    [ '9; 1; -3', [9, 1, -3], 'descending step' ],
    [ '; 4', [4], 'empty leading slot ignored' ],
    [ '1 ;; 5', [1, 5], 'empty intermediate slot ignored' ],
    [ '1; 5; ', [1, 5], 'empty trailing slot ignored' ],
    [ q{"a;b"; 5}, ['a;b', 5], 'quoted semicolon preserved' ],
    [ q{"a\";b"; 5}, ['a";b', 5], 'escaped quoted semicolon preserved' ],
    [ q{'a;b'; 5}, [q{'a;b'}, 5], 'single-quoted semicolon preserved' ],
    [ '4, 9; 10', [4, 10], 'only first comma-decoded element retained' ],
);
for my $case (@parse) {
    my ($raw, $expected, $name) = @$case;
    is_deeply([JQ::Lite::Util::_parse_range_arguments($raw)], $expected, $name);
}
is_deeply([JQ::Lite::Util::_parse_range_arguments(undef)], [],
    'undefined raw argument list stays empty');
is_deeply([JQ::Lite::Util::_parse_range_arguments('  ')], [],
    'whitespace-only argument list stays empty');

sub results {
    my ($json, $filter) = @_;
    return [$jq->run_query($json, $filter)];
}

is_deeply(results('null', 'range(4)'), [0,1,2,3],
    'range() emits a single-bound ordered stream');
is_deeply(results('null', 'range(1;6)'), [1,2,3,4,5],
    'range() emits a two-bound ordered stream');
is_deeply(results('null', 'range(1;8;3)'), [1,4,7],
    'range() uses a positive step');
is_deeply(results('null', 'range(7;0;-2)'), [7,5,3,1],
    'range() uses a negative step');
is_deeply(results('null', 'range(0;4;0)'), [],
    'zero step emits an empty stream');
is_deeply(results('null', 'range(5;5)'), [],
    'equal bounds emit no values');
is_deeply(results('null', 'range(2; 5) | .'), [2,3,4],
    'pipeline preserves range output order');
is_deeply(results('null', 'range(2;4), range(1)'), [2,3,0],
    'comma alternatives preserve range stream order');

for my $bad (
    [ 'range("1";5)', qr/range\(\): bounds must be numeric/, 'quoted numeric start' ],
    [ 'range(1; "a;b")', qr/range\(\): bounds must be numeric/, 'quoted semicolon bound' ],
    [ 'range(1;5;"bad")', qr/range\(\): step must be numeric/, 'bad step' ],
) {
    my ($filter, $error_pattern, $name) = @$bad;
    my $ok = eval { $jq->run_query('null', $filter); 1 };
    ok(!$ok, "$name raises a range error");
    like("$@", $error_pattern, "$name keeps its error category");
}

done_testing;
