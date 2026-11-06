use strict;
use warnings;
use Test::More;
use JSON::PP ();
use Scalar::Util qw(refaddr);
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
    is_deeply(run($values, $name), [$json->decode($expected)],
        "$name preserves array recursion, rounding, booleans and objects");
    is_deeply(run('null', $name), [undef],
        "$name preserves null scalar");
    is_deeply(run('{}', $name), [{}],
        "$name preserves object scalar");
    is_deeply(run('"oops"', $name), ['oops'],
        "$name preserves nonnumeric scalar");
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
    # The exact-name aliases are registered, but public ceil()/floor()/round()
    # expressions use their separate strict arithmetic evaluator.
    my ($alias_matched, $alias_outputs) = JQ::Lite::Builtin->dispatch(
        $jq, "$name()", [1.2]
    );
    ok($alias_matched, "$name() retains its direct registry alias");
    is(scalar @$alias_outputs, 1, "$name() retains one mapped result");
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


# The argument-taking clamp handler now uses the same unary stream adapter
# as the other numeric builtins. Bounds are parsed and captured independently
# on each invocation, and all v2 numeric/boolean/null behavior remains.
my @clamp_stream_cases = (
    ['[-2,0,12]', 'clamp(0,10)', '[0,0,10]', 'both bounds'],
    ['[-2,0,12]', 'clamp(10,0)', '[0,0,10]', 'reversed bounds'],
    ['[-2,0,12]', 'clamp(5)', '[5,5,12]', 'minimum only'],
    ['[-2,0,12]', 'clamp(null,5)', '[-2,0,5]', 'maximum only'],
    ['[-2,0,12]', 'clamp(null,null)', '[-2,0,12]',
        'two missing bounds'],
    ['[-2,0,12]', 'clamp()', '[-2,0,12]', 'no arguments'],
    ['[-2,0,12]', 'clamp("2","8")', '[2,2,8]',
        'numeric-string bounds'],
    ['[-2,0,12]', 'clamp("bad",8)', '[-2,0,8]',
        'nonnumeric lower bound ignored'],
    ['[-2,0,12]', 'clamp(true,false)', '[0,0,1]',
        'boolean bounds normalized and swapped'],
    ['[-2,0,12]', 'clamp(0,2,999)', '[0,0,2]',
        'extra arguments ignored'],
    ['["-5","3","11","oops"]', 'clamp(0,10)',
        '[0,3,10,"oops"]', 'numeric-looking and invalid strings'],
    ['[null,true,false,{"x":12},[2,30],[]]', 'clamp(3,8)',
        '[null,3,3,{"x":12},[3,8],[]]',
        'null, booleans, opaque objects and nested arrays'],
    ['[-2,0,12]', 'clamp(0,10)', '[0,0,10]',
        'first argument set after other invocations'],
);
for my $case (@clamp_stream_cases) {
    my ($input, $filter, $expected, $label) = @$case;
    my $values = $json->decode($input);
    my $before = $json->encode($values);
    my $wanted = $json->decode($expected);
    my ($matched, $outputs) =
        JQ::Lite::Builtin->dispatch($jq, $filter, $values);
    ok($matched, "$filter remains registered: $label");
    is_deeply($outputs, $wanted, "$filter direct stream: $label");
    is_deeply(run($input, ".[] | $filter"), $wanted,
        "$filter public ordered stream: $label");
    is($json->encode($values), $before,
        "$filter preserves caller's input values: $label");
}

my $opaque = { inner => [1,2] };
my $bool = JSON::PP::true;
my @clamp_inputs = ($opaque, undef, $bool, [[0,9]], 'oops');
my ($clamp_found, $clamp_outputs) = JQ::Lite::Builtin->dispatch(
    $jq, 'clamp(2,5)', \@clamp_inputs
);
ok($clamp_found, 'clamp registered for mixed direct streams');
is_deeply($clamp_outputs,
    [$opaque,undef,2,[[2,5]],'oops'],
    'clamp retains one output per input and nested array structure');
is(refaddr($clamp_outputs->[0]), refaddr($opaque),
    'clamp passes opaque objects through without cloning');
is_deeply(\@clamp_inputs, [$opaque,undef,$bool,[[0,9]],'oops'],
    'clamp does not modify caller stream');

my ($empty_found, $empty_outputs) =
    JQ::Lite::Builtin->dispatch($jq, 'clamp(2,5)', []);
ok($empty_found, 'clamp accepts an empty direct stream');
is_deeply($empty_outputs, [], 'clamp emits no values for empty stream');
is_deeply(run('null', 'empty | clamp(2,5)'), [],
    'clamp does not revive empty public streams');

my ($invalid_found) =
    JQ::Lite::Builtin->dispatch($jq, 'clamp', [1]);
ok(!$invalid_found, 'bare clamp without parentheses remains unregistered');

done_testing;
