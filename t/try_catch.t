use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;

my @preserved = $jq->run_query('{"value":5,"fallback":"ok"}', 'try .value catch .fallback');
is($preserved[0], 5, 'try returns success branch without invoking catch');

my @caught = $jq->run_query('{"fallback":"recovered"}', 'try (1/0) catch .fallback');
is($caught[0], 'recovered', 'catch expression runs when try branch throws and preserves input');

my @empty = $jq->run_query('null', 'try (1/0)');
is(scalar @empty, 0, 'try without catch swallows errors and yields no output');

done_testing;
