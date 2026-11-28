use strict;
use warnings;
use Test::More;
use JSON::PP ();
use Scalar::Util qw(refaddr looks_like_number);
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


# The old scalar-context grep counted *all* referenced children before
# deciding whether to recursively implode. The new probe may stop at the
# first ref, but it must retain all observable v2 semantics and ordering.
sub legacy_implode {
    my ($value) = @_;
    return undef unless defined $value;

    if (ref $value eq 'ARRAY') {
        my $has_nested = grep { ref $_ } @$value;
        return [ map { legacy_implode($_) } @$value ] if $has_nested;

        my $text = '';
        for my $code (@$value) {
            next unless defined $code;
            next unless looks_like_number($code);
            $text .= chr(int($code));
        }
        return $text;
    }
    return $value;
}

my $codec = JSON::PP->new->allow_nonref->canonical;
my @implode_cases = (
    [[], '', 'empty array becomes empty text'],
    [[65,66,67], 'ABC', 'flat numeric code points'],
    [[65,'66',67], 'ABC', 'numeric-looking strings'],
    [[65,'bad',undef,66], 'AB', 'invalid and null flat entries skipped'],
    [[0,65,66], "\0AB", 'NUL code point retained'],
    [[65,1.5,66], "A\x01B", 'fractional code point truncated'],
    [[[65,66],[67,68]], ['AB','CD'], 'nested numeric arrays'],
    [[[65],undef,[66]], ['A',undef,'B'], 'null slot in nested structure'],
    [[65,[66,[67,68]]], [65,[66,'CD']],
        'multiple recursion levels preserve scalar siblings'],
    [[JSON::PP::true,65,JSON::PP::false],
        [JSON::PP::true,65,JSON::PP::false],
        'Boolean references trigger recursive passthrough'],
    [[[65],{key=>[66]},[67]], ['A',{key=>[66]},'C'],
        'object reference passes through in recursive array'],
    [[{key=>[66]},65], [{key=>[66]},65],
        'object encountered first remains opaque'],
    [[(65) x 256, [66]], [(65) x 256,'B'],
        'late nested child after long scalar prefix'],
    [[[66], (65) x 256], ['B',(65) x 256],
        'early nested child before long scalar suffix'],
    [[(65) x 257], 'A' x 257,
        'long reference-free flat array'],
    [undef, undef, 'null scalar passthrough'],
    [JSON::PP::true, JSON::PP::true, 'Boolean scalar passthrough'],
    [{key=>[65]}, {key=>[65]}, 'opaque object scalar passthrough'],
);
for my $case (@implode_cases) {
    my ($input, $expected, $label) = @$case;
    my $encoded = $codec->encode($input);
    my $old_copy = $codec->decode($encoded);
    my $new_copy = $codec->decode($encoded);

    my $legacy = legacy_implode($old_copy);
    my $result = JQ::Lite::Util::_apply_implode($new_copy);
    is_deeply($result, $legacy, "implode legacy oracle: $label");
    is_deeply($result, $expected, "implode expected output: $label");
    is($codec->encode($new_copy), $codec->encode($old_copy),
        "implode input mutation matches old behavior: $label");
}

my $opaque_implode = { keep => [65] };
my $bool_implode = JSON::PP::false;
my @implode_stream = ([[65],[66]], [65,undef,66],
    $opaque_implode, $bool_implode, undef);
my ($implode_found, $implode_out) = JQ::Lite::Builtin->dispatch(
    $jq, 'implode', \@implode_stream
);
ok($implode_found, 'implode remains registered for direct streams');
is_deeply($implode_out,
    [['A','B'],'AB',$opaque_implode,$bool_implode,undef],
    'implode direct stream retains nested, flat, opaque, Boolean, null slots');
is(refaddr($implode_out->[2]), refaddr($opaque_implode),
    'implode preserves opaque object identity');
is(refaddr($implode_out->[3]), refaddr($bool_implode),
    'implode preserves Boolean reference identity');
is_deeply(\@implode_stream,
    [[[65],[66]],[65,undef,66],$opaque_implode,$bool_implode,undef],
    'implode does not mutate its original input stream');

my ($implode_alias_found, $implode_alias_out) =
    JQ::Lite::Builtin->dispatch($jq, 'implode()', [[65,66]]);
ok($implode_alias_found, 'implode() direct alias remains registered');
is_deeply($implode_alias_out, ['AB'],
    'implode() direct alias preserves flat decoding');

my ($implode_empty_found, $implode_empty_out) =
    JQ::Lite::Builtin->dispatch($jq, 'implode', []);
ok($implode_empty_found, 'implode accepts direct empty stream');
is_deeply($implode_empty_out, [], 'implode does not synthesize output');
is_deeply([ $jq->run_query('null', 'empty | implode') ], [],
    'implode does not revive an empty public stream');

my $public_implode = '[[65,66],[[65],[66]],[],[null,65],{"keep":1},true]';
my $public_expected = [
    'AB',['A','B'],'','A',{keep=>1},JSON::PP::true
];
is_deeply([ $jq->run_query($public_implode, '.[] | implode') ],
    $public_expected, 'public implode retains ordered mixed streams');
is_deeply([ $jq->run_query($public_implode, '.[] | implode()') ],
    $public_expected, 'public implode() alias retains ordered mixed streams');

done_testing;
