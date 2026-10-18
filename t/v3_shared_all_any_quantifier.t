use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Util ();
use Scalar::Util qw(refaddr);

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


# Reference the exact old copy/grep quantifier logic. This guards both the
# array-iteration semantics and all()/any() evaluation of multi-value child
# streams while the implementation avoids the input-array copy and scans
# each child's results only up to the decisive Boolean value.
sub legacy_quantifier {
    my ($self, $value, $expr, $all) = @_;
    my $is_array = ref $value eq 'ARRAY';
    my @items = $is_array ? @$value : ($value);

    return $all ? JSON::PP::true : JSON::PP::false
        if $is_array && !@items;

    for my $item (@items) {
        my @evaluated = defined $expr
            ? $self->run_query(JQ::Lite::Util::_encode_json($item), $expr)
            : ($item);

        if ($all) {
            return JSON::PP::false unless @evaluated;
            return JSON::PP::false
                if grep { !JQ::Lite::Util::_is_truthy($_) } @evaluated;
        }
        else {
            return JSON::PP::true
                if grep { JQ::Lite::Util::_is_truthy($_) } @evaluated;
        }
    }

    return $all ? JSON::PP::true : JSON::PP::false;
}

my $codec = JSON::PP->new->allow_nonref->canonical;
my @regression = (
    ['[]', undef, 1, 1, 'empty all array'],
    ['[]', undef, 0, 0, 'empty any array'],
    ['[true,true]', undef, 1, 1, 'all true'],
    ['[true,false,true]', undef, 1, 0, 'middle false for all'],
    ['[false,false,true]', undef, 0, 1, 'last true for any'],
    ['[true,false,false]', undef, 0, 1, 'first true for any'],
    ['[false,false]', undef, 0, 0, 'any all false'],
    ['[1,2,3]', undef, 1, 1, 'all nonzero numbers'],
    ['[0,1]', undef, 1, 0, 'numeric zero is false'],
    ['["","x"]', undef, 0, 1, 'empty and nonempty text'],
    ['[[],{}]', undef, 1, 0, 'empty containers count false'],
    ['[[1],{"x":2}]', undef, 1, 1, 'nonempty containers count true'],
    ['null', undef, 1, 0, 'null scalar all'],
    ['null', undef, 0, 0, 'null scalar any'],
    ['true', undef, 1, 1, 'Boolean scalar all'],
    ['false', undef, 0, 0, 'Boolean scalar any'],
    ['[{"ok":true},{"ok":false}]', '.ok', 1, 0,
        'all over object properties'],
    ['[{"ok":false},{"ok":true}]', '.ok', 0, 1,
        'any over object properties'],
    ['[{"flags":[true,false,true]}]', '.flags[]', 1, 0,
        'all over multiple outputs'],
    ['[{"flags":[false,true,false]}]', '.flags[]', 0, 1,
        'any over multiple outputs'],
    ['[true,false]', 'empty', 1, 0, 'all(empty) is false'],
    ['[true,false]', 'empty', 0, 0, 'any(empty) is false'],
    ['[{"flags":[true,true]},{"flags":[true,false]}]',
        '.flags[]', 1, 0, 'all across multiple multi-output objects'],
    ['[{"flags":[false,false]},{"flags":[false,true]}]',
        '.flags[]', 0, 1, 'any across multiple multi-output objects'],
);
for my $case (@regression) {
    my ($raw, $expr, $all, $expected, $label) = @$case;
    my $value = $codec->decode($raw);
    my $before_json = $codec->encode($value);
    my $legacy = legacy_quantifier($jq, $value, $expr, $all);
    my $got = JQ::Lite::Util::_apply_quantifier($jq, $value, $expr, $all);
    is($got ? 1 : 0, $legacy ? 1 : 0,
        "quantifier matches legacy truth value: $label");
    is($got ? 1 : 0, $expected,
        "quantifier expected truth value: $label");
    ok(JSON::PP::is_bool($got),
        "quantifier preserves JSON Boolean type: $label");
    is($codec->encode($value), $before_json,
        "quantifier never modifies caller data: $label");
}

# The optimized implementation stops inspecting multi-output child values
# after the first answer; the old scalar grep checked the entire list.
my $original_truthy = \&JQ::Lite::Util::_is_truthy;
for my $case (
    [1, [JSON::PP::true, JSON::PP::false, JSON::PP::true],
        0, 2, 'all stops at first false child result'],
    [0, [JSON::PP::false, JSON::PP::true, JSON::PP::false],
        1, 2, 'any stops at first true child result'],
) {
    my ($all, $flags, $wanted, $number_checked, $label) = @$case;
    my $checked = 0;
    my $got;
    {
        no warnings 'redefine';
        local *JQ::Lite::Util::_is_truthy = sub {
            $checked++;
            return $original_truthy->(@_);
        };
        $got = JQ::Lite::Util::_apply_quantifier(
            $jq, [{ flags => $flags }], '.flags[]', $all
        );
    }
    is($got ? 1 : 0, $wanted, "$label: result");
    is($checked, $number_checked, "$label: stops checking later values");
}

my $wide = [(JSON::PP::true) x 256, JSON::PP::false];
my $wide_id = refaddr($wide);
my $wide_json = $codec->encode($wide);
is(JQ::Lite::Util::_apply_all($jq, $wide) ? 1 : 0, 0,
    'all stops on the final false of a 257-element array');
is(JQ::Lite::Util::_apply_any($jq, $wide) ? 1 : 0, 1,
    'any accepts the first true of a 257-element array');
is(refaddr($wide), $wide_id, 'large caller array identity unchanged');
is($codec->encode($wide), $wide_json, 'large caller array is not mutated');

check('[{"flags":[true,false]},{"flags":[true,true]}]',
    'any(.flags[])', [1], 'public any with several truth results');
check('[{"flags":[true,true]},{"flags":[true,false]}]',
    'all(.flags[])', [0], 'public all sees later false result');
check('[[false,true],[true,true]]', '.[] | any', [1,1],
    'public any keeps successive stream results ordered');
check('[[true,true],[true,false]]', '.[] | all', [1,0],
    'public all keeps successive stream results ordered');

done_testing();
