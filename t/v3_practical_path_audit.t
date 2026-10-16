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
    push @cases, $case if exists $case->{audit_v3};
}
close $fh;
ok(@cases, 'practical path audit fixtures loaded');

# A maintainer can also verify the recorded v2 snapshot using that tree's lib.
my $column = $ENV{JQ_AUDIT_V2} ? 'audit_v2' : 'audit_v3';
for my $case (@cases) {
    subtest $case->{name} => sub {
        my $expected = $case->{$column};
        my @outputs;
        my $ok = eval {
            @outputs = JQ::Lite->new->run_query(
                $json->encode($case->{input}), $case->{filter}
            );
            1;
        };
        my $error = $@;
        if ($expected->{kind} eq 'runtime-error') {
            ok(!$ok, 'raises the recorded runtime error');
            isa_ok($error, 'JQ::Lite::Error::Evaluation') unless $ok;
        }
        else {
            ok($ok, 'evaluates successfully') or diag("$error");
            is_deeply(\@outputs, $expected->{out},
                'retains ordered values, nulls and empty streams');
        }
    };
}

done_testing;
