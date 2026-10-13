use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq = JQ::Lite->new;
my $json = JSON::PP->new->utf8->allow_nonref;
for my $case (["\x{65e5}\x{672c}x", '5pel5pyseA==', 6], ["\x{e9}x", 'w6l4', 2]) {
    my ($text, $base64, $offset) = @$case;
    is_deeply([ $jq->run_query($json->encode($base64), '@base64d') ], [$text],
        'base64 decoding returns Unicode characters');
    is_deeply([ $jq->run_query($json->encode($base64), '@base64d | indices("x")') ], [[$offset]],
        'decoded text keeps UTF-8 search offsets');
    my $object = {word=>$text};
    my $source = '{"word":"'.$text.'"}';
    for my $format ('tojson', 'tostring') {
        is_deeply([ $jq->run_query($json->encode($object), $format) ], [$source],
            "$format returns character text for a Unicode object");
    }
    is_deeply([ $jq->run_query($json->encode($source), 'fromjson') ], [$object],
        'fromjson accepts character text');
    is_deeply([ $jq->run_query($json->encode($object), 'tojson | fromjson') ], [$object],
        'JSON text round trip preserves Unicode values');
    my $csv = '"{""word"":""'.$text.'""}"';
    is_deeply([ $jq->run_query($json->encode([$object]), '@csv') ], [$csv],
        'retained structured CSV extension returns character text');
    is_deeply([ $jq->run_query($json->encode([$object]), '@tsv') ], [$source],
        'retained structured TSV extension returns character text');
}

is_deeply([ $jq->run_query('"not-json"', 'fromjson') ], ['not-json'],
    'malformed-fromjson fallback remains unchanged');
my $ok = eval { $jq->run_query('"not-base64"', '@base64d'); 1 };
ok(!$ok && "$@" =~ /input must be base64 text/,
    'base64 syntax errors remain unchanged');

done_testing;
