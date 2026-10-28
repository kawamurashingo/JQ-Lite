#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use version ();
use MIME::Base64 qw(decode_base64);
use MIME::QuotedPrint qw(decode_qp);
use Encode qw(decode FB_CROAK);
use Time::Local qw(timegm);

# Compare two independently saved observational sets. NOT a PAUSE ledger.
my ($backpan, $metacpan, $pause_receipts, $pause_mbox, $expected_pause_events, $help);
GetOptions(
    'backpan-author=s' => \$backpan,
    'metacpan=s'      => \$metacpan,
    'pause-receipts=s' => \$pause_receipts,
    'pause-mbox=s'     => \$pause_mbox,
    'expected-pause-events=i' => \$expected_pause_events,
    'help'            => \$help,
) or die "Invalid arguments; use --help\n";
my $usage = <<'USAGE';
Usage: perl ci/compare-backpan-author-metacpan-inventory.pl
  --backpan-author OBSERVED_AUTHOR_INDEX.tsv --metacpan OBSERVED_RELEASES.tsv
  [--pause-receipts PRIVATE_RECEIPTS.tsv | --pause-mbox PRIVATE_GMAIL_TAKEOUT.mbox]
  [--expected-pause-events COUNT]
Use --pause-mbox to read original PAUSE CPAN Upload message bodies
locally from a PRIVATE Google Takeout mbox. Keep the original mbox
in access-controlled storage; never commit it or upload it to public CI.
Recognizes plain-text single-part 7bit/8bit, base64 or quoted-printable.
Fails closed on unsupported multipart target receipts. No network access.
--expected-pause-events guards against a missing repeated upload but is
NOT proof of all-time completeness.
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
die "Select only one private PAUSE input source\n"
    if defined($pause_receipts) && defined($pause_mbox);
die "--expected-pause-events requires a PAUSE input\n"
    if defined($expected_pause_events) && !defined($pause_receipts) && !defined($pause_mbox);
die "Invalid expected PAUSE event count\n"
    if defined($expected_pause_events) && $expected_pause_events < 1;

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

# Parse an offline Google Takeout mbox without reporting or copying private
# headers / message identifiers. This is an RFC822-like mbox parser for the
# known PAUSE upload receipt format, NOT a complete mail authenticity check.
# Only messages with the exact JQ-Lite CPAN Upload subject are considered.
sub pause_utc {
    my ($value) = @_;
    my %month = (
        Jan => 1, Feb => 2, Mar => 3, Apr => 4, May => 5, Jun => 6,
        Jul => 7, Aug => 8, Sep => 9, Oct => 10, Nov => 11, Dec => 12,
    );
    die "Invalid PAUSE Request completed UTC format\n"
        unless defined($value)
            && $value =~ /\A(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun), (\d{1,2}) ([A-Z][a-z]{2}) (\d{4}) (\d\d):(\d\d):(\d\d) GMT\z/
            && exists $month{$2};
    my ($day, $mon, $year, $hour, $min, $sec) =
        ($1, $month{$2}, $3, $4, $5, $6);
    die "Invalid PAUSE UTC calendar time\n"
        if $day < 1 || $day > 31 || $hour > 23 || $min > 59 || $sec > 59;
    my $epoch = eval { timegm($sec, $min, $hour, $day, $mon - 1, $year) };
    die "Invalid PAUSE UTC calendar time\n" if $@;
    my @check = gmtime($epoch);
    die "Invalid PAUSE UTC calendar day\n"
        unless $check[3] == $day && $check[4] == $mon - 1
            && $check[5] + 1900 == $year;
    return (sprintf("%04d-%02d-%02dT%02d:%02d:%02dZ",
        $year, $mon, $day, $hour, $min, $sec), $epoch);
}


# RFC 2047 encoded-word decoding for MIME transport headers. Never
# silently ignore an encoded developer-build subject; fail closed on
# malformed words rather than treating them as unrelated messages.
sub decode_subject_words {
    my ($subject) = @_;
    $subject =~ s{(\?=)\s+(=\?)}{$1$2}g;
    $subject =~ s{=\?([A-Za-z0-9_.-]+)\?([BQbq])\?([^?]*)\?=}{
        my ($charset, $kind, $encoded) = ($1, uc($2), $3);
        my $bytes;
        if ($kind eq 'B') {
            die "Invalid encoded MIME subject\n"
                unless $encoded =~ /\A(?:[A-Za-z0-9+\/]{4})*
                    (?:[A-Za-z0-9+\/]{2}==|[A-Za-z0-9+\/]{3}=)?\z/x;
            $bytes = decode_base64($encoded);
        } else {
            die "Invalid encoded MIME subject\n"
                unless $encoded =~ /\A(?:[^=]|=[0-9A-Fa-f]{2})*\z/;
            $encoded =~ tr/_/ /;
            $encoded =~ s/=([0-9A-Fa-f]{2})/chr(hex($1))/ge;
            $bytes = $encoded;
        }
        my $decoded = eval { decode($charset, $bytes, FB_CROAK) };
        die "Unsupported or malformed encoded MIME subject\n"
            if $@ || !defined($decoded);
        $decoded;
    }gex;
    die "Unparsed encoded MIME subject\n"
        if $subject =~ /=\?[^ \t]*\?=/;
    return $subject;
}

