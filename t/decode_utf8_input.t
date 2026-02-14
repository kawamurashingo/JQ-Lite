use strict;
use warnings;

use Test::More;
use Encode qw(decode encode);
use JQ::Lite;

my $jq = JQ::Lite->new;

my $text = join q(), map { chr($_) } (0x3053, 0x3093, 0x306B, 0x3061, 0x306F, 0xFF01);
my $json = decode('UTF-8', encode('UTF-8', qq{"$text"}));

my @results = eval { $jq->run_query($json, '@uri') };
my $error   = $@;

is($error, '', 'running @uri on decoded UTF-8 input does not throw');
is_deeply(\@results, ['%E3%81%93%E3%82%93%E3%81%AB%E3%81%A1%E3%81%AF%EF%BC%81'], 'UTF-8 text is percent-encoded');

my $key   = join q(), map { chr($_) } (0x6328, 0x62F6);
my $value = join q(), map { chr($_) } (0x4E16, 0x754C);
my $object_json = decode('UTF-8', encode('UTF-8', qq|{"$key":"$value"}|));

my @object_uri = eval { $jq->run_query($object_json, '@uri') };
my $object_error = $@;

is($object_error, '', 'running @uri on decoded UTF-8 object input does not throw');
is_deeply(
    \@object_uri,
    ['%7B%22%E6%8C%A8%E6%8B%B6%22%3A%22%E4%B8%96%E7%95%8C%22%7D'],
    'UTF-8 object keys/values are percent-encoded without mojibake',
);

done_testing();
