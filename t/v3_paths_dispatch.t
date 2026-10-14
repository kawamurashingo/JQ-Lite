use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;

sub results {
    my ($input, $filter) = @_;
    return [$jq->run_query($input, $filter)];
}

my $nested = '{"a":[10],"b":{"c":4}}';
my $all_paths = [['a'], ['a',0], ['b'], ['b','c']];
my $scalar_paths = [['a',0], ['b','c']];

is_deeply(results($nested, 'paths'), $all_paths,
    'bare paths preserves deterministic depth-first order');
is_deeply(results($nested, 'paths()'), $all_paths,
    'existing v2 paths() spelling remains supported');
is_deeply(results($nested, 'paths(scalars)'), $scalar_paths,
    'paths(scalars) traverses only leaf values');
is_deeply(results($nested, 'paths( scalars )'), $scalar_paths,
    'existing optional whitespace in scalar selector remains supported');

is_deeply(results('[10,[20,30],{"k":true}]', 'paths(scalars)'),
    [[0], [1,0], [1,1], [2,'k']],
    'numeric and boolean scalar leaf paths retain order');
is_deeply(results('[null,false,3]', 'paths(scalars)'),
    [[0], [1], [2]],
    'v2 null-as-scalar extension is retained intentionally');
is_deeply(results('12', 'paths'), [],
    'paths emits no result for scalar root');
is_deeply(results('true', 'paths(scalars)'), [],
    'paths(scalars) emits no result for boolean root');
is_deeply(results('[]', 'paths'), [],
    'paths of an empty array emits no result');
is_deeply(results('{}', 'paths(scalars)'), [],
    'scalar paths of an empty object emits no result');

my $stream = '[{"a":1},{"b":2}]';
is_deeply(results($stream, '.[] | paths'),
    [['a'], ['b']],
    'pipeline preserves per-input path stream order');
is_deeply(results($stream, '.[] | paths(scalars)'),
    [['a'], ['b']],
    'scalar path pipeline preserves input order');

done_testing;
