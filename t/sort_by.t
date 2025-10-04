use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $json = <<'JSON';
{
  "users": [
    { "name": "Carol", "age": 25 },
    { "name": "Alice", "age": 30 },
    { "name": "Bob",   "age": 20 }
  ]
}
JSON

my $jq = JQ::Lite->new;

# Test sort_by(.age)
my @warnings;
my @result;
{
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    @result = $jq->run_query($json, '.users | sort_by(.age) | map(.name)');
}

is_deeply(
    \@result,
    [['Bob', 'Carol', 'Alice']],
    'sort_by(.age) returns users sorted by age'
);

is_deeply(
    \@warnings,
    [],
    'sort_by does not emit unexpected warnings'
);

done_testing();

