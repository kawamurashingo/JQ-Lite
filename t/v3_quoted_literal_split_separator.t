use strict;
use warnings;
use Test::More;
use JSON::PP ();
use Scalar::Util qw(refaddr);
use JQ::Lite;
use JQ::Lite::Builtin ();
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref->ascii;

sub run {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# Perl's /\Q$separator\E/ must be exactly as literal as the former
# quotemeta($separator) followed by /$pattern/. Check direct utility,
# public jq-like query and the registered stream dispatcher separately.
my @separators = (
    ['period', '.'],
    ['plus', '+'],
    ['asterisk', '*'],
    ['question', '?'],
    ['pipe', '|'],
    ['opening bracket', '['],
    ['closing bracket', ']'],
    ['opening paren', '('],
    ['closing paren', ')'],
    ['opening brace', '{'],
    ['closing brace', '}'],
    ['caret', '^'],
    ['dollar', '$'],
    ['backslash', "\\"],
    ['escaped Q', '\Q'],
    ['escaped E', '\E'],
    ['regex digit class', '\d'],
    ['regex range', '[a-z]'],
    ['regex wildcard', '.*'],
    ['multi character', '::'],
    ['punctuation pair', '$^'],
    ['plus in text', 'a+b'],
    ['space', ' '],
    ['Unicode hiragana', chr(0x3042)],
    ['Unicode accent', chr(0x00e9)],
);

for my $case (@separators) {
    my ($label, $separator) = @$case;
    my $input = 'lead' . $separator . 'middle' .
                $separator . 'tail' . $separator;
    my $expected = ['lead', 'middle', 'tail', ''];
    my $old_pattern = quotemeta $separator;
    is_deeply([ split /$old_pattern/, $input, -1 ], $expected,
        "original quoted separator behavior: $label");
    is_deeply(JQ::Lite::Util::_apply_split($input, $separator), $expected,
        "direct utility uses literal separator: $label");

    my $filter = 'split(' . $json->encode($separator) . ')';
    is_deeply(run($json->encode($input), $filter), [$expected],
        "public query preserves literal separator: $label");
    my ($matched, $outputs) = JQ::Lite::Builtin->dispatch(
        $jq, $filter, [$input]
    );
    ok($matched, "registered split accepts separator: $label");
    is_deeply($outputs, [$expected],
        "registered split preserves separator: $label");
}

# No change to the empty-string special case, to trailing and adjacent
# empty fields, or to the recursive flattening of arrays.
for my $spec (
    ['abc', '', ['a','b','c'], 'empty separator emits characters'],
    ['', '', [], 'empty input and separator'],
    ['a,,b,', ',', ['a','','b',''], 'adjacent and trailing empties'],
    [',head', ',', ['','head'], 'leading empty'],
    ['a::b::', '::', ['a','b',''], 'repeated longer delimiter'],
    ['no match', '.', ['no match'], 'no separator occurrence'],
) {
    my ($input, $separator, $expected, $label) = @$spec;
    is_deeply(JQ::Lite::Util::_apply_split($input, $separator), $expected,
        "direct edge case: $label");
    my $filter = 'split(' . $json->encode($separator) . ')';
    is_deeply(run($json->encode($input), $filter), [$expected],
        "public edge case: $label");
}

my $mixed = $json->decode('[true,false,null,"a.b",["c.d"],{"x":"e.f"}]');
my $expected_mixed = $json->decode(
    '["true","false",null,"a","b","c","d",{"x":"e.f"}]'
);
is_deeply(JQ::Lite::Util::_apply_split($mixed, '.'), $expected_mixed,
    'recursive split retains booleans, null, nested flattening and objects');
is_deeply(run($json->encode($mixed), 'split(".")'),
    [$expected_mixed], 'public split preserves nested mixed-array policy');
is_deeply(run('[true,false]', 'split("")'),
    [['t','r','u','e','f','a','l','s','e']],
    'boolean array can still split into characters');
is_deeply(run('null', 'split(".")'), [undef],
    'null input remains null');
is_deeply(run('42', 'split("")'), [['4','2']],
    'number input still stringifies');
is_deeply(run('["a.b","c.d"]', '.[] | split(".")'),
    [['a','b'],['c','d']], 'multiple input streams keep order');
is_deeply(run('null', 'empty | split(".")'), [],
    'empty upstream stream produces no values');

my $object = { keep => ['a.b'] };
is(refaddr(JQ::Lite::Util::_apply_split($object, '.')),
    refaddr($object), 'object passthrough retains identity');
my ($ok, $out) = JQ::Lite::Builtin->dispatch(
    $jq, 'split(".")', [$object, undef, 'a.b']
);
ok($ok, 'split remains registered as a nonempty-argument filter');
is_deeply($out, [$object, undef, ['a','b']],
    'direct dispatch retains input slots and passthrough objects');
is(refaddr($out->[0]), refaddr($object),
    'dispatch preserves object reference identity');
my ($empty_match) =
    JQ::Lite::Builtin->dispatch($jq, 'split()', ['a.b']);
ok(!$empty_match, 'split() without an argument stays unregistered');
my ($empty_stream_match, $empty_out) =
    JQ::Lite::Builtin->dispatch($jq, 'split(".")', []);
ok($empty_stream_match, 'split matches on an empty direct input stream');
is_deeply($empty_out, [], 'no values are emitted for an empty input stream');

done_testing;
