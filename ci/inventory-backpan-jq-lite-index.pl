#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use IO::Uncompress::Gunzip qw($GunzipError);

# Offline index extraction. BackPAN timestamps do NOT attest PAUSE upload order.
my ($input, $help);
GetOptions('input=s' => \$input, 'help' => \$help)
    or die "Invalid arguments; use --help\n";
my $usage = <<'USAGE';
Usage: perl ci/inventory-backpan-jq-lite-index.pl --input saved-releases-index.txt.gz
Read a locally saved BackPAN #FORMAT 1 releases-only index (plain or gzip)
and emit observational path/epoch/size TSV for JQ-Lite tarballs.
No network, dependency install, completeness claim or release approval.
This output is NOT a chronological --published-file ledger.
USAGE
if ($help) { print $usage; exit 0 }
die $usage if @ARGV || !defined($input) || !length($input);

open my $probe, '<:raw', $input or die "Cannot open BackPAN index $input: $!\n";
my $n = read $probe, my $magic, 2;
die "Cannot read BackPAN index $input: $!\n" unless defined $n;
close $probe or die "Cannot close BackPAN index $input: $!\n";
die "Empty BackPAN index\n" unless $n;

my $fh;
if ($n == 2 && $magic eq "\x1f\x8b") {
    $fh = IO::Uncompress::Gunzip->new($input)
        or die "Cannot decompress BackPAN index: $GunzipError\n";
} else {
    open $fh, '<', $input or die "Cannot open BackPAN index $input: $!\n";
}

my ($row, @observed, %seen_path, %seen_version, $internal_count);
$internal_count = 0;
while (my $line = <$fh>) {
    ++$row;
    $line =~ s/\r?\n\z//;
    if ($row == 1) {
        die "Unsupported BackPAN format: expected #FORMAT 1\n"
            unless $line eq '#FORMAT 1';
        next;
    }
    next unless $line =~ m{(?:\A|/)JQ-Lite-};
    my ($path, $epoch, $size) =
        $line =~ /\A(\S+)\s+([1-9]\d{8,10})\s+([1-9]\d*)\z/;
    die "Malformed JQ-Lite BackPAN record at line $row\n"
        unless defined $path;
    $path =~ s{\Aauthors/id/}{};
    die "Unexpected JQ-Lite BackPAN archive at line $row: $path\n"
        unless $path =~ m{\A[A-Z]/[A-Z]{2}/[A-Z0-9_-]+/JQ-Lite-((?:v)?\d+(?:\.\d+)+(?:_\d+)?)\.tar\.gz\z};
    my $version = $1;
    die "Duplicate BackPAN path at line $row: $path\n" if $seen_path{$path}++;
    die "Ambiguous duplicate BackPAN version at line $row: $version\n"
        if $seen_version{$version}++;
    ++$internal_count if $version =~ /\A(?:v)?3\.0+_\d+\z/;
    push @observed, [$path, $epoch, $size];
}
die "BackPAN index missing format header\n" unless $row;
close $fh or die "Cannot close BackPAN index: $!\n";
die "No JQ-Lite archives found in supplied BackPAN index\n" unless @observed;

@observed = sort { $a->[1] <=> $b->[1] || $a->[0] cmp $b->[0] } @observed;
print "path\tepoch\tsize\n";
for my $entry (@observed) {
    print join("\t", @$entry), "\n";
}
if ($internal_count) {
    die "INTERNAL-DEVELOPER-ARTIFACT-ALERT: $internal_count BackPAN JQ-Lite 3.00_0x candidate(s); investigate exposure\n";
}
