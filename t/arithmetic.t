use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $json = q([
  { "id": 1 },
  { "id": 5 },
  { "id": 15 },
  { "id": 25 }
]);

my $jq = JQ::Lite->new;
my @calc = $jq->run_query($json, 'map(select(.id + 5 > 20))');

is_deeply(
    $calc[0],
    [ { id => 25 } ],
    'id + 5 > 20 selects only 25'
);

my @division_by_zero_condition = $jq->run_query($json, 'map(select(.id / 0 > 1))');

is_deeply(
    $division_by_zero_condition[0],
    [],
    'division by zero inside select arithmetic condition is treated as false'
);

my @incremented = $jq->run_query($json, 'map(.id + 1)');

is_deeply(
    $incremented[0],
    [ 2, 6, 16, 26 ],
    'map(.id + 1) increments each id'
);

my $people = q([
  { "name": "Alice", "city": "Tokyo" },
  { "name": "Bob",   "city": "Osaka" }
]);

my @joined = $jq->run_query($people, 'map(.name + "@" + .city)');

is_deeply(
    $joined[0],
    [ 'Alice@Tokyo', 'Bob@Osaka' ],
    'map(.name + "@" + .city) concatenates name and city'
);

my $numbers = '{"a":10,"b":3,"s":"42"}';

my @precedence = $jq->run_query($numbers, '1+2*3');
is($precedence[0], 7, 'multiplication binds tighter than addition');

my @grouped = $jq->run_query($numbers, '(1+2)*3');
is($grouped[0], 9, 'parentheses override precedence');

my @divided = $jq->run_query($numbers, '.a/.b | floor');
is($divided[0], 3, 'division result is floored');

my @tonumber = $jq->run_query($numbers, 'tonumber(.s) + 1');
is($tonumber[0], 43, 'tonumber() converts to numeric value');

my $ok = eval { $jq->run_query($numbers, '1/0'); 1 };
my $error = $@;
ok(!$ok, 'division by zero throws');
like($error, qr/Division by zero/, 'division by zero error message');

my $search = '{"q":"東京 タワー","page":5}';
my @uri_concat = $jq->run_query($search, '"q=" + (.q|@uri)');
is(
    $uri_concat[0],
    'q=%E6%9D%B1%E4%BA%AC%20%E3%82%BF%E3%83%AF%E3%83%BC',
    '(.q|@uri) inside addition behaves like jq'
);

my $strings = '{"s1":"1","s2":"2","t":"a","n":3}';
my @string_concat = $jq->run_query($strings, '.s1 + .s2');
is($string_concat[0], '12', 'string addition concatenates numeric-looking strings');

my @string_mixed = $jq->run_query($strings, '.s1 + .t');
is($string_mixed[0], '1a', 'string addition concatenates mixed string content');

my $string_number_ok = eval { $jq->run_query($strings, '.s1 + .n'); 1 };
my $string_number_error = $@;
ok(!$string_number_ok, 'string plus number throws an error');
like($string_number_error, qr/addition operands/i, 'string plus number error message');

done_testing;


{
    my $ok = eval { $jq->run_query('true', '. + 1'); 1 };
    my $error = $@;
    ok(!$ok, 'boolean arithmetic throws in v3');
    isa_ok($error, 'JQ::Lite::Error::Evaluation');
    like("$error", qr/number|compatible jq types/i, 'boolean arithmetic reports a type error');
}

{
    my $ok = eval { $jq->run_query('"1"', '. * 2'); 1 };
    my $error = $@;
    ok(!$ok, 'numeric-looking string multiplication throws in v3');
    isa_ok($error, 'JQ::Lite::Error::Evaluation');
    like("$error", qr/must be a number/i, 'numeric-looking string multiplication reports a numeric type error');
}

{
    my @scientific = $jq->run_query('{}', '1e3 + 2');
    is($scientific[0], 1002, 'scientific notation remains numeric');
}

{
    my $ok = eval { $jq->run_query('{}', '5 % 0'); 1 };
    my $error = $@;
    ok(!$ok, 'modulo by zero throws');
    isa_ok($error, 'JQ::Lite::Error::Evaluation');
    like("$error", qr/Modulo by zero/, 'modulo by zero keeps its runtime message');
}
