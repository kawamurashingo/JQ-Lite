use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;

# Source archives are *not* private on public GitHub Actions. The
# inventory is allowed to retain existing API metadata, never internal
# developer tarball/ZIP bytes, and is not a PAUSE history attestation.
my $workflow = File::Spec->catfile($FindBin::Bin, '..',
    '.github', 'workflows', 'v3-internal-artifact-exposure-audit.yml');
plan skip_all => 'Actions YAML is not shipped in the source distribution'
    unless -f $workflow;

open my $fh, '<', $workflow or die "Cannot read $workflow: $!";
my $text = do { local $/; <$fh> };
close $fh or die "Cannot close $workflow: $!";

like($text, qr/^  actions: read\s*$/m,
    'audit receives read-only Actions API permission');
like($text, qr/gh api "repos\/\$GITHUB_REPOSITORY\/actions\/artifacts\?/,
    'inventory consumes GitHub Actions artifact metadata');
unlike($text, qr/gh api[^\n]*(?:-X|--method)\s+(?:DELETE|POST|PUT)/i,
    'inventory does not request GitHub API mutation');

my ($record) = $text =~
    /(?:^      - name: Record metadata-only snapshot provenance and SHA-256\n)(.*?)(?=^      - name:|\z)/ms;
ok(defined $record, 'metadata provenance step exists');
if (defined $record) {
    like($record, qr/^        if: always\(\)\s*$/m,
        'partial API responses are preserved after a failed inventory');
    like($record, qr/sha256sum provenance\.txt/,
        'provenance checksum is recorded');
    like($record, qr/sha256sum "\$\{pages\[\@\]\}"/,
        'original JSON page checksums are recorded');
}

my ($upload) = $text =~
    /(?:^      - name: Upload metadata-only exposure evidence\n)(.*?)(?=^      - name:|\z)/ms;
ok(defined $upload, 'separate metadata-only upload step exists');
if (defined $upload) {
    like($upload, qr/^        if: always\(\)\s*$/m,
        'upload preserves partial evidence if collection fails');
    like($upload, qr/^        uses: actions\/upload-artifact\@v4\s*$/m,
        'snapshot uses the supported artifact action');
    like($upload, qr/^          retention-days: 14\s*$/m,
        'short 14-day retention forces explicit human preservation');

    my ($paths) = $upload =~
        /^          path: \|\n((?:^            \S[^\n]*\n)+)/m;
    ok(defined $paths, 'upload has a literal, inspectable path whitelist');
    if (defined $paths) {
        my @paths = map { my $p = $_; $p =~ s/^            //; $p }
            grep { length } split /\n/, $paths;
        my $prefix = '\${{ runner.temp }}/v3-ci-exposure/';
        my @allowed = map { $prefix . $_ } (
            'artifact-page-*.json',
            'developer-artifacts.tsv',
            'provenance.txt',
            'manifest-sha256.txt',
        );
        is_deeply(\@paths, \@allowed,
            'upload whitelist cannot silently include archive bytes or workspace');
    }
    unlike($upload, qr/v3-unreleased-source-|JQ-Lite-\*\.tar\.gz/,
        'metadata artifact never uses the historic developer-archive name');
}
my $uploads = () = $text =~ /uses: actions\/upload-artifact\@/g;
is($uploads, 1, 'only the metadata-only upload step may export data');
done_testing;
