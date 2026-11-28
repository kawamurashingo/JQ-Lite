use strict;
use warnings;
use Test::More;
use JSON::PP ();
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;

sub output {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# @uri and @base64 share the same input text, but each must keep its own
# encoding. @base64d has a separate null-to-empty decoding policy.
my @cases = (
    ['null',               'null',                                  'bnVsbA==',             'null'],
    ['true',               'true',                                  'dHJ1ZQ==',             'true'],
    ['false',              'false',                                 'ZmFsc2U=',             'false'],
    ['123',                '123',                                   'MTIz',                 'integer'],
    ['-2.5',               '-2.5',                                  'LTIuNQ==',             'negative decimal'],
    ['""',                 '',                                      '',                     'empty string'],
    ['"hello world"',      'hello%20world',                         'aGVsbG8gd29ybGQ=',     'spaces'],
    ['"a/b?c&d=e"',       'a%2Fb%3Fc%26d%3De',                   'YS9iP2MmZD1l',         'URI reserved characters'],
    ['["a",2]',            '%5B%22a%22%2C2%5D',                   'WyJhIiwyXQ==',         'array JSON text'],
    ['{"foo":"bar"}',      '%7B%22foo%22%3A%22bar%22%7D',       'eyJmb28iOiJiYXIifQ==', 'object JSON text'],
    ['[1,null,false]',     '%5B1%2Cnull%2Cfalse%5D',              'WzEsbnVsbCxmYWxzZV0=', 'mixed array JSON text'],
);

for my $case (@cases) {
    my ($raw, $uri, $base64, $label) = @$case;
    is_deeply(output($raw, '@uri'), [$uri], "\@uri: $label");
    is_deeply(output($raw, '@base64'), [$base64], "\@base64: $label");
}

is_deeply(output('"\\u65e5\\u672c"', '@uri'),
    ['%E6%97%A5%E6%9C%AC'],
    'URI percent-encodes UTF-8 text exactly once');

is_deeply(output('["a b",null,true]', '.[] | @uri'),
    ['a%20b', 'null', 'true'],
    'URI mapping keeps the order and cardinality of upstream results');
is_deeply(output('["a b",null,true]', '.[] | @base64'),
    ['YSBi', 'bnVsbA==', 'dHJ1ZQ=='],
    'base64 mapping keeps the order and cardinality of upstream results');

is_deeply(output('null', '@base64d'), [''],
    'decoder still turns null into empty text, unlike both encoders');
is_deeply(output('null', 'empty | @uri'), [],
    'URI encoding does not create output from empty upstream');
is_deeply(output('null', 'empty | @base64'), [],
    'base64 encoding does not create output from empty upstream');

is(JQ::Lite::Util::_apply_uri(JSON::PP::true), 'true',
    'direct URI utility preserves JSON boolean text');
is(JQ::Lite::Util::_apply_base64(JSON::PP::false), 'ZmFsc2U=',
    'direct base64 utility preserves JSON boolean text');
is(JQ::Lite::Util::_apply_uri(undef), 'null',
    'direct URI utility preserves null text');
is(JQ::Lite::Util::_apply_base64d(undef), '',
    'direct base64 decoder preserves null-to-empty policy');

done_testing;
