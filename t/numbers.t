use strict;
use warnings;
use Test::More;
use JSON::PP qw(encode_json);
use JQ::Lite;

my $data = {
    mix => [
        1,
        "2",
        { nested => [3, { inner => 4 }, "skip"] },
        JSON::PP::true,
        JSON::PP::false,
        undef,
        [5, { also => 7, nope => "8" }],
    ],
};

my $json = encode_json($data);
my $jq   = JQ::Lite->new;

my @results = $jq->run_query($json, '.mix | numbers');
is_deeply(\@results, [1, 3, 4, 5, 7], 'numbers extracts numeric values recursively');

@results = $jq->run_query($json, '.mix[] | numbers');
is_deeply(\@results, [1, 3, 4, 5, 7], 'numbers works element-wise in pipelines');

@results = $jq->run_query('"42"', 'numbers');
is_deeply(\@results, [], 'numbers skips numeric-looking strings');

@results = $jq->run_query('42', 'numbers');
is_deeply(\@results, [42], 'numbers emits standalone numeric scalars');

done_testing();
