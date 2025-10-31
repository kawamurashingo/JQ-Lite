use strict;
use warnings;
use Test::More;

# Skip this test on Perl 5.20–5.26 because of known compatibility issues
if ($] >= 5.020000 && $] < 5.027000) {
    plan skip_all => "Skipped on Perl 5.20–5.26 due to known incompatibility";
}

use IPC::Open3;
use Symbol qw(gensym);
use File::Temp qw(tempfile tempdir);
use File::Spec;
use Cwd qw(abs_path);
use FindBin;

# Create a temporary directory for test files
my $tmpdir = tempdir(CLEANUP => 1);

# Create a temporary YAML file
my ($fh_yaml, $yaml_path) = tempfile(DIR => $tmpdir, SUFFIX => '.yaml', UNLINK => 1);
print {$fh_yaml} <<'YAML';
users:
  - name: Alice
    age: 30
  - name: Bob
    age: 25
YAML
close $fh_yaml;

# Determine the path to the jq-lite executable
my $exe = abs_path(File::Spec->catfile($FindBin::Bin, '..', 'bin', 'jq-lite'));

# Test reading YAML from a file
my $err = gensym;
my $pid = open3(my $in, my $out, $err,
    $^X, $exe, '.users[].name', $yaml_path);
close
