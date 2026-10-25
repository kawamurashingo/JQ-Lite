#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use JSON::PP ();

# Offline interpretation of one saved MetaCPAN /release/_search response.
# The API index is not a complete PAUSE ledger or an upload-time attestation.
my ($input, $help);
GetOptions('input=s' => \$input, 'help' => \$help)
    or die "Invalid arguments; use --help\n";
my $usage = <<'USAGE';
Usage: perl ci/inventory-metacpan-jq-lite-releases.pl --input SAVED_RESPONSE.json
Input is an unmodified MetaCPAN /v1/release/_search JSON response.
This tool does not query the network, approve public versions or establish
original PAUSE upload chronology. Require complete, non-truncated results.
USAGE
if ($help) { print $usage; exit 0 }
die $usage if @ARGV || !defined($input) || !length($input);

open my $fh, '<', $input or die "Cannot open MetaCPAN response $input: $!\n";
binmode $fh;
my $bytes = do { local $/; <$fh> };
close $fh or die "Cannot close MetaCPAN response $input: $!\n";
die "Empty MetaCPAN response\n" unless defined($bytes) && length($bytes);
my $data = eval { JSON::PP->new->utf8->decode($bytes) };
die "Malformed MetaCPAN JSON response: $@\n" if $@;
die "Expected MetaCPAN JSON object\n" unless ref($data) eq 'HASH';
die "MetaCPAN search response reports an error\n" if exists $data->{error};
die "MetaCPAN search timed out; results may be incomplete\n"
    if $data->{timed_out};
if (ref($data->{_shards}) eq 'HASH') {
    die "MetaCPAN search reports failed shards\n"
        if ($data->{_shards}{failed} || 0) > 0;
}
my $hits = $data->{hits};
die "MetaCPAN response missing hits object\n" unless ref($hits) eq 'HASH';
die "MetaCPAN response missing hits array\n" unless ref($hits->{hits}) eq 'ARRAY';
my $total = $hits->{total};
my $count;
if (ref($total) eq 'HASH') {
    die "MetaCPAN hits.total relation is not exact\n"
        unless ($total->{relation} || '') eq 'eq';
    $count = $total->{value};
} else {
    $count = $total;
}
die "MetaCPAN response has no exact numeric total\n"
    unless defined($count) && !ref($count) && $count =~ /\A\d+\z/;
die "MetaCPAN response is truncated or incomplete: total $count, received "
    . scalar(@{$hits->{hits}}) . "\n"
    unless $count == @{$hits->{hits}};
die "No MetaCPAN JQ-Lite release observations found\n" unless $count;

sub field {
    my ($source, $name) = @_;
    my $value = $source->{$name};
    if (ref($value) eq 'ARRAY') {
        die "Ambiguous MetaCPAN field $name\n" unless @$value == 1;
        $value = $value->[0];
    }
    die "Invalid MetaCPAN field $name\n" if ref($value);
    return $value;
}

my (@entries, %seen_release, %seen_version, $dev_count);
for my $hit (@{$hits->{hits}}) {
    die "Unexpected MetaCPAN search hit structure\n" unless ref($hit) eq 'HASH';
    my $src = ref($hit->{_source}) eq 'HASH' ? $hit->{_source} : $hit->{fields};
    die "MetaCPAN release lacks _source or fields\n" unless ref($src) eq 'HASH';
    my $dist = field($src, 'distribution');
    die "MetaCPAN release search returned a foreign distribution\n"
        unless defined($dist) && $dist eq 'JQ-Lite';
    my $name = field($src, 'name');
    die "Unexpected MetaCPAN release name\n"
        unless defined($name) &&
        $name =~ /\AJQ-Lite-((?:v)?\d+(?:\.\d+)+(?:_\d+)?)\z/;
    my $version = $1;
    die "Duplicate MetaCPAN release name: $name\n" if $seen_release{$name}++;
    die "Ambiguous MetaCPAN version: $version\n" if $seen_version{$version}++;
    my $date = field($src, 'date');
    die "Invalid or absent MetaCPAN observation date for $name\n"
        unless defined($date) &&
        $date =~ /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)?\z/;
    my $author = field($src, 'author');
    die "Invalid MetaCPAN author for $name\n"
        unless defined($author) && $author =~ /\A[A-Z0-9_-]+\z/;
    my $status = field($src, 'status');
    $status = 'unreported' if !defined($status);
    die "Invalid MetaCPAN status for $name\n"
        unless $status =~ /\A[a-zA-Z0-9_-]+\z/;
    my $internal = $version =~ /\A(?:v)?3\.0+_\d+\z/ ? 1 : 0;
    $dev_count++ if $internal;
    push @entries, [$name, $version, $date, $author, $status,
        $internal ? 'INTERNAL-DEVELOPER-ARTIFACT-ALERT' : 'observed-metacpan-release'];
}
@entries = sort { $a->[2] cmp $b->[2] || $a->[0] cmp $b->[0] } @entries;
print "release\tversion\tmetacpan_date\tauthor\tstatus\tclassification\n";
for my $row (@entries) {
    print join("\t", @$row), "\n";
}
die "INTERNAL-DEVELOPER-ARTIFACT-ALERT: $dev_count MetaCPAN developer candidate(s) require investigation\n"
    if $dev_count;
