use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Util ();
use Scalar::Util qw(refaddr);

my $jq = JQ::Lite->new;

# Both path operations intentionally use the same coercion and negative-index
# normalization. A get bounds-checks; a set may extend the array afterwards.
my @index_cases = (
    [0, 3, 0, 'first position'],
    [-1, 3, 2, 'negative last position'],
    [-3, 3, 0, 'negative first position'],
    [-4, 3, undef, 'negative index before start'],
    [4, 3, 4, 'future positive index is not clamped'],
    ['1', 3, 1, 'numeric string retained as v2 extension'],
    ['bad', 3, undef, 'nonnumeric string is not an index'],
    [JSON::PP::false, 3, 0, 'JSON false maps to zero'],
    [JSON::PP::true, 3, 1, 'JSON true maps to one'],
    [undef, 3, undef, 'JSON null is not an index'],
    [[], 3, undef, 'container is not an index'],
);
for my $case (@index_cases) {
    my ($segment, $length, $expected, $label) = @$case;
    is(JQ::Lite::Util::_normalize_array_index_segment($segment, $length),
        $expected, "shared get/set segment normalizer: $label");
}

sub results {
    my ($json, $filter) = @_;
    return [$jq->run_query($json, $filter)];
}

my $array = '[10,20,30]';
is_deeply(results($array, 'getpath([0])'), [10],
    'getpath reads the first array element');
is_deeply(results($array, 'getpath([-1])'), [30],
    'getpath reads a negative index');
is_deeply(results($array, 'getpath([5])'), [undef],
    'out-of-bounds getpath returns one null');
is_deeply(results($array, 'getpath([-4])'), [undef],
    'negative out-of-bounds getpath returns one null');
is_deeply(results($array, 'setpath([-1]; 77)'), [[10,20,77]],
    'setpath replaces the last array member');
is_deeply(results($array, 'setpath([4]; 77)'), [[10,20,30,undef,77]],
    'setpath grows the array with null padding');
is_deeply(results($array, 'setpath([0]; 0)'), [[0,20,30]],
    'setpath replaces the first array member');
is_deeply(results($array, 'setpath([-4]; 77)'), [[10,20,30]],
    'setpath negative out-of-bounds leaves array unchanged');

# Compatibility extensions inherited from v2, not jq 1.7 promises:
# jq rejects boolean path elements, unlike this implementation.
is_deeply(results($array, 'getpath([false])'), [10],
    'v2 boolean-false index extension remains');
is_deeply(results($array, 'getpath([true])'), [20],
    'v2 boolean-true index extension remains');
is_deeply(results($array, 'setpath([true]; 77)'), [[10,77,30]],
    'v2 boolean index update extension remains');
is_deeply(results($array, 'getpath(["1"])'), [20],
    'v2 numeric-string path extension remains');

is_deeply(results($array, 'getpath([-3])'), [10],
    'negative index at first array slot remains valid');
is_deeply(results($array, 'setpath([-3]; 77)'), [[77,20,30]],
    'setpath writes the first slot with equivalent negative index');
is_deeply(results($array, 'setpath(["1"]; 77)'), [[10,77,30]],
    'numeric-looking string segment remains valid in setpath');
is_deeply(results('[[10,20],[30,40]]', 'getpath([-1,-2])'), [30],
    'nested negative indices retain getpath traversal');
is_deeply(results('[[10,20],[30,40]]', 'setpath([-1,-2]; 7)'),
    [[[10,20],[7,40]]], 'nested negative indices retain setpath update');
is_deeply(results('[10,20,30]', 'getpath([-5])'), [undef],
    'out-of-range negative index still yields null on get');
is_deeply(results('[10,20,30]', 'setpath([-5]; 7)'), [[10,20,30]],
    'out-of-range negative index is ignored by set');


