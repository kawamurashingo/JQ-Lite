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
        }
        else {
            ok($ok, 'evaluates successfully') or diag("$error");
            is_deeply(\@outputs, $expected->{out},
                'retains JSON types, values and output cardinality');
        }
    };
}

done_testing;
