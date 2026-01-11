use strict;
use warnings;

use Test::More;
use JQ::Lite;
use JSON::PP;

my $jq = JQ::Lite->new;

my $json = encode_json({ numbers => [10, 20, 30, 40, 50] });

my @result = $jq->run_query($json, '.numbers | slice(1, 2)');
is_deeply($result[0], [20, 30], 'slice(1, 2) returns middle segment');

@result = $jq->run_query($json, '.numbers | slice(3)');
is_deeply($result[0], [40, 50], 'slice(3) defaults length to array end');

@result = $jq->run_query($json, '.numbers | slice(-2, 1)');
is_deeply($result[0], [40], 'slice(-2, 1) supports negative start offsets');

@result = $jq->run_query($json, '.numbers | slice(10)');
is_deeply($result[0], [], 'slice start beyond array produces empty array');

@result = $jq->run_query($json, '.numbers | slice(-10, 2)');
is_deeply($result[0], [10, 20], 'slice clamps negative starts earlier than array length');

@result = $jq->run_query($json, '.numbers | slice(2, 0)');
is_deeply($result[0], [], 'slice with non-positive length is empty');

my $json_scalar = encode_json({ value => 42 });
@result = $jq->run_query($json_scalar, '.value | slice(1, 2)');
is($result[0], 42, 'slice leaves scalar values unchanged');

my $invalid_start_ok = eval { $jq->run_query($json, '.numbers | slice("oops", 2)'); 1 };
ok(!$invalid_start_ok, 'slice dies when start index is not numeric');
like(
    $@,
    qr/slice\(\): start index must be numeric/i,
    'slice reports invalid start index error message',
);

my $invalid_length_ok = eval { $jq->run_query($json, '.numbers | slice(1, "nope")'); 1 };
ok(!$invalid_length_ok, 'slice dies when length is not numeric');
like(
    $@,
    qr/slice\(\): length must be numeric/i,
    'slice reports invalid length error message',
);


done_testing();