# _apply_setpath used to copy each validated path at the call boundary.
# _set_value_at_path destructures its own per-level segments and never
# modifies the supplied array. Spy on the resolved paths and outer setter
# calls, comparing results with an exact old-copy caller replay.
my $codec = JSON::PP->new->allow_nonref->canonical;
my $actual_set_value = \&JQ::Lite::Util::_set_value_at_path;
my $actual_resolve_paths = \&JQ::Lite::Util::_resolve_paths_from_expr;
my @setpath_cases = (
    ['{"a":1,"b":2}', '["a"]', '99', '{"a":99,"b":2}',
        'single root object property'],
    ['{"a":{"b":1,"c":2}}', '["a","b"]', '7',
        '{"a":{"b":7,"c":2}}', 'two-level object path'],
    ['[10,20,30]', '[1]', '77', '[10,77,30]',
        'array middle index'],
    ['{"items":[{"x":1}]}', '["items",1,"x"]', '"new"',
        '{"items":[{"x":1},{"x":"new"}]}',
        'missing nested array element is created'],
    ['{"a":[10,20,30]}', '["a",-1]', '77',
        '{"a":[10,20,77]}', 'negative array index'],
    ['{"a":[]}', '["a",2]', '8',
        '{"a":[null,null,8]}', 'array expansion and padding'],
    ['{"a":1,"b":2}', '[]', '{"fresh":true}',
        '{"fresh":true}', 'empty path replaces root'],
    ['{"a":1,"b":2}', '[["a"],["b"]]', '0',
        '{"a":0,"b":0}', 'multiple validated literal paths'],
    ['{"a":[1,2],"b":3}', '[["a",1],["b"]]', '9',
        '{"a":[1,9],"b":9}', 'mixed-depth multi-path setter'],
    ['{"a":{"b":1},"c":2}', '["a","d"]', 'null',
        '{"a":{"b":1,"d":null},"c":2}', 'null replacement in nested object'],
    ['{"a":[1,2,3]}', '["a",true]', '9',
        '{"a":[1,9,3]}', 'v2 Boolean array-index extension'],
    ['{"a":1}', '["missing","nested"]', '5',
        '{"a":1,"missing":{"nested":5}}',
        'missing hash containers are constructed'],
    ['{"a":1}', 'paths', '0',
        '{"a":0}', 'computed paths filter'],
    ['{"a":1}', '[[]]', '{"q":2}',
        '{"q":2}', 'empty path in multi-path literal'],
);
for my $case (@setpath_cases) {
    my ($raw, $path_expr, $value_expr, $expected_json, $label) = @$case;
    my $input = $codec->decode($raw);
    my $before = $codec->encode($input);
    my (@resolved, @passed, $paths_before);
    my ($actual, $ok, $failure);
    {
        no warnings 'redefine';
        local *JQ::Lite::Util::_resolve_paths_from_expr = sub {
            my @paths = $actual_resolve_paths->(@_);
            @resolved = @paths;
            $paths_before = $codec->encode(\@paths);
            return @paths;
        };
        my $depth = 0;
        local *JQ::Lite::Util::_set_value_at_path = sub {
            push @passed, $_[1] unless $depth;
            $depth++;
            my $result = $actual_set_value->(@_);
            $depth--;
            return $result;
        };
        $ok = eval {
            $actual = JQ::Lite::Util::_apply_setpath(
                $jq, $input, $path_expr, $value_expr
            );
            1;
        };
        $failure = $@;
    }
    ok($ok, "setpath call succeeds: $label") or diag($failure);

    # Replay the exact former caller boundary by cloning each validated
    # path before passing it to the same unchanged setter.
    my $old = $codec->decode($raw);
    my $replacement = JQ::Lite::Util::_evaluate_setpath_value(
        $jq, $old, $value_expr
    );
    for my $path (@resolved) {
        $old = $actual_set_value->($old, [@$path], $replacement);
    }
    is_deeply($actual, $old,
        "setpath result equals previous copied-path call: $label");
    is_deeply($actual, $codec->decode($expected_json),
        "setpath retains expected result: $label");
    is_deeply([map { refaddr($_) } @passed],
        [map { refaddr($_) } @resolved],
        "setpath receives the original validated path refs: $label");
    is($codec->encode(\@resolved), $paths_before,
        "setpath leaves every validated path untouched: $label");
    is($codec->encode($input), $before,
        "setpath leaves source data unchanged: $label");
}

is_deeply(results('[{"a":1},{"a":2}]',
    '.[] | setpath(["a"]; 7)'), [{a=>7},{a=>7}],
    'setpath still preserves ordered multi-root output');
is_deeply(results('{"a":1}', 'empty | setpath(["a"]; 7)'),
    [], 'setpath does not revive an empty upstream');
is_deeply(results('{"a":1}', 'setpath(["a"]; {"x":[1,2]})'),
    [{a=>{x=>[1,2]}}],
    'setpath retains replacement object cloning semantics');
