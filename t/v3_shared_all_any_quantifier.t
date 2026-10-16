use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq = JQ::Lite->new;

sub check {
    my ($json, $filter, $expected, $label) = @_;
    my @result = $jq->run_query($json, $filter);
    is(scalar @result, scalar @$expected, "$label output count");
    ok(!(grep { !JSON::PP::is_bool($_) } @result), "$label returns JSON booleans");
    is_deeply([ map { $_ ? 1 : 0 } @result ], $expected, $label);
}

check('[true,true]', 'all', [1], 'all true array');
check('[true,false]', 'all', [0], 'all short circuits on false');
check('[false,false]', 'any', [0], 'any false array');
check('[false,true]', 'any', [1], 'any short circuits on true');
check('[]', 'all', [1], 'all empty array is true');
check('[]', 'any', [0], 'any empty array is false');

check('[{"ok":true},{"ok":true}]', 'all(.ok)', [1],
    'all evaluated object properties are true');
check('[{"ok":true},{"ok":false}]', 'all(.ok)', [0],
    'all evaluated object properties include false');
check('[{"ok":false},{"ok":true}]', 'any(.ok)', [1],
    'any evaluated property is true');
check('[{"ok":false},{"ok":false}]', 'any(.ok)', [0],
    'any evaluated properties are false');

check('[[true,true],[false,true]]', '.[] | all', [1,0],
    'all retains ordered input streams');
check('[[false,true],[false,false]]', '.[] | any', [1,0],
    'any retains ordered input streams');

check('[true,true]', 'all()', [1],
    'v2 empty-parentheses all spelling');
check('[false,true]', 'any()', [1],
    'v2 empty-parentheses any spelling');
check('true', 'all', [1], 'v2 all scalar true');
check('false', 'any', [0], 'v2 any scalar false');
check('0', 'all', [0], 'v2 numeric zero remains false');
check('0', 'any', [0], 'v2 numeric zero remains false for any');
check('null', 'all', [0], 'v2 null scalar is false');
check('null', 'any', [0], 'v2 null scalar is false for any');

check('[true,false]', 'all(empty)', [0],
    'v2 all(empty) keeps false when a nonempty item emits no results');
check('[true,false]', 'any(empty)', [0],
    'v2 any(empty) keeps false when no results are emitted');

check('[{"flags":[true,true]},{"flags":[true,false]}]',
    'all(.flags[])', [0],
    'all checks every emitted callback value');
check('[{"flags":[false,false]},{"flags":[false,true]}]',
    'any(.flags[])', [1],
    'any checks emitted callback values in order');

done_testing();
