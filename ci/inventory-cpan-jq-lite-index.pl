#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions);

# Offline extraction only. CPAN directory mtimes are observations, NOT
# publication timestamps or evidence that the uploaded history is complete.
my ($input, $help);
GetOptions('input=s' => \$input, 'help' => \$help)
    or die "Invalid arguments; use --help\n";
my $usage = <<'USAGE';
Usage: perl ci/inventory-cpan-jq-lite-index.pl --input CPAN_INDEX.html
Extract JQ-Lite *.tar.gz entries from a saved SHINGO CPAN author HTML
index. Output is observational TSV, NOT an audited publication ledger.
Directory last-modified times must not be assumed to be upload times.
This script does not access the network or authorize any release.
USAGE
if ($help) {
    print $usage;
    exit 0;
}
die $usage if @ARGV || !defined($input) || !length($input);
open my $fh, '<', $input or die "Cannot open index file $input: $!\n";
local $/;
my $html = <$fh>;
close $fh or die "Cannot close index file $input: $!\n";
die "Empty CPAN index input\n" unless defined($html) && length($html);

my (@entries, %seen);
while ($html =~ m{<tr\b[^>]*>(.*?)</tr\s*>}sig) {
    my $row = $1;
    my ($name) = $row =~ m{<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>}i;
    next unless defined $name && $name =~ /\AJQ-Lite-/;
    next unless $name =~ /\.tar\.gz\z/i;
    die "Unexpected JQ-Lite archive filename: $name\n"
        unless $name =~ /\AJQ-Lite-((?:v)?\d+(?:\.\d+)+(?:_\d+)?)\.tar\.gz\z/;
    my $version = $1;
    my ($modified) = $row =~ /(\d{4}-\d\d-\d\d\s+\d\d:\d\d)/;
    die "Missing directory modification time for $name\n" unless defined $modified;
    $modified =~ s/\s+/ /g;
    die "Duplicate archive in supplied index: $name\n" if $seen{$name}++;
    # Optional leading "v" is accepted in archive names, so it must
    # also be recognized by the internal-only developer-version gate.
    my $internal = $version =~ /\A(?:v)?3\.0+_\d+\z/ ? 1 : 0;
    push @entries, [$name, $version, $modified, $internal];
}
die "No JQ-Lite archives found; expected HTML directory table rows\n"
    unless @entries;
@entries = sort { $a->[2] cmp $b->[2] || $a->[0] cmp $b->[0] } @entries;
print "archive\tversion\tindex_last_modified\tclassification\n";
for my $entry (@entries) {
    print join("\t", $entry->[0], $entry->[1], $entry->[2],
        $entry->[3] ? 'INTERNAL-DEVELOPER-ARTIFACT-ALERT' : 'observed-archive'), "\n";
}
if (grep { $_->[3] } @entries) {
    die "WARNING: candidate INTERNAL-only 3.00_0x archive in supplied index; investigate public distribution\n";
}
