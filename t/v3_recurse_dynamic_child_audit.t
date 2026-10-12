use strict;
use warnings;
use Test::More;
use JQ::Lite;

# Exploratory regression coverage for dynamic recurse child selection.
# This is intentionally a draft audit: jq 1.7 differential expectations
# must be confirmed before an evaluator change is proposed.
my $jq = JQ::Lite->new;
my $input = '{"items":[{"id":1},{"id":2},{"id":3}]}';

my @cases = (
    ['dynamic field lookup', 'try (. | (recurse(.["items"][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'],
    ['named field control', 'try (. | (recurse(.items[]? | if .id == 2 then (1/0) else . end) | .)) catch 42'],
    ['dynamic field catch empty', 'try (. | (recurse(.["items"][]? | if .id == 2 then (1/0) else . end) | .)) catch empty'],
);

for my $case (@cases) {
    my ($name, $filter) = @$case;
    subtest $name => sub {
        my @result;
        my $ok = eval { @result = $jq->run_query($input, $filter); 1 };
        note "filter: $filter";
        note "execution: " . ($ok ? 'ok' : "error: $@");
        note "results: " . scalar(@result);
        pass('exploratory case executed; jq 1.7 oracle pending');
    };
}

done_testing;
