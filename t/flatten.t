use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $json = <<'JSON';
{
  "items": [[1, 2], [3], [], [4, 5]]
}
JSON

my $jq = JQ::Lite->new;
my @results = $jq->run_query($json, '.items | flatten');

is_deeply(\@results, [[1,2], [3], [], [4,5]], 'flatten 1 layer of array');

my @string_chars = $jq->run_query('"hello"', '.[]');
is_deeply(\@string_chars, ['h', 'e', 'l', 'l', 'o'], 'flatten iterates over string characters');

my @numeric_string_chars = $jq->run_query('"123"', 'flatten');
is_deeply(\@numeric_string_chars, ['1', '2', '3'], 'flatten treats numeric-looking strings as strings');

my @number_results = $jq->run_query('123', '.[]');
is_deeply(\@number_results, [], 'flatten ignores non-string scalars');
done_testing();
