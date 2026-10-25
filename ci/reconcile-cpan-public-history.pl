#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions);

# Offline comparison only. Agreement with a CPAN directory snapshot does
# NOT establish complete publication history or permit --history-reviewed.
my ($inventory_file, $published_file, $help);
GetOptions(
    'inventory=s'      => \$inventory_file,
    'published-file=s' => \$published_file,
    'help'             => \$help,
) or die "Invalid arguments; use --help\n";
my $usage = <<'USAGE';
Usage: perl ci/reconcile-cpan-public-history.pl
       --inventory observed-archives.tsv --published-file historical-versions.txt
Compare archive versions seen in the offline CPAN directory inventory
against an independently compiled versions-only history file.
This checks set membership, NOT actual publication order, completeness,
PAUSE records, other public distribution channels or release readiness.
A zero exit status is NOT a --history-reviewed attestation.
USAGE
if ($help) {
    print $usage;
    exit 0;
}
die $usage if @ARGV || !defined($inventory_file) || !length($inventory_file)
    || !defined($published_file) || !length($published_file);

sub read_file {
    my ($path, $kind) = @_;
    open my $fh, '<', $path or die "Cannot open $kind $path: $!\n";
    my @lines = <$fh>;
    close $fh or die "Cannot close $kind $path: $!\n";
    return @lines;
}

my @records = read_file($inventory_file, 'CPAN inventory');
die "CPAN inventory has no header\n" unless @records;
my $header = shift @records;
$header =~ s/\r?\n\z//;
die "Unexpected CPAN inventory header\n"
    unless $header eq "archive\tversion\tindex_last_modified\tclassification";
my (%observed, $internal_found);
my $row = 1;
for my $line (@records) {
    ++$row;
    $line =~ s/\r?\n\z//;
    die "Blank CPAN inventory row at line $row\n" unless length $line;
    my @fields = split /\t/, $line, -1;
    die "Expected four CPAN inventory columns at line $row\n"
        unless @fields == 4;
    my ($archive, $version, $modified, $classification) = @fields;
    die "Invalid CPAN inventory archive at line $row\n"
        unless $archive =~ /\AJQ-Lite-((?:v)?\d+(?:\.\d+)+(?:_\d+)?)\.tar\.gz\z/
        && $1 eq $version;
    die "Invalid CPAN inventory index timestamp at line $row\n"
        unless $modified =~ /\A\d{4}-\d\d-\d\d \d\d:\d\d\z/;
    die "Unexpected CPAN inventory classification at line $row\n"
        unless $classification eq 'observed-archive'
            || $classification eq 'INTERNAL-DEVELOPER-ARTIFACT-ALERT';
    die "Duplicate CPAN inventory version $version at line $row\n"
        if exists $observed{$version};
    $observed{$version} = $archive;
    if ($version =~ /\A3\.0+_\d+\z/ ||
            $classification eq 'INTERNAL-DEVELOPER-ARTIFACT-ALERT') {
        ++$internal_found;
    }
}
die "CPAN inventory has no archive records\n" unless keys %observed;

my (%historical, $hist_row);
for my $line (read_file($published_file, 'public-version history')) {
    ++$hist_row;
    $line =~ s/\r?\n\z//;
    $line =~ s/\s*#.*\z//;
    $line =~ s/\A\s+//;
    $line =~ s/\s+\z//;
    next unless length $line;
    die "Invalid historical public version on line $hist_row: $line\n"
        unless $line =~ /\A(?:v)?\d+(?:\.\d+)+(?:_\d+)?\z/;
    die "Duplicate historical public version $line on line $hist_row\n"
        if $historical{$line}++;
}
die "Public-version history is empty; this comparison cannot establish no predecessors\n"
    unless keys %historical;

my @inventory_only = sort grep { !exists $historical{$_} } keys %observed;
my @history_only = sort grep { !exists $observed{$_} } keys %historical;
print "Observed CPAN archive versions: ", scalar(keys %observed), "\n";
print "Provided history versions: ", scalar(keys %historical), "\n";
for my $version (@inventory_only) {
    print "UNRECONCILED CPAN archive: $observed{$version}\n";
}
for my $version (@history_only) {
    print "NEEDS EXTERNAL EVIDENCE: history version $version is not in the supplied CPAN index\n";
}
if ($internal_found) {
    print "INTERNAL-DEVELOPER-ARTIFACT-ALERT: $internal_found CPAN archive(s) require investigation\n";
}
print "Reconciliation summary: ", scalar(@inventory_only),
    " observed-only; ", scalar(@history_only),
    " history-only. This is NOT publication-history approval.\n";
exit((@inventory_only || @history_only || $internal_found) ? 1 : 0);
