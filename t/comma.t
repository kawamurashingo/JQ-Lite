use strict;
use warnings;
use Test::More tests => 22;
use FindBin;
use lib "$FindBin::Bin/../lib";
use JQ::Lite;

my $jq = JQ::Lite->new;

my $simple_json = '{"a":1,"b":2}';
my @simple = $jq->run_query($simple_json, '.a, .b');
is_deeply(\@simple, [1, 2], 'comma emits multiple top-level values');

my $users_json = '[{"name":"Alice","age":30},{"name":"Bob","age":25}]';
my @flat = $jq->run_query($users_json, '.[] | (.name, .age)');
is_deeply(\@flat, ['Alice', 30, 'Bob', 25], 'comma branches run against identical inputs in pipelines');

my @arrays = $jq->run_query($users_json, '.[] | [.name, .age], ["extra"]');
is_deeply(\@arrays,
    [
        ['Alice', 30],
        ['extra'],
        ['Bob', 25],
        ['extra'],
    ],
    'comma preserves evaluation order for each input');

my @prefixed = $jq->run_query($users_json, '(["name","age"]), (.[] | [.name, .age])');
is_deeply(
    \@prefixed,
    [
        ['name', 'age'],
        ['Alice', 30],
        ['Bob', 25],
    ],
    'parenthesised literal branches evaluate in full before subsequent branches'
);

my @fallback = $jq->run_query('{}', '(.missing), 1');
is_deeply(\@fallback, [undef, 1], 'comma preserves JSON null from a missing field');

my @chain = $jq->run_query('null', '1, 2, 3');
is_deeply(\@chain, [1, 2, 3], 'comma is left-associative and preserves order');

my @empty_then = $jq->run_query('{}', 'empty, 1');
is_deeply(\@empty_then, [1], 'empty emits nothing before subsequent branches run');

my @optional = $jq->run_query('{"foo":0}', '.foo?, 1');
is_deeply(\@optional, [0, 1], 'optional lookup may yield zero or one result before the next branch');

my @array_seq = $jq->run_query('{"a":1,"b":2}', '[(.a, .b)]');
is_deeply(\@array_seq, [[1, 2]], 'sequence inside array literal collects all branch results for the element');

my @paren = $jq->run_query('[1,2]', '( .[] ), 3');
is_deeply(\@paren, [1, 2, 3], 'parenthesised sequence composes with subsequent branches');

my @trailing_empty = $jq->run_query('null', '1, empty');
is_deeply(\@trailing_empty, [1], 'empty trailing branch does not add results');


# A top-level comma binds more loosely than update assignment. Each
# alternative receives the unchanged input; a comma inside the RHS is not
# a sibling filter when nested in parentheses, arrays or quoted strings.
my $update_json = '{"a":0,"b":2}';
my @update_comma_cases = (
    ['.a |= 1, .b', [{ a => 1, b => 2 }, 2],
        'update followed by field alternative'],
    ['.a, .b |= 1', [0, { a => 0, b => 1 }],
        'field before update alternative'],
    ['(.a |= 1), .b', [{ a => 1, b => 2 }, 2],
        'parenthesized update remains a separate branch'],
    ['.a |= (1,2), .b', [{ a => 1, b => 2 }, 2],
        'parenthesized RHS comma takes only its first result'],
    ['.a |= (1,2)', [{ a => 1, b => 2 }],
        'parenthesized RHS comma without sibling does not branch'],
    ['.a |= "x,y", .b', [{ a => 'x,y', b => 2 }, 2],
        'quoted comma stays within update RHS'],
    ['.a |= 1, .b |= 3',
        [{ a => 1, b => 2 }, { a => 0, b => 3 }],
        'two updates each start from the original input'],
    ['.a |= (. + 1), .b', [{ a => 1, b => 2 }, 2],
        'update RHS arithmetic stays scoped to old leaf'],
    ['.a |= [1,2], .b', [{ a => [1, 2], b => 2 }, 2],
        'array constructor comma stays inside the RHS'],
    ['(.a |= 1, .b)', [{ a => 1, b => 2 }, 2],
        'wrapped top-level alternatives retain update precedence'],
    ['.a |= 1, 99', [{ a => 1, b => 2 }, 99],
        'literal sibling still evaluates after update'],
);
for my $case (@update_comma_cases) {
    my ($filter, $expected, $label) = @$case;
    my @actual = $jq->run_query($update_json, $filter);
    is_deeply(\@actual, $expected, $label);
}