is_deeply(results('[10,20,30]', 'setpath([-2]; 0)'),
    [[10,0,30]], 'public setpath retains negative array indexing');


# Before the indexed recursion, each nested setter call destructured the
# remaining path into @rest. Compare its exact original implementation with
# the new offset-based walker on diverse paths and preserve source isolation.
sub legacy_set_value_at_path {
    my ($current, $path, $replacement) = @_;

    return JQ::Lite::Util::_deep_clone($replacement) unless @$path;
    my ($segment, @rest) = @$path;

    if (ref $current eq 'HASH') {
        my $key = JQ::Lite::Util::_coerce_hash_key($segment);
        return $current unless defined $key;

        my %copy = %$current;
        if (@rest) {
            my $next_value = exists $copy{$key}
                ? $copy{$key}
                : JQ::Lite::Util::_guess_container_for_segment($rest[0]);
            $copy{$key} = legacy_set_value_at_path(
                $next_value, \@rest, $replacement
            );
        }
        else {
            $copy{$key} = JQ::Lite::Util::_deep_clone($replacement);
        }
        return \%copy;
    }

    if (ref $current eq 'ARRAY') {
        my $index = JQ::Lite::Util::_normalize_array_index_segment(
            $segment, scalar @$current
        );
        return $current unless defined $index;

        my @copy = @$current;
        JQ::Lite::Util::_ensure_array_length(\@copy, $index);
        if (@rest) {
            my $next_value = defined $copy[$index]
                ? $copy[$index]
                : JQ::Lite::Util::_guess_container_for_segment($rest[0]);
            $copy[$index] = legacy_set_value_at_path(
                $next_value, \@rest, $replacement
            );
        }
        else {
            $copy[$index] = JQ::Lite::Util::_deep_clone($replacement);
        }
        return \@copy;
    }

    my $container = JQ::Lite::Util::_guess_container_for_segment($segment);
    return legacy_set_value_at_path($container, $path, $replacement);
}

my @indexed_set_cases = (
    ['{"a":1,"b":2}', '["a"]', '9',
        '{"a":9,"b":2}', 'one object segment'],
    ['{"a":{"b":1,"c":2}}', '["a","b"]', '7',
        '{"a":{"b":7,"c":2}}', 'nested object write'],
    ['{"items":[{"x":1},{"x":2}]}', '["items",1,"x"]', '3',
        '{"items":[{"x":1},{"x":3}]}', 'object-array-object nesting'],
    ['[10,20,30]', '[1]', '0',
        '[10,0,30]', 'array middle member'],
    ['[10,20,30]', '[-1]', '0',
        '[10,20,0]', 'negative final array member'],
    ['[10,20,30]', '[-4]', '0',
        '[10,20,30]', 'out-of-range negative index ignored'],
    ['[10,20,30]', '[true]', '0',
        '[10,0,30]', 'boolean index true v2 extension'],
    ['[10,20,30]', '[false]', '0',
        '[0,20,30]', 'boolean index false v2 extension'],
    ['{"a":[]}', '["a",2]', '8',
        '{"a":[null,null,8]}', 'padded array growth'],
    ['{"a":1}', '["new","branch",0]', '5',
        '{"a":1,"new":{"branch":[5]}}', 'missing mixed containers'],
    ['{"a":null}', '["a","b"]', '4',
        '{"a":{"b":4}}', 'null intermediate container'],
    ['{"a":1}', '[]', '{"fresh":[1,2]}',
        '{"fresh":[1,2]}', 'empty path replaces root'],
    ['null', '["a"]', '8',
        '{"a":8}', 'null root creates object'],
    ['3', '[0]', '8',
        '[8]', 'numeric root creates array'],
    ['{"":{"a.b":1}}', '["","a.b"]', '12',
        '{"":{"a.b":12}}', 'empty and dotted object keys'],
    ['{"a":{"x":1}}', '["a","new"]', '{"nested":[1]}',
        '{"a":{"x":1,"new":{"nested":[1]}}}',
        'compound replacement'],
    ['{"a":1}', '[null]', '8',
        '{"a":1}', 'undefined object key remains ignored'],
    ['{"a":[1,2]}', '["a","bad"]', '8',
        '{"a":[1,2]}', 'invalid array index remains ignored'],
    ['{"\u65e5\u672c":{"\u8449":1}}',
        '["\u65e5\u672c","\u8449"]', '6',
        '{"\u65e5\u672c":{"\u8449":6}}',
        'Unicode nested object keys'],
    ['{"data":[[1,2],[3,4]]}', '["data",-1,-2]', '11',
        '{"data":[[1,2],[11,4]]}', 'negative nested array indices'],
);
for my $case (@indexed_set_cases) {
    my ($raw, $raw_path, $raw_replacement, $raw_expected, $label) = @$case;
    my $value = $codec->decode($raw);
    my $path = $codec->decode($raw_path);
    my $replacement = $codec->decode($raw_replacement);
    my $value_before = $codec->encode($value);
    my $path_before = $codec->encode($path);
    my $replacement_before = $codec->encode($replacement);

    my $legacy = legacy_set_value_at_path($value, $path, $replacement);
    my $actual = JQ::Lite::Util::_set_value_at_path(
        $value, $path, $replacement
    );
    is_deeply($actual, $legacy,
        "indexed setter matches previous recursive tails: $label");
    is_deeply($actual, $codec->decode($raw_expected),
        "indexed setter retains expected value: $label");
    is($codec->encode($value), $value_before,
        "indexed setter leaves source input untouched: $label");
    is($codec->encode($path), $path_before,
        "indexed setter leaves supplied path unchanged: $label");
    is($codec->encode($replacement), $replacement_before,
        "indexed setter leaves replacement unchanged: $label");
}

