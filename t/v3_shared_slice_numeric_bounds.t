use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;

sub results {
    my ($input, $filter) = @_;
    return [$jq->run_query($input, $filter)];
}

my $json = '{"numbers":[10,20,30,40,50]}';
my @good = (
    [ '.numbers | slice(1, 2)', [[20,30]], 'v2 length-based slice' ],
    [ '.numbers | slice(-2, 1)', [[40]], 'v2 negative start' ],
    [ '.numbers | slice(-10, 2)', [[10,20]], 'v2 clamped start' ],
    [ '.numbers | slice(2, 0)', [[]], 'v2 zero length' ],
    [ '.numbers | slice(8, 2)', [[]], 'v2 beyond-end start' ],
    [ '.numbers[1:3]', [[20,30]], 'jq end-exclusive bracket slice' ],
    [ '.numbers[-2:-1]', [[40]], 'negative bracket start/end' ],
    [ '.numbers[2:]', [[30,40,50]], 'bracket omitted end' ],
    [ '.numbers[:2]', [[10,20]], 'bracket omitted start' ],
    [ '.numbers[2:2]', [[]], 'bracket equal bounds' ],
    [ '.numbers[-8:2]', [[10,20]], 'bracket clamped negative start' ],
    [ '.numbers[9:12]', [[]], 'bracket out-of-range start' ],
);
for my $case (@good) {
    my ($filter, $expected, $name) = @$case;
    is_deeply(results($json, $filter), $expected, $name);
}

for my $case (
    [ '.numbers | slice("1", 2)', qr/slice\(\): start must be numeric/, 'length-form string start' ],
    [ '.numbers | slice(1, "2")', qr/slice\(\): length must be numeric/, 'length-form string length' ],
    [ '.numbers["1":2]', qr/slice\(\): start must be numeric/, 'bracket string start' ],
    [ '.numbers[1:"2"]', qr/slice\(\): length must be numeric/, 'bracket string end' ],
) {
    my ($filter, $pattern, $name) = @$case;
    my $ok = eval { $jq->run_query($json, $filter); 1 };
    ok(!$ok, "$name raises a runtime error");
    like("$@", $pattern, "$name retains the existing error category");
}

is_deeply([JQ::Lite::Util::_apply_slice([10,20], 9, 'bad')], [[]],
    'v2 length-form returns empty before validating an unused length');
my $valid = eval { JQ::Lite::Util::_apply_bracket_slice([10,20], 9, 'bad'); 1 };
ok(!$valid, 'bracket slice validates end despite out-of-range start');
like("$@", qr/slice\(\): length must be numeric/,
    'bracket invalid end uses the existing length error label');
is(JQ::Lite::Util::_apply_slice(7, 'bad', 'bad'), 7,
    'v2 slice leaves non-array values unchanged before bounds validation');
is(JQ::Lite::Util::_apply_bracket_slice(7, 'bad', 'bad'), 7,
    'bracket helper leaves non-array values unchanged');
ok(!defined JQ::Lite::Util::_apply_slice(undef, 'bad'),
    'undefined input still produces undefined output without a bound error');

done_testing;
