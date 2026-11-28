use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;

sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

my $json = '{"a":1,"b":2,"nested":{"k":3}}';

is_deeply(results($json, 'getpath(["a"])'), [1],
    'getpath reads a single literal field path');
is_deeply(results($json, 'getpath(["nested","k"])'), [3],
    'getpath reads a nested literal field path');
is_deeply(results($json, 'getpath([])'),
    [{a=>1,b=>2,nested=>{k=>3}}],
    'getpath empty path returns root object');
is_deeply(results($json, 'getpath([["a"],["missing"],["b"]])'),
    [[1, undef, 2]],
    'getpath literal path list retains missing/null slots and ordering');
is_deeply(results($json, 'setpath(["a"]; 9)'),
    [{a=>9,b=>2,nested=>{k=>3}}],
    'setpath updates single literal field');
is_deeply(results($json, 'setpath([["a"],["b"]]; 9)'),
    [{a=>9,b=>9,nested=>{k=>3}}],
    'setpath applies literal multi-path updates in order');
is_deeply(results($json, 'setpath([]; {"x":7})'), [{x=>7}],
    'setpath empty literal path replaces root');
is_deeply(results('[10,20,30]', 'getpath([-1])'), [30],
    'negative literal index remains available');
is_deeply(results('[10,20,30]', 'setpath([-1]; 9)'),
    [[10,20,9]], 'setpath negative index remains available');

for my $call (qw(getpath setpath)) {
    my $filter = $call eq 'getpath'
        ? 'getpath("a")' : 'setpath("a"; 9)';
    my $ok = eval { $jq->run_query($json, $filter); 1 };
    ok(!$ok, "$call rejects scalar literal instead of an array path");
    like("$@", qr/^\Q$call\E\(\): path must be an array/,
        "$call uses its own array-path diagnostic");

    $filter = $call eq 'getpath'
        ? 'getpath(["a",null])' : 'setpath(["a",null]; 9)';
    $ok = eval { $jq->run_query($json, $filter); 1 };
    ok(!$ok, "$call rejects literal null segments");
    like("$@", qr/^\Q$call\E\(\): path elements must be defined/,
        "$call preserves its null-segment diagnostic");

    $filter = $call eq 'getpath'
        ? 'getpath([["a"],["b",{}]])'
        : 'setpath([["a"],["b",{}]]; 9)';
    $ok = eval { $jq->run_query($json, $filter); 1 };
    ok(!$ok, "$call rejects invalid segments in multi-path literals");
    like("$@", qr/^\Q$call\E\(\): path elements must be scalars/,
        "$call validates every multi-path member");
}

# Direct tests of the shared validation preserve empty root and v2 path-list
# interpretations independently from expression evaluation.
is_deeply(
    [JQ::Lite::Util::_validate_literal_paths([], 'getpath')], [[]],
    'empty JSON array is one empty root path, not an empty stream'
);
is_deeply(
    [JQ::Lite::Util::_validate_literal_paths([['a'], ['b']], 'setpath')],
    [['a'], ['b']], 'array-of-arrays yields ordered literal paths'
);
for my $caller (qw(getpath setpath)) {
    my $ok = eval {
        JQ::Lite::Util::_validate_literal_paths({bad=>1}, $caller);
        1;
    };
    ok(!$ok, "$caller direct validation rejects object literal");
    like("$@", qr/^\Q$caller\E\(\): path must be an array/,
        "$caller direct validation keeps its error prefix");
}

done_testing;
