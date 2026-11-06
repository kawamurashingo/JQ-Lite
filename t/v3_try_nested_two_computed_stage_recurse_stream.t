use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->allow_nonref;

sub results {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

my $input = '{"first":"children","second":"list","children":{"list":[{"first":"children","second":"list","id":1,"children":{"list":[]}},{"first":"children","second":"list","id":2,"children":{"list":[]}},{"first":"children","second":"list","id":3,"children":{"list":[]}}]}}';
my $nested = '{"first":"children","second":"list","children":{"list":[{"first":"children","second":"list","id":1,"children":{"list":[{"first":"children","second":"list","id":4,"children":{"list":[]}}]}},{"first":"children","second":"list","id":2,"children":{"list":[]}},{"first":"children","second":"list","id":3,"children":{"list":[]}}]}}';
my $root = $json->decode($input);
my $first = $root->{children}{list}[0];
my $prior = [$root,$first];
my $child = 'recurse(.[.first][.second][]? | if .id == 2 then (1/0) else . end)';

subtest 'two computed stages retain completed outputs' => sub {
    is_deeply(results($input, "try (. | ($child | .)) catch 42"),
        [@$prior,42], 'root and first child precede later error');
    is_deeply(results($input, "try (. | ($child | .))"),
        $prior, 'implicit empty handler retains previous nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch empty"),
        $prior, 'explicit empty handler retains previous nodes');
    is_deeply(results($input, "try (. | ($child | .)) catch null"),
        [@$prior,undef], 'catch null follows previous values');
    is_deeply(results($input, "try (. | ($child | .)) catch (42,43)"),
        [@$prior,42,43], 'multi-output handler follows previous values');
    is_deeply(results($input, "try (. | ($child | type)) catch type"),
        ['object','object','string'], 'error reaches type handler as string');
    my $tree = $json->decode($nested);
    is_deeply(results($nested, "try (. | ($child | .)) catch 42"),
        [$tree,$tree->{children}{list}[0],
         $tree->{children}{list}[0]{children}{list}[0],42],
        'depth-first descendants precede a later sibling error');
};

subtest 'pipeline ordering and outer inputs' => sub {
    is_deeply(results($input, "try (. | ($child | (.,0))) catch 42"),
        [$root,0,$first,0,42], 'comma tail follows each completed node');
    is_deeply(results($input, "try (. | (($child | .),99)) catch 42"),
        [@$prior,42], 'later comma alternative does not run');
    is_deeply(results($input, "try (. | (($child | .))) catch 42"),
        [@$prior,42], 'extra parentheses preserve emitted stream');
    is_deeply(results($input,
        "try (. | ($child | if .id == 1 then (1/0) else . end)) catch 42"),
        [$root,42], 'tail failure prevents expansion of later children');
    my $other = '{"first":"children","second":"list","children":{"list":[]}}';
    is_deeply(results("[$input,$other]",
        "try (.[] | ($child | type)) catch 42"),
        ['object','object',42], 'outer array stops on first child error');
    is_deeply(results('{"groups":[' . $input . ',' . $other . ']}',
        "try (.groups[] | ($child | type)) catch 42"),
        ['object','object',42], 'outer named iterator stops on first error');
};

subtest 'selector error and child iteration boundaries' => sub {
    is_deeply(results('null', "try (. | ($child | .)) catch 42"),
        [undef,42], 'null root emits before invalid computed selector');
    is_deeply(results('3', "try (. | ($child | .)) catch 42"),
        [3,42], 'number root emits before computed selector error');
    is_deeply(results('{}', "try (. | ($child | .)) catch 42"),
        [{},42], 'missing first key raises before optional []?');
    is_deeply(results('{"first":null,"second":"list"}',
        "try (. | ($child | .)) catch 42"),
        [{first=>undef,second=>'list'},42], 'null first key errors');
    is_deeply(results('{"first":"children","second":null,"children":{"list":[]}}',
        "try (. | ($child | .)) catch 42"),
        [{first=>'children',second=>undef,children=>{list=>[]}},42],
        'null second key errors');
    is_deeply(results('{"first":"children","second":"list"}',
        "try (. | ($child | .)) catch 42"),
        [{first=>'children',second=>'list'}],
        'optional []? skips absent selected array');
    is_deeply(results('{"first":"children","second":"list","children":{"list":null}}',
        "try (. | ($child | .)) catch 42"),
        [{first=>'children',second=>'list',children=>{list=>undef}}],
        'optional []? skips null selected array');
    is_deeply(results('{"first":"children","second":"list","children":{"list":[]}}',
        "try (. | ($child | .)) catch 42"),
        [{first=>'children',second=>'list',children=>{list=>[]}}],
        'empty array ends normally');

    my $strict = 'recurse(.[.first][.second][] | .)';
    is_deeply(results('{"first":"children","second":"list"}',
        "try (. | ($strict | .)) catch 42"),
        [{first=>'children',second=>'list'},42],
        'strict [] errors on absent selected array');
    is_deeply(results('{"first":"children","second":"list","children":{"list":null}}',
        "try (. | ($strict | .)) catch 42"),
        [{first=>'children',second=>'list',children=>{list=>undef}},42],
        'strict [] errors on selected null');
    is_deeply(results('{"first":"children","second":"list","children":{"list":[]}}',
        "try (. | ($strict | .)) catch 42"),
        [{first=>'children',second=>'list',children=>{list=>[]}}],
        'strict [] accepts empty array');
    my $missing = '{"first":"children","second":"list","children":{"list":[{"id":1}]}}';
    is_deeply(results($missing,
        'try (. | (recurse(.[.first][.second][]? | .) | .)) catch 42'),
        [$json->decode($missing),{id=>1},42],
        'later child selector error retains already emitted child');
};

subtest 'child filtering and computed selector controls' => sub {
    is_deeply(results($input,
        'try (. | (recurse(.[.first][.second][]? | empty) | .)) catch 42'),
        [$root], 'empty custom child stream yields only root');
    is_deeply(results($input,
        'try (. | (recurse(.[.first][.second][]? | if .id == 2 then empty else . end) | .)) catch 42'),
        [$root,$first,$root->{children}{list}[2]],
        'one empty child result skips only that sibling');
    is_deeply(results($input,
        'try (. | (recurse(.[.first][.second][]? | (.,.)) | type)) catch 42'),
        [('object') x 7], 'duplicate child outputs retain depth-first order');
    is_deeply(results($input,
        'try (. | (recurse(.[.first][.second][] | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [@$prior,42], 'strict child iterator preserves emitted results');
    is_deeply(results($input, "try ($child | type) catch 42"),
        ['object','object',42], 'unwrapped custom recurse remains unchanged');

    my $configured = $json->decode($input);
    sub decorate {
        my ($v) = @_;
        $v->{cfg} = { first=>'children', second=>'list' };
        delete $v->{first};
        delete $v->{second};
        for my $kid (@{$v->{children}{list}}) {
            decorate($kid);
        }
    }
    decorate($configured);
    is_deeply(results($json->encode($configured),
        'try (. | (recurse(.[.cfg.first][.cfg.second][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$configured,$configured->{children}{list}[0],42],
        'dotted computed selectors resolve on every recursion node');

    my $special = {
        first=>'a.b',second=>'full name',
        'a.b'=>{'full name'=>[
            {first=>'a.b',second=>'full name',id=>1,
                'a.b'=>{'full name'=>[]}},
            {first=>'a.b',second=>'full name',id=>2,
                'a.b'=>{'full name'=>[]}}
        ]}
    };
    is_deeply(results($json->encode($special),
        "try (. | ($child | .)) catch 42"),
        [$special,$special->{'a.b'}{'full name'}[0],42],
        'separate computed keys may contain literal punctuation');
};

done_testing;
