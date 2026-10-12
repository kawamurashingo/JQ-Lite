use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Parser ();

my $jq = JQ::Lite->new;

sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

subtest 'try empty array is a constructor, not an iterator' => sub {
    for my $input ('null', '1', '{}', '[1,2]') {
        is_deeply(results($input, 'try []'), [[]],
            "compact empty array constructor on $input");
        is_deeply(results($input, 'try [ ]'), [[]],
            "padded empty array constructor on $input");
    }
    is_deeply(results('null', 'try[ ]'), [[]],
        'try adjacent to padded constructor');
    is_deeply(results('null', 'try[  ]'), [[]],
        'try with multiple bracket interior spaces');
    is_deeply(results('null', "try [\t]"), [[]],
        'try constructor containing a tab');
    is_deeply(results('null', 'try [] catch 9'), [[]],
        'catch is not evaluated when array construction succeeds');
    is_deeply(results('null', 'try [ ] catch 9'), [[]],
        'spaced constructor succeeds without entering catch');
    is_deeply(results('null', 'try ["catch me"]'),
        [['catch me']], 'nonempty array constructor unchanged');
};

subtest 'pipeline and comma context retain array values' => sub {
    is_deeply(results('null', 'try [] | length'), [0],
        'length sees the constructed array');
    is_deeply(results('null', 'try [ ] | length'), [0],
        'length sees the padded constructed array');
    is_deeply(results('null', 'try [ ] | .[]'), [],
        'strict iterator over the resulting empty array emits nothing');
    is_deeply(results('null', 'try [ ] | .[]?'), [],
        'optional iterator over the resulting empty array emits nothing');
    is_deeply(results('null', 'try [] | .[]?'), [],
        'optional iterator works after compact constructor');
    is_deeply(results('null', '0, try []'), [0, []],
        'comma branch does not split compact empty array');
    is_deeply(results('null', '0, try [ ]'), [0, []],
        'comma branch does not split padded empty array');
    is_deeply(results('null', 'try [], 9'), [[], 9],
        'comma branch preserves following constant');
    is_deeply(results('null', 'try [ ], 9'), [[], 9],
        'padded array branch preserves following constant');
};

subtest 'parser boundary and unrelated suffix regressions' => sub {
    is_deeply([JQ::Lite::Parser::parse_query('try []')],
        ['try []'], 'parser keeps compact try-array expression');
    is_deeply([JQ::Lite::Parser::parse_query('try [ ]')],
        ['try [ ]'], 'parser keeps padded try-array expression');
    is_deeply([JQ::Lite::Parser::parse_query('0, try [ ]')],
        ['0, try [ ]'], 'comma parser retains array constructor');
    is_deeply(results('null', '[]'), [[]],
        'ordinary compact array constructor still works');
    is_deeply(results('null', '[ ]'), [[]],
        'ordinary padded array constructor still works');
    is_deeply(results('{"items":[1,2]}', '.items [ ]'), [1,2],
        'rooted literal iterator still expands path values');
    is_deeply(results('{"items":[1,2]}', '.items[ ]?'), [1,2],
        'rooted optional iterator still expands values');
    is_deeply(results('{"a":2,"b":1}', 'keys[]'), ['a','b'],
        'value-returning keys iterator remains expanded');
    is_deeply(results('{"a":2,"b":1}', 'keys []?'), ['a','b'],
        'optional value-producing iterator still expands');
    is_deeply(results('null', 'try .[]'), [undef],
        'try catches a genuine strict iterator error');
};

done_testing;
