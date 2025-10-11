use strict;
use warnings;
use Test::More;
use JSON::PP qw();
use JQ::Lite;

my $json = q({
  "user": {
    "profile": {
      "name": "Alice",
      "email": "alice@example.com"
    },
    "roles": ["admin", "user", "editor"],
    "preferences": {
      "notifications": {
        "email": true,
        "sms": false
      },
      "theme": "dark"
    }
  }
});

my $jq = JQ::Lite->new;

my @nested = $jq->run_query(
    $json,
    'delpaths([["user","profile","email"], ["user","roles",0]])'
);

is_deeply(
    $nested[0],
    {
        user => {
            profile => { name => 'Alice' },
            roles    => [ 'user', 'editor' ],
            preferences => {
                notifications => { email => JSON::PP::true, sms => JSON::PP::false },
                theme          => 'dark',
            },
        },
    },
    'delpaths removes nested keys and array entries described by explicit paths',
);

my @computed = $jq->run_query(
    $json,
    '.user.roles | delpaths([0])'
);

is_deeply(
    $computed[0],
    [ 'user', 'editor' ],
    'delpaths handles single path arrays applied to array inputs',
);

my @root = $jq->run_query($json, '.user | delpaths([[]])');
is($root[0], undef, 'delpaths([[]]) removes the entire value, yielding null');

my @noop = $jq->run_query($json, '.user | delpaths([])');
is_deeply(
    $noop[0],
    {
        profile => {
            name  => 'Alice',
            email => 'alice@example.com',
        },
        roles => [ 'admin', 'user', 'editor' ],
        preferences => {
            notifications => { email => JSON::PP::true, sms => JSON::PP::false },
            theme          => 'dark',
        },
    },
    'delpaths([]) leaves the value unchanged',
);

done_testing;
