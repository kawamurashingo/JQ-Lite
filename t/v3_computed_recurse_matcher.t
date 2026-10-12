use strict;
use warnings;
use Test::More;
use JQ::Lite;

my @audited = (
    '.[.field][]? | .',
    '.[.cfg.key][] | .',
    '.[.cfg["key"]][]? | .',
    '.[.cfg."key"][] | .',
    '.[.keys[0]][]? | .',
    '.[.cfg.names[0][0]][]? | .',
    '.[.cfg.names[0][0][0]][]? | .',
    '.[.keys[0]?][]? | .',
    '.[.cfg["names"][-1]?][] | .',
    '.[.cfg.names[0]?[0]?][]? | .',
    '.[.cfg["a"][0]?][.cfg.b[-1]?][]? | .',
    '.[.cfg["names"][-1][0][-1]][] | .',
    '.[.cfg["names"][-1][-1]][] | .',
    '.[.cfg."names"[-1][0]][]? | .',
    '.[.cfg["a]b"]][]? | .',
    '.[.cfg["a|b"]][]? | .',
    '.[.a][.b][]? | .',
    '.[.cfg["a"]][.cfg."b"][]? | .',
    '.[.a[0]][.b[-1]][]? | .',
    '.[.a][.b][.c][]? | .',
    '.[.cfg["a"][0]][.cfg."b"[0]][.cfg.c[-1]][]? | .',
    '.[.a][.b][.c][.d][]? | .',
    '.[.cfg["a"][0]][.cfg."b"[0]][.cfg.c[-1]][.cfg.d[0]][] | .',
);

for my $child (@audited) {
    ok(JQ::Lite::Util::_has_scoped_computed_recurse_child($child),
        "null-node scope includes $child");
    my $nested = "try (. | (recurse($child) | .)) catch 42";
    ok(JQ::Lite::Util::_is_nested_scoped_computed_recurse($nested),
        "nested stream scope matches $child");
}

my @excluded = (
    '.[]? | .',
    '.items[]? | .',
    '.[.a[]][]? | .',
    '.[.a[1+2]][]? | .',
    '.[.a[0:2]][]? | .',
    '.[.a | .b][]? | .',
    '.[.a][.b][.c][.d][.e][]? | .',
    '.[.cfg.names[0][0][0][0]][]? | .',
    '.[.a][.b][][]? | .',
    '.[.a][]? garbage | .',
    'prefix .[.a][]? | .',
);
for my $child (@excluded) {
    ok(!JQ::Lite::Util::_has_scoped_computed_recurse_child($child),
        "null-node scope excludes $child");
}
ok(!JQ::Lite::Util::_is_nested_scoped_computed_recurse(
    'try (. | (recurse(.[.a[]][]? | .) | .)) catch 42'),
    'unsupported selector is excluded from nested dispatch');
ok(!JQ::Lite::Util::_is_nested_scoped_computed_recurse(
    'try (. | (recurse(.items[]? | .) | .)) catch 42'),
    'named-field recurse keeps its separate existing dispatch');

is(JQ::Lite::Util::_has_scoped_computed_recurse_child(undef),0,
    'undefined child filter is not recognized');
is(JQ::Lite::Util::_is_nested_scoped_computed_recurse(undef),0,
    'undefined nested expression is not recognized');

done_testing;
