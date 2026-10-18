use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Util ();
use JSON::PP ();
use Scalar::Util qw(refaddr);

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


# delpaths sorts deepest paths first and removes array siblings from the
# highest index. Its comparator formerly rebuilt each parent signature for
# every sort comparison; check the exact old sort order against the
# decorated/cached implementation, including reference identity.
sub reference_deletion_sort {
    my @paths = @_;
    return sort {
        my $depth = @$b <=> @$a;
        return $depth if $depth;
        my $prefix = JQ::Lite::Util::_path_prefix_key($a)
                   cmp JQ::Lite::Util::_path_prefix_key($b);
        return $prefix if $prefix;
        return JQ::Lite::Util::_compare_path_segments(
            $b->[-1], $a->[-1]
        );
    } @paths;
}

my $codec = JSON::PP->new->allow_nonref->canonical;
my @sort_cases = (
    [[], 'empty set'],
    [[['a']], 'single path'],
    [[['a'], ['b'], ['c']], 'different root keys'],
    [[['a',0], ['a',2], ['a',1]], 'array sibling indices'],
    [[['a',1], ['a',2], ['a',1], ['a',0]],
        'duplicates and repeated indexes'],
    [[['a',0,'b'], ['a'], ['a',1], ['a',0], ['z','x']],
        'nested and parent paths by depth'],
    [[['z','leaf'], ['a','leaf'], ['z','deep','x'], ['b']],
        'parent signatures split sibling groups'],
    [[['a',0], ['a',-1], ['a',2], ['a','2']],
        'negative numeric and numeric-looking string segments'],
    [[['a',JSON::PP::true], ['a',JSON::PP::false],
        ['a',0], ['a',1]], 'boolean and numeric last segments'],
    [[['a.b','c'], ['a','b.c'], ['','x'], ['日本','葉']],
        'dots, empty and Unicode keys'],
    [[["a\x1fb",'x'], ['a','b','x'], ["a\x1fb",'y']],
        'delimiter-like key remains ordered as before'],
    [[['deep','layer','leaf'], ['deep','layer','other'],
        ['deep','other'], ['shallow']], 'different path depths'],
);
for my $case (@sort_cases) {
    my ($paths, $label) = @$case;
    my $before = $codec->encode($paths);
    my @legacy = reference_deletion_sort(@$paths);
    my @current = JQ::Lite::Util::_sort_paths_for_deletion(@$paths);
    is_deeply(\@current, \@legacy, "delpaths sort order: $label");
    is_deeply([map { refaddr($_) } @current],
        [map { refaddr($_) } @legacy],
        "delpaths original path identities: $label");
    is($codec->encode($paths), $before,
        "delpaths input remains unchanged: $label");
}

my @wide_paths = (
    map { ['items', $_] } 0 .. 256
);
push @wide_paths, ['root'], ['nested','array',2], ['nested','array',0];
my @wide_reference = reference_deletion_sort(@wide_paths);
my @wide_current = JQ::Lite::Util::_sort_paths_for_deletion(@wide_paths);
is_deeply(\@wide_current, \@wide_reference,
    '260-path decorated sort retains old ordering');
is_deeply([map { refaddr($_) } @wide_current],
    [map { refaddr($_) } @wide_reference],
    '260-path decorated sort reuses original path references');
is(scalar(@wide_current), 260, 'large path set retains cardinality');

# Public delpaths dispatch is gated to the existing supported interpreter
# versions; direct sort contracts above run on the Perl 5.14 matrix too.
my @delete_cases = (
    ['{"a":[0,1,2,3,4]}',
     'delpaths([["a",1],["a",3]])',
     [{a=>[0,2,4]}], 'higher array positions removed first'],
    ['{"a":[0,1,2,3]}',
     'delpaths([["a",1],["a",1]])',
     [{a=>[0,3]}], 'duplicate paths retain legacy repeated deletion'],
    ['{"a":{"b":1,"c":2},"d":3}',
     'delpaths([["a","b"],["a"]])',
     [{d=>3}], 'nested path deleted before its parent'],
    ['{"nested":[{"x":1,"y":2},{"x":3,"y":4}],"keep":true}',
     'delpaths([["nested",0,"x"],["nested",1,"y"]])',
     [{nested=>[{y=>2},{x=>3}],keep=>JSON::PP::true}],
     'nested indices and object siblings'],
    ['{"items":[5,6,7]}',
     'delpaths([["items",false],["items",true]])',
     [{items=>[7]}], 'boolean indices removed in descending order'],
    ['{"a":1,"b":2}',
     'delpaths([["unknown"],["b"]])',
     [{a=>1}], 'missing path ignored alongside valid deletion'],
    ['{"a":{"b":1},"c":2}',
     'delpaths([["a","b"],["c"]])',
     [{a=>{}}], 'mixed-depth deletions'],
);
SKIP: {
    skip 'public delpaths dispatch requires Perl 5.34+', scalar @delete_cases + 1
        if $] < 5.034;
    for my $case (@delete_cases) {
        my ($input, $filter, $expected, $label) = @$case;
        is_deeply(results($input, $filter), $expected,
            "public delpaths sorted deletion: $label");
    }
    is_deeply(results('[{"a":[1,2,3]},{"a":[4,5,6]}]',
        '.[] | delpaths([["a",1]])'),
        [{a=>[1,3]},{a=>[4,6]}],
        'public delpaths per-stream output order preserved');
}

done_testing;
