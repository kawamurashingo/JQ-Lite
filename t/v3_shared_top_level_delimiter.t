use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;

sub parts {
    my ($which, $text) = @_;
    return [ $which eq ';'
        ? JQ::Lite::Util::_split_top_level_semicolons($text)
        : JQ::Lite::Util::_split_top_level_commas($text) ];
}

for my $which (';', ',') {
    is_deeply(parts($which, undef), [],
        "$which splitter returns no parts for undefined input");
    is_deeply(parts($which, ''), [''],
        "$which splitter keeps the empty defined input");
    my $with_tail = 'a' . $which . 'b' . $which;
    is_deeply(parts($which, $with_tail), ['a','b',''],
        "$which splitter retains a trailing empty part");
    my $with_gap = 'a' . $which . $which . 'b';
    is_deeply(parts($which, $with_gap), ['a','','b'],
        "$which splitter retains consecutive empty parts");
    my $quoted = '("a' . $which . 'b")' . $which . 'next';
    is_deeply(parts($which, $quoted),
        ['("a' . $which . 'b")', 'next'],
        "$which splitter protects quoted punctuation inside parens");
    my $nested = '[1' . $which . '2]' . $which . '{"k":1}';
    is_deeply(parts($which, $nested),
        ['[1' . $which . '2]', '{"k":1}'],
        "$which splitter does not split nested arrays or objects");
    is_deeply(parts($which, 'a]' . $which . 'b'), [],
        "$which splitter rejects a mismatched closing bracket");
    my $unclosed = '(a' . $which . 'b';
    is_deeply(parts($which, $unclosed), [$unclosed],
        "$which splitter preserves the pre-existing unmatched-open behavior");
}
is_deeply(parts(',', '"a,b", next'), ['"a,b"', ' next'],
    'comma inside a double-quoted string is not a separator');
is_deeply(parts(';', "'a;b'; next"), ["'a;b'", ' next'],
    'semicolon inside a single-quoted string is not a separator');
is_deeply(parts(',', '"a\\",b", next'),
    ['"a\\",b"', ' next'],
    'escaped quote does not prematurely end comma-protected string');
is_deeply(parts(';', '"a\\";b"; next'),
    ['"a\\";b"', ' next'],
    'escaped quote does not prematurely end semicolon-protected string');

sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

is_deeply(results('{"a":null,"b":2}', '.a, .b'),
    [undef,2], 'comma maintains explicit null and output order');
is_deeply(results('{"a":null,"b":2}', 'empty, .a, .b'),
    [undef,2], 'empty branch does not introduce a null value');
is_deeply(results('[{"a":1},{"a":2}]', '.[] | (.a, 0)'),
    [1,0,2,0], 'comma branches preserve per-input stream order');
is_deeply(results('[1,2]', 'reduce .[] as $x (0; . + $x)'),
    [3], 'semicolon splitting preserves reduce accumulator');
is_deeply(results('[1,2]', 'foreach .[] as $x (0; . + $x; .)'),
    [1,3], 'semicolon splitting preserves foreach ordered outputs');
is_deeply(results('[1,2]', 'foreach .[] as $x (0; . + $x; empty)'),
    [undef,undef], 'foreach retains legacy null outputs for an empty extractor');

done_testing;
