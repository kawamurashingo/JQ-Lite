use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Error ();

my $jq = JQ::Lite->new;

sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

sub assert_handler_error {
    my ($json, $filter, $description) = @_;
    my $ok = eval { $jq->run_query($json, $filter); 1 };
    my $error = $@;
    ok(!$ok, "$description: catch handler failure propagates");
    if (!$ok) {
        isa_ok($error, 'JQ::Lite::Error::Evaluation',
            "$description: structured runtime error");
        like("$error", qr/Cannot iterate over string/i,
            "$description: secondary strict iterator error is visible");
    }
}

subtest 'catch handler failures are not converted into null results' => sub {
    assert_handler_error('null', 'try (1 / 0) catch recurse(.[])',
        'failed handler after division error');
    assert_handler_error('null', '0, try (1 / 0) catch recurse(.[]), 9',
        'failed handler after prior comma branch');
};

subtest 'outer try handles failures raised inside a catch handler' => sub {
    is_deeply(results('null',
        'try (try (1 / 0) catch recurse(.[])) catch 42'), [42],
        'outer try handles new error from nested catch');
};

subtest 'successful try and explicit fallbacks remain unchanged' => sub {
    is_deeply(results('null', 'try 7 catch recurse(.[])'), [7],
        'handler is not evaluated on successful try');
    is_deeply(results('null', 'try (1 / 0) catch null'), [undef],
        'explicit null fallback still emits null');
    is_deeply(results('null', 'try (1 / 0) catch empty'), [],
        'explicit empty fallback remains empty');
};

done_testing;
