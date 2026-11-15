use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;

# MANIFEST determines what goes into an ExtUtils::MakeMaker source archive.
# A normal prove run finds every checked-out test and would otherwise miss
# registrations omitted from a release tarball.
my $root = File::Spec->catdir($FindBin::Bin, '..');
chdir $root or die "Cannot enter distribution root: $!";

open my $manifest, '<', 'MANIFEST' or die "Cannot read MANIFEST: $!";
my %listed;
my @duplicates;
while (my $line = <$manifest>) {
    next if $line =~ /^\s*(?:#|$)/;
    my ($path) = split /\s+/, $line;
    push @duplicates, $path if $listed{$path}++;
}
close $manifest;

is_deeply(\@duplicates, [], 'MANIFEST has no duplicate paths');

my @missing_files = sort grep { !-f $_ } keys %listed;
is_deeply(\@missing_files, [], 'all MANIFEST entries exist in the source tree');

if (-e '.git') {
    # Use the repository's own packaging exclusions rather than maintaining
    # a competing list of allowed omissions in the test.
    open my $skip, '<', 'MANIFEST.SKIP' or die "Cannot read MANIFEST.SKIP: $!";
    my @skip_patterns;
    while (my $line = <$skip>) {
        $line =~ s/\r?\n\z//;
        next if $line =~ /^\s*(?:#|$)/;
        push @skip_patterns, qr/$line/;
    }
    close $skip;

    open my $tracked, '-|', 'git', 'ls-files', '-z'
        or die "Cannot list Git-tracked distribution files: $!";
    my @unlisted;
    {
        local $/ = "\0";
        while (my $path = <$tracked>) {
            $path =~ s/\0\z//;
            next if grep { $path =~ $_ } @skip_patterns;
            push @unlisted, $path unless $listed{$path};
        }
    }
    close $tracked or die 'git ls-files failed';

    is_deeply([sort @unlisted], [],
        'every non-skipped Git-tracked file is registered in MANIFEST');
}
else {
    pass('Git-tracked coverage check is not required in a release tarball');
}

done_testing;
