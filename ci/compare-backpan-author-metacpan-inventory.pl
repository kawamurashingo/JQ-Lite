#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use version ();

# Compare two independently saved observational sets. NOT a PAUSE ledger.
my ($backpan, $metacpan, $pause_receipts, $help);
GetOptions(
    'backpan-author=s' => \$backpan,
    'metacpan=s'      => \$metacpan,
    'pause-receipts=s' => \$pause_receipts,
    'help'            => \$help,
) or die "Invalid arguments; use --help\n";
my $usage = <<'USAGE';
Usage: perl ci/compare-backpan-author-metacpan-inventory.pl
  --backpan-author OBSERVED_AUTHOR_INDEX.tsv --metacpan OBSERVED_RELEASES.tsv
  [--pause-receipts PRIVATE_RECEIPTS.tsv]
Optional PRIVATE_RECEIPTS.tsv has columns:
archive<TAB>version<TAB>completed_utc<TAB>bytes<TAB>sha256
Timestamps must be original PAUSE "Request completed" UTC (ISO 8601 Z).
Extract values locally from original receipt BODIES, including repeats.
Never upload private email bodies, mail IDs or headers to the public repo.
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
# Optional private PAUSE receipt comparison: only public archive facts enter
# output. No original emails, personal addresses or message identifiers.
# Duplicates are retained as distinct events, but same-version hashes
# and byte counts MUST agree or the observation is ambiguous.
my (%pause, %seen_event, @chronology, $repeats, @pause_only, @pause_missing,
    @ambiguous_order, @historical_regressions);
if (defined $pause_receipts) {
    die "Empty PAUSE receipts path\n" unless length $pause_receipts;
    my @receipts = read_tsv($pause_receipts,
        "archive\tversion\tcompleted_utc\tbytes\tsha256", 5,
        'PAUSE receipts');
    for my $r (@receipts) {
        my ($archive, $version, $utc, $bytes, $digest) = @$r;
        die "Malformed PAUSE receipt (archive/version/timestamp/size/digest)\n"
            unless $version =~ /\A\d+(?:\.\d+)+\z/
            && $archive eq "JQ-Lite-$version.tar.gz"
            && $utc =~ /\A\d{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\dZ\z/
            && $bytes =~ /\A[1-9]\d*\z/
            && $digest =~ /\A[a-f0-9]{64}\z/;
        die "Repeated identical PAUSE version+completion-time event\n"
            if $seen_event{"$version\t$utc"}++;
        if (exists $pause{$version}) {
            die "Conflicting PAUSE archive size or SHA-256 for $version\n"
                if $pause{$version}{bytes} ne $bytes
                    || $pause{$version}{digest} ne $digest;
            ++$repeats;
        } else {
            $pause{$version} = { bytes => $bytes, digest => $digest };
        }
        push @chronology, [$utc, $version];
    }
    @pause_only = sort grep { !$archived{$_} || !$indexed{$_} } keys %pause;
    @pause_missing = sort grep { !$pause{$_} } keys %archived;
    @chronology = sort { $a->[0] cmp $b->[0] || $a->[1] cmp $b->[1] }
        @chronology;
    my ($peak, $highest);
    for my $item (@chronology) {
        my ($utc, $literal) = @$item;
        my $parsed = version->parse($literal);
        if (defined($highest) && !($highest < $parsed)) {
            push @historical_regressions, "$literal after $peak"
                if $literal ne $peak;
        } else {
            ($highest, $peak) = ($parsed, $literal);
        }
    }
    for my $i (1 .. $#chronology) {
        if ($chronology[$i][0] eq $chronology[$i - 1][0]
                && $chronology[$i][1] ne $chronology[$i - 1][1]) {
            push @ambiguous_order, $chronology[$i][0];
        }
    }
}
my @archive_only = sort grep { !$indexed{$_} } keys %archived;
my @meta_only = sort grep { !$archived{$_} } keys %indexed;
if (defined $pause_receipts) {
    print "PAUSE original receipt events: ", scalar(@chronology), "\n";
    print "PAUSE distinct versions: ", scalar(keys %pause), "\n";
    print "PAUSE same-byte repeated uploads: ", ($repeats || 0), "\n";
    print "PAUSE-ONLY VERSION: $_\n" for @pause_only;
    print "PAUSE-MISSING VERSION: $_\n" for @pause_missing;
    print "HISTORICAL NON-INCREASE: $_\n" for @historical_regressions;
    print "AMBIGUOUS PAUSE COMPLETION TIME: $_\n" for @ambiguous_order;
}
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
exit((@archive_only || @meta_only || @off_author || $developers
    || @pause_only || @pause_missing || @ambiguous_order) ? 1 : 0);
