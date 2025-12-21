use strict;
use warnings;
use Test::More;
use IPC::Open3 qw(open3);
use Symbol qw(gensym);
use File::Temp qw(tempdir);
use File::Spec;
use FindBin;

# ----------------------------
# Locate jq-lite executable reliably (AUR / make test friendly)
# ----------------------------
sub _is_file {
    my ($p) = @_;
    return defined($p) && -f $p;
}

sub _find_jq_lite {
    # 1) explicit override
    return $ENV{JQ_LITE} if _is_file($ENV{JQ_LITE});

    # 2) Prefer build output (ExtUtils::MakeMaker / Module::Build)
    my @candidates = (
        File::Spec->catfile($FindBin::Bin, '..', 'blib', 'script', 'jq-lite'),
        File::Spec->catfile($FindBin::Bin, '..', 'blib', 'bin',    'jq-lite'),
        File::Spec->catfile($FindBin::Bin, '..', 'script',         'jq-lite'),
        File::Spec->catfile($FindBin::Bin, '..', 'bin',            'jq-lite'),
    );

    for my $p (@candidates) {
        return $p if _is_file($p);
    }

    # 3) Fall back to PATH
    return 'jq-lite';
}

my $JQ = _find_jq_lite();

# We'll execute via perl to avoid shebang/exec-bit issues in build envs
my @JQ_CMD = ($^X, $JQ);
