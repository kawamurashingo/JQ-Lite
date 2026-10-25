use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;

# Release safety invariant: public CI must never re-expose the internal
# developer candidate as a downloadable Actions artifact. This test does
# not prohibit evidence-only provenance JSON/TSV, or an eventual explicitly
# authorized stable public release in a separate reviewed workflow.
my $root = File::Spec->catdir($FindBin::Bin, '..');
my $workflow = File::Spec->catfile($root, '.github', 'workflows',
    'v3-source-dist.yml');
ok(-f $workflow, 'source distribution workflow exists');
open my $fh, '<', $workflow or die "Cannot read $workflow: $!";
my $text = do { local $/; <$fh> };
close $fh or die "Cannot close $workflow: $!";
ok(length($text), 'workflow is nonempty');

unlike($text, qr/actions\/upload-artifact(?:\@v[0-9]+)?/,
    'source distribution workflow must not upload internal build artifacts');
unlike($text, qr/v3-unreleased-source-/,
    'historic artifact naming pattern cannot be reintroduced');
like($text, qr/make disttest/,
    'actual MakeMaker source distribution verification stays in place');
like($text, qr/tar -xzf "\$archive"/,
    'real tarball extraction verification stays in place');
like($text, qr/make install/,
    'isolated package installation verification stays in place');
like($text, qr/sha256sum "\$archive"/,
    'checksum remains observable without exporting archive bytes');
like($text, qr/test "\$archive" = "JQ-Lite-\$candidate_version\.tar\.gz"/,
    'source artifact version name is checked against package metadata');

done_testing;
