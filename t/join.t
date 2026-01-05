use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $json = '{"users":[{"name":"Alice"},{"name":"Bob"},{"name":"Carol"}]}';

my $jq = JQ::Lite->new;

my @result = $jq->run_query($json, '.users | map(.name) | join(", ")');
is_deeply(\@result, ['Alice, Bob, Carol'], 'join() concatenates string array elements');

my @mixed = $jq->run_query($json, '.users | map(.name) + [null, true, 123] | join("|")');
is($mixed[0], 'Alice|Bob|Carol||true|123', 'join() stringifies booleans/numbers and treats null as empty string');

my $non_array_ok = eval { $jq->run_query($json, '.users[0].name | join(",")'); 1 };
ok(!$non_array_ok && $@ =~ /input must be an array/, 'join() rejects non-array inputs');

my $nested_error = eval { $jq->run_query($json, '.users + [["extra"]] | join(",")'); 1 };
ok(!$nested_error && $@ =~ /array elements must be scalars or booleans/,
    'join() rejects nested arrays or object values');

done_testing();

