use strict;
use warnings;
use Test::More;
use JSON::PP qw(encode_json);
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;

sub apply_query {
    my ($data, $query) = @_;
    my $json = encode_json($data);
    my @results = $jq->run_query($json, $query);
    return @results;
}

subtest 'update existing value' => sub {
    my $data = { spec => { replicas => 1 } };
    my ($result) = apply_query($data, '.spec.replicas = 3');

    is($result->{spec}{replicas}, 3, 'replicas updated to 3');
};

subtest 'create new nested key' => sub {
    my $data = { spec => {} };
    my ($result) = apply_query($data, '.spec.version = "1.2.3"');

    is($result->{spec}{version}, '1.2.3', 'version key created');
};

subtest 'assign from another path' => sub {
    my $data = { spec => { replicas => 2 } };
    my ($result) = apply_query($data, '.spec.copy = .spec.replicas');

    is($result->{spec}{copy}, 2, 'value copied from other path');
};

subtest 'update array element' => sub {
    my $data = { items => [ { value => 1 }, { value => 2 } ] };
    my ($result) = apply_query($data, '.items[1].value = 5');

    is($result->{items}[1]{value}, 5, 'second item updated');
    is($result->{items}[0]{value}, 1, 'first item untouched');
};

subtest 'assign within root array' => sub {
    my $data = [ { value => 1 }, { value => 2 } ];
    my ($result) = apply_query($data, '.[0].value = 9');

    is($result->[0]{value}, 9, 'first element updated');
};

subtest 'assignment from variable reference' => sub {
    my $jq_with_var = JQ::Lite->new(vars => { greeting => 'hello' });
    my $json       = encode_json({});

    my ($result) = $jq_with_var->run_query($json, '.hello = $greeting');

    is($result->{hello}, 'hello', 'variable reference resolved in assignment RHS');
};

subtest 'assign null literal' => sub {
    my $data = { spec => { replicas => 4 } };
    my ($result) = apply_query($data, '.spec.replicas = null');

    ok(!defined $result->{spec}{replicas}, 'value set to null');
};

subtest 'assign single-quoted strings' => sub {
    my $data = { spec => {} };
    my ($simple) = apply_query($data, ".spec.label = 'release'");

    is($simple->{spec}{label}, 'release', 'single-quoted literal stored as string');

    my ($escaped) = apply_query($data, ".spec.label = 'O\\'Reilly'");

    is($escaped->{spec}{label}, "O'Reilly", 'single-quoted literal unescapes embedded quotes');
};

subtest 'compound assignments on numbers' => sub {
    subtest 'addition assignment' => sub {
        my $data = { spec => { count => 2 } };
        my ($result) = apply_query($data, '.spec.count += 3');

        is($result->{spec}{count}, 5, 'count increased by 3');
    };

    subtest 'subtraction assignment' => sub {
        my $data = { spec => { count => 10 } };
        my ($result) = apply_query($data, '.spec.count -= 4');

        is($result->{spec}{count}, 6, 'count decreased by 4');
    };

    subtest 'multiplication assignment' => sub {
        my $data = { spec => { factor => 3 } };
        my ($result) = apply_query($data, '.spec.factor *= 5');

        is($result->{spec}{factor}, 15, 'factor multiplied by 5');
    };

    subtest 'division assignment' => sub {
        my $data = { spec => { ratio => 20 } };
        my ($result) = apply_query($data, '.spec.ratio /= 4');

        is($result->{spec}{ratio}, 5, 'ratio divided by 4');
    };

    subtest 'addition assignment on missing key initializes value' => sub {
        my $data = { spec => {} };
        my ($result) = apply_query($data, '.spec.count += 4');

        is($result->{spec}{count}, 4, 'missing count treated as zero');
    };

    subtest 'division assignment by zero leaves value unchanged' => sub {
        my $data = { spec => { ratio => 10 } };
        my ($result) = apply_query($data, '.spec.ratio /= 0');

        is($result->{spec}{ratio}, 10, 'division by zero ignored');
    };
};


