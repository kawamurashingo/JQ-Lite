use strict;
use warnings;
use Test::More;
use JQ::Lite;
use JQ::Lite::Error ();
use JSON::PP ();

my $jq = JQ::Lite->new;

sub results {
    my ($json, $filter) = @_;
    return [ $jq->run_query($json, $filter) ];
}

subtest 'catch receives its error as a JSON string, not the original input' => sub {
    for my $json ('null', '3', 'false', '{"num":1,"den":0}') {
        is_deeply(results($json, 'try (1 / 0) catch type'), ['string'],
            "catch type sees a string for $json");
    }
    my $message = results('null', 'try (1 / 0) catch .');
    is(scalar(@$message), 1, 'catch identity returns exactly one error value');
    like($message->[0], qr/division by zero/i,
        'catch identity emits a useful error message');
    is_deeply(results('null', 'try (1 / 0) catch (type == "string")'),
        [JSON::PP::true], 'handler comparisons see a JSON string');
    is_deeply(results('null', 'try (1 / 0) catch (length > 0)'),
        [JSON::PP::true], 'error input has nonzero length');
    is_deeply(results('null', 'try (1 / 0) catch (. | type)'),
        ['string'], 'pipeline handler receives error string');
    is_deeply(results('null', '0, (try (1 / 0) catch type), 9'),
        [0, 'string', 9], 'comma branches keep their output order');
};

subtest 'error-string input is distinct from the original JSON object' => sub {
    is_deeply(results('{"num":1,"den":0}',
        'try (.num / .den) catch type'), ['string'],
        'an object input does not become the handler input');
    is_deeply(results('{"num":1,"den":0}',
        '. as $original | try (.num / .den) catch $original.den'),
        [0], 'the original input remains accessible when explicitly bound');

    my $ok = eval {
        $jq->run_query('null', 'try (1 / 0) catch .["den"]');
        1;
    };
    ok(!$ok, 'strict field lookup fails against error string');
    isa_ok($@, 'JQ::Lite::Error::Evaluation',
        'the new error remains structured') if !$ok;
    is_deeply(results('null', 'try (1 / 0) catch .den?'), [],
        'optional invalid field lookup on the error string is empty');
};

subtest 'controls and legacy error alias' => sub {
    is_deeply(results('null', 'try 5 catch type'), [5],
        'successful try bypasses catch');
    is_deeply(results('null', 'try (1 / 0) catch null'), [undef],
        'explicit null remains a value');
    is_deeply(results('null', 'try (1 / 0) catch empty'), [],
        'explicit empty stays empty');
    my $alias = results('null', 'try (1 / 0) catch $error');
    like($alias->[0], qr/division by zero/i,
        'legacy $error alias remains available');
};

done_testing;
