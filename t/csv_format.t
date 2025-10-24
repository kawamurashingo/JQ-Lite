use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $json = '{"row":["foo","bar","baz,qux","he said \"hi\""]}';

my $jq = JQ::Lite->new;

my @row = $jq->run_query($json, '.row | @csv');
is_deeply(\@row, ['"foo","bar","baz,qux","he said ""hi"""'], '@csv formats arrays as CSV rows');

my @single = $jq->run_query($json, '.row[0] | @csv');
is_deeply(\@single, ['"foo"'], '@csv formats scalar values as CSV fields');

done_testing();
