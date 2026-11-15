use strict;
use warnings;
use Test::More;
use JSON::PP ();
use B ();
use JQ::Lite;
use JQ::Lite::Util ();

my $jq = JQ::Lite->new;
my $decoder = JSON::PP->new->allow_nonref;

sub results {
    my ($input, $filter) = @_;
    return [ $jq->run_query($input, $filter) ];
}

# Both private predicates use the same guarded Perl SV flag inspection.
# A numeric-looking JSON string must not become an unquoted CSV number.
my @values = (
    ['null',        0, 0, 'null'],
    ['true',        0, 0, 'JSON true'],
    ['false',       0, 0, 'JSON false'],
    ['[]',          0, 0, 'array reference'],
    ['{}',          0, 0, 'object reference'],
    ['"text"',      1, 0, 'ordinary string'],
    ['""',          1, 0, 'empty string'],
    ['"42"',        1, 0, 'numeric-looking string'],
    ['"1e3"',       1, 0, 'exponential-looking string'],
    ['0',           0, 1, 'zero number'],
    ['42',          0, 1, 'integer number'],
    ['-2.5',        0, 1, 'decimal number'],
    ['1e3',         0, 1, 'scientific-notation number'],
);

for my $case (@values) {
    my ($raw, $string, $number, $label) = @$case;
    my $value = $decoder->decode($raw);
    is(JQ::Lite::Util::_is_string_scalar($value) ? 1 : 0,
        $string, "string SV flag: $label");
    is(JQ::Lite::Util::_is_unquoted_csv_number($value) ? 1 : 0,
        $number, "numeric SV flag: $label");
}

for my $case (
    ['null', 0, 'null flag guard'],
    ['true', 0, 'boolean ref flag guard'],
    ['false', 0, 'false ref flag guard'],
    ['[]', 0, 'array ref flag guard'],
    ['{}', 0, 'object ref flag guard'],
) {
    my ($raw, $expected, $label) = @$case;
    is(JQ::Lite::Util::_scalar_flags($decoder->decode($raw)),
        $expected, $label);
}

ok(JQ::Lite::Util::_scalar_flags($decoder->decode('"42"')) & B::SVp_POK(),
    'text scalar retains string flags');
ok(JQ::Lite::Util::_scalar_flags($decoder->decode('42')) &
    (B::SVp_IOK() | B::SVp_NOK()), 'numeric scalar retains numeric flags');

is_deeply(
    results('[42,"42",0,"0",2.5,"2.5",true,false,null]', '@csv'),
    ['42,"42",0,"0",2.5,"2.5",true,false,'],
    'public CSV distinguishes numeric flags from numeric-looking strings'
);
is_deeply(
    results('[42,"42",true,false,null]', '@tsv'),
    ["42\t42\ttrue\tfalse\t"],
    'public TSV retains existing unquoted field policy'
);
is_deeply(results('"MTIzNA=="', '@base64d'), ['1234'],
    'base64d accepts an encoded numeric-looking string');
is_deeply(results('"hello"', 'startswith("he")'), [JSON::PP::true],
    'string predicate still recognizes ordinary strings');
is_deeply(results('42', 'startswith("4")'), [JSON::PP::false],
    'string predicate does not reinterpret numeric scalars as text');

my $ok = eval { $jq->run_query('1234', '@base64d'); 1 };
my $error = $@;
ok(!$ok, 'base64d still rejects numeric scalar inputs');
like("$error", qr/\@base64d\(\): input must be base64 text/,
    'base64d retains numeric-input validation message');
is_deeply(results('[42,"42"]', '.[] | @csv'),
    ['42','"42"'], 'streamed CSV output preserves type and order');
is_deeply(results('null', 'empty | @csv'), [],
    'empty upstream stream remains empty');

done_testing;
