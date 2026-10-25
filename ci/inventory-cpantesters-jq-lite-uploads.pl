#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use JSON::PP ();

# Parse one saved CPAN Testers /v1/upload/dist/JQ-Lite response offline.
# Its 'released' dates can originate from mirror mtimes OR NNTP notices.
# They are NOT PAUSE's authoritative upload timestamps or completeness proof.
my ($input, $help);
GetOptions('input=s' => \$input, 'help' => \$help)
    or die "Invalid arguments; use --help\n";
my $usage = <<'USAGE';
Usage: perl ci/inventory-cpantesters-jq-lite-uploads.pl --input SAVED_RESPONSE.json
Interpret a saved CPAN Testers /v1/upload/dist/JQ-Lite JSON response.
Preserves every row; flags duplicates, internal candidates and off-author
records for review. No network, PAUSE completeness attestation or release.
USAGE
if ($help) { print $usage; exit 0 }
die $usage if @ARGV || !defined($input) || !length($input);
open my $fh, '<', $input or die "Cannot open CPAN Testers response $input: $!\n";
binmode $fh;
my $raw = do { local $/; <$fh> };
close $fh or die "Cannot close CPAN Testers response: $!\n";
die "Empty CPAN Testers response\n" unless defined($raw) && length($raw);
my $rows = eval { JSON::PP->new->utf8->decode($raw) };
die "Malformed CPAN Testers JSON: $@\n" if $@;
die "Expected CPAN Testers uploads JSON array\n" unless ref($rows) eq 'ARRAY';
die "No upload records; cannot establish a historical observation\n" unless @$rows;
my (@out, %versions, %names, $internal, $off_author, $duplicates);
my $n = 0;
for my $r (@$rows) {
    ++$n;
    die "CPAN Testers row $n is not a JSON object\n" unless ref($r) eq 'HASH';
    for my $required (qw(dist version author filename released)) {
        die "Missing/invalid $required in CPAN Testers row $n\n"
            if !defined($r->{$required}) || ref($r->{$required})
                || !length($r->{$required});
    }
    die "Foreign distribution in CPAN Testers row $n\n"
        unless $r->{dist} eq 'JQ-Lite';
    my $filename = $r->{filename};
    die "Unexpected upload filename at row $n: $filename\n"
        unless $filename =~ /\AJQ-Lite-((?:v)?\d+(?:\.\d+)+(?:_\d+)?)\.tar\.gz\z/;
    my $version = $1;
    die "Filename/version mismatch in CPAN Testers row $n\n"
        unless $version eq $r->{version};
    my $date = $r->{released};
    die "Invalid CPAN Testers release date at row $n\n"
        unless $date =~ /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)\z/;
    die "Invalid upload author in CPAN Testers row $n\n"
        unless $r->{author} =~ /\A[A-Z0-9_-]+\z/;
    my $type = exists $r->{type} && defined $r->{type}
        ? $r->{type} : 'unreported';
    die "Invalid CPAN Testers upload type at row $n\n"
        if ref($type) || $type !~ /\A(?:cpan|backpan|upload|unreported)\z/;
    my @flags;
    if ($version =~ /\A(?:v)?3\.0+_\d+\z/) {
        ++$internal;
        push @flags, 'INTERNAL-DEVELOPER-ARTIFACT-ALERT';
    }
    if ($r->{author} ne 'SHINGO') {
        ++$off_author;
        push @flags, 'NON-SHINGO-UPLOADER-REVIEW';
    }
    if ($versions{$version}++ || $names{$filename}++) {
        ++$duplicates;
        push @flags, 'DUPLICATE-UPLOAD-NEEDS-REVIEW';
    }
    push @out, [$date, $version, $r->{author}, $filename, $type,
        @flags ? join(',', @flags) : 'observed-upload'];
}
@out = sort { $a->[0] cmp $b->[0] || $a->[3] cmp $b->[3] } @out;
print "released_observed\tversion\tauthor\tfilename\ttype\tclassification\n";
print join("\t", @$_), "\n" for @out;
die "CPAN Testers upload results require investigation: internal=$internal, off_author=$off_author, duplicates=$duplicates\n"
    if $internal || $off_author || $duplicates;
