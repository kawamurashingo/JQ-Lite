#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use Digest::SHA qw(sha256_hex);
use JSON::PP ();
use IO::Uncompress::Unzip qw($UnzipError);

# Read one previously downloaded *metadata-only* Actions artifact ZIP.
# Never contact GitHub, extract files, or inspect developer source archives.
my ($input, $expected_sha256, $help);
GetOptions('input=s' => \$input, 'expected-sha256=s' => \$expected_sha256,
    'help' => \$help) or die "Invalid options; use --help\n";
my $usage = <<'USAGE';
Usage: perl ci/verify-actions-exposure-snapshot.pl --input METADATA.zip
       --expected-sha256 64_HEX_DIGIT_ZIP_DIGEST

Verify the exact, independently obtained ZIP SHA-256 first. Check its
whitelisted metadata members, saved SHA-256 manifest, JSON page integrity,
and exact v3-unreleased-source-* JSON-to-TSV reconciliation. Core Perl only;
no networking, extraction, deletion or release actions. Passing results are
one point-in-time GitHub Actions artifact metadata observation, NOT historical
publication completeness, downloads, or --history-reviewed authorization.
USAGE
if ($help) { print $usage; exit 0 }
die $usage unless defined($input) && length($input)
    && defined($expected_sha256) && $expected_sha256 =~ /\A[0-9a-fA-F]{64}\z/
    && !@ARGV;

open my $fh, '<', $input or die "Cannot open snapshot ZIP: $!\n";
binmode $fh;
my $zip_sha = Digest::SHA->new(256);
while (1) {
    my $n = read($fh, my $buffer, 65536);
    die "Failed reading snapshot ZIP: $!\n" unless defined $n;
    last if $n == 0;
    $zip_sha->add($buffer);
}
close $fh or die "Cannot close snapshot ZIP: $!\n";
die "Snapshot ZIP SHA-256 differs from independently recorded expected value\n"
    unless lc($expected_sha256) eq $zip_sha->hexdigest;

my $zip = IO::Uncompress::Unzip->new($input)
    or die "Invalid snapshot ZIP: $UnzipError\n";
my (%members, $count, $total_bytes);
for (;;) {
    my $name = $zip->getHeaderInfo->{Name};
    die "Unsafe/extra snapshot member: $name\n"
        unless defined($name) && $name =~ /\A(?:artifact-page-[1-9][0-9]*\.json|developer-artifacts\.tsv|provenance\.txt|manifest-sha256\.txt)\z/;
    die "Duplicate snapshot member $name\n" if exists $members{$name};
    die "Too many snapshot members\n" if ++$count > 205;
    my $bytes = '';
    while (1) {
        my $n = $zip->read(my $chunk, 65536);
        die "Corrupt snapshot member $name: $UnzipError\n" if $n < 0;
        last unless $n;
        $bytes .= $chunk;
        die "Snapshot member $name exceeds safe size limit\n"
            if length($bytes) > 12_000_000;
    }
    $total_bytes += length($bytes);
    die "Snapshot metadata exceeds safe aggregate size\n"
        if $total_bytes > 48_000_000;
    $members{$name} = $bytes;
    my $next = $zip->nextStream();
    die "Corrupt ZIP stream: $UnzipError\n" if $next < 0;
    last unless $next;
}
for my $required (qw(developer-artifacts.tsv provenance.txt manifest-sha256.txt artifact-page-1.json)) {
    die "Missing required snapshot member: $required\n"
        unless exists $members{$required};
}
my @pages = sort { ( $a =~ /page-(\d+)/ )[0] <=> ( $b =~ /page-(\d+)/ )[0] }
    grep { /\Aartifact-page-\d+\.json\z/ } keys %members;
for my $i (0 .. $#pages) {
    die "Missing/duplicate snapshot page numbering\n"
        unless $pages[$i] eq 'artifact-page-' . ($i+1) . '.json';
}
my %hash_list;
for my $line (split /\n/, $members{'manifest-sha256.txt'}) {
    $line =~ s/\r\z//;
    next unless length $line;
    die "Invalid snapshot checksum manifest line\n"
        unless $line =~ /\A([a-f0-9]{64})  ([a-zA-Z0-9._-]+)\z/;
    my ($digest,$name)=($1,$2);
    die "Duplicate manifest entry $name\n" if exists $hash_list{$name};
    die "Unexpected self/foreign manifest member $name\n"
        if $name eq 'manifest-sha256.txt' || !exists($members{$name});
    $hash_list{$name}=$digest;
}
for my $name (keys %members) {
    next if $name eq 'manifest-sha256.txt';
    die "Unchecksummed snapshot member: $name\n"
        unless exists $hash_list{$name};
    die "Mismatch for snapshot member: $name\n"
        unless sha256_hex($members{$name}) eq $hash_list{$name};
}

