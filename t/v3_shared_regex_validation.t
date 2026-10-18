use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite::Util ();
use JQ::Lite;

ok(JQ::Lite::Util::_apply_test('Alpha', '^alpha$', 'i'),
    'test() uses case-insensitive flag');
ok(!JQ::Lite::Util::_apply_test('Alpha', '^alpha$', ''),
    'test() remains case-sensitive without flags');

is_deeply(
    JQ::Lite::Util::_apply_test(['abc', undef], '^a', ''),
    [JSON::PP::true, JSON::PP::false],
    'test() still maps arrays and returns JSON booleans for null',
);

is_deeply(
    JQ::Lite::Util::_apply_match('Abc', '(b)', 'i'),
    {
        offset => 1, length => 1, string => 'b',
        captures => [{offset => 1, length => 1, string => 'b'}],
    },
    'match() retains match offsets and capture objects',
);

is_deeply(
    JQ::Lite::Util::_apply_match(['abc', undef], '^a', ''),
    [{offset => 0, length => 1, string => 'a', captures => []}, undef],
    'match() retains array mapping and null slots',
);

for my $name (qw(test match)) {
    my $filter = $name eq 'test'
        ? \&JQ::Lite::Util::_apply_test
        : \&JQ::Lite::Util::_apply_match;

    for my $bad (
        ['[', '', 'invalid pattern'],
        ['a', 'z', 'invalid flag'],
    ) {
        my ($pattern, $flags, $label) = @$bad;
        my $ok = eval { $filter->('abc', $pattern, $flags); 1 };
        ok(!$ok, "$name() rejects $label");
        like($@, qr/\Q$name\E\(\): invalid regular expression - /,
            "$name() preserves function-specific $label error text");
    }
}


# All 16 combinations of the established imsx alphabet keep their
# independent modifier effects. Exercise both public filter callbacks with
# fixtures that only match when the corresponding single flag is enabled.
my @modifier_letters = qw(i m s x);
my @modifier_probes = (
    ['i', 'Abc', '^abc$', 0, 3, 'Abc'],
    ['m', "a\nb", '^b$', 2, 1, 'b'],
    ['s', "a\nb", 'a.b', 0, 3, "a\nb"],
    ['x', 'ab', 'a b', 0, 2, 'ab'],
);

for my $mask (0 .. 15) {
    my $flags = join '', map {
        ($mask & (1 << $_)) ? $modifier_letters[$_] : ()
    } 0 .. $#modifier_letters;

    for my $probe_index (0 .. $#modifier_probes) {
        my ($flag, $value, $pattern, $offset, $length, $string) =
            @{ $modifier_probes[$probe_index] };
        my $enabled = ($mask & (1 << $probe_index)) ? 1 : 0;
        my $label = "flags '$flags' controlling $flag";

        is_deeply(JQ::Lite::Util::_apply_test($value, $pattern, $flags),
            $enabled ? JSON::PP::true : JSON::PP::false,
            "test() $label");

        my $expected_match = $enabled
            ? {offset=>$offset, length=>$length, string=>$string,
                captures=>[]}
            : undef;
        is_deeply(JQ::Lite::Util::_apply_match($value, $pattern, $flags),
            $expected_match, "match() $label");
    }
}

# The input may contain duplicates or an arbitrary flag order. The old
# implementation canonicalized each invocation to imsx without carrying
# modifiers into the next call.
for my $case (
    ['ii', 'i'],
    ['mimii', 'im'],
    ['xim', 'imx'],
    ['smxxii', 'imsx'],
    ['sxmi', 'imsx'],
    ['mm', 'm'],
    ['ss', 's'],
    ['xx', 'x'],
) {
    my ($raw, $canonical) = @$case;
    my ($got, $got_error) = JQ::Lite::Util::_build_regex(
        'a.b', $raw
    );
    my ($reference, $ref_error) = JQ::Lite::Util::_build_regex(
        'a.b', $canonical
    );
    ok(defined($got) && !defined($got_error),
        "duplicate/order '$raw' compiles");
    ok(defined($reference) && !defined($ref_error),
        "canonical '$canonical' compiles");
    is("$got", "$reference",
        "flags '$raw' canonicalize exactly to '$canonical'");
}

# Invalid flags still fail at the first offending character with the
# function-specific error prefix, even after successful invocations.
for my $case (
    ['z','z'],
    ['g','g'],
    ['I','I'],
    ['imq','q'],
    ['i m',' '],
) {
    my ($flags, $offender) = @$case;
    for my $name (qw(test match)) {
        my $call = $name eq 'test'
            ? \&JQ::Lite::Util::_apply_test
            : \&JQ::Lite::Util::_apply_match;
        my $ok = eval { $call->('Abc', '^abc$', $flags); 1 };
        ok(!$ok, "$name() rejects '$flags'");
        like("$@", qr/\Q$name\E\(\): invalid regular expression - unknown regex flag '\Q$offender\E'/,
            "$name() retains first invalid flag '$offender' error");
    }
}

is_deeply(JQ::Lite::Util::_apply_test(
    ['Abc', undef, JSON::PP::true], '^a', 'i'
), [JSON::PP::true, JSON::PP::false, JSON::PP::false],
    'shared regex flags still map arrays, null and booleans');

my $jq = JQ::Lite->new;
is_deeply([ $jq->run_query('["Alpha","beta"]',
    '.[] | test("^a"; "i")') ],
    [JSON::PP::true, JSON::PP::false],
    'public test flag handling preserves multi-value streams');
is_deeply([ $jq->run_query('"alpha\nbeta"',
    'match("^beta"; "m")') ],
    [{offset=>6,length=>4,string=>'beta',captures=>[]}],
    'public match flag handling preserves multiline captures');
is_deeply([ $jq->run_query('"Alpha"',
    'test("^a"; "i"), test("^a")') ],
    [JSON::PP::true, JSON::PP::false],
    'repeated public regex calls do not leak flags');

done_testing;
