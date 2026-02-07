use strict;
use warnings;

use JSON::PP qw(encode_json);
use Test::More;

use JQ::Lite;

my $jq = JQ::Lite->new(
    vars => {
        greeting => 'hello',
        user     => { name => 'Alice' },
    }
);

my $empty_json = encode_json({});
my @results    = $jq->run_query($empty_json, '$greeting');
is_deeply(\@results, ['hello'], 'string variable is exposed to queries');

@results = $jq->run_query($empty_json, '$greeting | length');
is_deeply(\@results, [5], 'variables participate in pipeline expressions');

@results = $jq->run_query($empty_json, '$user.name');
is_deeply(\@results, ['Alice'], 'variable paths resolve using stored values');

my $array_json = encode_json({ users => [ { id => 1 }, { id => 2 } ] });
@results = $jq->run_query($array_json, '.users[] | $greeting');
is_deeply(\@results, ['hello', 'hello'], 'variables remain available across pipelines');

@results = $jq->run_query('{"value":1}', '. as $tmp | $tmp.value');
is_deeply(\@results, [1], 'query-local variables work within the same pipeline');

@results = $jq->run_query($empty_json, '$tmp');
is_deeply(\@results, [undef], 'query-local variables do not leak into later top-level queries');

@results = $jq->run_query($empty_json, '$greeting');
is_deeply(\@results, ['hello'], 'predeclared variables remain available after local variable usage');

done_testing();
