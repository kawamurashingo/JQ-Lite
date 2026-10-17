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

# The three filters share stream iteration, but must retain their exact
# array/object/scalar categories and original values, including booleans.
my $mixed = '[null,false,true,0,"0",[],[1],[2,3],{},{"x":1},1.5,"text"]';
my @cases = (
    [arrays  => '[[],[1],[2,3]]'],
    [objects => '[{},{"x":1}]'],
    [scalars => '[null,false,true,0,"0",1.5,"text"]'],
);

for my $case (@cases) {
    my ($name, $expected) = @$case;
    for my $spelling ($name, "$name()") {
        is_deeply(
            run($mixed, ".[] | $spelling"), $json->decode($expected),
            "$spelling filters mixed streams without reordering or coercing",
        );
        is_deeply(
            run('null', "empty | $spelling"), [],
            "$spelling preserves an empty upstream stream",
        );
    }
}

for my $case (
    ['[]', arrays  => '[[]]'],
    ['{}', objects => '[{}]'],
    ['0',  scalars => '[0]'],
    ['"0"', scalars => '["0"]'],
    ['null', scalars => '[null]'],
    ['false', scalars => '[false]'],
    ['true', scalars => '[true]'],
    ['[0]', objects => '[]'],
    ['{"a":1}', arrays => '[]'],
    ['null', arrays => '[]'],
    ['null', objects => '[]'],
    ['[]', scalars => '[]'],
    ['{}', scalars => '[]'],
) {
    my ($input, $name, $expected) = @$case;
    is_deeply(run($input, $name), $json->decode($expected),
        "$name retains type-filter behavior for $input");
}

my @inputs = (
    undef,
    JSON::PP::false,
    JSON::PP::true,
    0,
    '0',
    [],
    [1],
    {},
    { x => 1 },
);
for my $spec (
    [arrays  => [5,6]],
    [objects => [7,8]],
    [scalars => [0,1,2,3,4]],
) {
    my ($name, $indices) = @$spec;
    my @expected = @inputs[@$indices];
    my ($matched, $outputs) = JQ::Lite::Builtin->dispatch(
        $jq, $name, \@inputs
    );
    ok($matched, "$name is registered");
    is_deeply($outputs, \@expected,
        "$name passes through exact values, null and boolean types");
    my ($alias_matched, $alias_outputs) = JQ::Lite::Builtin->dispatch(
        $jq, "$name()", \@inputs
    );
    ok($alias_matched, "$name() remains registered");
    is_deeply($alias_outputs, \@expected,
        "$name() selects the same ordered inputs");
    my ($empty_matched, $empty_outputs) = JQ::Lite::Builtin->dispatch(
        $jq, $name, []
    );
    ok($empty_matched, "$name handles an empty direct stream");
    is_deeply($empty_outputs, [],
        "$name does not invent values on empty streams");
}

my %registered = map { $_ => 1 } JQ::Lite::Builtin->registered_names;
for my $name (qw(arrays objects scalars)) {
    ok($registered{$name}, "$name retains bare registry spelling");
    ok($registered{"$name()"}, "$name retains parenthesized registry spelling");
}

done_testing;
