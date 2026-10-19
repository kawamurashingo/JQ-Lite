use strict;
use warnings;
use Test::More;
use JSON::PP;
use JQ::Lite;
use JQ::Lite::Util ();
use Scalar::Util ();
use utf8;

my $jq = JQ::Lite->new;

my $json = encode_json({ users => [ { name => 'Alice' }, { name => 'Bob' } ] });
my @first_three = $jq->run_query($json, '.users[].name | substr(0, 3)');
is_deeply(\@first_three, ['Ali', 'Bob'], 'substr(0, 3) slices expected prefixes');

my @from_index = $jq->run_query($json, '.users[0].name | substr(2)');
is($from_index[0], 'ice', 'substr(2) without length returns remainder of string');

my @last_char = $jq->run_query($json, '.users[].name | substr(-1)');
is_deeply(\@last_char, ['e', 'b'], 'substr(-1) returns final character for each name');

my @boolean_slice = $jq->run_query('true', 'substr(1, 2)');
is($boolean_slice[0], 'ru', 'substr() stringifies booleans before slicing');

my @boolean_array = $jq->run_query('[true, false]', 'substr(0, 3)');
is_deeply($boolean_array[0], ['tru', 'fal'], 'substr() maps across arrays of booleans');

my $json_words = encode_json({ words => [ 'Perl', 'JSON' ] });
my @array_slice = $jq->run_query($json_words, '.words | substr(0, 2)');
is_deeply($array_slice[0], ['Pe', 'JS'], 'substr applies element-wise to arrays');

my $json_null = encode_json({ name => undef });
my @null_slice = $jq->run_query($json_null, '.name | substr(0, 2)');
ok(!defined $null_slice[0], 'substr preserves undef for downstream defaults');

my @no_args = $jq->run_query($json, '.users[1].name | substr');
is($no_args[0], 'Bob', 'substr with no arguments returns original value');

my $non_numeric_start_ok = eval { $jq->run_query($json, '.users[0].name | substr("foo")') };
ok(!$non_numeric_start_ok && $@ =~ /substr\(\): start index must be numeric/,
    'substr() rejects non-numeric start argument');

my $non_numeric_length_ok = eval { $jq->run_query($json, '.users[0].name | substr(0, "bar")') };
ok(!$non_numeric_length_ok && $@ =~ /substr\(\): length must be numeric/,
    'substr() rejects non-numeric length argument');

# Compare the new per-array bound cache against the original recursive
# helper, including lazy rejection of bad bounds on scalar leaves only.
sub _original_recursive_substr {
    my ($value, @args) = @_;

    if (ref $value eq 'ARRAY') {
        return [ map { _original_recursive_substr($_, @args) } @$value ];
    }

    return undef if !defined $value;
    if (JSON::PP::is_bool($value)) {
        $value = $value ? 'true' : 'false';
    }
    elsif (ref $value) {
        return $value;
    }

    my ($start, $length) = @args;
    if (defined $start && !Scalar::Util::looks_like_number($start)) {
        die 'substr(): start index must be numeric';
    }
    $start = 0 unless defined $start;
    $start = int($start);

    if (defined $length) {
        if (!Scalar::Util::looks_like_number($length)) {
            die 'substr(): length must be numeric';
        }
        $length = int($length);
        return substr($value, $start, $length);
    }

    return substr($value, $start);
}

