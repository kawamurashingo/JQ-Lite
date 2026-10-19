use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JSON::PP ();
use JQ::Lite::Util ();
use Scalar::Util qw(looks_like_number);

my $json = q({
  "title": "Hello World",
  "tags": ["perl", "shell", "world"],
  "details": {
    "description": "perl world",
    "count": 2
  },
  "mixed": ["World", 42, null]
});

my $jq = JQ::Lite->new;

my @title = $jq->run_query($json, '.title | replace("World", "Perl")');
is($title[0], 'Hello Perl', 'replace updates simple scalar values');

my @tags = $jq->run_query($json, '.tags | replace("world", "globe")');
is_deeply(
    $tags[0],
    ['perl', 'shell', 'globe'],
    'replace processes array elements recursively'
);

my @description = $jq->run_query($json, '.details.description | replace("perl", "Perl")');
is($description[0], 'Perl world', 'replace respects case-sensitive search term');

my @count = $jq->run_query($json, '.details.count | replace("2", "three")');
is($count[0], 2, 'replace leaves non-string scalars untouched');

my @mixed = $jq->run_query($json, '.mixed | replace("World", "Earth")');
is_deeply(
    $mixed[0],
    ['Earth', 42, undef],
    'replace leaves non-string values unchanged and keeps undef'
);

my @empty_search = $jq->run_query($json, '.title | replace("", "no-op")');
is($empty_search[0], 'Hello World', 'replace is a no-op when search term is empty');

my @missing = $jq->run_query($json, '.missing? | replace("foo", "bar")');
ok(!defined $missing[0], 'replace leaves undef values as undef');

my @chained = $jq->run_query($json, '.title | replace("World", "Perl") | upper');
is($chained[0], 'HELLO PERL', 'replace result can be chained with other functions');

my @double = $jq->run_query($json, '.title | replace("l", "L")');
is($double[0], 'HeLLo WorLd', 'replace substitutes all occurrences of the search term');

my @literal_meta = $jq->run_query('"a.b.c"', '. | replace(".", "-")');
is($literal_meta[0], 'a-b-c', 'replace treats regex metacharacters in the search term as literals');

my @empty_replacement = $jq->run_query('"foooo"', '. | replace("o", "")');
is($empty_replacement[0], 'f', 'replace supports empty replacement text');

my @object_input = $jq->run_query('{"name":"world","nested":{"name":"world"}}', '. | replace("world", "earth")');
is_deeply(
    $object_input[0],
    { name => 'world', nested => { name => 'world' } },
    'replace leaves object inputs untouched instead of stringifying or mutating hashes'
);


# Retain the original recursive copy of replace() as the result oracle.
# It prepares quotemeta and replacement text separately for every leaf.
sub old_replace {
    my ($value, $search, $replacement) = @_;
    if (ref $value eq 'ARRAY') {
        return [map { old_replace($_, $search, $replacement) } @$value];
    }
    return $value if !defined $value;
    return $value if ref $value;
    return $value if looks_like_number($value);
    $search = defined $search ? "$search" : '';
    $replacement = defined $replacement ? "$replacement" : '';
    return $value if $search eq '';
    my $pattern = quotemeta $search;
    (my $copy = "$value") =~ s/$pattern/$replacement/g;
    return $copy;
}

