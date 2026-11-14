use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;

my $path=File::Spec->catfile($FindBin::Bin, '..', 'README.md');
open my $fh,'<',$path or die "Cannot read $path: $!";
my $readme=do { local $/; <$fh> };
close $fh or die "Cannot close $path: $!";
my ($download)=$readme =~ /(## From Source \(Latest Stable CPAN Release\).*?)(?=^### Install \(user-local|\z)/ms;
ok(defined $download,'stable-only manual CPAN download example exists');
if (defined $download) {
    unlike($download,qr{http://}i,'no insecure HTTP metadata or tarball fetch');
    unlike($download,qr{JSON-PP-4\.xx\.tar\.gz|JSONPP_LIB},'no broken external JSON::PP bootstrap');
    like($download,qr/set -euo pipefail/,'Bash pipefail rejects a failed API request');
    like($download,qr/curl -fsSL --proto '=https' --proto-redir '=https'/,
        'curl and redirects limited to HTTPS');
    like($download,qr{https://fastapi\.metacpan\.org/v1/release/JQ-Lite},
        'HTTPS release metadata endpoint');
    like($download,qr{https://cpan\.metacpan\.org/authors/id/S/SH/SHINGO/JQ-Lite-\$ver\.tar\.gz},
        'HTTPS tarball endpoint');
    like($download,qr/perl -MJSON::PP/,'Perl-core JSON decoder');
    like($download,qr/ref\(\$release\) eq "HASH"/,'reject non-object API metadata');
    like($download,qr/defined\(\$version\) && !ref\(\$version\)/,
        'reject missing/structured version fields');
    like($download,qr/\$version =~ \/\\A\[0-9\]\+\\\.\[0-9\]\+/,
        'numeric stable-only release version validation');
    like($download,qr/developer artifact/,'internal developer trains are not public install paths');
}
done_testing;