my $parser = JSON::PP->new->allow_nonref;
my @recursive_cases = (
    ['"abcdef"', 1, 3, '"bcd"', 'direct string'],
    ['["abcd","xyz"]', 1, 2, '["bc","yz"]', 'array siblings'],
    ['["abc",["def",null,{}],"xy"]', 1, 1,
        '["b",["e",null,{}],"y"]', 'nested arrays and passthrough'],
    ['[[],[[]],null,{"flag":true}]', 'invalid', 'also invalid',
        '[[],[[]],null,{"flag":true}]', 'passthrough-only lazy bounds'],
    ['[true,false,"false"]', 1, 3, '["rue","als","als"]',
        'JSON booleans and string'],
    ['[12,3.5,-2]', 1, undef, '["2",".5","2"]',
        'numeric values'],
    ['[["abc"],["x"],[]]', -2, undef, '[["bc"],["x"],[]]',
        'negative start'],
    ['["abcdef","1234"]', 2, -1, '["cde","3"]',
        'negative length'],
    ['["","abc",["x"]]', 0, 0, '["","",[""]]',
        'zero length'],
    ['["abcdef",["xy"]]', "1", "2", '["bc",["y"]]',
        'numeric string bounds'],
    ['["abcdef",["xy"]]', 1.9, 1.8, '["b",["y"]]',
        'fractional bounds truncated'],
    ['["あいう",["かきく"]]', 1, 1, '["い",["き"]]',
        'Unicode code-point slicing'],
    ['[null,{},["abcd",false,[]]]', undef, undef,
        '[null,{},["abcd","false",[]]]', 'default start and length'],
);

for my $case (@recursive_cases) {
    my ($input, $start, $length, $expected, $name) = @$case;
    my $value = $parser->decode($input);
    my $original = $parser->decode($input);
    my $untouched = $parser->decode($input);
    my @args = ($start, $length);

    my $actual = JQ::Lite::Util::_apply_substr($value, @args);
    is_deeply($actual, _original_recursive_substr($original, @args),
        "cached substr matches original: $name");
    is_deeply($actual, $parser->decode($expected),
        "cached substr exact output: $name");
    is_deeply($value, $untouched, "cached substr does not mutate input: $name");
    is_deeply(\@args, [$start, $length],
        "cached substr leaves original bounds unchanged: $name");
}

my $many_values = [ ('abcd') x 257 ];
is_deeply(JQ::Lite::Util::_apply_substr($many_values, 1, 2),
    [ ('bc') x 257 ], 'cached substr handles 257 ordered scalar leaves');
is_deeply($many_values, [ ('abcd') x 257 ],
    'cached substr leaves long input unchanged');

for my $case (
    ['["x",null]', 'bad', 2, qr/start index must be numeric/,
        'invalid start after scalar leaf'],
    ['[null,{},["x"]]', 0, 'bad', qr/length must be numeric/,
        'invalid length after passthrough leaves'],
    ['"abc"', 'bad', 2, qr/start index must be numeric/,
        'scalar still rejects invalid start'],
    ['"abc"', 0, 'bad', qr/length must be numeric/,
        'scalar still rejects invalid length'],
) {
    my ($input, $start, $length, $error, $name) = @$case;
    my $value = $parser->decode($input);
    my $ok = eval { JQ::Lite::Util::_apply_substr($value, $start, $length); 1 };
    ok(!$ok, "$name: error raised");
    like($@, $error, "$name: error message retained");
}

my @public_nested = $jq->run_query(
    '[["abcd",true],[null,{"k":1},"xyz"]]', 'substr(1,2)');
is_deeply(\@public_nested, [[['bc','ru'],[undef,{ k => 1 },'yz']]],
    'public substr keeps nested arrays, booleans and objects');

my @public_stream = $jq->run_query(
    '[["abcd","xy"],["mnop","qr"]]', '.[] | substr(1,2)');
is_deeply(\@public_stream, [['bc','y'],['no','r']],
    'public substr keeps ordered multi-root streams');

my @public_empty = $jq->run_query('[1,2]', '.[] | empty | substr(1,2)');
is_deeply(\@public_empty, [], 'public substr keeps empty upstream empty');

is_deeply(JQ::Lite::Util::_apply_substr(['abcd','xyz'], 1, 2, 99),
    ['bc','yz'], 'numeric extra argument is ignored in recursive substr');
is_deeply(JQ::Lite::Util::_apply_substr(['abcd','xyz'], 1, 2, [99]),
    ['bc','yz'], 'array-reference extra argument is ignored in recursive substr');
is_deeply([ $jq->run_query('["abcd","xyz"]', 'substr(1,2,99)') ],
    [['bc','yz']], 'public recursive substr ignores extra arguments');

done_testing;
