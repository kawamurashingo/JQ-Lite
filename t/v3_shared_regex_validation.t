use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite::Util ();

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

done_testing;
