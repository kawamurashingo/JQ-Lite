use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Builtin ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;

sub run {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# The numeric wrapper now delegates to the same stream mapper as tonumber
# and to_number; its recursive evaluator and rounding callbacks are unchanged.
my $values = '[1.2,-1.2,2.5,-2.5,"bad",null,true,false,[3.1,-3.1],{"v":1.5}]';
my @cases = (
    ['ceil',  '[2,-1,3,-2,"bad",null,1,0,[4,-3],{"v":1.5}]'],
    ['floor', '[1,-2,2,-3,"bad",null,1,0,[3,-4],{"v":1.5}]'],
    ['round', '[1,-1,3,-3,"bad",null,1,0,[3,-3],{"v":1.5}]'],
);

for my $case (@cases) {
    my ($name, $expected) = @$case;
    for my $spelling ($name, "$name()") {
        is_deeply(run($values, $spelling), [$json->decode($expected)],
            "$spelling preserves array recursion, rounding, booleans and objects");
        is_deeply(run('null', $spelling), [undef],
            "$spelling preserves null scalar");
        is_deeply(run('{}', $spelling), [{}],
            "$spelling preserves object scalar");
        is_deeply(run('"oops"', $spelling), ['oops'],
            "$spelling preserves nonnumeric scalar");
    }
}

is_deeply(run('["1.9","-1.9","bad"]', 'ceil'), [[2,-1,'bad']],
    'ceil retains numeric-looking string conversion');
is_deeply(run('["1.9","-1.9","bad"]', 'floor'), [[1,-2,'bad']],
    'floor retains numeric-looking string conversion');
is_deeply(run('["1.9","-1.9","bad"]', 'round'), [[2,-2,'bad']],
    'round retains numeric-looking string conversion');

for my $name (qw(ceil floor round)) {
    is_deeply(run('[1.2,-1.2]', "empty | $name"), [],
        "$name returns no results for an empty upstream stream");
    my ($matched, $outputs) = JQ::Lite::Builtin->dispatch(
        $jq, $name, [1.2, -1.2, undef]
    );
    ok($matched, "$name retains exact-name registry dispatch");
    is(scalar @$outputs, 3,
        "$name maps once per input and preserves the null slot");
    ok(!defined $outputs->[2], "$name keeps null in direct dispatch");
}

is_deeply(run('[1.2,-1.2,2.5]', '.[] | ceil'), [2,-1,3],
    'ceil preserves ordered multi-value streams');
is_deeply(run('[1.2,-1.2,2.5]', '.[] | floor'), [1,-2,2],
    'floor preserves ordered multi-value streams');
is_deeply(run('[1.2,-1.2,2.5]', '.[] | round'), [1,-1,3],
    'round preserves ordered multi-value streams');

# The pre-existing plain stream wrapper remains shared by the conversion
# functions and must not be changed as a side effect of this refactor.
is_deeply(run('["12","oops",true,false]', 'to_number'),
    [[12,'oops',1,0]], 'to_number retains permissive recursive conversion');
is_deeply(run('"12"', 'tonumber'), [12],
    'tonumber retains its strict numeric-string conversion');
is_deeply(run('"oops"', 'to_number'), ['oops'],
    'to_number still passes invalid strings through');

done_testing;
