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
        (@$b <=> @$a)
            || (JQ::Lite::Util::_path_prefix_key($a)
                cmp JQ::Lite::Util::_path_prefix_key($b))
            || JQ::Lite::Util::_compare_path_segments(
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
    my (@legacy, @current, @warnings);
    {
        local $SIG{__WARN__} = sub { push @warnings, @_ };
        @legacy = reference_deletion_sort(@$paths);
        @current = JQ::Lite::Util::_sort_paths_for_deletion(@$paths);
    }
    is_deeply(\@warnings, [], "delpaths sort emits no warnings: $label");
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
my (@wide_reference, @wide_current, @wide_warnings);
{
    local $SIG{__WARN__} = sub { push @wide_warnings, @_ };
    @wide_reference = reference_deletion_sort(@wide_paths);
    @wide_current = JQ::Lite::Util::_sort_paths_for_deletion(@wide_paths);
}
is_deeply(\@wide_warnings, [],
    '260-path sort emits no warnings on older Perl');
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


# _delete_path_inplace copies its own segments before removing the final
# segment. _apply_delpaths should pass the sorted, validated path reference
# directly rather than cloning each path first. Capture both ends of the
# private call and verify identity and nonmutation, even on old Perl where
# the public delpaths parser is currently gated.
my $real_delpaths_sort = \&JQ::Lite::Util::_sort_paths_for_deletion;
my $real_delete_path = \&JQ::Lite::Util::_delete_path_inplace;
my @copy_cases = (
    ['{"a":[0,1,2,3],"keep":true}',
     '[["a",1],["a",3]]',
     {a=>[0,2],keep=>JSON::PP::true},2,
     'descending array sibling deletion'],
    ['{"a":{"b":1,"c":2},"d":3}',
     '[["a","b"],["a"]]',
     {d=>3},2,
     'nested path removed before parent'],
    ['{"a":[10,20,30]}',
     '[["a",1],["a",1]]',
     {a=>[10]},2,
     'repeated array index removes twice'],
    ['{"a":[4,5,6],"n":null}',
     '[["a",false],["a",true]]',
     {a=>[6],n=>undef},2,
     'boolean path indices and null fields'],
    ['{"":"v","a.b":{"x":1},"keep":3}',
     '[[""],["a.b","x"]]',
     {'a.b'=>{},keep=>3},2,
     'empty and dotted object keys'],
    ['{"a":["p","q","r"],"z":1}',
     '[["a",-1],["a",0]]',
     {a=>['q'],z=>1},2,
     'negative and positive array indices'],
    ['{"a":[1,2],"other":{"x":3}}',
     '[["a",90],["other","missing"]]',
     {a=>[1,2],other=>{x=>3}},2,
     'nonexistent deletion targets'],
);
my $many_paths = [map { ['a',$_] } 0 .. 63];
push @copy_cases, [
    $codec->encode({a=>[0 .. 63]}), $codec->encode($many_paths),
    {a=>[]},64, '64 distinct array indices'
];

for my $case (@copy_cases) {
    my ($json, $filter, $expected, $count, $label) = @$case;
    my $input = $codec->decode($json);
    my $before = $codec->encode($input);
    my (@sorted, @snapshots, @received);
    my ($actual, $ok, $failure);
    {
        no warnings 'redefine';
        local *JQ::Lite::Util::_sort_paths_for_deletion = sub {
            @sorted = $real_delpaths_sort->(@_);
            @snapshots = map { $codec->encode($_) } @sorted;
            return @sorted;
        };
        local *JQ::Lite::Util::_delete_path_inplace = sub {
            my ($target, $path) = @_;
            push @received, $path;
            return $real_delete_path->($target, $path);
        };
        $ok = eval {
            $actual = JQ::Lite::Util::_apply_delpaths($jq, $input, $filter);
            1;
        };
        $failure = $@;
    }
    ok($ok, "delpaths direct helper runs: $label") or diag($failure);

    # Replay exactly the previous caller behavior, using the same sorted
    # path references but copying each array at the call boundary.
    my $legacy_result = $codec->decode($json);
    for my $path (@sorted) {
        $real_delete_path->($legacy_result, [@$path]);
    }
    is_deeply($actual, $legacy_result,
        "delpaths output equals old copied-path implementation: $label");

    # The public delpaths grammar is only supported by the existing suite
    # on Perl >= 5.34. Older Perl sort behavior differs in some index
    # ordering cases; check its *unchanged* result above, not new semantics.
    SKIP: {
        skip 'public delpaths semantics require Perl 5.34+', 1
            if $] < 5.034;
        is_deeply($actual, $expected,
            "supported Perl delpaths expected output: $label");
    }
    is($codec->encode($input), $before,
        "delpaths leaves original input unchanged: $label");
    is(scalar @received, $count,
        "delpaths visits all normalized paths: $label");
    is_deeply([map { refaddr($_) } @received],
        [map { refaddr($_) } @sorted],
        "delpaths forwards original sorted path identities: $label");
    is_deeply([map { $codec->encode($_) } @sorted], \@snapshots,
        "delpaths never changes validated path arrays: $label");
}