# Watch recursion itself. All nested calls must use the SAME path array
# and advance the offset, rather than construct shorter segment arrays.
my $real_indexed_setter = \&JQ::Lite::Util::_set_value_at_path;
my $spy_path = ['a','b',1];
my (@seen_path_ids, @seen_offsets);
my $spy_result;
{
    no warnings 'redefine';
    local *JQ::Lite::Util::_set_value_at_path = sub {
        push @seen_path_ids, refaddr($_[1]);
        push @seen_offsets, defined $_[3] ? $_[3] : 0;
        return $real_indexed_setter->(@_);
    };
    $spy_result = JQ::Lite::Util::_set_value_at_path(
        {a=>{b=>[1,2]}}, $spy_path, 9
    );
}
is_deeply($spy_result, {a=>{b=>[1,9]}},
    'recursion instrumentation retains nested setter result');
is_deeply(\@seen_offsets, [0,1,2],
    'indexed recursion consumes segments without slicing tails');
is(scalar(keys %{ { map { $_ => 1 } @seen_path_ids } }), 1,
    'every nested setter call reuses the same path reference');

# Stress a deep path that formerly allocated one shorter @rest per level.
my $deep_set_source = {value=>1, keep=>2};
my @deep_set_segments = ((map { 'next' } 1 .. 80), 'value');
for (1 .. 80) {
    $deep_set_source = { next => $deep_set_source };
}
my $deep_set_path = [@deep_set_segments];
my $deep_set_before = $codec->encode($deep_set_source);
my $deep_set_path_before = $codec->encode($deep_set_path);
my $deep_legacy = legacy_set_value_at_path(
    $deep_set_source, $deep_set_path, 99
);
my $deep_indexed = JQ::Lite::Util::_set_value_at_path(
    $deep_set_source, $deep_set_path, 99
);
is_deeply($deep_indexed, $deep_legacy,
    '81-segment setter matches old recursive tails');
my $deep_set_leaf = $deep_indexed;
$deep_set_leaf = $deep_set_leaf->{next} for 1 .. 80;
is_deeply($deep_set_leaf, {value=>99,keep=>2},
    '81-segment setter replaces only the deepest leaf');
is($codec->encode($deep_set_source), $deep_set_before,
    '81-segment setter does not mutate input data');
is($codec->encode($deep_set_path), $deep_set_path_before,
    '81-segment setter does not change its path');

is_deeply(results('{"a":{"b":[1,2]}}',
    'setpath(["a","b",1]; 9)'), [{a=>{b=>[1,9]}}],
    'public setpath retains nested index updates');
is_deeply(results('{"a":null}', 'setpath(["a","new"]; 5)'),
    [{a=>{new=>5}}], 'public setpath retains null autovivification');
is_deeply(results('[10,20,30]', 'setpath([-1]; 8)'),
    [[10,20,8]], 'public setpath retains negative indices');
is_deeply(results('[1,2]', 'empty | setpath([0]; 3)'),
    [], 'public setpath preserves empty upstream streams');

done_testing;
