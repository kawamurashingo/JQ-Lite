use strict;
use warnings;
use Test::More;
use JSON::PP qw(encode_json);
use JQ::Lite;

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

done_testing();
