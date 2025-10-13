use strict;
use warnings;
use Test::More;
use JSON::PP qw(encode_json);
use JQ::Lite;

my $jq = JQ::Lite->new;

sub apply_query {
    my ($data, $query) = @_;
    my $json = encode_json($data);
    my @results = $jq->run_query($json, $query);
    return @results;
}

subtest 'update existing value' => sub {
    my $data = { spec => { replicas => 1 } };
    my ($result) = apply_query($data, '.spec.replicas = 3');

    is($result->{spec}{replicas}, 3, 'replicas updated to 3');
};

subtest 'create new nested key' => sub {
    my $data = { spec => {} };
    my ($result) = apply_query($data, '.spec.version = "1.2.3"');

    is($result->{spec}{version}, '1.2.3', 'version key created');
};

subtest 'assign from another path' => sub {
    my $data = { spec => { replicas => 2 } };
    my ($result) = apply_query($data, '.spec.copy = .spec.replicas');

    is($result->{spec}{copy}, 2, 'value copied from other path');
};

subtest 'update array element' => sub {
    my $data = { items => [ { value => 1 }, { value => 2 } ] };
    my ($result) = apply_query($data, '.items[1].value = 5');

    is($result->{items}[1]{value}, 5, 'second item updated');
    is($result->{items}[0]{value}, 1, 'first item untouched');
};

subtest 'assign within root array' => sub {
    my $data = [ { value => 1 }, { value => 2 } ];
    my ($result) = apply_query($data, '.[0].value = 9');

    is($result->[0]{value}, 9, 'first element updated');
};

subtest 'assign null literal' => sub {
    my $data = { spec => { replicas => 4 } };
    my ($result) = apply_query($data, '.spec.replicas = null');

    ok(!defined $result->{spec}{replicas}, 'value set to null');
};

done_testing();
