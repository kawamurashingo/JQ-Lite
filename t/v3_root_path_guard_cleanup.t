use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Parser ();

my $jq = JQ::Lite->new;

# One representative per rooted-path guard shape, with ordinary v2 paths,
# comma ordering and error semantics as controls. The complete jq 1.7
# differential suite remains the integration oracle.
my @cases = (
    ['{"a.b":7}', '."a.b"', [7],
        'strict dot-quoted root remains a field lookup'],
    ['{"obj":{"name":"Ada"}}', '.obj .name', ['Ada'],
        'whitespace before a named dotted suffix'],
    ['{"items":[[2,3]]}', '.items[0] . [1]', [3],
        'whitespace-separated dotted numeric bracket'],
    ['{"items":[{"a.b":7}]}', '.items[0] . ["a.b"]', [7],
        'quoted bracket after a whitespace-separated dot'],
    ['{"obj":{"name":"Ada"},"key":"name"}', '.obj [.key]', ['Ada'],
        'computed context selector retains root'],
    ['{"obj":{"a.b":9}}', '.obj ["a.b"]', [9],
        'quoted selector preceded by whitespace'],
    ['{"items":[1,2]}', '.items [ ]', [1,2],
        'padded strict iterator preserves order'],
    ['{"items":null}', '.items [ ]?', [],
        'optional padded iterator drops null without a result'],
    ['{"items":[4,5]}', '0, .items [ ], 9', [0,4,5,9],
        'comma branches preserve output order'],
    ['null', 'try [ ]', [[]],
        'try empty-array constructor is not a rooted path'],
    ['{"a.b":7}', '["a.b"]', [['a.b']],
        'bare quoted array constructor stays an array'],
    ['{"obj":{"a.b":9}}', '.obj . ["a.b"]', [9],
        'spaced dot and quoted bracket preserve root'],
);

for my $case (@cases) {
    my ($input, $filter, $expected, $description) = @$case;
    is_deeply([$jq->run_query($input, $filter)], $expected, $description);
}

for my $filter ('.obj .name', '.items[0] . [1]', '.obj [.key]',
    '.items [ ]', '.obj ["a.b"]', '."a.b"')
{
    is_deeply([JQ::Lite::Parser::parse_query($filter)], [$filter],
        "parser retains rooted spelling: $filter");
}

my $strict_ok = eval { $jq->run_query('{"items":null}', '.items [ ]'); 1 };
ok(!$strict_ok, 'strict padded iterator fails on null');
isa_ok($@, 'JQ::Lite::Error::Evaluation',
    'strict iterator error retains its structured category');

done_testing;