my %provenance;
for my $line (split /\n/, $members{'provenance.txt'}) {
    $line =~ s/\r\z//;
    next unless length($line);
    die "Invalid provenance record\n" unless $line =~ /\A([a-z_]+)=(.*)\z/;
    die "Duplicate provenance key: $1\n" if exists $provenance{$1};
    $provenance{$1}=$2;
}
die "Invalid saved repository provenance\n"
    unless ($provenance{repository} || '') eq 'kawamurashingo/JQ-Lite';
die "Invalid captured UTC time\n"
    unless ($provenance{captured_utc} || '') =~ /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/;
die "Invalid checkout SHA provenance\n"
    unless ($provenance{checkout_sha} || '') =~ /\A[0-9a-f]{40}\z/;
die "Invalid saved workflow run URL\n"
    unless ($provenance{workflow_run} || '') =~ m{\Ahttps://github\.com/kawamurashingo/JQ-Lite/actions/runs/[1-9][0-9]*\z};
die "Missing audit limitation provenance\n"
    unless ($provenance{scope} || '') =~ /metadata/ && ($provenance{missing} || '') =~ /PAUSE/;

my ($reported_total, @rows, %ids, @expected_tsv, $matched, $live);
my $json = JSON::PP->new->utf8;
for my $page (@pages) {
    my $obj = eval { $json->decode($members{$page}) };
    die "Invalid saved API JSON page $page: $@\n" if $@;
    die "Invalid saved API JSON structure in $page\n"
        unless ref($obj) eq 'HASH' && ref($obj->{artifacts}) eq 'ARRAY'
        && defined($obj->{total_count}) && !ref($obj->{total_count})
        && $obj->{total_count} =~ /\A(?:0|[1-9][0-9]*)\z/;
    $reported_total = $obj->{total_count} unless defined $reported_total;
    die "Snapshot page totals disagree\n"
        unless $reported_total == $obj->{total_count};
    die "Too many API rows in $page\n" if @{$obj->{artifacts}} > 100;
    for my $row (@{$obj->{artifacts}}) {
        die "Malformed artifact metadata row\n" unless ref($row) eq 'HASH';
        my ($id,$name,$expired,$date) = @{$row}{qw(id name expired created_at)};
        die "Invalid artifact ID or duplicate row\n"
            unless defined($id) && !ref($id) && $id =~ /\A[1-9][0-9]*\z/
                && !$ids{$id}++;
        die "Invalid artifact name/time\n"
            unless defined($name) && !ref($name) && length($name)
                && defined($date) && !ref($date)
                && $date =~ /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/;
        die "Invalid API expired boolean\n"
            unless ref($expired) eq 'JSON::PP::Boolean';
        push @rows, $row;
        next unless $name =~ /\Av3-unreleased-source-/;
        my $run = ref($row->{workflow_run}) eq 'HASH'
            ? $row->{workflow_run}{id} : undef;
        die "Invalid artifact workflow-run ID\n"
            if defined($run) && (ref($run) || $run !~ /\A[1-9][0-9]*\z/);
        my @columns = ($id,$name,$expired ? 'true':'false',$date,
            defined($run) ? $run : 'unknown');
        for (@columns) {
            s/\\/\\\\/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g;
        }
        push @expected_tsv, join("\t", @columns);
        ++$matched;
        ++$live unless $expired;
    }
}
die "Saved API snapshot incomplete: reported $reported_total, received " . @rows . "\n"
    unless $reported_total == @rows;
my $actual_tsv = $members{'developer-artifacts.tsv'};
my $expected_tsv = join("\n",@expected_tsv) . (@expected_tsv ? "\n" : '');
die "Saved TSV does not match original API response exactly\n"
    unless $actual_tsv eq $expected_tsv;

print "Actions artifact metadata verification: PASS (ZIP+member hashes, "
    . scalar(@pages) . " API pages; " . scalar(@rows)
    . " unique artifacts; " . ($matched||0) . " matching source names; "
    . ($live||0) . " not-expired at capture).\n";
print "Observation only: no historic downloads, complete access ledger, "
    . "PAUSE history, version approval or publication asserted.\n";
