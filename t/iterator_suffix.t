use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;

my $json = '{"b":2,"a":1}';

my @keys_suffix = $jq->run_query($json, 'keys[]');
my @keys_pipe   = $jq->run_query($json, 'keys | .[]');
is_deeply(\@keys_suffix, \@keys_pipe, 'keys[] matches keys | .[]');

my @entries_suffix = $jq->run_query($json, 'to_entries[]');
my @entries_pipe   = $jq->run_query($json, 'to_entries | .[]');
is_deeply(\@entries_suffix, \@entries_pipe, 'to_entries[] matches to_entries | .[]');

my $users = '{"users":[{"name":"Alice"},{"name":"Bob"}]}';
my @path_results = $jq->run_query($users, '.users[] | .name');
is_deeply(\@path_results, ['Alice', 'Bob'], 'existing path iteration remains unchanged');

my $builtin_named_fields = '{"keys":["x","y"],"to_entries":[1,2]}';
my @dotted_keys = $jq->run_query($builtin_named_fields, '.keys[]');
is_deeply(\@dotted_keys, ['x', 'y'], '.keys[] remains dotted field traversal');

my @dotted_to_entries = $jq->run_query($builtin_named_fields, '.to_entries[]');
is_deeply(\@dotted_to_entries, [1, 2], '.to_entries[] remains dotted field traversal');

done_testing();
