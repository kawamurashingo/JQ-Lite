use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Error ();
use JQ::Lite::Parser ();
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;

sub results {
    my ($json, $query) = @_;
    return [ $jq->run_query($json, $query) ];
}

sub error_for {
    my ($json, $query, $fragment, $description) = @_;
    my $ok = eval { $jq->run_query($json, $query); 1 };
    my $err = $@;
    ok(!$ok, "$description: query fails");
    if (!$ok) {
        isa_ok($err, 'JQ::Lite::Error::Evaluation',
            "$description: structured runtime failure");
        like("$err", qr/\Q$fragment\E/,
            "$description: error explains wrong type or stage");
    }
}

subtest 'simple computed field selector reads a field from input' => sub {
    is_deeply(results('{"key":"name","name":"Ada"}', '.[.key]'),
        ['Ada'], 'string key selects named field');
    is_deeply(results('{"key":"missing"}', '.[.key]'),
        [undef], 'missing selected field emits null');
    is_deeply(results('{"key":"0","0":"zero"}', '.[.key]'),
        ['zero'], 'numeric-looking STRING remains an object key');
    is_deeply(results('{"key":"","":"empty"}', '.[.key]'),
        ['empty'], 'empty-string computed key is valid');
    is_deeply(results('{"key":"a.b","a.b":7}', '.[.key]'),
        [7], 'computed string with period is a single key');
    is_deeply(results('{"key":"x-y","x-y":8}', '.[.key]'),
        [8], 'computed string with hyphen is a single key');
    is_deeply(results('{"key":"a","a":null}', '.[.key]'),
        [undef], 'explicit null is returned as one result');
    is_deeply(results('{"key":"a","a":false}', '.[.key]'),
        [JSON::PP::false], 'boolean false value is not dropped');
    is_deeply(results('{"key":"a","a":[1,2]}', '.[.key]'),
        [[1,2]], 'selected array is one result, not a stream');
    is_deeply(results('{"cfg":{"selected":"a"},"a":12}',
            '.[.cfg.selected]'),
        [12], 'simple dotted selector resolves against the original root');
};

subtest 'computed root index composes with literal stages' => sub {
    is_deeply(results('{"key":"a","a":[1,2]}',
            '.[.key][]'), [1,2],
        'strict iterator visits computed array field');
    is_deeply(results('{"key":"a","a":[1,2]}',
            '.[.key][]?'), [1,2],
        'optional iterator visits array values');
    is_deeply(results('{"key":"a","a":3}',
            '.[.key][]?'), [],
        'optional iterator drops a numeric computed value');
    is_deeply(results('{"key":"a","a":null}',
            '.[.key][]?'), [],
        'optional iterator drops computed null');
    is_deeply(results('{"key":"a","a":[]}',
            '.[.key][]'), [],
        'strict iterator succeeds for empty computed array');
    is_deeply(results('{"key":"a","a":[{"name":"A"},{"name":"B"}]}',
            '.[.key][].name'), ['A','B'],
        'computed field feeds iterator then literal named field');
    is_deeply(results('{"key":"a","a":[8,9]}',
            '.[.key][0]'), [8],
        'numeric index reads the computed array');
    is_deeply(results('{"key":"a","a":[8,9]}',
            '.[.key][-1]'), [9],
        'negative numeric index reads the computed array');
    is_deeply(results('{"key":"a","a":{"child":8}}',
            '.[.key].child'), [8],
        'named field after computed lookup');
    is_deeply(results('{"key":"a","a":null}',
            '.[.key].child'), [undef],
        'named field read through computed null returns null');
    is_deeply(results('{"key":"missing"}',
            '.[.key][]?'), [],
        'optional iterator drops missing computed result');
    error_for('{"key":"a","a":3}', '.[.key][]',
        'Cannot iterate over number',
        'strict iterator rejects numeric computed value');
    error_for('{"key":"a","a":3}', '.[.key].child',
        'Cannot index number with string "child"',
        'later field lookup is not suppressed');
    error_for('{"key":"a","a":{}}', '.[.key][0][]?',
        'Cannot index object with number',
        'optional final iterator cannot hide bad numeric indexing');
};

