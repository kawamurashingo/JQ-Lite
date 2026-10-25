#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions);

# Compare two independently saved observational sets. NOT a PAUSE ledger.
my ($backpan, $metacpan, $help);
GetOptions(
    'backpan-author=s' => \$backpan,
    'metacpan=s'      => \$metacpan,
    'help'            => \$help,
) or die "Invalid arguments; use --help\n";
my $usage = <<'USAGE';
Usage: perl ci/compare-backpan-author-metacpan-inventory.pl
  --backpan-author OBSERVED_AUTHOR_INDEX.tsv --metacpan OBSERVED_RELEASES.tsv
Use ONLY original-source-derived offline TSV observations.
Identical sets do NOT attest complete upload history, PAUSE chronology,
absence of deleted/off-author releases, or publication approval.
USAGE
if ($help) { print $usage; exit 0 }
die $usage if @ARGV || !$backpan || !$metacpan;

sub read_tsv {
    my ($file, $header, $width, $kind) = @_;
    open my $fh, '<', $file or die "Cannot open $kind $file: $!\n";
    my $first = <$fh>;
    die "Missing $kind TSV header\n" unless defined $first;
    $first =~ s/\r?\n\z//;
    die "Unexpected $kind TSV header\n" unless $first eq $header;
    my @rows;
    my $line = 1;
    while (my $text = <$fh>) {
        ++$line;
        $text =~ s/\r?\n\z//;
        my @fields = split /\t/, $text, -1;
        die "Invalid $kind TSV at line $line\n" unless @fields == $width;
        push @rows, \@fields;
    }
    close $fh or die "Cannot close $kind $file: $!\n";
    die "Empty $kind observation set\n" unless @rows;
    return @rows;
}
my @a = read_tsv($backpan,
    "archive\tversion\tindex_last_modified\tclassification", 4, "BackPAN author");
my @b = read_tsv($metacpan,
    "release\tversion\tmetacpan_date\tauthor\tstatus\tclassification", 6,
    "MetaCPAN");
my (%archived, %indexed, $developers);
for my $r (@a) {
    my ($archive, $version, $mtime, $class) = @$r;
    die "Invalid BackPAN author archive/version\n"
        unless $archive =~ /\AJQ-Lite-((?:v)?\d+(?:\.\d+)+(?:_\d+)?)\.tar\.gz\z/
            && $1 eq $version;
    die "Invalid BackPAN listing modification time\n"
        unless $mtime =~ /\A\d{4}-\d\d-\d\d \d\d:\d\d\z/;
    die "Invalid BackPAN classification\n" unless $class eq 'observed-archive'
        || $class eq 'INTERNAL-DEVELOPER-ARTIFACT-ALERT';
    die "Duplicate BackPAN author version $version\n" if $archived{$version}++;
    ++$developers if $class eq 'INTERNAL-DEVELOPER-ARTIFACT-ALERT'
        || $version =~ /\A(?:v)?3\.0+_\d+\z/;
}
my @off_author;
for my $r (@b) {
    my ($name, $version, $date, $author, $status, $class) = @$r;
    die "Invalid MetaCPAN release/version\n"
        unless $name =~ /\AJQ-Lite-((?:v)?\d+(?:\.\d+)+(?:_\d+)?)\z/
            && $1 eq $version;
    die "Invalid MetaCPAN date\n"
        unless $date =~ /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)?\z/;
    die "Invalid MetaCPAN author\n" unless $author =~ /\A[A-Z0-9_-]+\z/;
    die "Invalid MetaCPAN status\n" unless $status =~ /\A[a-zA-Z0-9_-]+\z/;
    die "Invalid MetaCPAN classification\n" unless
        $class eq 'observed-metacpan-release'
        || $class eq 'INTERNAL-DEVELOPER-ARTIFACT-ALERT';
    die "Duplicate MetaCPAN version $version\n" if $indexed{$version}++;
    push @off_author, $version if $author ne 'SHINGO';
    ++$developers if $class eq 'INTERNAL-DEVELOPER-ARTIFACT-ALERT'
        || $version =~ /\A(?:v)?3\.0+_\d+\z/;
}
my @archive_only = sort grep { !$indexed{$_} } keys %archived;
my @meta_only = sort grep { !$archived{$_} } keys %indexed;
print "BackPAN SHINGO author archive versions: ", scalar(keys %archived), "\n";
print "MetaCPAN JQ-Lite release versions: ", scalar(keys %indexed), "\n";
print "BACKPAN AUTHOR ONLY: $_\n" for @archive_only;
print "METACPAN ONLY: $_\n" for @meta_only;
print "NON-SHINGO RELEASE AUTHOR: $_\n" for sort @off_author;
print "INTERNAL-DEVELOPER-ARTIFACT-ALERT: $developers observations\n"
    if $developers;
print "Comparison: ",scalar(@archive_only)," BackPAN-only; ",
    scalar(@meta_only)," MetaCPAN-only; ",scalar(@off_author),
    " non-SHINGO authors. REVIEW ONLY; no original PAUSE upload chronology, ",
    "complete all-time history, version signoff, or publication authority.\n";
exit((@archive_only || @meta_only || @off_author || $developers) ? 1 : 0);
