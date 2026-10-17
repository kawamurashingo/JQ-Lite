use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Util ();
use FindBin ();
use File::Spec ();

# Each builtin subpackage previously supported direct require/register without
# first loading the parent registry. Verify that contract in fresh processes:
# this test process has already loaded JQ::Lite and cannot test load order.
my $lib = File::Spec->catdir($FindBin::Bin, '..', 'lib');
my $standalone = <<'PERL';
use strict;
use warnings;
use JSON::PP ();
my ($module, $builtin, $input, $expected) = @ARGV;
my $package = "JQ::Lite::Builtin::$module";
my $file = "$package.pm";
$file =~ s{::}{/}g;
require $file;
die "parent loaded implicitly" if exists $INC{'JQ/Lite/Builtin.pm'};
my %handlers;
$package->register(sub {
    my ($names, $handler) = @_;
    return if ref($names) eq 'Regexp';
    my @names = ref($names) eq 'ARRAY' ? @$names : ($names);
    $handlers{$_} = $handler for @names;
});
die "missing standalone handler: $builtin" unless $handlers{$builtin};
my $json = JSON::PP->new->allow_nonref->canonical;
my $value = $json->decode($input);
my $got = $handlers{$builtin}->(undef, [$value]);
die "unexpected standalone result" unless
    $json->encode($got) eq $json->encode($json->decode($expected));
die "parent loaded by registration" if exists $INC{'JQ/Lite/Builtin.pm'};
PERL
for my $case (
    ['Array', 'first', '[3,4]', '[3]'],
    ['Array', 'flatten', '[[1],[2]]', '[[1,2]]'],
    ['String', 'upper', '"hello"', '["HELLO"]'],
    ['Math', 'ceil', '1.2', '[2]'],
    ['Math', 'to_number', '"12"', '[12]'],
    ['Encoding', '@uri', '"a b"', '["a%20b"]'],
    ['Object', 'to_entries', '{"b":2,"a":1}',
     '[[{"key":"a","value":1},{"key":"b","value":2}]]'],
) {
    my ($module, $builtin, $input, $expected) = @$case;
    is(system($^X, "-I$lib", '-e', $standalone,
              $module, $builtin, $input, $expected), 0,
       "standalone $module registration works without loading parent");
}

my $jq = JQ::Lite->new;

