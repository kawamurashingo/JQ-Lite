#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use version ();

# Offline preflight only. The caller MUST independently audit the actual
# publication history; this script cannot query CPAN/GitHub Releases.
my (@published, @planned, $history_reviewed, $help);
GetOptions(
    'published=s'      => \@published,
    'planned=s'        => \@planned,
    'history-reviewed' => \$history_reviewed,
    'help'             => \$help,
) or die "Invalid arguments; use --help\n";

my $usage = <<'USAGE';
Usage: perl ci/check-public-version-order.pl --history-reviewed
       [--published VERSION ...] --planned VERSION [--planned VERSION ...]
List ALL actually public versions oldest first, then the entire proposed
public prerelease-to-stable sequence in order. If none were public, omit
--published ONLY after independently confirming that fact. The last
--planned version must be stable (no underscore).
This checks numeric Perl version ordering, not publication history.
No release is authorized or performed by this tool.
USAGE
if ($help) {
    print $usage;
    exit 0;
}
die $usage if @ARGV;
die "Publication history must be independently audited; pass --history-reviewed only after doing so\n"
    unless $history_reviewed;
die "At least one --planned public version (ending in stable) is required\n"
    unless @planned;
die "The final --planned version must be stable (no underscore)\n"
    if $planned[-1] =~ /_/;

my @sequence;
for my $pair (
    (map { ['published', $_] } @published),
    (map { ['planned', $_] } @planned),
) {
    my ($kind, $literal) = @$pair;
    die "Invalid Perl version string: $literal\n"
        unless $literal =~ /\A(?:v)?\d+(?:\.\d+)+(?:_\d+)?\z/;
    die "Internal-only 3.00_0x developer versions cannot be planned for publication: $literal\n"
        if $kind eq 'planned' && $literal =~ /\A3\.0+_\d+\z/;
    my $parsed = eval { version->parse($literal) };
    die "Cannot parse Perl version $literal: $@\n" if $@;
    push @sequence, [$kind, $literal, $parsed];
}

for my $i (1 .. $#sequence) {
    my ($previous, $current) = @sequence[$i - 1, $i];
    die "Public version must strictly increase: $previous->[1] is not below $current->[1]\n"
        unless $previous->[2] < $current->[2];
}

print "Perl public-version order: PASS (", scalar(@published),
    " audited public predecessors; ", scalar(@planned),
    " proposed future versions). No publication authorized.\n";
