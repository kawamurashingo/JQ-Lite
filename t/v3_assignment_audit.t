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
my (@cases, @audited);
while (my $line = <$fh>) {
    next if $line =~ /^\s*(?:#|$)/;
    my $case = $json->decode($line);
    push @audited, $case if exists $case->{assignment_scope};
    next unless exists $case->{assignment_v3};
    next if $ENV{JQ_AUDIT_V2}
        && $case->{assignment_scope} !~ /\A(?:plain|compound)\z/;
    push @cases, $case;
}
close $fh;
ok(@cases, 'assignment audit snapshots loaded');

# #626 release scope: do not turn a recorded v2 extension into a jq
# compatibility promise, or silently adopt incidental unsupported results.
# JQ_AUDIT_V2 retains just the 65 plain/compound snapshots for comparison
# with the stable v2.59 Library implementation.
if ($ENV{JQ_AUDIT_V2}) {
    is(scalar @cases, 65, 'v2 baseline comparison keeps 65 setters');
}
else {
    is(scalar @audited, 101, 'assignment audit retains all 101 fixtures');
    is(scalar @cases, 95, '95 supported/rejected snapshots remain gated');

    my (%by_scope, %statuses, %outcomes, @invalid);
    my %allowed = (
        plain => { compatible => 1, 'known-difference' => 1 },
        compound => { compatible => 1, 'known-difference' => 1 },
        update => { compatible => 1 },
        'rejected-selector' => { unsupported => 1 },
        'unsupported-stream' => { unsupported => 1 },
    );
    for my $case (@audited) {
        my $scope = $case->{assignment_scope};
        my $status = $case->{status} || '';
        ++$by_scope{$scope}{$status};
        ++$statuses{$status};

        push @invalid, $case->{name}
            unless exists $allowed{$scope}
                && $allowed{$scope}{$status};

        if (exists $case->{assignment_v3}) {
            my $expected = $case->{assignment_v3};
            my $kind = $expected->{kind} || '';
            ++$outcomes{$kind};
            push @invalid, $case->{name}
                unless ($kind eq 'ok' || $kind eq 'runtime-error')
                    && ref($expected->{out}) eq 'ARRAY'
                    && ($scope ne 'rejected-selector'
                        || $kind eq 'runtime-error')
                    && ($status ne 'compatible'
                        || $kind eq ($case->{expected} || ''));
        }
        else {
            push @invalid, $case->{name}
                unless $scope eq 'unsupported-stream';
        }
    }
    is_deeply(\%by_scope, {
        plain => { compatible => 19, 'known-difference' => 4 },
        compound => { compatible => 7, 'known-difference' => 35 },
        update => { compatible => 14 },
        'rejected-selector' => { unsupported => 16 },
        'unsupported-stream' => { unsupported => 6 },
    }, 'plain, compound, update and unsupported scope stay explicit');
    is_deeply(\%statuses,
        { compatible => 40, 'known-difference' => 39,
          unsupported => 22 },
        'release classification keeps 40 parity cases and 39 v2 differences');
    is_deeply(\%outcomes,
        { ok => 77, 'runtime-error' => 18 },
        'recorded Library results and rejected-target errors remain covered');
    is_deeply(\@invalid, [],
        'fixture metadata and supported/unsupported boundaries are consistent');
}

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
            is($error->category, 'evaluation',
                'retains the public Library runtime-error category')
                if !$ok && ref($error)
                    && $error->isa('JQ::Lite::Error::Evaluation');
        }
        else {
            ok($ok, 'evaluates successfully') or diag("$error");
            is_deeply(\@outputs, $expected->{out},
                'preserves the recorded root, value types and cardinality');
        }
    };
}

done_testing;
