use strict;
use warnings;

use Test::More;

use JQ::Lite;

my $jq = JQ::Lite->new;

sub run {
    my ($json, $query) = @_;
    return [ $jq->run_query($json, $query) ];
}

my $binding = run('{"a": 1}', '. as $x | $x');

is_deeply(
    $binding,
    [{ a => 1 }],
    'as binds the current value to a variable'
);

my $path_suffix = run('{"a": {"b": 2}}', '. as $x | $x.a.b');

is_deeply(
    $path_suffix,
    [2],
    'variable references can apply path suffixes'
);

my $pipeline = run('{"a": 1}', '. as $x | $x | .a');

is_deeply(
    $pipeline,
    [1],
    'variable references can flow through pipelines'
);

my $expression = run('3', '. as $x | $x + 1');

is_deeply(
    $expression,
    [4],
    'variable references can be used in expressions'
);

DONE_TESTING:

done_testing();
