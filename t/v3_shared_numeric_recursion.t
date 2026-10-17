use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref->canonical;

# Both wrappers now use the same recursion already shared by
# ceil/floor/round. Protect v2's coercion, passthrough and stream shapes,
# not an expanded jq numeric type policy.
my @cases = (
    ['null',       'null',     'null',       'null root'],
    ['true',       '1',        '1',          'boolean true'],
    ['false',      '0',        '0',          'boolean false'],
    ['7',          '7',        '5',          'number above upper bound'],
    ['-9',         '-9',       '0',          'number below lower bound'],
    ['3.5',        '3.5',      '3.5',        'fractional number'],
    ['"12"',      '12',       '5',          'numeric string converts'],
    ['"-2"',      '-2',       '0',          'negative numeric string'],
    ['"0"',       '0',        '0',          'zero numeric string'],
    ['"nope"',    '"nope"',   '"nope"',     'nonnumeric string passes through'],
    ['""',        '""',       '""',         'empty string passes through'],
    ['[]',         '[]',       '[]',         'empty array'],
    ['{}',         '{}',       '{}',         'empty object'],
    ['["2",true,null,8,"bad",false]',
     '[2,1,null,8,"bad",0]', '[2,1,null,5,"bad",0]',
     'mixed array'],
    ['[["-3",false],[true,"9"],[]]',
     '[[-3,0],[1,9],[]]', '[[0,0],[1,5],[]]',
     'nested arrays'],
    ['[{"n":"9","flag":true},"4",["-2",null]]',
     '[{"n":"9","flag":true},4,[-2,null]]',
     '[{"n":"9","flag":true},4,[0,null]]',
     'objects inside arrays stay untouched'],
    ['{"outer":["9",true],"n":"6"}',
     '{"outer":["9",true],"n":"6"}',
     '{"outer":["9",true],"n":"6"}',
     'root object stays untouched'],
);

sub stream_json {
    my (@values) = @_;
    return $json->encode(\@values);
}

for my $case (@cases) {
    my ($input, $to_expected, $clamp_expected, $label) = @$case;
    my $value = $json->decode($input);
    my $to_number = JQ::Lite::Util::_apply_to_number($value);
    my $clamped = JQ::Lite::Util::_apply_clamp($value, 0, 5);

    is($json->encode($to_number), $json->encode($json->decode($to_expected)),
       "direct to_number: $label");
    is($json->encode($clamped), $json->encode($json->decode($clamp_expected)),
       "direct clamp: $label");

    my @to_stream = $jq->run_query($input, 'to_number');
    my @clamp_stream = $jq->run_query($input, 'clamp(0,5)');
    is(stream_json(@to_stream), stream_json($json->decode($to_expected)),
       "public to_number stream: $label");
    is(stream_json(@clamp_stream), stream_json($json->decode($clamp_expected)),
       "public clamp stream: $label");
}

# Arrays recurse, but hashes and embedded object members do not. Even when
# wrapper results change, neither may mutate the caller's original input.
my $object = $json->decode('{"n":"4","array":[true,"9"]}');
my $original = $json->encode($object);
is(JQ::Lite::Util::_apply_to_number($object), $object,
   'to_number keeps the original object reference');
is(JQ::Lite::Util::_apply_clamp($object, 0, 5), $object,
   'clamp keeps the original object reference');
is($json->encode($object), $original, 'object remains unmodified');

my $array = $json->decode('["6",true,[false,-5]]');
my $array_original = $json->encode($array);
JQ::Lite::Util::_apply_to_number($array);
JQ::Lite::Util::_apply_clamp($array, 0, 5);
is($json->encode($array), $array_original,
   'array recursion does not mutate original array');

# Multiplicity, order and empty-output propagation are public contracts.
my @converted = $jq->run_query(
    '[true,"12",null,{"n":"4"},[false,"1"]]', '.[] | to_number'
);
is(stream_json(@converted), $json->encode(
    $json->decode('[1,12,null,{"n":"4"},[0,1]]')
), 'to_number preserves ordered multi-result streams');

my @bounded = $jq->run_query(
    '[false,7,"2",{"n":7},[true,-5]]', '.[] | clamp(0,3)'
);
is(stream_json(@bounded), $json->encode(
    $json->decode('[0,3,2,{"n":7},[1,0]]')
), 'clamp preserves ordered multi-result streams');

my @empty_to = $jq->run_query('null', 'empty | to_number');
my @empty_clamp = $jq->run_query('null', 'empty | clamp(0,5)');
is(scalar(@empty_to), 0, 'to_number does not create an output from empty');
is(scalar(@empty_clamp), 0, 'clamp does not create an output from empty');

is(stream_json($jq->run_query('7', 'clamp(5,0)')), '[5]',
   'reversed bounds still normalize in public clamp dispatcher');
is(stream_json($jq->run_query('7', 'clamp(null,5)')), '[5]',
   'omitted lower bound still works');
is(stream_json($jq->run_query('-3', 'clamp(0)')), '[0]',
   'single lower bound still works');

done_testing;
