use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;

sub results {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

my @cases = (
    ['drop', '0',   [1,2,3,4]],
    ['drop', '1',   [2,3,4]],
    ['drop', '2',   [3,4]],
    ['drop', '4',   []],
    ['drop', '5',   []],
    ['drop', '100', []],
    ['drop', '002', [3,4]],
    ['drop', ' 2 ', [3,4]],
    ['tail', '0',   []],
    ['tail', '1',   [4]],
    ['tail', '2',   [3,4]],
    ['tail', '4',   [1,2,3,4]],
    ['tail', '5',   [1,2,3,4]],
    ['tail', '100', [1,2,3,4]],
    ['tail', '002', [3,4]],
    ['tail', ' 2 ', [3,4]],
);
for my $case (@cases) {
    my ($function, $count, $expected) = @$case;
    is_deeply(results('[1,2,3,4]', "$function($count)"), [$expected],
        "$function($count) retains the original suffix");
}

for my $function (qw(drop tail)) {
    for my $count (0, 1, 3) {
        is_deeply(results('[]', "$function($count)"), [[]],
            "$function($count) preserves the empty array");
        is_deeply(results('[7]', "$function($count)"),
            [ $function eq 'drop'
                ? ($count ? [] : [7])
                : ($count ? [7] : []) ],
            "$function($count) handles a singleton array");
    }
    is_deeply(results('{"k":7}', "$function(2)"), [{k=>7}],
        "$function passes through an object");
    is_deeply(results('42', "$function(2)"), [42],
        "$function passes through a number");
    is_deeply(results('"hello"', "$function(2)"), ['hello'],
        "$function passes through a string");
    is_deeply(results('null', "$function(2)"), [undef],
        "$function passes through null");
    is_deeply(results('true', "$function(2)"), [JSON::PP::true],
        "$function passes through a JSON boolean");
}

for my $function (qw(drop tail)) {
    for my $invalid ('-1', '+2', '1.5', '1e2', 'abc', ' ') {
        my $filter = "$function($invalid)";
        my $ok = eval { $jq->run_query('[1,2,3]', $filter); 1 };
        ok(!$ok, "$function rejects count [$invalid]");
        like("$@", qr/\Q$function(): count must be a non-negative integer\E/,
            "$function keeps the original error text for [$invalid]");
    }
    my $ok = eval { $jq->run_query('null', "$function(-1)"); 1 };
    ok(!$ok, "$function rejects invalid count on scalar input");
    like("$@", qr/\Q$function(): count must be a non-negative integer\E/,
        "$function validates even when input is not an array");
}

my $mixed = '[[1,2,3],"hello",null,[4,5,6],{"k":1}]';
is_deeply(results($mixed, '.[] | drop(2)'),
    [[3], 'hello', undef, [6], {k=>1}],
    'drop preserves ordered mixed input stream');
is_deeply(results($mixed, '.[] | tail(2)'),
    [[2,3], 'hello', undef, [5,6], {k=>1}],
    'tail preserves ordered mixed input stream');

done_testing();
