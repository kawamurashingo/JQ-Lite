use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;

my @decoded = $jq->run_query('"aGVsbG8h"', '@base64d');
is_deeply(\@decoded, ['hello!'], '@base64d decodes base64 text');

my @roundtrip = $jq->run_query('{"foo":"bar"}', '@base64 | @base64d');
is_deeply(\@roundtrip, ['{"foo":"bar"}'], '@base64d reverses @base64 output');

my @empty = $jq->run_query('""', '@base64d');
is_deeply(\@empty, [''], '@base64d accepts empty base64 text');

my $invalid_chars_ok = eval { $jq->run_query('"not-base64"', '@base64d'); 1 };
my $invalid_chars_error = $@;
ok(!$invalid_chars_ok, '@base64d throws on non-base64 characters');
like(
    $invalid_chars_error,
    qr/\@base64d\(\): input must be base64 text/,
    'invalid characters report descriptive @base64d error'
);

my $invalid_length_ok = eval { $jq->run_query('"Zg"', '@base64d'); 1 };
my $invalid_length_error = $@;
ok(!$invalid_length_ok, '@base64d throws when length is not divisible by 4');
like(
    $invalid_length_error,
    qr/\@base64d\(\): input must be base64 text/,
    'invalid length reports descriptive @base64d error'
);

my $misplaced_padding_ok = eval { $jq->run_query('"Zm=8"', '@base64d'); 1 };
my $misplaced_padding_error = $@;
ok(!$misplaced_padding_ok, '@base64d throws when padding appears in the middle');
like(
    $misplaced_padding_error,
    qr/\@base64d\(\): input must be base64 text/,
    'misplaced padding reports descriptive @base64d error'
);

my $non_string_ok = eval { $jq->run_query('1234', '@base64d'); 1 };
my $non_string_error = $@;
ok(!$non_string_ok, '@base64d throws when input is not base64 text');
like(
    $non_string_error,
    qr/\@base64d\(\): input must be base64 text/,
    'non-string input also reports descriptive @base64d error'
);

done_testing();