my $no_path_input = {a=>[1,2]};
my $no_path_before = $codec->encode($no_path_input);
is_deeply(JQ::Lite::Util::_apply_delpaths($jq, $no_path_input, '[]'),
    $no_path_input, 'empty path list keeps its input');
ok(!defined JQ::Lite::Util::_apply_delpaths(
    $jq, $no_path_input, '[[]]'
), 'root deletion remains null');
is($codec->encode($no_path_input), $no_path_before,
    'root and empty path handling never mutate original input');


# The deletion walker previously copied the entire path, popped its final
# segment and traversed the remainder. The indexed walk must produce the
# same result without modifying the caller's array, including one-segment
# and empty paths (which must not enter the traversal loop).
my @walker_cases = (
    ['{"a":1,"keep":2}', '["a"]', '{"keep":2}',
        'single root object key'],
    ['{"a":{"b":1,"c":2}}', '["a","b"]', '{"a":{"c":2}}',
        'nested object property'],
    ['{"a":[10,20,30]}', '["a",1]', '{"a":[10,30]}',
        'array middle index'],
    ['{"a":[10,20,30]}', '["a",-1]', '{"a":[10,20]}',
        'negative last array index'],
    ['{"a":[{"x":1,"z":2},{"x":3}]}', '["a",0,"x"]',
        '{"a":[{"z":2},{"x":3}]}',
        'object inside array inside object'],
    ['{"a":[10,20,30]}', '["a",false]', '{"a":[20,30]}',
        'false array index'],
    ['{"a":[10,20,30]}', '["a",true]', '{"a":[10,30]}',
        'true array index'],
    ['{"":0,"other":2}', '[""]', '{"other":2}',
        'empty object key'],
    ['{"a.b":{"":1,"x":2}}', '["a.b",""]', '{"a.b":{"x":2}}',
        'literal dotted and empty keys'],
    ['{"a":{"b":1}}', '["a","missing"]', '{"a":{"b":1}}',
        'missing leaf key'],
    ['{"a":[1,2]}', '["a",7]', '{"a":[1,2]}',
        'out-of-range array member'],
    ['{"a":[1,2]}', '["a","bad"]', '{"a":[1,2]}',
        'invalid array index'],
    ['{"a":null}', '["a","x"]', '{"a":null}',
        'null intermediate scalar'],
    ['{"a":[1,null,2]}', '["a",1,"x"]', '{"a":[1,null,2]}',
        'null nested array member'],
    ['{"a":1}', '[]', '{"a":1}',
        'empty path is a no-op'],
    ['{"a":1}', '[null]', '{"a":1}',
        'undefined final key is ignored'],
    ['"scalar"', '["a"]', '"scalar"',
        'non-container root is unchanged'],
    ['{"\u65e5\u672c":{"\u8449":3,"stay":4}}',
        '["\u65e5\u672c","\u8449"]',
        '{"\u65e5\u672c":{"stay":4}}',
        'Unicode object key path'],
);
for my $case (@walker_cases) {
    my ($source_json, $path_json, $expected_json, $label) = @$case;
    my $target = $codec->decode($source_json);
    my $path = $codec->decode($path_json);
    my $path_before = $codec->encode($path);
    my $target_identity = ref($target) ? refaddr($target) : undef;

    JQ::Lite::Util::_delete_path_inplace($target, $path);

    is_deeply($target, $codec->decode($expected_json),
        "in-place deletion: $label");
    is($codec->encode($path), $path_before,
        "in-place deletion preserves path segments: $label");
    is(ref($target) ? refaddr($target) : undef, $target_identity,
        "in-place deletion preserves root identity: $label");
}

