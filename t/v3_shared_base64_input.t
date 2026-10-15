use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;
sub run {
    my ($json, $query) = @_;
    return [ $jq->run_query($json, $query) ];
}

is_deeply(run('"hello"', '@base64'), ['aGVsbG8='],
    'simple string encoding stays unchanged');
is_deeply(run('42', '@base64'), ['NDI='],
    'number encoding retains textual value');
is_deeply(run('null', '@base64'), ['bnVsbA=='],
    'encoder encodes explicit JSON null literally');
is_deeply(run('true', '@base64'), ['dHJ1ZQ=='],
    'encoder preserves true boolean spelling');
is_deeply(run('false', '@base64'), ['ZmFsc2U='],
    'encoder preserves false boolean spelling');
is_deeply(run('{"foo":"bar"}', '@base64'), ['eyJmb28iOiJiYXIifQ=='],
    'structured object serializes to JSON text before encoding');
is_deeply(run('["a","b"]', '@base64'), ['WyJhIiwiYiJd'],
    'structured array serializes to JSON text before encoding');

is_deeply(run('"aGVsbG8="', '@base64d'), ['hello'],
    'valid base64 text decodes');
is_deeply(run('""', '@base64d'), [''],
    'empty base64 text remains empty');
is_deeply(run('" YQ==\\n "', '@base64d'), ['a'],
    'decoder retains v2 whitespace tolerance');
is_deeply(run('null', '@base64d'), [''],
    'decoder retains v2 null-to-empty policy');
is_deeply(run('["a","b"]', '.[] | @base64'), ['YQ==','Yg=='],
    'array iteration keeps encoding output order');

for my $item (
    ['1234', 'numeric scalar'],
    ['"not-base64"', 'invalid alphabet'],
    ['"Zg"', 'invalid length'],
    ['"Zm=8"', 'invalid padding'],
    ['[1]', 'v2 structured decoder fallback error'],
) {
    my ($json, $label) = @$item;
    my $ok = eval { $jq->run_query($json, '@base64d'); 1 };
    ok(!$ok, "@base64d rejects $label");
    like($@, qr/\@base64d\(\): input must be base64 text/,
        "@base64d keeps error text for $label");
}

is_deeply(JQ::Lite::Util::_apply_base64(JSON::PP::true), 'dHJ1ZQ==',
    'direct utility boolean conversion is still true');
is_deeply(JQ::Lite::Util::_apply_base64d(undef), '',
    'direct utility decoder null input remains empty');

done_testing;