sub run {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# Exercise the dependency-safe private shared mapper without binding to a specific
# builtin implementation: one callback call and one result per input.
my $calls = 0;
my $twice = JQ::Lite::Util::_stream_map(sub {
    $calls++;
    return defined $_[0] ? $_[0] * 2 : undef;
});
my @numbers = (1, 2, undef, 0);
is_deeply($twice->(undef, \@numbers), [2, 4, undef, 0],
    'stream mapper preserves ordered values and null slots');
is($calls, 4, 'one callback call per input');
is_deeply(\@numbers, [1, 2, undef, 0],
    'stream mapper does not change caller input list');

$calls = 0;
is_deeply($twice->(undef, []), [],
    'empty inputs create an empty result array');
is($calls, 0, 'empty inputs never invoke callback');

my $identity = JQ::Lite::Util::_stream_map(sub { $_[0] });
my $bool = JSON::PP::true;
my $container = { key => [1,2] };
my $unchanged = $identity->(undef, [$bool, $container, undef]);
is_deeply($unchanged, [$bool, $container, undef],
    'mapper does not flatten containers or drop null and boolean values');
is($unchanged->[1], $container,
    'mapper preserves unmodified reference identity');

my $caught = eval {
    my $fail = JQ::Lite::Util::_stream_map(sub {
        die "callback failure\n" if $_[0] == 2;
        return $_[0];
    });
    $fail->(undef, [1,2,3]);
    1;
};
my $error = $@;
ok(!$caught, 'callback errors are not swallowed');
like("$error", qr/callback failure/,
    'callback exception content is preserved');

# Each group now calls the same mapper but retains distinct scalar semantics.
my @public_cases = (
    ['["one","two",""]', '.[] | upper',
     ['ONE','TWO',''], 'string uppercase'],
    ['["One","TWO"]', '.[] | lower',
     ['one','two'], 'string lowercase'],
    ['["foo","BAR"]', '.[] | titlecase',
     ['Foo','Bar'], 'string titlecase'],
    ['["a","b"]', '.[] | tojson',
     ['"a"','"b"'], 'string tojson'],
    ['[1,null,"x"]', '.[] | tostring',
     ['1','null','x'], 'string tostring with null'],
    ['["  a  "," b "]', '.[] | trim',
     ['a','b'], 'string trim'],
    ['["true","2","not-json"]', '.[] | fromjson',
     [JSON::PP::true,2,'not-json'], 'string fromjson fallback'],
    ['[1.2,-1.2,2]', '.[] | ceil',
     [2,-1,2], 'math ceil'],
    ['[1.8,-1.2,2]', '.[] | floor',
     [1,-2,2], 'math floor'],
    ['[1.5,-1.5,0]', '.[] | round',
     [2,-2,0], 'math round'],
    ['["2",true,false,"text"]', '.[] | to_number',
     [2,1,0,'text'], 'math to_number preserves nonnumeric'],
    ['["2","4"]', '.[] | tonumber',
     [2,4], 'math tonumber'],
    ['["a b","a/b",null]', '.[] | @uri',
     ['a%20b','a%2Fb','null'], 'encoding uri'],
    ['["a","b"]', '.[] | @base64',
     ['YQ==','Yg=='], 'encoding base64'],
    ['["YQ==","Yg=="]', '.[] | @base64d',
     ['a','b'], 'encoding base64 decode'],
    ['[[1,"1"],["a","b"]]', '.[] | @csv',
     ['1,"1"','"a","b"'], 'encoding csv'],
    ['[[1,"1"],["a","b"]]', '.[] | @tsv',
     ["1\t1","a\tb"], 'encoding tsv'],
    ['[{"b":2,"a":1},{"x":3}]', '.[] | to_entries',
     [[{key=>'a',value=>1},{key=>'b',value=>2}],
      [{key=>'x',value=>3}]], 'object to_entries'],
    ['[[{"key":"a","value":1}],[{"key":"b","value":2}]]',
     '.[] | from_entries',
     [{a=>1},{b=>2}], 'object from_entries'],
    ['[[{"a":1},{"b":2}],[{"c":3}]]', '.[] | merge_objects',
     [{a=>1,b=>2},{c=>3}], 'object merge_objects'],
    ['[[1,2],[],[9]]', '.[] | first',
     [1,undef,9], 'array first'],
    ['[[1,2],[],[9]]', '.[] | last',
     [2,undef,9], 'array last'],
    ['[[1,2,3],[],{"keep":1}]', '.[] | rest',
     [[2,3],[],{keep=>1}], 'array rest and object passthrough'],
    ['[[1,2,3],"abc",123]', '.[] | reverse',
     [[3,2,1],'cba',123], 'array/string reverse and number passthrough'],
    ['[[[1,[2]],3],[],{"x":[[4]]}]', '.[] | flatten',
     [[1,[2],3],[],{x=>[[4]]}], 'array flatten one level'],
    ['[[[1,[2]],3],[],{"x":[[4]]}]', '.[] | flatten_all',
     [[1,2,3],[],{x=>[[4]]}], 'array flatten recursively'],
    ['[[null,false,0,"",4],[],null]', '.[] | compact',
     [[JSON::PP::false,0,'',4],[],undef], 'array compact retains falsey nonnull'],
    ['[[null,1],[2,null]]', '.[] | compact()',
     [[1],[2]], 'compact parenthesized alias'],
    ['[[1,[2]],[[3]]]', '.[] | flatten()',
     [[1,2],[3]], 'flatten parenthesized alias'],
    ['[[1,[2]],[[3]]]', '.[] | flatten_all()',
     [[1,2],[3]], 'flatten_all parenthesized alias'],
);
for my $case (@public_cases) {
    my ($input, $filter, $expected, $name) = @$case;
    is_deeply(run($input, $filter), $expected,
        "public builtin stream order and cardinality: $name");
}

for my $filter ('upper', 'ceil', '@uri', 'to_entries',
               'first', 'last', 'rest', 'reverse',
               'flatten', 'flatten_all', 'compact') {
    is_deeply(run('null', "empty | $filter"), [],
        "empty upstream stays empty: $filter");
}

# Direct dispatch keeps the v2 contracts of each unary Array builtin:
# first/last yield undef for invalid or empty arrays; others pass through.
my $opaque = { keep => [1,2] };
my $truth = JSON::PP::true;
for my $name (qw(rest reverse flatten flatten_all compact)) {
    my ($found, $result) = JQ::Lite::Builtin->dispatch(
        $jq, $name, [$opaque, $truth, undef]
    );
    ok($found, "$name remains registered as a direct builtin");
    is($result->[0], $opaque, "$name preserves object reference identity");
    is($result->[1], $truth, "$name preserves boolean reference identity");
    is_deeply($result, [$opaque, $truth, undef],
        "$name preserves ordered non-array input values");
}
for my $name (qw(first last)) {
    my ($found, $result) = JQ::Lite::Builtin->dispatch(
        $jq, $name, [[], $opaque, undef, [1,2]]
    );
    ok($found, "$name remains registered as a direct builtin");
    is_deeply($result, [undef,undef,undef,$name eq 'first' ? 1 : 2],
        "$name retains one output per input including null fallback");
}

my $ok = eval {
    $jq->run_query('[[],42]', '.[] | from_entries');
    1;
};
my $invalid_error = $@;
ok(!$ok, 'builtin evaluation errors remain fatal in a mapped stream');
like("$invalid_error", qr/from_entries\(\): argument must be an array/,
    'object builtin error wording passes through shared mapper');

is_deeply(run('["z","a"]', '.[] | upper'), ['Z','A'],
    'instance remains reusable after an error');

done_testing;
