use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

# Exercise the documented Library entry point, not private evaluators.
# A Perl list can contain zero, one, or several JSON-derived results.
my $jq = JQ::Lite->new;
isa_ok($jq, 'JQ::Lite', 'public constructor');

sub outputs {
    my ($input, $query) = @_;
    return [ $jq->run_query($input, $query) ];
}

is_deeply(outputs('[1,2,3]', '.[]'), [1, 2, 3],
    'array iterator returns three values in source order');
is_deeply(outputs('[1,2,3]', 'empty'), [],
    'empty filter returns zero results, not one null');
is_deeply(outputs('{"a":1}', '.missing'), [undef],
    'missing object field returns one null, not an empty stream');

is_deeply(outputs('{"a":1}', '.'), [{a => 1}],
    'identity returns an object as a hash reference');
is_deeply(outputs('[1,true,null]', '.'), [[1, JSON::PP::true, undef]],
    'identity returns an array reference preserving element types');
is_deeply(outputs('"hello"', '.'), ['hello'],
    'identity returns a JSON string as a Perl string');
is_deeply(outputs('42', '.'), [42],
    'identity returns a JSON number');
is_deeply(outputs('null', '.'), [undef],
    'identity returns a single null result');
my $boolean_output = outputs('false', '.');
is(scalar(@$boolean_output), 1, 'boolean input produces one result');
ok(JSON::PP::is_bool($boolean_output->[0]),
    'JSON boolean remains a JSON boolean, not an ordinary scalar');
ok(!$boolean_output->[0], 'false preserves its boolean value');

is_deeply(outputs('[9,8]', undef), [[9, 8]],
    'undefined query preserves the decoded input');
is_deeply(outputs('[9,8]', '  .  '), [[9, 8]],
    'whitespace-padded identity query preserves the decoded input');

# A single reusable object must not accumulate the previous query's
# results or change list cardinality across independent invocations.
is_deeply(outputs('[4,5]', '.[]'), [4, 5],
    'a later call still returns an independent ordered result list');
is_deeply(outputs('null', 'empty'), [],
    'a later empty filter still yields zero results');

my $with_vars = JQ::Lite->new(vars => { wanted => 7 });
isa_ok($with_vars, 'JQ::Lite', 'constructor with documented vars option');
is_deeply([ $with_vars->run_query('null', '$wanted') ], [7],
    'constructor variables remain available to the public query method');
is_deeply([ $with_vars->run_query('null', '$wanted') ], [7],
    'constructor variables survive independent top-level queries');

done_testing;
