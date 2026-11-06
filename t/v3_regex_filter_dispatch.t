use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;

my $jq = JQ::Lite->new;

sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

is_deeply(results('"Alpha"', 'test("^a")'),
    [JSON::PP::false], 'test without flags remains case-sensitive');
is_deeply(results('"Alpha"', 'test("^a"; "i")'),
    [JSON::PP::true], 'test decodes case-insensitive flags');
is_deeply(results('"Alpha"', 'test("z")'),
    [JSON::PP::false], 'test false is a value, not an empty stream');
is_deeply(results('["Alpha","beta"]', 'test("^a"; "i")'),
    [[JSON::PP::true, JSON::PP::false]],
    'test preserves the v2 array-mapping extension');
is_deeply(results('["Alpha","beta"]', '.[] | test("a"; "i")'),
    [JSON::PP::true, JSON::PP::true],
    'test preserves stream order through iteration');
is_deeply(results('"Alpha"', 'match("lph"; "i")'),
    [{
        offset => 1, length => 3, string => 'lph', captures => [],
    }], 'match returns its existing structured first match');
is_deeply(results('"Alpha"', 'match("ph")'),
    [{
        offset => 2, length => 2, string => 'ph', captures => [],
    }], 'match without flags retains offset and length');

for my $function (qw(test match)) {
    my $ok = eval { $jq->run_query('"abc"', qq{$function("[")}); 1 };
    ok(!$ok, "$function rejects an invalid regular expression");
    like("$@", qr/\Q$function\E\(\): invalid regular expression/,
        "$function retains its function-specific regex error");
    $ok = eval { $jq->run_query('"abc"', qq{$function("a"; "z")}); 1 };
    ok(!$ok, "$function rejects unknown regex flags");
    like("$@", qr/\Q$function\E\(\): invalid regular expression - unknown regex flag 'z'/,
        "$function retains its function-specific flag error");
}

done_testing;
