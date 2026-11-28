#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use version ();

# Offline preflight only. The caller MUST independently audit the actual
# publication history; this script cannot query CPAN/GitHub Releases.
# Conservative policy after PR #886: one actual public-repository Actions
# artifact ZIP was inspected and contained JQ-Lite-3.00_03.tar.gz.
# https://github.com/kawamurashingo/JQ-Lite/actions/runs/40188275036/artifacts/12597242129
# This is observed public *accessibility*, NOT proof of a PAUSE upload
# or any particular download. Require an increasing future public version
# over this known exposed build unless a later reviewed policy PR revises it.
my $known_exposed_developer_version = '3.00_03';
my (@published, @planned, $published_file, $history_reviewed, $ack_historical, $help);
GetOptions(
    'published=s'      => \@published,
    'published-file=s' => \$published_file,
    'planned=s'        => \@planned,
    'history-reviewed' => \$history_reviewed,
    'acknowledge-historical-regressions' => \$ack_historical,
    'help'             => \$help,
) or die "Invalid arguments; use --help\n";

my $usage = <<'USAGE';
Usage: perl ci/check-public-version-order.pl --history-reviewed
       [--published VERSION ... | --published-file FILE]
       --planned VERSION [--planned VERSION ...]
       [--acknowledge-historical-regressions]
List ALL actually public versions oldest first, then the entire proposed
public prerelease-to-stable sequence in order. If none were public, omit
--published/--published-file ONLY after independently confirming that fact.
FILE contains one public version per line, oldest first; empty lines and
# comments are ignored. Never combine --published and --published-file.
The last --planned version must be stable (no underscore).
Past public versions may contain real historical order regressions.
Those require an additional explicit acknowledgement, and future public
versions must exceed EVERY historical version and strictly increase.
This also applies a conservative minimum version-order floor after
confirmed public GitHub Actions accessibility of developer build 3.00_03.
The floor does not claim a CPAN upload, public download or release.
Changing that floor requires separately reviewed historical evidence.
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

# Large historical publication ledgers are easier to reconcile as an
# explicitly human-reviewed, line-oriented file than as hundreds of CLI
# flags. A file never proves that the ledger is complete.
if (defined $published_file) {
    die "Cannot combine --published and --published-file; select one history source\n"
        if @published;
    die "Published-version file path must not be empty\n"
        unless length $published_file;
    open my $ledger, '<', $published_file
        or die "Cannot open published-version file $published_file: $!\n";
    my $line_number = 0;
    while (my $line = <$ledger>) {
        ++$line_number;
        $line =~ s/\r?\n\z//;
        $line =~ s/\s*#.*\z//;
        $line =~ s/\A\s+//;
        $line =~ s/\s+\z//;
        next unless length $line;
        die "Invalid published-version file entry on line $line_number: $line\n"
            unless $line =~ /\A(?:v)?\d+(?:\.\d+)+(?:_\d+)?\z/;
        push @published, $line;
    }
    close $ledger or die "Cannot close published-version file $published_file: $!\n";
    die "Published-version file is empty; omit --published-file only after ",
        "verifying that no public predecessors exist\n"
        unless @published;
}

my @sequence;
for my $pair (
    (map { ['published', $_] } @published),
    (map { ['planned', $_] } @planned),
) {
    my ($kind, $literal) = @$pair;
    die "Invalid Perl version string: $literal\n"
        unless $literal =~ /\A(?:v)?\d+(?:\.\d+)+(?:_\d+)?\z/;
    die "Internal-only 3.00_0x developer versions cannot be planned for publication: $literal\n"
        if $kind eq 'planned' && $literal =~ /\A(?:v)?3\.0+_\d+\z/;
    my $parsed = eval { version->parse($literal) };
    die "Cannot parse Perl version $literal: $@\n" if $@;
    push @sequence, [$kind, $literal, $parsed];
}

# Historical publication cannot be undone. Record every non-increase
# against the highest prior public version; do not mistake the most recent
# published literal for the maximum Perl version ever distributed.
my @history = grep { $_->[0] eq 'published' } @sequence;
my @future  = grep { $_->[0] eq 'planned' } @sequence;
my ($highest_public, @historical_regressions);
for my $entry (@history) {
    if ($highest_public && !($highest_public->[2] < $entry->[2])) {
        push @historical_regressions,
            "$highest_public->[1] is not below $entry->[1]";
    } else {
        $highest_public = $entry;
    }
}

if (@historical_regressions && !$ack_historical) {
    die "Historical public version order has ", scalar(@historical_regressions),
        " non-increase(s); first: $historical_regressions[0]. ",
        "Audit ALL public predecessors and explicitly pass ",
        "--acknowledge-historical-regressions; this does NOT waive ",
        "any future version-order requirement.\n";
}

# Every newly proposed version must be later than the all-time historical
# maximum, not merely the last item in a regressed publication history.
if ($highest_public && !($highest_public->[2] < $future[0][2])) {
    die "Proposed public version must strictly increase beyond every ",
        "previously published version: historical maximum ",
        "$highest_public->[1] is not below $future[0][1]\n";
}
for my $i (1 .. $#future) {
    my ($previous, $current) = @future[$i - 1, $i];
    die "Proposed public versions must strictly increase: ",
        "$previous->[1] is not below $current->[1]\n"
        unless $previous->[2] < $current->[2];
}

# A source tarball named JQ-Lite-3.00_03.tar.gz was publicly
# accessible as a GitHub Actions artifact even though CPAN/MetaCPAN's
# observed published inventories contain no 3.x release. The policy
# floor is deliberately checked separately from the PAUSE history
# maximum: absence from a CPAN ledger must not silently clear exposure.
my $exposed_parsed = version->parse($known_exposed_developer_version);
if (!($exposed_parsed < $future[0][2])) {
    die "Proposed public version $future[0][1] does not exceed known "
        . "GitHub Actions developer artifact exposure baseline "
        . "$known_exposed_developer_version. A public CI tarball is NOT "
        . "a PAUSE upload, but stable 3.00 is blocked under the "
        . "conservative public-distribution policy. Independently "
        . "review evidence and version decision; no release authorized.\n";
}

if (@historical_regressions) {
    print "Historical public version regressions: ",
        scalar(@historical_regressions),
        " acknowledged after independent history review; ",
        "no retroactive repair or publication authorized.\n";
}
print "Conservative public-CI developer artifact exposure floor: ",
    $known_exposed_developer_version,
    " (not a PAUSE upload or release approval).\n";
print "Perl public-version order: PASS (", scalar(@published),
    " audited public predecessors; ", scalar(@planned),
    " proposed future versions). No publication authorized.\n";