# Exactly one copy of each PAUSE producer field is required. Counting
# labels before parsing values avoids a second conflicting 'sha256:' or
# 'Request completed:' being silently hidden by scalar regexp capture.
sub receipt_field {
    my ($body, $name) = @_;
    my @values = $body =~ /^[ \t]*\Q$name\E:[ \t]*([^\n]*?)[ \t]*$/gm;
    die "Missing or duplicate PAUSE receipt field $name\n"
        unless @values == 1;
    return $values[0];
}

sub parse_pause_mbox_message {
    my ($raw, $rows) = @_;
    $raw =~ s/\r\n/\n/g;
    my ($header_text, $body) = split /\n\n/, $raw, 2;
    return unless defined($body);  # A malformed unrelated message.
    my %header;
    my $last = '';
    for my $line (split /\n/, $header_text) {
        if ($line =~ /\A([A-Za-z0-9-]+):\s*(.*)\z/) {
            $last = lc $1;
            $header{$last} = $2 unless exists $header{$last};
        } elsif ($line =~ /\A[ \t]+(.*)\z/ && length($last)) {
            $header{$last} .= ' ' . $1;
        } else {
            $last = '';
        }
    }
    my $subject = $header{subject};
    return unless defined $subject;
    $subject = decode_subject_words($subject);
    return unless $subject =~ /\ACPAN Upload: S\/SH\/SHINGO\/JQ-Lite-(\d+(?:\.\d+)+(?:_\d+)?)\.tar\.gz\z/;
    my $version = $1;
    die "Internal/developer PAUSE receipt needs independent investigation\n"
        if $version =~ /_/;

    my $type = lc($header{'content-type'} || 'text/plain');
    die "Unsupported non-plain-text PAUSE receipt MIME content\n"
        unless $type =~ /\Atext\/plain(?:\s*;|\s*\z)/;
    my $encoding = lc($header{'content-transfer-encoding'} || '7bit');
    $encoding =~ s/\s+\z//;
    if ($encoding eq 'base64') {
        die "Malformed PAUSE base64 transfer encoding\n"
            unless $body =~ /\A[A-Za-z0-9+\/=\s]*\z/;
        $body = decode_base64($body);
    } elsif ($encoding eq 'quoted-printable') {
        $body = decode_qp($body);
    } else {
        die "Unsupported PAUSE transfer encoding\n"
            unless $encoding =~ /\A(?:7bit|8bit|binary)\z/;
    }
    $body =~ s/\r\n/\n/g;
    my $archive = "JQ-Lite-$version.tar.gz";
    die "PAUSE message archive narrative mismatch\n"
        unless $body =~ /\AThe uploaded file\s+\Q$archive\E\s+has entered CPAN as\s+/s;
    my $path = receipt_field($body, 'file');
    die "PAUSE message archive/path mismatch\n"
        unless $path eq '$CPAN/authors/id/S/SH/SHINGO/' . $archive;
    my $size = receipt_field($body, 'size');
    my $digest = receipt_field($body, 'sha256');
    my $entered = receipt_field($body, 'Request entered on');
    my $completed = receipt_field($body, 'Request completed');
    die "Invalid PAUSE archive size or SHA-256\n"
        unless $size =~ /\A([1-9][0-9]*) bytes\z/
            && $digest =~ /\A[0-9a-f]{64}\z/;
    my $bytes = $1;
    my ($iso, $finished_epoch) = pause_utc($completed);
    my ($entered_iso, $entered_epoch) = pause_utc($entered);
    die "PAUSE upload completed before request entry\n"
        if $finished_epoch < $entered_epoch;
    push @$rows, [$archive, $version, $iso, $bytes, $digest];
}

sub read_pause_mbox {
    my ($path) = @_;
    open my $fh, '<', $path or die "Cannot open private PAUSE mbox\n";
    my (@rows, $record, $seen_envelope);
    while (my $line = <$fh>) {
        if ($line =~ /\AFrom \S+ (?:Mon|Tue|Wed|Thu|Fri|Sat|Sun) /) {
            if ($seen_envelope) {
                parse_pause_mbox_message($record, \@rows);
            }
            $record = '';
            ++$seen_envelope;
        } else {
            die "Invalid mbox envelope separator\n" unless $seen_envelope;
            $record .= $line;
        }
    }
    parse_pause_mbox_message($record, \@rows) if $seen_envelope;
    close $fh or die "Cannot close private PAUSE mbox\n";
    die "No PAUSE CPAN Upload receipts found in private mbox\n"
        unless @rows;
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
if (defined($pause_receipts) || defined($pause_mbox)) {
    die "Empty PAUSE input path\n"
        if defined($pause_receipts) && !length($pause_receipts)
            || defined($pause_mbox) && !length($pause_mbox);
    my @receipts = defined($pause_mbox)
        ? read_pause_mbox($pause_mbox)
        : read_tsv($pause_receipts,
            "archive\tversion\tcompleted_utc\tbytes\tsha256", 5,
            'PAUSE receipts');
    die "Unexpected PAUSE receipt event count\n"
        if defined($expected_pause_events)
            && @receipts != $expected_pause_events;
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
if (defined($pause_receipts) || defined($pause_mbox)) {
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
