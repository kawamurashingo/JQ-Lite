use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $json = q({
  "meta": {
    "version": "1.0",
    "author": "you"
  }
});

my $jq = JQ::Lite->new;

my @result1 = $jq->run_query($json, 'select(.meta has "version")');
my @result2 = $jq->run_query($json, 'select(.meta has "missing")');

ok(@result1, 'meta has version');
ok(!@result2, 'meta does not have missing key');

# has() uses jq's key categories on ordinary object and array inputs.
# Keep working string object keys and numeric array indices unchanged.
my @object_key = $jq->run_query('{"1":true}', 'has("1")');
ok($object_key[0], 'has() accepts a numeric-looking string object key');
my @array_key = $jq->run_query('[10,20]', 'has(1)');
ok($array_key[0], 'has() accepts a numeric array index');
my @array_fraction = $jq->run_query('[10,20]', 'has(1.5)');
ok($array_fraction[0], 'has() retains jq numeric index truncation');
my @array_missing = $jq->run_query('[10,20]', 'has(3)');
ok(!$array_missing[0], 'out-of-bounds numeric index remains false');
my @null_needle = $jq->run_query('[10,20]', 'has(null)');
ok(!$null_needle[0], 'legacy null-needle fallback remains false');

# Unlike the legacy numeric-string coercion deliberately preserved for
# index/rindex/indices, has() requires a correctly typed key in jq 1.7.
for my $case (
    ['[10,20]', 'has("0")', qr/Cannot check whether array has a string key/,
        'array rejects string index'],
    ['[10,20]', 'has(true)', qr/Cannot check whether array has a boolean key/,
        'array rejects boolean index'],
    ['{"1":true}', 'has(1)', qr/Cannot check whether object has a number key/,
        'object rejects numeric index'],
    ['{"1":true}', 'has(true)', qr/Cannot check whether object has a boolean key/,
        'object rejects boolean key'],
) {
    my ($input, $filter, $diagnostic, $label) = @$case;
    my $ok = eval { $jq->run_query($input, $filter); 1 };
    ok(!$ok, "$label: evaluation fails");
    like("$@", $diagnostic, "$label: typed evaluation diagnostic");
}

done_testing;
