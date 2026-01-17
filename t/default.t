use strict;
use warnings;
use Test::More tests => 6;
use FindBin;
use lib "$FindBin::Bin/../lib";
use JSON::PP;
use JQ::Lite;

my $jq = JQ::Lite->new;

# --- 1. Existing value should not be replaced
my $json1 = '{"nickname":"alice"}';
my @result1 = $jq->run_query($json1, '.nickname | default("unknown")');
is($result1[0], 'alice', 'default() does not override existing value');

# --- 2. Undefined value should be replaced
my $json2 = '{}';
my @result2 = $jq->run_query($json2, '.nickname | default("unknown")');
is($result2[0], 'unknown', 'default() applies default for missing field');

# --- 3. Null value should be replaced
my $json3 = '{"nickname":null}';
my @result3 = $jq->run_query($json3, '.nickname | default("unknown")');
is($result3[0], 'unknown', 'default() applies default for null');

# --- 4. False should be preserved
my $json4 = '{"active":false}';
my @result4 = $jq->run_query($json4, '.active | default(true)');
ok(@result4 && !$result4[0], 'default() preserves false values');

# --- 5. Zero should be preserved
my $json5 = '{"count":0}';
my @result5 = $jq->run_query($json5, '.count | default(99)');
is($result5[0], 0, 'default() preserves numeric zero values');

# --- 6. Empty string should be preserved
my $json6 = '{"note":""}';
my @result6 = $jq->run_query($json6, '.note | default("missing")');
is($result6[0], '', 'default() preserves empty strings');
