use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;
use JQ::Lite;

# Release checks must run both from a Git checkout and from a clean
# MakeMaker source tarball; avoid Git-only assumptions here.
my $root = File::Spec->catdir($FindBin::Bin, '..');

sub file_content {
    my ($relative) = @_;
    my $path = File::Spec->catfile($root, split m{/}, $relative);
    open my $fh, '<', $path or die "Cannot read $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}

my $version = $JQ::Lite::VERSION;
like($version, qr/\A\d+\.\d+(?:_\d+)?\z/,
    'module has a Perl distribution version');

my $module = file_content('lib/JQ/Lite.pm');
like($module, qr/^Version\s+\Q$version\E\s*$/m,
    'POD version matches the module version');

my $changes = file_content('Changes');
like($changes, qr/\A\Q$version\E\s+\d{4}-\d{2}-\d{2}/,
    'Changes starts with the current module release version');

my $makefile = file_content('Makefile.PL');
like($makefile, qr/MIN_PERL_VERSION\s*=>\s*['"]5\.014['"]/,
    'distribution declares the existing Perl 5.14 minimum');
like($makefile, qr/VERSION_FROM\s*=>\s*['"]lib\/JQ\/Lite\.pm['"]/,
    'MakeMaker reads the version from the public module');
like($makefile, qr/EXE_FILES\s*=>\s*\['bin\/jq-lite'\]/,
    'distribution registers the documented CLI binary');

done_testing;