# A deep path used to allocate a temporary O(depth) segment array. A
# 97-segment path now walks the input directly, removing only its leaf.
my $deep_target = {drop=>1,keep=>2};
my @deep_segments = (('next') x 96, 'drop');
for (1 .. 96) {
    $deep_target = {next=>$deep_target};
}
my $deep_path = [@deep_segments];
my $deep_before = $codec->encode($deep_path);
my $deep_root_addr = refaddr($deep_target);
JQ::Lite::Util::_delete_path_inplace($deep_target, $deep_path);
my $deep_leaf = $deep_target;
$deep_leaf = $deep_leaf->{next} for 1 .. 96;
is_deeply($deep_leaf, {keep=>2},
    '97-segment path removes only the nested leaf');
is($codec->encode($deep_path), $deep_before,
    '97-segment path remains untouched');
is(refaddr($deep_target), $deep_root_addr,
    '97-segment deletion retains the original root object');


# The deletion sorter now builds each parent signature directly from its
# input path. Compare against the pre-change slice/map/join implementation
# to lock down exact delimiter bytes, scalar coercions and ref labels.
sub old_parent_key {
    my ($path) = @_;
    return '' if !$path || @$path < 2;
    my @segments = @$path[0 .. $#$path - 1];
    return join "\x1f",
        map { JQ::Lite::Util::_path_segment_key($_) } @segments;
}
my @prefix_cases = (
    [undef, '', 'undefined path'],
    [[], '', 'empty path'],
    [['leaf'], '', 'single segment has no parent'],
    [['a','leaf'], 'scalar:a', 'single hash parent'],
    [[0,'leaf'], 'scalar:0', 'numeric zero parent'],
    [[undef,'leaf'], 'undef', 'null parent segment'],
    [[JSON::PP::true,'leaf'], 'bool:true', 'true parent segment'],
    [[JSON::PP::false,'leaf'], 'bool:false', 'false parent segment'],
    [[{},'leaf'], 'ref:HASH', 'hash reference parent'],
    [[[],'leaf'], 'ref:ARRAY', 'array reference parent'],
    [['','leaf'], 'scalar:', 'empty-string parent'],
    [['a','b','leaf'], "scalar:a\x1fscalar:b",
        'two object parents'],
    [['a',1,'leaf'], "scalar:a\x1fscalar:1",
        'mixed string and integer parents'],
    [['a',-3,'leaf'], "scalar:a\x1fscalar:-3",
        'negative numeric parent'],
    [["a\x1fb",'leaf'], "scalar:a\x1fb",
        'embedded delimiter character remains unescaped'],
    [['a','','leaf'], "scalar:a\x1fscalar:",
        'empty intermediate key'],
    [['a.b','c','leaf'], "scalar:a.b\x1fscalar:c",
        'dots are not path separators in parent keys'],
    [["\x{65e5}\x{672c}","\x{8449}",'leaf'],
        "scalar:\x{65e5}\x{672c}\x1fscalar:\x{8449}",
        'Unicode key bytes and order'],
    [[1,undef,JSON::PP::true,{},'leaf'],
        "scalar:1\x1fundef\x1fbool:true\x1fref:HASH",
        'numeric, null, Boolean and object parent mix'],
    [[JSON::PP::false,JSON::PP::true,'leaf'],
        "bool:false\x1fbool:true",
        'both Boolean parent values'],
    [[1,'2','leaf'], "scalar:1\x1fscalar:2",
        'numeric-looking string parent'],
);
for my $case (@prefix_cases) {
    my ($path, $expected, $label) = @$case;
    my $before = $codec->encode($path);
    is(JQ::Lite::Util::_path_prefix_key($path), old_parent_key($path),
        "parent prefix exact legacy equivalence: $label");
    is(JQ::Lite::Util::_path_prefix_key($path), $expected,
        "parent prefix exact expected text: $label");
    is($codec->encode($path), $before,
        "parent prefix does not mutate path: $label");
}

# Lock down the complete deletion ordering using the original prefix
# implementation inside the reference sort, not the current helper.
sub old_parent_deletion_sort {
    return sort {
        (@$b <=> @$a)
            || (old_parent_key($a) cmp old_parent_key($b))
            || JQ::Lite::Util::_compare_path_segments(
                $b->[-1], $a->[-1]
            );
    } @_;
}
my @prefix_sort_cases = (
    ['mixed depths',
        [['z'],['a'],['a',2],['a',0],['b','c','d'],['b','c']]],
    ['array index siblings',
        [['a',0],['a',2],['a',1],['a',-1],['a','1']]],
    ['embedded delimiter and punctuation',
        [['a.b','c','x'],['a','b.c','x'],["a\x1fb",'x'],
         ['a','b','x'],['','x']]],
    ['different segment types',
        [[JSON::PP::true,'x'],[JSON::PP::false,'x'],
         [undef,'x'],[{},'x'],[[],'x']]],
    ['repeated paths',
        [['a',1],['a',1],['a',1],['a',2],['a',0]]],
    ['Unicode and nested paths',
        [["\x{65e5}\x{672c}",0,'x'],
         ["\x{65e5}\x{672c}",2,'x'],['a',3,'x'],
         ['a',1,'x'],['z']]],
    ['parent versus descendant',
        [['a'],['a','b'],['a','b','c'],['a','b','d'],
         ['a','z'],['z','x']]],
);
for my $case (@prefix_sort_cases) {
    my ($label, $paths) = @$case;
    my $before = $codec->encode($paths);
    my (@old, @new, @warnings);
    {
        local $SIG{__WARN__} = sub { push @warnings, @_ };
        @old = old_parent_deletion_sort(@$paths);
        @new = JQ::Lite::Util::_sort_paths_for_deletion(@$paths);
    }
    is_deeply(\@warnings, [],
        "parent-prefix reference sort emits no warnings: $label");
    is_deeply(\@new, \@old,
        "deletion ordering matches original parent encoding: $label");
    is_deeply([map { refaddr($_) } @new],
        [map { refaddr($_) } @old],
        "deletion sorting preserves original path identities: $label");
    is($codec->encode($paths), $before,
        "deletion sorting never mutates input: $label");
}

my $long_prefix_path = [(map { "part$_" } 0 .. 255), 'leaf'];
my $long_prefix_before = $codec->encode($long_prefix_path);
is(JQ::Lite::Util::_path_prefix_key($long_prefix_path),
    old_parent_key($long_prefix_path),
    '257-segment prefix matches original encoding');
is($codec->encode($long_prefix_path), $long_prefix_before,
    'long prefix computation does not modify input');

my @wide_prefix_paths = (
    map { ['items',$_] } 0 .. 256
);
push @wide_prefix_paths, ['z'], ['a','child'], ['z','other'];
my (@old_wide, @new_wide, @wide_prefix_warnings);
{
    local $SIG{__WARN__} = sub { push @wide_prefix_warnings, @_ };
    @old_wide = old_parent_deletion_sort(@wide_prefix_paths);
    @new_wide = JQ::Lite::Util::_sort_paths_for_deletion(@wide_prefix_paths);
}
is_deeply(\@wide_prefix_warnings, [],
    'wide parent-prefix reference sort emits no warnings');
is_deeply(\@new_wide, \@old_wide,
    '260 deletion paths retain original order');
is_deeply([map { refaddr($_) } @new_wide],
    [map { refaddr($_) } @old_wide],
    '260 deletion paths retain original references');

done_testing;