subtest 'computed selector rejects invalid types and invalid roots' => sub {
    for my $case (
        ['{"key":null}', 'Cannot index object with null', 'null selector'],
        ['{"key":0}', 'Cannot index object with number', 'number selector'],
        ['{"key":true}', 'Cannot index object with boolean', 'true selector'],
        ['{"key":false}', 'Cannot index object with boolean', 'false selector'],
        ['{"key":["x"]}', 'Cannot index object with array', 'array selector'],
        ['{"key":{"x":1}}', 'Cannot index object with object', 'object selector'],
        ['{}', 'Cannot index object with null', 'missing selector'],
        ['null', 'Cannot index null with null', 'null root'],
        ['1', 'Cannot index number with string "key"', 'number root'],
        ['"abc"', 'Cannot index string with string "key"', 'string root'],
        ['[]', 'Cannot index array with string "key"', 'array root'],
        ['true', 'Cannot index boolean with string "key"', 'boolean root'],
    ) {
        my ($input, $fragment, $description) = @$case;
        error_for($input, '.[.key]', $fragment, $description);
    }
    error_for('{"cfg":{"selected":7}}',
        '.[.cfg.selected]', 'Cannot index object with number',
        'nested computed selector returns number');
    error_for('{"cfg":7}', '.[.cfg.selected]',
        'Cannot index number with string "selected"',
        'nested computed selector cannot read scalar parent');
    error_for('{"key":null}', '.[.key][]?',
        'Cannot index object with null',
        'optional later iterator never hides computed-key type error');
};

subtest 'computed keys resolve separately for each pipeline input' => sub {
    is_deeply(results(
        '{"items":[{"field":"name","name":"A"},{"field":"score","score":2}]}',
        '.items[] | .[.field]'
    ), ['A',2], 'each yielded object supplies its own selector');
    is_deeply(results(
        '{"items":[{"field":"name","name":"A"},{"field":"missing"}]}',
        '.items[] | .[.field]'
    ), ['A',undef], 'missing selected value still emits null');
    is_deeply(results(
        '{"items":[{"field":"tags","tags":[1,2]},{"field":"tags","tags":null}]}',
        '.items[] | .[.field][]?'
    ), [1,2], 'computed key plus optional iterator at next pipeline stage');
    is_deeply(results('{"items":[]}',
        '.items[] | .[.field]'), [],
        'no upstream values cause no computed lookup or error');
    is_deeply(results('{"key":"a","a":7}',
        '.[.key] | . + 1'), [8],
        'computed value feeds subsequent arithmetic');
    is_deeply(results('{"key":"a","a":7}',
        '0, .[.key]'), [0,7],
        'computed lookup works in later comma alternative');
    is_deeply(results('{"key":"a","a":7}',
        '.[.key], .a'), [7,7],
        'computed and literal comma alternatives preserve order');
    error_for('{"items":[{"field":null}]}',
        '.items[] | .[.field]',
        'Cannot index object with null',
        'a bad selector in one streamed object propagates error');
};

subtest 'scoped parser and literal path compatibility' => sub {
    is_deeply(
        JQ::Lite::Util::_parse_v3_literal_iterator_path('.[.key]'),
        [['computed_root','.key']],
        'computed-root parser emits an explicit step');
    is_deeply(
        JQ::Lite::Util::_parse_v3_literal_iterator_path('.[.cfg.field][]?'),
        [['computed_root','.cfg.field'],['iterator',1]],
        'computed selector followed by optional iterator parses in order');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.obj[.key]')),
        'computed selector after an earlier path stage is excluded');
    ok(!defined(JQ::Lite::Util::_parse_v3_literal_iterator_path(
        '.[.keys[]]')),
        'generator-backed selector is excluded until separately audited');
    is_deeply(results('{"key":"x","x":7}', '."key"'),
        ['x'], 'existing dot-quoted field differs from computed key');
    is_deeply(results('{"key":"x","x":7}', '."x"'),
        [7], 'existing dot-quoted field lookup remains intact');
    is_deeply(results('{"items":[{"name":"A"}]}',
        '.["items"][].name'), ['A'],
        'prior quoted iterator path remains intact');
    is_deeply(results('{"items":[[1,2]]}',
        '.items[0][]'), [1,2],
        'prior numeric-index iterator path remains intact');
    is_deeply(results('{"a":null}', '.a[]?'), [],
        'prior optional named-field iterator remains intact');
};

done_testing;
