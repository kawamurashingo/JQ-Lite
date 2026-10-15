use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;

sub split_colon {
    return [JQ::Lite::Util::_split_top_level_colon($_[0])];
}

for my $case (
    [undef, [], 'undefined input returns no parts'],
    ['', [], 'empty string has no separator'],
    ['key:value', ['key','value'], 'simple field separator'],
    ['key:value:more', ['key','value:more'], 'only first top-level colon splits'],
    [':value', ['','value'], 'empty left side retained'],
    ['key:', ['key',''], 'empty right side retained'],
    ['"x:y":.a', ['"x:y"','.a'], 'quoted colon inside key is protected'],
    ["'x:y':.a", ["'x:y" . "'",'.a'], 'single-quoted colon is protected'],
    ['{"a":1}:next', ['{"a":1}','next'], 'nested object key colon is protected'],
    ['[1:2]:next', ['[1:2]','next'], 'nested bracket colon is protected'],
    ['(a:b):next', ['(a:b)','next'], 'nested parentheses protect colons'],
    ['{"a":[1:2]}:rest', ['{"a":[1:2]}','rest'], 'nested arrays and objects protect colons'],
    ['"a\\":b":next', ['"a\\":b"','next'], 'escaped quote keeps inner colon protected'],
    ['key]:value', [], 'invalid unmatched closing bracket rejects split'],
    ['(key:value', [], 'unclosed opening paren yields no top-level split'],
    ['key:value)', ['key','value)'], 'first valid split returned before later invalid close'],
) {
    my ($input, $expected, $label) = @$case;
    is_deeply(split_colon($input), $expected, $label);
}

sub run {
    my ($json, $query) = @_;
    return [ $jq->run_query($json, $query) ];
}

is_deeply(run('{"name":"Ada"}', '{name: .name}'), [{name=>'Ada'}],
    'unquoted object constructor field');
is_deeply(run('{"name":"Ada"}', '{"a:b": .name}'), [{'a:b'=>'Ada'}],
    'quoted colon in object constructor key');
is_deeply(run('{"name":"Ada"}', '{nested: {name: .name}}'),
    [{nested=>{name=>'Ada'}}], 'nested object constructor');
is_deeply(run('{"name":"Ada"}', '{missing: .missing}'), [{missing=>undef}],
    'object constructor preserves missing as explicit null');
is_deeply(run('[{"name":"Ada"},{"name":"Ben"}]', '.[] | {name: .name}'),
    [{name=>'Ada'},{name=>'Ben'}], 'object constructors preserve iterator order');
is_deeply(run('{"x":1,"y":2}', '{left: .x, right: .y}'),
    [{left=>1,right=>2}], 'multiple object fields remain distinct');

done_testing;
