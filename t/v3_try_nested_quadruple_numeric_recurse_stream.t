use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;
sub results {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

my $names = [[[['items']]]];
my $node = sub {
    my ($id, $children) = @_;
    return {cfg => {names => $names}, id => $id, items => $children};
};
my $root = {
    cfg => {names => $names},
    items => [$node->(1, []), $node->(2, []), $node->(3, [])],
};
my $input = $json->encode($root);
my $first = $root->{items}[0];
my $child = 'recurse(.[.cfg.names[0][0][0][0]][]? | if .id == 2 then (1/0) else . end)';

subtest 'four numeric stages preserve completed nodes and catch order' => sub {
    is_deeply(results($input, "try (. | ($child | .)) catch 42"),
        [$root, $first, 42], 'completed nodes precede later error');
    is_deeply(results($input, "try (. | ($child | .))"),
        [$root, $first], 'implicit empty handler keeps prior nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch empty"),
        [$root, $first], 'explicit empty handler keeps prior nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch null"),
        [$root, $first, undef], 'null handler follows completed nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch (42,43)"),
        [$root, $first, 42, 43], 'multi-result catch stays ordered');
    is_deeply(results($input, "try (. | ($child | type)) catch type"),
        ['object', 'object', 'string'], 'catch receives error string');
    is_deeply(results($input, "try (. | ($child | (.,0))) catch 42"),
        [$root, 0, $first, 0, 42], 'comma tail streams before error');
    is_deeply(results($input, "try (. | (($child | .),99)) catch 42"),
        [$root, $first, 42], 'later alternative is not evaluated');
    is_deeply(results($input,
        "try (. | ($child | if .id == 1 then (1/0) else . end)) catch 42"),
        [$root, 42], 'tail error stops expansion');
};

subtest 'nested descendants retain depth-first traversal' => sub {
    my $tree = {
        cfg => {names => $names},
        items => [
            $node->(1, [$node->(4, [])]),
            $node->(2, []),
            $node->(3, []),
        ],
    };
    is_deeply(results($json->encode($tree),
        "try (. | ($child | .)) catch 42"),
        [$tree, $tree->{items}[0], $tree->{items}[0]{items}[0], 42],
        'grandchild is emitted before the failing sibling');
    is_deeply(results($input,
        'try (. | (recurse(.[.cfg.names[0][0][0][0]][] | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$root, $first, 42], 'strict child iterator also streams');
    is_deeply(results($input, "try ($child | type) catch 42"),
        ['object', 'object', 42], 'unwrapped recurse remains compatible');
};

subtest 'selector errors and stage-local optionality' => sub {
    is_deeply(results('null', "try (. | ($child | .)) catch 42"),
        [undef, 42], 'null node precedes strict selector error');
    is_deeply(results('3', "try (. | ($child | .)) catch 42"),
        [3, 42], 'scalar node precedes selector error');
    is_deeply(results('{}', "try (. | ($child | .)) catch 42"),
        [{}, 42], 'missing selector produces invalid computed key');
    my $bad = '{"cfg":{"names":3}}';
    is_deeply(results($bad, "try (. | ($child | .)) catch 42"),
        [$json->decode($bad), 42], 'wrong numeric target still raises');
    my $out_of_bounds = '{"cfg":{"names":[[[[]]]]}}';
    is_deeply(results($out_of_bounds,
        "try (. | ($child | .)) catch 42"),
        [$json->decode($out_of_bounds), 42],
        'fourth out-of-range index produces invalid computed key');
    my $missing_selected = '{"cfg":{"names":[[[["items"]]]]}}';
    is_deeply(results($missing_selected,
        "try (. | ($child | .)) catch 42"),
        [$json->decode($missing_selected)],
        'optional child iterator skips absent selected field');
    is_deeply(results($missing_selected,
        'try (. | (recurse(.[.cfg.names[0][0][0][0]][] | .) | .)) catch 42'),
        [$json->decode($missing_selected), 42],
        'strict child iterator errors on absent selected field');
    is_deeply(results($bad,
        'try (. | (recurse(.[.cfg.names[0]?[0][0][0]][]? | .) | .)) catch 42'),
        [$json->decode($bad)],
        'optional first numeric stage skips invalid target');
    is_deeply(results('{}',
        'try (. | (recurse(.[.cfg.names[0][0][0][0]]?[]? | .) | .)) catch 42'),
        [{}], 'optional outer computed lookup skips null key');
};

subtest 'negative indices and parser boundary' => sub {
    my $neg_names = [[[['unused', 'items']]]];
    my $negative = {
        cfg => {names => $neg_names},
        items => [
            {cfg => {names => $neg_names}, id => 1, items => []},
            {cfg => {names => $neg_names}, id => 2, items => []},
        ],
    };
    is_deeply(results($json->encode($negative),
        'try (. | (recurse(.[.cfg["names"][-1][-1][-1][-1]][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$negative, $negative->{items}[0], 42],
        'four negative indices select final nested key');
    is_deeply(JQ::Lite::Util::_parse_v3_computed_selector_fields(
        '.cfg.names[0][0][0][0]'),
        ['cfg', 'names', ['index',0], ['index',0], ['index',0],
            ['index',0]], 'parser already supports four index stages');
    ok(JQ::Lite::Util::_has_scoped_computed_recurse_child(
        '.[.cfg.names[0][0][0][0]][]? | .'),
        'four numeric stages are inside scoped recurse matcher');
    ok(!JQ::Lite::Util::_has_scoped_computed_recurse_child(
        '.[.cfg.names[0][0][0][0][0]][]? | .'),
        'five numeric stages remain outside scoped matcher');
    ok(!JQ::Lite::Util::_has_scoped_computed_recurse_child(
        '.[.cfg.names[0][0][0][1+1]][]? | .'),
        'computed arithmetic remains outside matcher');
};

done_testing;
