#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use version ();

# Offline observation reconciliation, not a publication-history attestation.
my ($backpan_file, $inventory_file, $help);
GetOptions(
    'backpan-file=s' => \$backpan_file,
    'inventory=s'    => \$inventory_file,
    'help'           => \$help,
) or die "Invalid arguments; use --help\n";
my $usage = <<'USAGE';
Usage: perl ci/compare-backpan-cpan-inventory.pl
       --backpan-file observed-backpan.tsv --inventory observed-cpan.tsv
Compare saved BackPAN release-history observations against a saved CPAN
archive inventory. Output is REVIEW ONLY: BackPAN epochs and CPAN index
mtimes do not by themselves attest PAUSE upload order, corpus completeness,
or release safety. Never use this output as a --published-file ledger.
USAGE
if ($help) { print $usage; exit 0 }
die $usage if @ARGV || !defined($backpan_file) || !length($backpan_file)
    || !defined($inventory_file) || !length($inventory_file);

sub read_lines {
    my ($file, $kind) = @_;
    open my $fh, '<', $file or die "Cannot open $kind $file: $!\n";
    my @lines = <$fh>;
    close $fh or die "Cannot close $kind $file: $!\n";
    return @lines;
}
sub fields {
    my ($line, $expected, $where) = @_;
    $line =~ s/\r?\n\z//;
    my @parts = split /\t/, $line, -1;
    die "Expected $expected TSV columns in $where\n"
        unless @parts == $expected;
    return @parts;
}
sub parse_version {
    my ($version_string, $where) = @_;
    my $parsed = eval { version->parse($version_string) };
    die "Cannot parse Perl version $version_string in $where\n" if $@ || !$parsed;
    return $parsed;
}

my @raw_backpan = read_lines($backpan_file, 'BackPAN observations');
die "BackPAN TSV missing header\n" unless @raw_backpan;
my $bheader = shift @raw_backpan;
$bheader =~ s/\r?\n\z//;
die "Unexpected BackPAN TSV header\n" unless $bheader eq "path\tepoch\tsize";
my (%backpan, %seen_path, @by_time, $internal_count);
my $row = 1;
for my $line (@raw_backpan) {
    ++$row;
    my ($path, $epoch, $size) = fields($line, 3, "BackPAN line $row");
    die "Invalid BackPAN archive path at line $row: $path\n"
        unless $path =~ m{\A[A-Z]/[A-Z]{2}/[A-Z0-9_-]+/JQ-Lite-((?:v)?\d+(?:\.\d+)+(?:_\d+)?)\.tar\.gz\z};
    my $version = $1;
    die "Invalid BackPAN timestamp at line $row\n"
        unless $epoch =~ /\A[1-9]\d{8,10}\z/;
    die "Invalid BackPAN byte size at line $row\n"
        unless $size =~ /\A[1-9]\d*\z/;
    die "Duplicate BackPAN path at line $row: $path\n" if $seen_path{$path}++;
    die "Ambiguous duplicate BackPAN version $version at line $row\n"
        if exists $backpan{$version};
    $backpan{$version} = $path;
    push @by_time, [$epoch, $version, $path];
    parse_version($version, "BackPAN line $row");
    ++$internal_count if $version =~ /\A(?:v)?3\.0+_\d+\z/;
}
die "BackPAN input contains no JQ-Lite archives\n" unless keys %backpan;

my @raw_cpan = read_lines($inventory_file, 'CPAN inventory');
die "CPAN TSV missing header\n" unless @raw_cpan;
my $cheader = shift @raw_cpan;
$cheader =~ s/\r?\n\z//;
die "Unexpected CPAN TSV header\n"
    unless $cheader eq "archive\tversion\tindex_last_modified\tclassification";
my %cpan;
$row = 1;
for my $line (@raw_cpan) {
    ++$row;
    my ($archive, $version, $mtime, $class) = fields($line, 4, "CPAN line $row");
    die "Invalid CPAN archive/version at line $row\n"
        unless $archive =~ /\AJQ-Lite-((?:v)?\d+(?:\.\d+)+(?:_\d+)?)\.tar\.gz\z/
        && $1 eq $version;
    die "Invalid CPAN index mtime at line $row\n"
        unless $mtime =~ /\A\d{4}-\d\d-\d\d \d\d:\d\d\z/;
    die "Unexpected CPAN classification at line $row\n"
        unless $class eq 'observed-archive' || $class eq 'INTERNAL-DEVELOPER-ARTIFACT-ALERT';
    die "Duplicate CPAN version $version at line $row\n"
        if exists $cpan{$version};
    $cpan{$version} = $archive;
    parse_version($version, "CPAN line $row");
    ++$internal_count if $class eq 'INTERNAL-DEVELOPER-ARTIFACT-ALERT'
        || $version =~ /\A(?:v)?3\.0+_\d+\z/;
}
die "CPAN input contains no JQ-Lite archives\n" unless keys %cpan;

my @backpan_only = sort grep { !exists $cpan{$_} } keys %backpan;
my @cpan_only = sort grep { !exists $backpan{$_} } keys %cpan;
my @path_mismatch = sort grep {
    exists $cpan{$_} && $backpan{$_} ne "S/SH/SHINGO/$cpan{$_}"
} keys %backpan;
print "BackPAN observed versions: ", scalar(keys %backpan), "\n";
print "CPAN index observed versions: ", scalar(keys %cpan), "\n";
for my $v (@backpan_only) {
    print "BACKPAN ONLY (investigate removed/older archive): $backpan{$v}\n";
}
for my $v (@cpan_only) {
    print "CPAN ONLY (investigate stale/partial BackPAN index): $cpan{$v}\n";
}
for my $v (@path_mismatch) {
    print "AUTHOR/PATH MISMATCH for $v: BackPAN=$backpan{$v}; CPAN=S/SH/SHINGO/$cpan{$v}\n";
}
@by_time = sort { $a->[0] <=> $b->[0] || $a->[2] cmp $b->[2] } @by_time;
my ($prior_epoch, $peak, $peak_version, $ties) = (undef, undef, undef, 0);
for my $entry (@by_time) {
    my ($epoch, $v, $path) = @$entry;
    print "BACKPAN ORDER OBSERVATION: $epoch\t$v\t$path\n";
    if (defined $prior_epoch && $prior_epoch == $epoch) {
        ++$ties;
        print "AMBIGUOUS ORDER: identical BackPAN epochs for $v and earlier entry\n";
    }
    my $parsed = parse_version($v, "BackPAN order observation");
    if (defined $peak && $parsed <= $peak) {
        print "HISTORICAL PERL ORDER NON-INCREASE: $v <= $peak_version (verify chronology)\n";
    }
    if (!defined $peak || $parsed > $peak) {
        $peak = $parsed;
        $peak_version = $v;
    }
    $prior_epoch = $epoch;
}
if ($internal_count) {
    print "INTERNAL-DEVELOPER-ARTIFACT-ALERT: $internal_count observed occurrence(s); investigate publication\n";
}
print "Observation summary: ", scalar(@backpan_only), " BackPAN-only; ",
    scalar(@cpan_only), " CPAN-only; ", scalar(@path_mismatch),
    " author/path mismatches; $ties same-epoch ambiguities. ",
    "NOT a complete PAUSE/publication audit or --history-reviewed approval.\n";
exit((@backpan_only || @cpan_only || @path_mismatch || $ties || $internal_count) ? 1 : 0);
