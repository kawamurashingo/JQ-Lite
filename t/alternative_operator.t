use strict;
use warnings;
use Test::More tests => 5;
use JQ::Lite;

my $jq = JQ::Lite->new;

# 1. Existing value should pass through
my $json1 = '{"foo":"value","bar":"fallback"}';
my @result1 = $jq->run_query($json1, '.foo // .bar');
is($result1[0], 'value', '// keeps existing non-null value');

# 2. Missing value should fall back to alternate field
my $json2 = '{"bar":"fallback"}';
my @result2 = $jq->run_query($json2, '.foo // .bar');
is($result2[0], 'fallback', '// uses alternate expression when field missing');

# 3. Null value should trigger default literal
my $json3 = '{"foo":null}';
my @result3 = $jq->run_query($json3, '.foo // "default"');
is($result3[0], 'default', '// treats null as missing');

# 4. False boolean should not trigger default
my $json4 = '{"flag":false}';
my @result4 = $jq->run_query($json4, '.flag // true');
ok(defined $result4[0] && !$result4[0], '// preserves explicit false values');

# 5. Works inside map over array entries
my $json5 = '[null, 1, 0]';
my @result5 = $jq->run_query($json5, 'map(. // 2)');
is_deeply($result5[0], [2, 1, 0], '// cooperates with map for element-wise defaults');

