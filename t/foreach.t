use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq = JQ::Lite->new;

my $numbers = '{ "numbers": [1, 2, 3, 4] }';
my @running_totals = $jq->run_query($numbers, 'foreach .numbers[] as $n (0; . + $n)');

is_deeply(\@running_totals, [1, 3, 6, 10], 'foreach emits running totals without extractor');

my $init_filter = '[1, 2, 3]';
my @length_seed = $jq->run_query($init_filter, 'foreach .[] as $n (length; . + $n)');

is_deeply(\@length_seed, [4, 6, 9], 'foreach init expression uses filter evaluation when needed');

my @emitted = $jq->run_query(
    $numbers,
    'foreach .numbers[] as $n (0; . + $n; $n)'
);

is_deeply(
    \@emitted,
    [1, 2, 3, 4],
    'foreach extractor can reference iteration variable'
);

my $strings = '{ "words": ["a", "b", "c"] }';
my @concat = $jq->run_query($strings, 'foreach .words[] as $w (""; . + $w)');

is_deeply(\@concat, ['a', 'ab', 'abc'], 'foreach concatenates strings via addition semantics');

is_deeply([ $jq->run_query('[false,0,null]', 'foreach .[] as $n (null; $n; .)') ],
    [ JSON::PP::false, 0, undef ], 'foreach retains false, zero and null through extraction');
is_deeply([ $jq->run_query('[1]', 'foreach .[] as $n ("abcd"; length; type)') ],
    ['number'], 'foreach supports update and extraction filter fallbacks');
is_deeply([ $jq->run_query('["a","bb"]', 'foreach .[] as $n (null; $n; length)') ],
    [1,2], 'foreach extraction uses the updated accumulator');
is_deeply([ $jq->run_query('[1,2]', 'foreach .[] as $n (0; . + $n; empty)') ],
    [undef,undef], 'foreach preserves existing null outputs for an empty extractor');
for my $extract ('. / 0', '(7, 1 / 0)') {
    my $ok = eval { $jq->run_query('[1]', "foreach .[] as \$n (0; . + \$n; $extract)"); 1 };
    ok(!$ok && ref($@) && $@->isa('JQ::Lite::Error::Evaluation'),
        "foreach propagates errors from $extract");
}

done_testing;
