use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;

sub run {
    my ($input, $query) = @_;
    return [ $jq->run_query($input, $query) ];
}

is_deeply(
    run(q(["a,b","say \"hi\"",42,null,true,false]), '@csv'),
    ['"a,b","say ""hi""",42,,true,false'],
    'CSV quotes text, retains numeric flags, and emits null/booleans',
);

is_deeply(
    run(q(["a\tb","line\nnext","slash\\back",42,null,true,false]), '@tsv'),
    ["a\\tb\tline\\nnext\tslash\\\\back\t42\t\ttrue\tfalse"],
    'TSV escapes tabs, newlines and backslashes without CSV quoting',
);

is_deeply(run(q([42,"42",0]), '@csv'), ['42,"42",0'],
    'CSV distinguishes JSON numbers from numeric-looking strings');
is_deeply(run(q([]), '@csv'), [''], 'empty CSV row emits one empty string');
is_deeply(run(q([]), '@tsv'), [''], 'empty TSV row emits one empty string');

is_deeply(
    run(q([["a"],["b"]]), '.[] | @csv'),
    ['"a"', '"b"'],
    'multiple CSV rows preserve stream order',
);
is_deeply(
    run(q([["a"],["b"]]), '.[] | @tsv'),
    ['a', 'b'],
    'multiple TSV rows preserve stream order',
);

is_deeply(run(q("42"), '@csv'), ['"42"'],
    'v2 scalar CSV string extension remains quoted');
is_deeply(run('42', '@csv'), ['42'],
    'v2 scalar CSV numeric extension remains unquoted');
is_deeply(run('null', '@csv'), [''],
    'v2 scalar CSV null extension remains empty');

is_deeply(
    run(q([{"a":1},[1,2]]), '@csv'),
    ['"{""a"":1}","[1,2]"'],
    'v2 CSV nested JSON container formatting is preserved',
);
is_deeply(
    run(q([{"a":1},[1,2]]), '@tsv'),
    ['{"a":1}' . "\t" . '[1,2]'],
    'v2 TSV nested JSON container formatting is preserved',
);

is_deeply(
    JQ::Lite::Util::_apply_csv([JSON::PP::true, JSON::PP::false, undef]),
    'true,false,',
    'direct CSV serializer preserves boolean and null fields',
);
is_deeply(
    JQ::Lite::Util::_apply_tsv([JSON::PP::true, JSON::PP::false, undef]),
    "true\tfalse\t",
    'direct TSV serializer preserves boolean and null fields',
);

done_testing;
