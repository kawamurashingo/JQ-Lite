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

# #625 release gate: preserve the bounded practical-v2 inventory rather
# than broadening jq grammar or silently classifying v2 extensions as jq.
my %intentional_difference = map { $_ => 1 } qw(
    practical-v2-audit-string-bracket-slice
    practical-v2-audit-array-field-projection
    practical-v2-audit-mixed-array-field-projection
    practical-v2-audit-strict-ordinary-scalar-field
);
my (%status_count, %v3_kind, %seen, @invalid);
my ($corrected_from_v2, $unchanged_compatible, $preserved_differences)
    = (0, 0, 0);
my $canonical = JSON::PP->new->allow_nonref->canonical->utf8;

for my $case (@cases) {
    my $name = $case->{name};
    my $status = $case->{status} || '';
    my $old = $case->{audit_v2} || {};
    my $new = $case->{audit_v3} || {};
    ++$status_count{$status};
    ++$v3_kind{ $new->{kind} || '' };
    push @invalid, $name if $seen{$name}++
        || ($status ne 'compatible' && $status ne 'known-difference')
        || ($status eq 'known-difference'
            && !$intentional_difference{$name})
        || ($status eq 'compatible'
            && $intentional_difference{$name})
        || !defined($old->{kind}) || !defined($new->{kind})
        || ($old->{kind} ne 'ok' && $old->{kind} ne 'runtime-error')
        || ($new->{kind} ne 'ok' && $new->{kind} ne 'runtime-error')
        || ref($old->{out}) ne 'ARRAY'
        || ref($new->{out}) ne 'ARRAY'
        || ($status eq 'compatible'
            && $new->{kind} ne ($case->{expected} || ''));

    my $same = $canonical->encode($old) eq $canonical->encode($new);
    if ($status eq 'compatible') {
        $same ? ++$unchanged_compatible : ++$corrected_from_v2;
    }
    else {
        ++$preserved_differences if $same;
        push @invalid, $name unless $same;
    }
}
is(scalar @cases, 54, 'practical path/iterator inventory retains 54 fixtures');
is_deeply(\%status_count,
    { compatible => 50, 'known-difference' => 4 },
    '50 jq-compatible examples and four retained v2 differences');
is_deeply(\%v3_kind,
    { ok => 52, 'runtime-error' => 2 },
    'v3 output versus structured-error cardinality remains explicit');
is($corrected_from_v2, 19, '19 practical v2-to-v3 corrections remain covered');
is($unchanged_compatible, 31, '31 already-compatible practical examples remain');
is($preserved_differences, 4,
    'all four intentional jq divergences retain the v2 behavior');
is_deeply(\@invalid, [], 'audited snapshot/status metadata is consistent');

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
            is($error->category, 'evaluation',
                'retains the public Library runtime-error category')
                if !$ok && ref($error)
                    && $error->isa('JQ::Lite::Error::Evaluation');
        }
        else {
            ok($ok, 'evaluates successfully') or diag("$error");
            is_deeply(\@outputs, $expected->{out},
                'retains ordered values, nulls and empty streams');
        }
    };
}

done_testing;