# A compound assignment only coerces the old leaf to a number. JSON
# cloning that leaf is unnecessary, including for arrays/objects that the
# existing conversion rejects without changing the original value.
subtest 'compound numeric coercion keeps scalar and container contracts' => sub {
    my @cases = (
        [{ n => undef }, '.n += 5', { n => 5 },
            'missing arithmetic value from null'],
        [{ n => JSON::PP::true }, '.n += 2', { n => 3 },
            'boolean true coerces to one'],
        [{ n => JSON::PP::false }, '.n -= 2', { n => -2 },
            'boolean false coerces to zero'],
        [{ n => '12' }, '.n /= 3', { n => 4 },
            'numeric-looking string remains numeric'],
        [{ n => 2 }, '.n *= 0', { n => 0 },
            'multiply by zero'],
        [{ n => 0 }, '.n /= 0', { n => 0 },
            'division by zero does not mutate value'],
        [{ n => '12' }, '.n /= 0', { n => '12' },
            'zero division retains numeric-looking string'],
        [{ n => 'not-a-number' }, '.n += 4', { n => 'not-a-number' },
            'nonnumeric string passthrough'],
        [{ n => [1,2] }, '.n *= 3', { n => [1,2] },
            'array old value remains unchanged'],
        [{ n => { inner => 1 } }, '.n -= 2',
            { n => { inner => 1 } },
            'object old value remains unchanged'],
        [{ group => [{ n => 4 }, { n => 10 }] },
            '.group[1].n -= 3',
            { group => [{ n => 4 }, { n => 7 }] },
            'nested object under indexed array'],
        [{ group => [{ n => 4 }, { n => 10 }] },
            '.group[0].n *= 3',
            { group => [{ n => 12 }, { n => 10 }] },
            'first indexed array element'],
        [[1,2,3], '.[-1] *= 4', [1,2,12],
            'negative root array index'],
    );
    for my $case (@cases) {
        my ($input, $query, $expected, $label) = @$case;
        my $before = encode_json($input);
        my @result = apply_query($input, $query);
        is_deeply(\@result, [$expected], "$label: result unchanged");
        is(encode_json($input), $before, "$label: source untouched");
    }

    # Numeric conversion of an SV in place can change how JSON::PP
    # encodes a numeric-looking string. The local scalar copy above must
    # protect the original leaf on a no-op compound assignment.
    my ($unchanged_string) = apply_query({ n => '12' }, '.n /= 0');
    is(encode_json($unchanged_string), '{"n":"12"}',
        'division-by-zero leaves numeric-looking string JSON quoted');
};


# _get_path_value and _set_path_value share the parsed-segment loop.
# Retain direct internal contracts for empty/missing paths, negative array
# indexes, mixed key/index paths, and early exits on invalid containers.
my $path_fixture = {
    outer => [
        { inner => { leaf => 9 } },
        { inner => { leaf => JSON::PP::false } },
    ],
    text => 'raw',
    null => undef,
};
my $path_before = encode_json($path_fixture);
my @get_segment_cases = (
    ['outer[0].inner.leaf', 9, 'first mixed path'],
    ['outer[1].inner.leaf', JSON::PP::false, 'JSON false leaf'],
    ['outer[-1].inner.leaf', JSON::PP::false, 'negative last array index'],
    ['.outer[0].inner.leaf', 9, 'leading dot'],
    ['outer[0].inner', { leaf => 9 }, 'object leaf'],
    ['outer[2].inner.leaf', undef, 'out of range index'],
    ['outer[-3].inner.leaf', undef, 'negative out of range index'],
    ['outer[0].missing.leaf', undef, 'missing intermediate object key'],
    ['outer[0].inner.missing', undef, 'missing final object key'],
    ['outer[0].inner.leaf.child', undef, 'scalar intermediate'],
    ['text.child', undef, 'scalar root child'],
    ['null.child', undef, 'null intermediate'],
    ['outer[0][0]', undef, 'object cannot be indexed numerically'],
    ['', undef, 'empty path'],
    [undef, undef, 'undefined path'],
);
for my $case (@get_segment_cases) {
    my ($path, $expected, $label) = @$case;
    is_deeply(JQ::Lite::Util::_get_path_value($path_fixture, $path),
        $expected, "indexed-path getter: $label");
}
is(encode_json($path_fixture), $path_before,
    'getter leaves the original container and JSON types unchanged');

