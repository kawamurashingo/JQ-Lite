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


# Comparison and keyword scanners have their own semantics; only their
# bracket lookup now shares the already-initialized table.
my @comparisons = (
    [undef, [], 'undefined input'],
    ['', [], 'empty input'],
    ['plain', [], 'no comparison operator'],
    ['1==2', ['1','==','2'], 'adjacent operands'],
    ['1 != 2', ['1 ','!=',' 2'], 'not equal'],
    ['.a >= .b', ['.a ','>=',' .b'], 'greater than or equal'],
    ['.a <= .b', ['.a ','<=',' .b'], 'less than or equal'],
    ['.a > .b', ['.a ','>',' .b'], 'greater than'],
    ['.a < .b', ['.a ','<',' .b'], 'less than'],
    ['[1,2] == [2]', ['[1,2] ','==',' [2]'], 'nested arrays'],
    ['{"x":1} == {"x":2}', ['{"x":1} ','==',' {"x":2}'],
        'nested objects'],
    ['"a>b" == "z"', ['"a>b" ','==',' "z"'],
        'quoted operator'],
    ['(.a > 0) == true', ['(.a > 0) ','==',' true'],
        'parenthesized comparison'],
    ['["x == y"] == []', ['["x == y"] ','==',' []'],
        'quoted comparison inside array'],
    ['a == ', [], 'missing right operand'],
    [' == b', [], 'missing left operand'],
    ['a == b and c == d', [], 'compound and uses conditional evaluator'],
    ['a == b or c == d', [], 'compound or uses conditional evaluator'],
    ['a == b == c', ['a ','==',' b == c'],
        'first top-level comparison wins'],
);
for my $case (@comparisons) {
    my ($input, $expected, $label) = @$case;
    for my $attempt (1, 2) {
        is_deeply([JQ::Lite::Util::_split_top_level_comparison($input)],
            $expected, "comparison split: $label ($attempt)");
    }
}

my @keywords = (
    [undef, 'and', [undef], 'undefined input retained'],
    ['', 'and', [''], 'empty input retained'],
    ['a', undef, ['a'], 'undefined keyword retained'],
    ['a', '', ['a'], 'empty keyword retained'],
    ['a and b', 'and', ['a ',' b'], 'simple and'],
    ['a or b', 'or', ['a ',' b'], 'simple or'],
    ['and b', 'and', ['',' b'], 'leading keyword'],
    ['a and', 'and', ['a ',''], 'trailing keyword'],
    ['a and b and c', 'and', ['a ',' b ',' c'],
        'multiple keyword separators'],
    ['a xor b or c', 'or', ['a xor b ',' c'],
        'word boundary before or'],
    ['candy and b', 'and', ['candy ',' b'],
        'do not split keyword suffix'],
    ['a andrew b', 'and', ['a andrew b'],
        'do not split keyword prefix'],
    ['a and(b)', 'and', ['a and(b)'],
        'keyword without whitespace after it'],
    ['a (x and y) and b', 'and', ['a (x and y) ',' b'],
        'parenthesized keyword'],
    ['a ["and"] and b', 'and', ['a ["and"] ',' b'],
        'array and quoted keyword'],
    ['a {"k":"and"} and b', 'and', ['a {"k":"and"} ',' b'],
        'object and quoted keyword'],
    ['a "and" and b', 'and', ['a "and" ',' b'],
        'top-level string keyword'],
    ['a and b', 'or', ['a and b'],
        'independent keyword calls'],
);
for my $case (@keywords) {
    my ($input, $keyword, $expected, $label) = @$case;
    for my $attempt (1, 2) {
        is_deeply([JQ::Lite::Util::_split_top_level_keyword($input, $keyword)],
            $expected, "keyword split: $label ($attempt)");
    }

}

# Public comparisons and boolean conditions still use their original
# evaluators; they must not pick up state from any other splitter.
is_deeply([$jq->run_query('{"a":1,"b":2}', '.a < .b')],
    [JSON::PP::true], 'public comparison remains valid');
is_deeply([$jq->run_query('{"a":1,"b":2}', '.a == 1 and .b == 2')],
    [JSON::PP::true], 'public and condition remains valid');
is_deeply([$jq->run_query('{"a":1,"b":2}', '.a == 0 or .b == 2')],
    [JSON::PP::true], 'public or condition remains valid');

done_testing;