my $codec = JSON::PP->new->allow_nonref->canonical;
my @preparation_cases = (
    ['"foo foo"', '"foo"', '"X"', '"X X"', 'scalar matches'],
    ['["foo","food","bar"]', '"foo"', '"X"',
        '["X","Xd","bar"]', 'sibling strings'],
    ['[["foo"],["food","no"],["foo"]]', '"foo"', '"X"',
        '[["X"],["Xd","no"],["X"]]', 'nested arrays'],
    ['["a.b","a*b","a.b"]', '"."', '"!"',
        '["a!b","a*b","a!b"]', 'literal dot'],
    ['["a*b","ab","a*b"]', '"*"', '"-"',
        '["a-b","ab","a-b"]', 'literal star'],
    ['["x[y]","y","x[y]"]', '"[y]"', '"Z"',
        '["xZ","y","xZ"]', 'literal square brackets'],
    ['["ab$cd","$","ab$cd"]', '"$"', '"_"',
        '["ab_cd","_","ab_cd"]', 'literal dollar'],
    ['["foo","foo"]', '"foo"', '"$1"',
        '["$1","$1"]', 'replacement is not interpolated twice'],
    ['["foo","foo"]', '""', '"X"',
        '["foo","foo"]', 'empty search'],
    ['["foo","foo"]', 'null', '"X"',
        '["foo","foo"]', 'null search'],
    ['["foo","food","foo"]', '"foo"', 'null',
        '["","d",""]', 'null replacement'],
    ['["hello","Hello","hello"]', '"hello"', '"bye"',
        '["bye","Hello","bye"]', 'case-sensitive search'],
    ['["abc","abc"]', '"z"', '"X"',
        '["abc","abc"]', 'unmatched search'],
    ['["", "foo", ""]', '"foo"', '"bar"',
        '["","bar",""]', 'empty string leaves'],
    ['[42,0,-3,"foo","foo"]', '"foo"', '"bar"',
        '[42,0,-3,"bar","bar"]', 'number passthrough'],
    ['["42","1e3","foo"]', '"2"', '"X"',
        '["42","1e3","foo"]', 'numeric-looking string passthrough'],
    ['[null,true,false,"foo","foo"]', '"foo"', '"bar"',
        '[null,true,false,"bar","bar"]', 'Boolean/null passthrough'],
    ['[{"nested":"foo"},"foo",{"x":["foo"]}]', '"foo"', '"bar"',
        '[{"nested":"foo"},"bar",{"x":["foo"]}]', 'opaque hash'],
    ['[[null,[],{}],["foo",["food"]]]', '"foo"', '"bar"',
        '[[null,[],{}],["bar",["bard"]]]', 'deep heterogeneous nesting'],
    ['[true,4,null,[],{"x":"foo"}]', '"foo"', '"bar"',
        '[true,4,null,[],{"x":"foo"}]', 'no convertible leaves'],
    ['["\u65e5\u672c","\u65e5","\u65e5\u672c"]',
        '"\u65e5"', '"X"', '["X\u672c","X","X\u672c"]',
        'Unicode search'],
    ['["abab","ab","abab"]', '"ab"', '"&"',
        '["&&","&","&&"]', 'multiple non-overlapping matches'],
    ['["foo","foo"]', 'false', '"X"',
        '["foo","foo"]', 'Boolean search coercion'],
    ['["foo",["foo"],"foo"]', '"foo"', 'true',
        '["1",["1"],"1"]', 'Boolean replacement coercion'],
);
for my $case (@preparation_cases) {
    my ($raw, $search_json, $replacement_json, $expected_json, $name) = @$case;
    my $source = $codec->decode($raw);
    my $search = $codec->decode($search_json);
    my $replacement = $codec->decode($replacement_json);
    my ($source_before, $search_before, $replacement_before) =
        map { $codec->encode($_) } ($source, $search, $replacement);
    my $got = JQ::Lite::Util::_apply_replace($source, $search, $replacement);
    my $old = old_replace($source, $search, $replacement);
    is_deeply($got, $old, "replace legacy equivalence: $name");
    is_deeply($got, $codec->decode($expected_json),
        "replace expected result: $name");
    is($codec->encode($source), $source_before,
        "replace preserves input: $name");
    is($codec->encode($search), $search_before,
        "replace preserves search operand: $name");
    is($codec->encode($replacement), $replacement_before,
        "replace preserves replacement operand: $name");
}

# The overloaded probe observes lazy, shared coercion across string leaves.
# This is an internal test only; no new JSON input type is introduced.
{
    package JQ::Lite::Test::ReplaceLiteralCounter;
    use overload '""' => sub {
        my $counter = $_[0];
        $counter++;
        return 'foo';
    }, fallback => 1;
}
my $coercions = 0;
my $search_probe = bless \$coercions,
    'JQ::Lite::Test::ReplaceLiteralCounter';
my $nested = [['foo','food'],['foo',['foo']],{x=>'foo'},undef];
my $nested_before = $codec->encode($nested);
is_deeply(JQ::Lite::Util::_apply_replace($nested, $search_probe, 'X'),
    [['X','Xd'],['X',['X']],{x=>'foo'},undef],
    'nested arrays prepare shared search correctly');
is($coercions, 1, 'nested arrays stringify search only once');
is($codec->encode($nested), $nested_before,
    'nested array source is not modified');

my $no_strings_coercions = 0;
my $no_strings_probe = bless \$no_strings_coercions,
    'JQ::Lite::Test::ReplaceLiteralCounter';
my $no_strings = [[10,undef,JSON::PP::true],[{},[],JSON::PP::false]];
is_deeply(JQ::Lite::Util::_apply_replace(
    $no_strings, $no_strings_probe, 'bar'
), $no_strings, 'array with no string leaves passes through unchanged');
is($no_strings_coercions, 0,
    'array without string leaves does not prepare search');

my $wide = [map { $_ % 2 ? 'foo' : 'food' } 0 .. 256];
my $wide_original = $codec->encode($wide);
is_deeply(JQ::Lite::Util::_apply_replace($wide, 'foo', 'X'),
    [map { $_ % 2 ? 'X' : 'Xd' } 0 .. 256],
    '257 string leaves keep order with one preparation');
is($codec->encode($wide), $wide_original,
    '257-element input array stays unchanged');

is_deeply([$jq->run_query('["foo","food","foo"]',
    'replace("foo","X")')], [['X','Xd','X']],
    'public replace preserves array output');
is_deeply([$jq->run_query('[[["foo"],["food"]],"foo"]',
    'replace("foo","X")')], [[[['X'],['Xd']],'X']],
    'public replace preserves nested arrays');
is_deeply([$jq->run_query('["foo","bar"]',
    '.[] | replace("foo","X")')], ['X','bar'],
    'public replace preserves stream output');
is_deeply([$jq->run_query('"foo"',
    'empty | replace("foo","X")')], [],
    'public replace preserves empty stream');

done_testing;
