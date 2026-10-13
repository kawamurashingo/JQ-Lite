use strict;
use warnings;
use Test::More;
use JSON::PP ();
use Encode qw(encode);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);
use FindBin;
use File::Spec;

# The distribution test suite must remain independent of upstream jq.
plan skip_all => 'Set JQ_DIFFERENTIAL=1 to compare against jq 1.7'
    unless $ENV{JQ_DIFFERENTIAL};

my $jq_bin  = $ENV{JQ_BIN} || 'jq';
my $lib_dir = File::Spec->catdir($FindBin::Bin, '..', 'lib');
my $lite_bin = $ENV{JQ_LITE_BIN} || File::Spec->catfile($FindBin::Bin, '..', 'bin', 'jq-lite');
my $fixtures = File::Spec->catfile($FindBin::Bin, 'data', 'jq-differential.jsonl');
# Fixtures and subprocess streams contain UTF-8 bytes, including Latin-1
# characters that Perl would otherwise print as single-byte values.
my $json = JSON::PP->new->allow_nonref->canonical->utf8;

sub run_command {
    my ($cmd, $input) = @_;
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, @$cmd);
    if (defined $input && length $input) {
        local $SIG{PIPE} = 'IGNORE';
        print {$in} $input or die "Could not write command stdin: $!";
    }
    close $in;
    my $stdout = do { local $/; <$out> };
    my $stderr = do { local $/; <$err> };
    close $out;
    close $err;
    waitpid($pid, 0);
    return {
        rc     => ($? >> 8),
        stdout => defined($stdout) ? $stdout : '',
        stderr => defined($stderr) ? $stderr : '',
    };
}

sub result_kind {
    my ($result, $lite) = @_;
    return 'ok' if $result->{rc} == 0;
    return 'runtime-error' if $lite && $result->{rc} == 3;
    # jq 1.7 emits nonzero on runtime failures; do not compare its
    # numeric exit code or diagnostic wording to jq-lite's CLI contract.
    return 'runtime-error' if !$lite && $result->{rc} == 5;
    return 'other-error';
}

sub canonical_output {
    my ($result) = @_;
    my @values;
    for my $line (split /\n/, $result->{stdout}) {
        next unless $line =~ /\S/;
        push @values, $json->encode($json->decode($line));
    }
    return \@values;
}

my $version = eval { run_command([$jq_bin, '--version'], '') };
BAIL_OUT('jq is required when JQ_DIFFERENTIAL=1: ' . $@) if $@;
BAIL_OUT('Require jq 1.7.x; found ' . $version->{stdout})
    unless $version->{rc} == 0 && $version->{stdout} =~ /^jq-1\.7(?:\.\d+)?\s*$/;

open my $fh, '<', $fixtures or BAIL_OUT("Cannot read $fixtures: $!");
my %seen;
my $line_no = 0;
while (my $line = <$fh>) {
    ++$line_no;
    next if $line =~ /^\s*(?:#|$)/;
    my $case = eval { $json->decode($line) };
    BAIL_OUT("Invalid fixture JSON at line $line_no: $@") if $@;
    for my $field (qw(name input filter status expected)) {
        BAIL_OUT("Fixture line $line_no missing '$field'")
            unless exists $case->{$field};
    }
    BAIL_OUT("Duplicate fixture name: $case->{name}") if $seen{$case->{name}}++;
    BAIL_OUT("Invalid fixture status: $case->{status}")
        unless $case->{status} =~ /\A(?:compatible|planned|known-difference|unsupported)\z/;
    BAIL_OUT("Invalid fixture expected: $case->{expected}")
        unless $case->{expected} =~ /\A(?:ok|runtime-error)\z/;

    if ($case->{status} eq 'unsupported') {
        pass("$case->{name}: unsupported feature explicitly tracked (not compared)");
        next;
    }

    # Raw text fixtures cover the public CLI input boundary as well as JSON.
    BAIL_OUT("Raw fixture $case->{name} needs scalar text input")
        if $case->{raw_input} && (!defined($case->{input}) || ref($case->{input}));
    my @input_args = $case->{raw_input} ? ('-R') : ();
    push @input_args, '-s' if $case->{raw_input} && $case->{slurp};
    my $input = $case->{raw_input} ? encode('UTF-8', $case->{input})
        : $json->encode($case->{input}) . "\n";
    my $jq = run_command([$jq_bin, '-c', @input_args, $case->{filter}], $input);
    my $lite = run_command([$^X, '-I' . $lib_dir, $lite_bin, '-c', @input_args, $case->{filter}], $input);
    my $jq_kind = result_kind($jq, 0);
    my $lite_kind = result_kind($lite, 1);

    if ($case->{status} ne 'compatible') {
        is($jq_kind, $case->{expected}, "$case->{name}: upstream reference outcome");
        pass("$case->{name}: $case->{status} (jq-lite non-gating)");
        my $match = $jq_kind eq $lite_kind;
        if ($match && $jq_kind eq 'ok') {
            my $jq_out = eval { canonical_output($jq) };
            my $jq_error = $@;
            my $lite_out = eval { canonical_output($lite) };
            my $lite_error = $@;
            $match = !$jq_error && !$lite_error
                && join("\n", @$jq_out) eq join("\n", @$lite_out);
        }
        diag("$case->{name}: " . ($match ? 'now matches jq; review fixture status' : 'difference remains'));
        next;
    }

    is($jq_kind, $case->{expected}, "$case->{name}: upstream outcome");
    is($lite_kind, $case->{expected}, "$case->{name}: jq-lite outcome")
        or diag("jq-lite stderr: $lite->{stderr}");
    if ($jq_kind eq 'ok' && $lite_kind eq 'ok') {
        my $jq_out = eval { canonical_output($jq) };
        my $jq_decode_err = $@;
        my $lite_out = eval { canonical_output($lite) };
        my $lite_decode_err = $@;
        ok(!$jq_decode_err && !$lite_decode_err, "$case->{name}: valid compact JSON output")
            or diag("jq: $jq_decode_err; jq-lite: $lite_decode_err");
        is_deeply($lite_out, $jq_out, "$case->{name}: ordered JSON results")
            unless $jq_decode_err || $lite_decode_err;
    }
}
close $fh;
done_testing;
