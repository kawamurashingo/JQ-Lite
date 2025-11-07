use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new(vars => { a => 'hello', b => 'world' });
my @results = $jq->run_query('null', '{"msg": "\($a) \($b)"}');

is_deeply(
    \@results,
    [ { msg => 'hello world' } ],
    'string interpolation uses provided variables',
);

my $data = <<'JSON';
[
  {"name": "Alice", "age": 30},
  {"name": "Bob",   "age": 25}
]
JSON

$jq = JQ::Lite->new;
@results = $jq->run_query($data, '.[] | {"desc": "\(.name) is \(.age)"}');

is_deeply(
    \@results,
    [
        { desc => 'Alice is 30' },
        { desc => 'Bob is 25' },
    ],
    'string interpolation supports expressions using the current context',
);

$jq = JQ::Lite->new;
@results = $jq->run_query('[{"items": [1,2]}]', '.[] | {"items": "\(.items)"}');

is_deeply(
    \@results,
    [ { items => '[1,2]' } ],
    'string interpolation stringifies arrays as JSON',
);

$jq = JQ::Lite->new;
@results = $jq->run_query('[{"flag": true}]', '.[] | {"flag": "\(.flag)"}');

is_deeply(
    \@results,
    [ { flag => 'true' } ],
    'boolean values are stringified to lowercase words',
);

done_testing();
