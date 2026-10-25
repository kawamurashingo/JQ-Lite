#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use JSON::PP ();

# Observational CPAN Testers data can include repeat uploads or incomplete
# historic records. Preserve them; never invent missing fields or dates.
my ($input, $help);
GetOptions('input=s' => \$input, 'help' => \$help)
    or die "Invalid arguments; use --help\n";
my $usage = <<'USAGE';
Usage: perl ci/inventory-cpantesters-jq-lite-uploads.pl --input SAVED_RESPONSE.json
Offline reader for CPAN Testers /v1/upload/dist/JQ-Lite JSON arrays.
Print all rows. Exit 0 clean; 2 observed incomplete/duplicate data (audit
BLOCKED); nonzero otherwise for malformed data or an internal 3.00_0x build.
Dates may originate from mirror file mtimes or NNTP, NOT original PAUSE
upload chronology. No network access or release approval.
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

my (@out, %versions, $internal, $off_author, $anomalies);
my $n = 0;
for my $r (@$rows) {
    ++$n;
    die "CPAN Testers row $n is not a JSON object\n" unless ref($r) eq 'HASH';
    for my $required (qw(dist version released)) {
        die "Missing/invalid $required in CPAN Testers row $n\n"
            if !defined($r->{$required}) || ref($r->{$required})
                || !length($r->{$required});
    }
    die "Foreign distribution in CPAN Testers row $n\n"
        unless $r->{dist} eq 'JQ-Lite';
    my $version = $r->{version};
    die "Invalid CPAN Testers version at row $n\n"
        unless $version =~ /\A(?:v)?\d+(?:\.\d+)+(?:_\d+)?\z/;
    my $filename = $r->{filename};
    my $author = $r->{author};
    die "Invalid filename/author field type at row $n\n"
        if (defined($filename) && ref($filename))
            || (defined($author) && ref($author));
    $filename = '' unless defined $filename;
    $author = '' unless defined $author;
    my $date = $r->{released};
    die "Invalid CPAN Testers release date at row $n\n"
        unless $date =~ /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)\z/;
    my $type = exists $r->{type} && defined $r->{type}
        ? $r->{type} : 'unreported';
    die "Invalid CPAN Testers upload type at row $n\n"
        if ref($type) || $type !~ /\A(?:cpan|backpan|upload|unreported)\z/;

    my @flags;
    if ($version =~ /\A(?:v)?3\.0+_\d+\z/) {
        ++$internal;
        push @flags, 'INTERNAL-DEVELOPER-ARTIFACT-ALERT';
    }
    if (!length($filename)) {
        push @flags, 'MISSING-FILENAME-REVIEW';
    } else {
        die "Invalid upload filename at row $n: $filename\n"
            unless $filename =~ /\AJQ-Lite-((?:v)?\d+(?:\.\d+)+(?:_\d+)?)\.tar\.gz\z/
                && $1 eq $version;
    }
    if (!length($author)) {
        push @flags, 'MISSING-AUTHOR-REVIEW';
    } elsif ($author !~ /\A[A-Z0-9_-]+\z/) {
        die "Invalid upload author at row $n\n";
    } elsif ($author ne 'SHINGO') {
        ++$off_author;
        push @flags, 'NON-SHINGO-UPLOADER-REVIEW';
    }
    if ($date =~ /\A1970-01-01T00:00:00(?:\.0+)?Z\z/) {
        push @flags, 'EPOCH-SENTINEL-REVIEW';
    }
    if ($versions{$version}++) {
        push @flags, 'DUPLICATE-VERSION-REVIEW';
    }
    ++$anomalies if @flags;
    push @out, [$date, $version, $author, $filename, $type,
        @flags ? join(',', @flags) : 'observed-upload'];
}
@out = sort { $a->[0] cmp $b->[0] || $a->[3] cmp $b->[3] } @out;
print "released_observed\tversion\tauthor\tfilename\ttype\tclassification\n";
print join("\t", @$_), "\n" for @out;
die "INTERNAL-DEVELOPER-ARTIFACT-ALERT or off-author upload; investigation required: internal=$internal, other_authors=$off_author\n"
    if $internal || $off_author;
if ($anomalies) {
    warn "REVIEW_ONLY_UPLOAD_RECORD_ANOMALIES: $anomalies flagged rows. Historical data is not clean or attested.\n";
    exit 2;
}
