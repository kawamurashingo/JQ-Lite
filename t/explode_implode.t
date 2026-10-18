use strict;
use warnings;
use Test::More;
use JSON::PP ();
use Scalar::Util qw(refaddr);
use JQ::Lite::Util ();
use JQ::Lite::Builtin ();
use JQ::Lite;

my $json = q({
  "word": "Perl",
  "words": ["Hi", "JSON", null, {"skip": true}],
  "codes": [80, 101, 114, 108],
  "nested": [[65, 66], [67, 68]],
  "bool": true
});

my $jq = JQ::Lite->new;

my @exploded = $jq->run_query($json, '.word | explode');
is_deeply($exploded[0], [80, 101, 114, 108], 'explode converts string into Unicode code points');

my @exploded_array = $jq->run_query($json, '.words | explode');
my $expected_array = [
    [72, 105],
    [74, 83, 79, 78],
    undef,
    { skip => JSON::PP::true },
];
is_deeply($exploded_array[0], $expected_array, 'explode applies element-wise and preserves non-strings');

my @bool_exploded = $jq->run_query($json, '.bool | explode');
is_deeply($bool_exploded[0], [116, 114, 117, 101], 'explode stringifies booleans similar to jq');

my @imploded = $jq->run_query($json, '.codes | implode');
is($imploded[0], 'Perl', 'implode converts array of code points into string');

my @roundtrip = $jq->run_query($json, '.nested | implode');
my $expected_roundtrip = ['AB', 'CD'];
is_deeply($roundtrip[0], $expected_roundtrip, 'implode maps nested arrays of code points back to strings');

my @loop = $jq->run_query($json, '.word | explode | implode');
is($loop[0], 'Perl', 'explode + implode roundtrip returns original string');

my @mixed_implode = $jq->run_query($json, '.words | explode | implode');
my $expected_mixed = ['Hi', 'JSON', undef, { skip => JSON::PP::true }];
is_deeply($mixed_implode[0], $expected_mixed, 'implode reverses explode for arrays while leaving passthrough entries intact');


# Compare direct code-point extraction to the exact old split/ord path,
# including character, byte and UTF-8 flagged inputs. A byte string's
# bytes must retain their legacy code-point interpretation.
my @scalar_cases = (
    ['', [], 'empty string'],
    ['abc', [97,98,99], 'plain ASCII'],
    ["A\0\r\n", [65,0,13,10], 'embedded NUL and newlines'],
    ["\x{65e5}\x{672c}", [0x65e5,0x672c], 'Japanese Unicode characters'],
    ["A\x{1F600}\x{65e5}", [65,0x1F600,0x65e5],
        'ASCII, supplementary and BMP characters'],
    ["e\x{301}", [101,0x301], 'combining accent stays separate'],
    [pack('C*', 0x80, 0xA9, 0xFF), [128,169,255],
        'unflagged high bytes are not decoded as UTF-8'],
    [pack('C*', 0 .. 255), [0 .. 255],
        'every possible byte preserves its code point'],
    ['12.5', [49,50,46,53], 'numeric-looking text'],
    [('z' x 256) . "\x{1F642}", [(122) x 256,0x1F642],
        '257-codepoint ASCII and emoji tail'],
);
for my $case (@scalar_cases) {
    my ($input, $expected, $label) = @$case;
    my $before = "$input";
    my $utf8_before = utf8::is_utf8($input) ? 1 : 0;
    my @legacy = map { ord($_) } split(//u, "$input");
    my $actual = JQ::Lite::Util::_apply_explode($input);
    is_deeply($actual, $expected, "explode code points: $label");
    is_deeply($actual, \@legacy, "explode legacy split/ord: $label");
    is($input, $before, "explode does not modify scalar: $label");
    is(utf8::is_utf8($input) ? 1 : 0, $utf8_before,
        "explode preserves scalar UTF-8 flag: $label");
}

# Recursive array handling, null slots, JSON booleans and opaque object
# references remain the responsibility of the unchanged outer branches.
my $object = { keep => ["\x{65e5}"] };
my $truth = JSON::PP::true;
my $falsehood = JSON::PP::false;
my @stream = (
    "\x{65e5}", undef, $truth, $falsehood, $object,
    ["A\x{1F600}", undef, ["\0"]], 42
);
my $expected_stream = [
    [0x65e5], undef,
    [116,114,117,101], [102,97,108,115,101],
    $object, [[65,0x1F600],undef,[[0]]], [52,50]
];
my ($matched, $outputs) =
    JQ::Lite::Builtin->dispatch($jq, 'explode', \@stream);
ok($matched, 'explode remains registered for direct stream dispatch');
is_deeply($outputs, $expected_stream,
    'explode preserves recursive arrays and stream cardinality');
is(refaddr($outputs->[4]), refaddr($object),
    'explode preserves opaque object reference identity');
is(refaddr($stream[2]), refaddr($truth),
    'explode leaves caller Boolean object untouched');
is_deeply(\@stream, [
    "\x{65e5}",undef,$truth,$falsehood,$object,
    ["A\x{1F600}",undef,["\0"]],42
], 'explode does not mutate caller input stream');

my ($alias_matched, $alias_out) =
    JQ::Lite::Builtin->dispatch($jq, 'explode()', ['Hi']);
ok($alias_matched, 'explode() direct registry alias is preserved');
is_deeply($alias_out, [[72,105]],
    'explode() direct alias preserves exact code points');

my ($empty_matched, $empty_out) =
    JQ::Lite::Builtin->dispatch($jq, 'explode', []);
ok($empty_matched, 'explode matches an empty direct stream');
is_deeply($empty_out, [], 'explode emits no empty-stream values');
is_deeply([ $jq->run_query('null', 'empty | explode') ], [],
    'explode does not revive an empty public stream');

my $public = JSON::PP->new->allow_nonref;
my $unicode_json = $public->encode([
    "A\x{65e5}", "\x{1F600}", undef, $truth, ['Hi']
]);
is_deeply([ $jq->run_query($unicode_json, '.[] | explode') ], [
    [65,0x65e5], [0x1F600], undef,
    [116,114,117,101], [[72,105]]
], 'public explode preserves multi-value Unicode stream and nesting');
is_deeply([ $jq->run_query($unicode_json, '.[] | explode()') ], [
    [65,0x65e5], [0x1F600], undef,
    [116,114,117,101], [[72,105]]
], 'public explode() alias preserves Unicode stream');

is_deeply([ $jq->run_query('"\u65e5\u672c\uD83D\uDE42"', 'explode | implode') ],
    ["\x{65e5}\x{672c}\x{1F642}"],
    'Unicode supplementary-plane explode/implode roundtrip');

done_testing;
