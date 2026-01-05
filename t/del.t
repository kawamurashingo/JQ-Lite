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
  },
  "a b": {
    "c.d": "needs quoting"
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
    'deleted password field',
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
    'del() removes key specified as path expression',
);

my @del_email = $jq->run_query($json, '.profile.emails | del(.[0])');

is_deeply(
    $del_email[0],
    ['alice.work@example.com'],
    'del() removes array element when given index path',
);

my @del_space = $jq->run_query($json, 'del(."a b")');

is_deeply(
    $del_space[0],
    {
        profile => {
            name     => 'Alice',
            age      => 30,
            password => 'secret',
            emails   => [
                'alice@example.com',
                'alice.work@example.com'
            ],
        },
    },
    'del() deletes quoted key via dot notation',
);

my @del_nested_quoted = $jq->run_query($json, 'del(."a b"."c.d")');

is_deeply(
    $del_nested_quoted[0],
    {
        profile => {
            name     => 'Alice',
            age      => 30,
            password => 'secret',
            emails   => [
                'alice@example.com',
                'alice.work@example.com'
            ],
        },
        'a b' => {},
    },
    'del() supports quoted path segments within dotted expressions',
);

done_testing();
