use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Builtin ();
use JQ::Lite::Util ();

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

done_testing;