my @set_segment_cases = (
    [{}, 'meta.flag', JSON::PP::true,
        { meta => { flag => JSON::PP::true } },
        'create nested object fields'],
    [{ meta => undef }, 'meta.flag', 7,
        { meta => { flag => 7 } }, 'replace null intermediate'],
    [{ meta => { flag => 1, keep => 2 } }, 'meta.flag', 9,
        { meta => { flag => 9, keep => 2 } },
        'update leaf and retain siblings'],
    [{}, 'entries[0].name', 'a',
        { entries => [{ name => 'a' }] }, 'create nested array'],
    [{ entries => [] }, 'entries[2].name', 'last',
        { entries => [undef, undef, { name => 'last' }] },
        'extend array with null slots'],
    [{ entries => [{ name => 'a' }, { name => 'b' }] },
        'entries[-1].name', 'last',
        { entries => [{ name => 'a' }, { name => 'last' }] },
        'negative index updates last array entry'],
    [{ entries => [{ name => 'a' }, { name => 'b' }] },
        'entries[-3].name', 'invalid',
        { entries => [{ name => 'a' }, { name => 'b' }] },
        'too negative index leaves array unchanged'],
    [{ entries => [{ name => 'a' }] }, 'entries[0].name', undef,
        { entries => [{ name => undef }] }, 'write explicit JSON null'],
    [{ plain => 2 }, 'plain.child', 7,
        { plain => 2 }, 'do not replace numeric intermediate'],
    [{ entries => {} }, 'entries[0]', 8,
        { entries => {} }, 'do not index object with array segment'],
    [[], '[0].value', 3, [{ value => 3 }],
        'root array segment'],
    [{}, '', 5, {}, 'empty path leaves source unchanged'],
);
for my $case (@set_segment_cases) {
    my ($input, $path, $value, $expected, $label) = @$case;
    JQ::Lite::Util::_set_path_value($input, $path, $value);
    is_deeply($input, $expected, "indexed-path setter: $label");
}

# Deeply nested key paths should traverse every segment without generating
# a range, both when creating a leaf and reading it back.
my $deep_root = {};
my $deep_path = join '.', map { "level$_" } 0 .. 95;
JQ::Lite::Util::_set_path_value($deep_root, $deep_path, 42);
is(JQ::Lite::Util::_get_path_value($deep_root, $deep_path), 42,
    '96-segment setter/getter roundtrip');
is_deeply(JQ::Lite::Util::_get_path_value($deep_root, $deep_path . '.absent'),
    undef, 'deep path early exit on missing child');

# The public assignment entry point still uses these internal path
# walkers without mutating the user-provided source.
my @assignment_walk_cases = (
    [{ group => [{ n => 2 }, { n => 4 }] },
        '.group[1].n += 3',
        { group => [{ n => 2 }, { n => 7 }] },
        'compound assignment to nested indexed leaf'],
    [{ group => [{ n => 2 }, { n => 4 }] },
        '.group[0].n = 11',
        { group => [{ n => 11 }, { n => 4 }] },
        'plain assignment to first indexed leaf'],
    [{ group => [{ n => 2 }, { n => 4 }] },
        '.group[-1].n *= 2',
        { group => [{ n => 2 }, { n => 8 }] },
        'negative array index in compound assignment'],
    [{ root => { a => { b => 1 } } },
        '.root.a.b += 1',
        { root => { a => { b => 2 } } },
        'nested object compound assignment'],
    [{ root => { a => 1 } }, '.root.a = null',
        { root => { a => undef } },
        'assign explicit null leaf'],
);
for my $case (@assignment_walk_cases) {
    my ($source, $query, $expected, $label) = @$case;
    my $original = encode_json($source);
    is_deeply([apply_query($source, $query)], [$expected],
        "public indexed-path assignment: $label");
    is(encode_json($source), $original,
        "public assignment does not mutate original source: $label");
}

done_testing();
