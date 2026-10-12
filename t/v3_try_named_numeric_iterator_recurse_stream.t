use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq=JQ::Lite->new;
my $json=JSON::PP->new->allow_nonref;
sub results {
    my ($input,$filter)=@_;
    return [ $jq->run_query($input,$filter) ];
}
my $input='{"items":[[{"id":1,"items":[[]]},{"id":2,"items":[[]]},{"id":3,"items":[[]]}]]}';
my $nested='{"items":[[{"id":1,"items":[[{"id":4,"items":[[]]}]]},{"id":2,"items":[[]]},{"id":3,"items":[[]]}]]}';
my $root=$json->decode($input);
my $first=$root->{items}[0][0];

for my $field ('.items', '.["items"]', '."items"') {
    my $head="recurse($field\[0\][]? | if .id == 2 then (1/0) else . end)";
    subtest "optional indexed named child iterator $field" => sub {
        is_deeply(results($input,"try (. | ($head | .)) catch 42"),
            [$root,$first,42], 'root and prior child survive later failure');
        is_deeply(results($input,"try (. | ($head | .))"),
            [$root,$first], 'implicit catch empty retains previous nodes');
        is_deeply(results($input,"try (. | ($head | .)) catch null"),
            [$root,$first,undef], 'caught null follows previous results');
        is_deeply(results($input,"try (. | ($head | (.,0))) catch 42"),
            [$root,0,$first,0,42], 'comma tail follows each completed node');
        is_deeply(results($input,"try (. | (($head | .),99)) catch 42"),
            [$root,$first,42], 'later comma alternative does not run');
        my $deep=$json->decode($nested);
        is_deeply(results($nested,"try (. | ($head | .)) catch 42"),
            [$deep,$deep->{items}[0][0],$deep->{items}[0][0]{items}[0][0],42],
            'grandchild precedes later failing child');
        is_deeply(results('null',"try (. | ($head | .)) catch 42"),
            [undef], 'optional child iteration stops on null root');
        is_deeply(results('{}',"try (. | ($head | .)) catch 42"),
            [{}], 'optional child iteration skips missing selected array');
        is_deeply(results('{"items":3}',"try (. | ($head | .)) catch 42"),
            [{items=>3},42], 'earlier numeric index type error remains visible');
        my $strict="recurse($field\[0\][] | .)";
        is_deeply(results('null',"try (. | ($strict | .)) catch 42"),
            [undef,42], 'strict iterator expands null after root');
        is_deeply(results('{}',"try (. | ($strict | .)) catch 42"),
            [{},42], 'strict iterator errors on missing selected array');
        is_deeply(results('{"items":[]}',"try (. | ($strict | .)) catch 42"),
            [{items=>[]},42], 'strict iterator errors on null index result');
        is_deeply(results($input,
            "try (. | (recurse($field\[0\][] | if .id == 2 then (1/0) else . end) | .)) catch 42"),
            [$root,$first,42], 'strict indexed child retains completed output');
        is_deeply(results($input,
            "try (. | (recurse($field\[0\][]? | (.,.)) | type)) catch 42"),
            [('object') x 7], 'duplicate child outputs preserve depth-first order');
    };
}

subtest 'negative numeric indices and special literal field names' => sub {
    my $tree = {
        items=>[[],[
            {id=>1,items=>[[]]},{id=>2,items=>[[]]}
        ]]
    };
    is_deeply(results($json->encode($tree),
        'try (. | (recurse(.items[-1][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$tree,$tree->{items}[1][0],42],
        'negative index selects final child array');
    my $special={
        'a.b'=>[[
            {id=>1,'a.b'=>[[]]},{id=>2,'a.b'=>[[]]}
        ]]
    };
    is_deeply(results($json->encode($special),
        'try (. | (recurse(.["a.b"][0][]? | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$special,$special->{'a.b'}[0][0],42],
        'bracket-quoted dotted literal key');
    is_deeply(results($input,
        'try (. | (recurse(.items[] | if .id == 2 then (1/0) else . end) | .)) catch 42'),
        [$root,42],
        'preexisting direct named iterator errors on array child';
};

done_testing;
