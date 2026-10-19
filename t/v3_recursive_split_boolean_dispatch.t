use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Builtin ();
use JQ::Lite::Util ();
use Scalar::Util qw(refaddr);

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;

sub run {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# Recursive splitting already handles JSON booleans in the scalar case.
# Array traversal must not stringify them a second time or change shape.
my @cases = (
    ['[true,false]', ',', '["true","false"]', 'top-level booleans'],
    ['[[true],[false]]', ',', '["true","false"]', 'nested booleans'],
    ['[[[true]],[[false]]]', ',', '["true","false"]', 'deeply nested booleans'],
    ['[true,false]', 'r', '["t","ue","false"]', 'separator within true'],
    ['[true,false]', 'a', '["true","f","lse"]', 'separator within false'],
    ['[true,false]', '', '["t","r","u","e","f","a","l","s","e"]',
        'character splitting booleans'],
    ['[true,false]', 'true', '["","","false"]',
        'separator equals true'],
    ['[true,false]', 'false', '["true","",""]',
        'separator equals false'],
    ['[null,true,false]', ',', '[null,"true","false"]',
        'null slots preserved'],
    ['[true,"a,b",false]', ',', '["true","a","b","false"]',
        'booleans beside delimited strings'],
    ['[[true,["a,b"]],null,[false,"c,d"]]', ',',
        '["true","a","b",null,"false","c","d"]',
        'nested arrays flattened and ordered'],
    ['[{},true,{"flag":false},false]', ',',
        '[{},"true",{"flag":false},"false"]',
        'objects and nested JSON booleans stay opaque'],
    ['[true,0,false,"0"]', ',', '["true","0","false","0"]',
        'numeric and string scalars'],
    ['[[],[true],[],[false]]', ',', '["true","false"]',
        'empty array branches'],
    ['[true,false]', 'z', '["true","false"]',
        'unmatched delimiter'],
);

for my $case (@cases) {
    my ($input, $separator, $expected, $name) = @$case;
    my $value = $json->decode($input);
    my $wanted = $json->decode($expected);
    is_deeply(JQ::Lite::Util::_apply_split($value, $separator), $wanted,
        "direct recursive split: $name");
    my $argument = $json->encode($separator);
    is_deeply(run($input, "split($argument)"), [$wanted],
        "public split: $name");
}

# Existing scalar handling must still be the sole boolean normalization
# path; empty/null separator behavior stays available to callers.
for my $case (
    ['true',  ',', '["true"]', 'true scalar'],
    ['false', ',', '["false"]', 'false scalar'],
    ['true',  '', '["t","r","u","e"]', 'true characters'],
    ['false', '', '["f","a","l","s","e"]', 'false characters'],
    ['null',  ',', 'null', 'null scalar'],
) {
    my ($input, $separator, $expected, $name) = @$case;
    is_deeply(JQ::Lite::Util::_apply_split($json->decode($input), $separator),
        $json->decode($expected), "scalar helper: $name");
}
is_deeply(run('[true,false]', 'split(null)'),
    [['t','r','u','e','f','a','l','s','e']],
    'null argument continues to mean character separator');
is_deeply(run('[true,false]', 'split("")'),
    [['t','r','u','e','f','a','l','s','e']],
    'quoted empty separator also works recursively');
is_deeply(run('[true,false]', 'empty | split(",")'), [],
    'empty upstream stream remains empty');
is_deeply(run('[[true,false],[false,true]]', '.[] | split(",")'),
    [['true','false'], ['false','true']],
    'split preserves separate output values across the stream');

my ($matched, $outputs) = JQ::Lite::Builtin->dispatch(
    $jq, 'split(",")', [
        [JSON::PP::true, JSON::PP::false],
        undef,
        {flag => JSON::PP::true},
        ['a,b', JSON::PP::false],
    ],
);
ok($matched, 'split remains registered for nonempty delimiter arguments');
is_deeply($outputs, [
    ['true','false'], undef, {flag => JSON::PP::true}, ['a','b','false']
], 'direct dispatch preserves booleans, objects and input cardinality');
my ($no_argument) = JQ::Lite::Builtin->dispatch($jq, 'split()', ['a,b']);
ok(!$no_argument, 'split() remains outside the registered grammar');
my ($empty_matched, $empty_results) = JQ::Lite::Builtin->dispatch(
    $jq, 'split(",")', []
);
ok($empty_matched, 'direct split accepts empty input streams');
is_deeply($empty_results, [], 'no values are synthesized for empty streams');


# Previous split recursively re-normalized its separator and interpolated
# the same literal regex for each scalar leaf. The prepared-pattern path
# must match the exact original flattening and v2 coercion rules.
sub old_recursive_split {
    my ($value, $separator) = @_;
    if (ref $value eq 'ARRAY') {
        my @parts;
        for my $element (@$value) {
            my $result = old_recursive_split($element, $separator);
            push @parts, ref($result) eq 'ARRAY' ? @$result : $result;
        }
        return \@parts;
    }
    return undef if !defined $value;
    if (JSON::PP::is_bool($value)) {
        $value = $value ? 'true' : 'false';
    }
    elsif (ref $value) {
        return $value;
    }
    $separator = '' unless defined $separator;
    return [split(//, $value)] if $separator eq '';
    return [split(/\Q$separator\E/, $value, -1)];
}

my $canonical = JSON::PP->new->allow_nonref->canonical;
my @cached_split_cases = (
    ['"a,b,c"', '","', '["a","b","c"]', 'single string'],
    ['["a,b","c,d"]', '","', '["a","b","c","d"]',
        'adjacent string siblings'],
    ['[["a,b"],["c,d"]]', '","', '["a","b","c","d"]',
        'nested arrays flatten once'],
    ['[[["a,b"]],[["c,d"]]]', '","', '["a","b","c","d"]',
        'deep nested arrays'],
    ['["a,,b,",",c"]', '","', '["a","","b","","","c"]',
        'interior leading and trailing empty fields'],
    ['["a::b::","c::d"]', '"::"',
        '["a","b","","c","d"]', 'multi-character delimiter'],
    ['["a.b","c.d"]', '"."', '["a","b","c","d"]',
        'regex dot is literal'],
    ['["a$^b","c$^d"]', '"$^"', '["a","b","c","d"]',
        'multiple regex metacharacters'],
    ['["a[b]c","x[b]y"]', '"[b]"',
        '["a","c","x","y"]', 'literal brackets'],
    ['["a,b","c,d"]', 'null', '["a",",","b","c",",","d"]',
        'null delimiter means characters'],
    ['["ab","cd"]', '""', '["a","b","c","d"]',
        'empty delimiter means characters'],
    ['[true,false,"t,r"]', '","', '["true","false","t","r"]',
        'Boolean leaves are strings'],
    ['[[true,false],null,["a,b"]]', '","',
        '["true","false",null,"a","b"]',
        'nested Boolean and null leaves'],
    ['[{},["a,b"],{"nested":"a,b"}]', '","',
        '[{},"a","b",{"nested":"a,b"}]',
        'hash values remain opaque'],
    ['[[],{},null]', '","', '[{},null]',
        'empty arrays disappear, opaque values survive'],
    ['[12,304,"4,5"]', '","', '["12","304","4","5"]',
        'numeric values stringified'],
    ['["\u65e5,\u672c","\u8a9e,\u65e5"]', '","',
        '["\u65e5","\u672c","\u8a9e","\u65e5"]',
        'Unicode fragments'],
    ['["\u65e5\u672c","\u8a9e\u65e5"]', '"\u65e5"',
        '["","\u672c","\u8a9e",""]',
        'Unicode separator'],
    ['["ab","ab","ab"]', '"x"', '["ab","ab","ab"]',
        'unmatched nonempty separator'],
    ['[]', '","', '[]', 'empty root array'],
    ['[[],[],[]]', '","', '[]', 'empty nested arrays'],
    ['["ab","c,d","ef"]', '"b"', '["a","c,d","ef"]',
        'later siblings do not reuse first result'],
);
for my $case (@cached_split_cases) {
    my ($raw, $raw_separator, $raw_expected, $name) = @$case;
    my $source = $canonical->decode($raw);
    my $separator = $canonical->decode($raw_separator);
    my $original_source = $canonical->encode($source);
    my $original_separator = $canonical->encode($separator);
    my $actual = JQ::Lite::Util::_apply_split($source, $separator);
    is_deeply($actual, old_recursive_split($source, $separator),
        "cached split matches legacy helper: $name");
    is_deeply($actual, $canonical->decode($raw_expected),
        "cached split retains expected result: $name");
    is($canonical->encode($source), $original_source,
        "cached split preserves original input: $name");
    is($canonical->encode($separator), $original_separator,
        "cached split preserves separator argument: $name");
}

# A private stringification probe observes regex preparation across the
# entire nested array. It does not introduce new public JSON input types.
{
    package JQ::Lite::Test::SplitLiteralCounter;
    use overload '""' => sub {
        my $counter = $_[0];
        $$counter++;
        return ',';
    }, fallback => 1;
}
my $separator_coercions = 0;
my $separator_probe = bless \$separator_coercions,
    'JQ::Lite::Test::SplitLiteralCounter';
my $probe_input = [['a,b','c,d'],['e,f'],{name=>'g,h'},undef];
my $probe_original = $canonical->encode($probe_input);
is_deeply(JQ::Lite::Util::_apply_split($probe_input, $separator_probe),
    ['a','b','c','d','e','f',{name=>'g,h'},undef],
    'nested arrays share one literal delimiter');
is($separator_coercions, 1,
    'nonempty separator is stringified only once per root array');
is($canonical->encode($probe_input), $probe_original,
    'prepared split does not mutate nested source');

my $passthrough_coercions = 0;
my $passthrough_probe = bless \$passthrough_coercions,
    'JQ::Lite::Test::SplitLiteralCounter';
my $opaque = {k=>'keep'};
my $passthrough = [[],undef,[$opaque]];
my $opaque_addr = refaddr($opaque);
is_deeply(JQ::Lite::Util::_apply_split($passthrough, $passthrough_probe),
    [undef,$opaque], 'null and object-only arrays remain unchanged');
is($passthrough_coercions, 0,
    'no scalar leaf means no separator preparation');
is(refaddr($opaque), $opaque_addr,
    'opaque object reference is not replaced');

my $wide_input = [map { $_ % 2 ? 'a,b' : 'c,d' } 0 .. 256];
my $wide_before = $canonical->encode($wide_input);
my @wide_expected = map { $_ % 2 ? ('a','b') : ('c','d') } 0 .. 256;
is_deeply(JQ::Lite::Util::_apply_split($wide_input, ','),
    \@wide_expected, '257-element array shares the same delimiter');
is($canonical->encode($wide_input), $wide_before,
    '257-element input is unchanged');

is_deeply(run('[["a,b"],["c,d"]]', 'split(",")'),
    [['a','b','c','d']], 'public nested split retains flattening');
is_deeply(run('[true,"a,b",null]', 'split(",")'),
    [['true','a','b',undef]], 'public split preserves booleans and null');
is_deeply(run('["a,b","c,d"]', '.[] | split(",")'),
    [['a','b'],['c','d']], 'public stream output remains ordered');
is_deeply(run('["a,b"]', 'empty | split(",")'),
    [], 'empty upstream still produces no values');

done_testing;
