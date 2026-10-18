use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;

# The bracket table is shared, but nesting/quote state remains per call.
my @balanced = (
    [undef,             1, 'undefined input'],
    ['',                1, 'empty input'],
    ['plain',           1, 'no bracket'],
    ['()',              1, 'empty parentheses'],
    ['[{"k":(x)}]',     1, 'all bracket types'],
    ['["([)]"]',        1, 'bracket-looking text in quotes'],
    ["'(]'",            1, 'single-quoted mismatched characters'],
    ['"a\"(b)"',       1, 'escaped quote with parentheses'],
    ['([)]',            0, 'mismatched nesting'],
    ['[}',              0, 'mismatched close'],
    [']',               0, 'unmatched closing bracket'],
    ['(a',              0, 'unclosed opening bracket'],
    ['"unterminated',   0, 'unclosed double quote'],
    ["'unterminated",   0, 'unclosed single quote'],
);
for my $case (@balanced) {
    my ($source, $expected, $label) = @$case;
    for my $attempt (1, 2) {
        is(JQ::Lite::Util::_are_brackets_balanced($source) ? 1 : 0,
            $expected, "bracket balance: $label ($attempt)");
    }
}

# Comma and semicolon must preserve empty parts and nested delimiters.
for my $separator (',', ';') {
    my @cases = (
        [undef, [], 'undefined text'],
        ['', [''], 'empty defined text'],
        ['a' . $separator . 'b' . $separator,
            ['a','b',''], 'trailing empty field'],
        ['a' . $separator . $separator . 'b',
            ['a','','b'], 'adjacent delimiters'],
        ['[x' . $separator . 'y]' . $separator . 'z',
            ['[x' . $separator . 'y]','z'], 'nested array'],
        ['{"k":"x' . $separator . 'y"}' . $separator . 'z',
            ['{"k":"x' . $separator . 'y"}','z'], 'nested object and quote'],
        ['"x' . $separator . 'y"' . $separator . 'z',
            ['"x' . $separator . 'y"','z'], 'quoted delimiter'],
        ['a]' . $separator . 'b', [], 'unmatched closing bracket'],
        ['(a' . $separator . 'b',
            ['(a' . $separator . 'b'], 'unclosed opening bracket'],
        ['x' . $separator . '("y' . $separator . 'z")',
            ['x','("y' . $separator . 'z")'], 'quoted nested parentheses'],
    );
    for my $case (@cases) {
        my ($source, $expected, $label) = @$case;
        for my $attempt (1, 2) {
            my @parts = $separator eq ','
                ? JQ::Lite::Util::_split_top_level_commas($source)
                : JQ::Lite::Util::_split_top_level_semicolons($source);
            is_deeply(\@parts, $expected,
                "$separator split: $label ($attempt)");
        }
    }
}

my @pipes = (
    [undef, [], 'undefined input'],
    ['', [''], 'empty input'],
    ['a|b|', ['a','b',''], 'trailing pipeline'],
    ['a||(b)', ['a||(b)'], 'logical-or is not a pipe'],
    ['a|=b', ['a|=b'], 'update assignment is not a pipe'],
    ['a|(b|c)|d', ['a','(b|c)','d'], 'parenthesized inner pipe'],
    ['a|"b|c"|d', ['a','"b|c"','d'], 'quoted inner pipe'],
    ['a]|b', [], 'unmatched closing bracket'],
    ['a|(b|c', ['a','(b|c'], 'unclosed nested opening bracket'],
);
for my $case (@pipes) {
    my ($source, $expected, $label) = @$case;
    for my $attempt (1, 2) {
        is_deeply([JQ::Lite::Util::_split_top_level_pipes($source)],
            $expected, "pipe split: $label ($attempt)");
    }
}

my @operators = (
    [undef, ':', [], 'undefined input'],
    ['', ':', [], 'empty input'],
    ['a+b', '+', ['a','b'], 'basic addition'],
    ['a+', '+', ['a',''], 'empty right expression'],
    ['a+=b', '+', [], 'do not split compound update'],
    ['1e+2 + 3', '+', ['1e+2 ',' 3'], 'exponent sign is not addition'],
    ['3e-2-1', '-', ['3e-2','1'], 'exponent sign is not subtraction'],
    ['{"a":1}:next', ':', ['{"a":1}','next'], 'nested object colon'],
    ['"x:y":.z', ':', ['"x:y"','.z'], 'quoted colon'],
    ['[1:2]:rest', ':', ['[1:2]','rest'], 'nested array colon'],
    ['key]:rest', ':', [], 'mismatched closer before separator'],
    ['key:value)', ':', ['key','value)'], 'early return before later bad close'],
    ['(a+b)+c', '+', ['(a+b)','c'], 'nested addition'],
    ['no_operator', '+', [], 'absent operator'],
);
for my $case (@operators) {
    my ($source, $operator, $expected, $label) = @$case;
    for my $attempt (1, 2) {
        my @parts = $operator eq ':'
            ? JQ::Lite::Util::_split_top_level_colon($source)
            : JQ::Lite::Util::_split_top_level_operator($source, $operator);
        is_deeply(\@parts, $expected,
            "operator $operator: $label ($attempt)");
    }
}

# Public queries keep their independent parsing behavior.
is_deeply([$jq->run_query('{"a":2,"b":3}', '.a, .b')],
    [2,3], 'public comma stream order');
is_deeply([$jq->run_query('{"a":{"b":5}}', '.a | .b')],
    [5], 'public pipe traversal');
is_deeply([$jq->run_query('{"name":"A"}', '{name: .name}')],
    [{name=>'A'}], 'public object-colon parsing');
is_deeply([$jq->run_query('[1,2]', 'reduce .[] as $x (0; . + $x)')],
    [3], 'public semicolon/reduce parsing');

done_testing;
