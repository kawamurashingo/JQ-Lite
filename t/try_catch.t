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

my @literal_fallback = $jq->run_query('[{"id":1}]', '.[] | {id, result: (try (10 / 0) catch "fallback")}');
is($literal_fallback[0]{result}, 'fallback', 'literal handler is emitted when try branch fails');

my @string_literal = $jq->run_query('null', '"hello"');
is($string_literal[0], 'hello', 'bare string literal emits its value');

my $mixed = q([
  {"id":1,"value":10},
  {"id":2,"value":"oops"}
]);
my @type_errors = $jq->run_query($mixed, '.[] | {id, result: (try (.value + 1) catch "fallback")}');
is_deeply(
    \@type_errors,
    [
        { id => 1, result => 11 },
        { id => 2, result => 'fallback' },
    ],
    'type mismatch inside addition triggers catch handlers'
);

done_testing;
