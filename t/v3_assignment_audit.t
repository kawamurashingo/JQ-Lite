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
    next unless exists $case->{assignment_v3};
    next if $ENV{JQ_AUDIT_V2}
        && $case->{assignment_scope} !~ /\A(?:plain|compound)\z/;
    push @cases, $case;
}
close $fh;
ok(@cases, 'assignment audit snapshots loaded');

for my $case (@cases) {
    subtest $case->{name} => sub {
        my @outputs;
        my $ok = eval {
            @outputs = JQ::Lite->new(vars => $case->{assignment_vars} || {})
                ->run_query($json->encode($case->{input}), $case->{filter});
            1;
        };
        my $error = $@;
        my $expected = $case->{assignment_v3};
        if ($expected->{kind} eq 'runtime-error') {
            ok(!$ok, 'rejects the unsupported or invalid target');
            isa_ok($error, 'JQ::Lite::Error::Evaluation') unless $ok;
        }
        else {
            ok($ok, 'evaluates successfully') or diag("$error");
            is_deeply(\@outputs, $expected->{out},
                'preserves the recorded root, value types and cardinality');
        }
    };
}

done_testing;
