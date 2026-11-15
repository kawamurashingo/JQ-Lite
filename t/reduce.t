use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq = JQ::Lite->new;

my $numbers = '{ "numbers": [1, 2, 3, 4] }';
my @sum = $jq->run_query($numbers, 'reduce .numbers[] as $n (0; . + $n)');
is($sum[0], 10, 'reduce sums numeric arrays');

my $with_init_filter = '[1, 2, 3]';
my @length_init = $jq->run_query($with_init_filter, 'reduce .[] as $n (length; . + $n)');
is($length_init[0], 9, 'reduce falls back to filter evaluation for init expression');

my $items = '{ "items": [ { "name": "alice", "value": 2 }, { "name": "bob", "value": 3 } ] }';
my @total = $jq->run_query($items, 'reduce .items[] as $item (0; . + $item.value)');
is($total[0], 5, 'reduce accesses variable paths');

my @last_name = $jq->run_query($items, 'reduce .items[] as $item (null; $item.name)');
is($last_name[0], 'bob', 'reduce assigns variable value without arithmetic');

for my $literal ('false', '0', 'null') {
    is_deeply([ $jq->run_query("[1,$literal]", 'reduce .[] as $n (null; $n)') ],
        [ JSON::PP->new->decode($literal) ], "reduce retains $literal as a value");
}
is_deeply([ $jq->run_query('[1]', 'reduce .[] as $n ("abcd"; length)') ],
    [4], 'reduce evaluates update filters against the accumulator');
is_deeply([ $jq->run_query('[1,2]', 'reduce .[] as $n ([]; .[])') ],
    [undef], 'reduce preserves its existing empty scalar-result behavior');
for my $update ('. / 0', '(7, 1 / 0)') {
    my $ok = eval { $jq->run_query('[1]', "reduce .[] as \$n (1; $update)"); 1 };
    ok(!$ok && ref($@) && $@->isa('JQ::Lite::Error::Evaluation'),
        "reduce propagates errors from $update");
}

done_testing;
