use strict;
use warnings;
use Test::More;
use JSON::PP ();
use FindBin;
use File::Spec;
use JQ::Lite;

my $json = JSON::PP->new->allow_nonref->utf8;
my $path = File::Spec->catfile($FindBin::Bin, 'data', 'jq-differential.jsonl');
open my $fh, '<:raw', $path or die "Cannot read $path: $!";
my @cases;
while (my $line = <$fh>) {
    next if $line =~ /^\s*(?:#|$)/;
    my $case = $json->decode($line);
    push @cases, $case if exists $case->{arithmetic_v3};
}
close $fh;
ok(@cases, 'arithmetic contract fixtures loaded');

# #623 release gate: fixture count and jq classifications are deliberate
# choices. A compatible case must match the upstream outcome category,
# while the known nonnumeric overloads remain explicitly non-gating.
my (%status_count, %outcome_count);
my @invalid_metadata;
for my $case (@cases) {
    my $status = $case->{status} || '';
    my $result = $case->{arithmetic_v3} || {};
    my $kind = $result->{kind} || '';
    ++$status_count{$status};
    ++$outcome_count{$kind};
    push @invalid_metadata, $case->{name}
        if ($status ne 'compatible' && $status ne 'known-difference')
        || ($kind ne 'ok' && $kind ne 'runtime-error')
        || ($status eq 'compatible' && $kind ne ($case->{expected} || ''));
}
is(scalar @cases, 408, 'practical arithmetic audit retains 408 fixtures');
is_deeply(\%status_count,
    { compatible => 396, 'known-difference' => 12 },
    'arithmetic jq parity claims and intentional differences stay explicit');
is_deeply(\%outcome_count,
    { ok => 57, 'runtime-error' => 351 },
    'arithmetic Library snapshots retain success/error coverage');
is_deeply(\@invalid_metadata, [],
    'arithmetic metadata is valid and compatible results match jq categories');

for my $case (@cases) {
    subtest $case->{name} => sub {
        my @outputs;
        my $ok = eval {
            @outputs = JQ::Lite->new->run_query(
                $json->encode($case->{input}), $case->{filter}
            );
            1;
        };
        my $error = $@;
        my $expected = $case->{arithmetic_v3};
        if ($expected->{kind} eq 'runtime-error') {
            ok(!$ok, 'rejects invalid arithmetic');
            isa_ok($error, 'JQ::Lite::Error::Evaluation') unless $ok;
            is($error->category, 'evaluation',
                'retains the public Library runtime-error category')
                if !$ok && ref($error)
                    && $error->isa('JQ::Lite::Error::Evaluation');
        }
        else {
            ok($ok, 'evaluates successfully') or diag("$error");
            is_deeply(\@outputs, $expected->{out},
                'retains JSON types, values and output cardinality');
        }
    };
}

done_testing;
