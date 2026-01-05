use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $json = <<'JSON';
{
  "profile": {
    "name": "Alice",
    "age": 30,
    "password": "secret",
    "emails": [
      "alice@example.com",
      "alice.work@example.com"
    ]
  }
}
JSON

my $jq = JQ::Lite->new;

my @result = $jq->run_query($json, '.profile | del("password")');

is_deeply(
    $result[0],
    {
        "name" => "Alice",
        "age" => 30,
        "emails" => [
            'alice@example.com',
            'alice.work@example.com',
        ],
    },
    'deleted password field'
);

my @del_age = $jq->run_query($json, '.profile | del(.age)');

is_deeply(
    $del_age[0],
    {
        name     => 'Alice',
        password => 'secret',
        emails   => [
            'alice@example.com',
            'alice.work@example.com'
        ],
    },
    'del() removes key specified as path expression'
);

my @del_email = $jq->run_query($json, '.profile.emails | del(.[0])');

is_deeply(
    $del_email[0],
    ['alice.work@example.com'],
    'del() removes array element when given index path'
);

done_testing();

