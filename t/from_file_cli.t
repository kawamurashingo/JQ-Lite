use strict;
use warnings;
use Test::More;
use IPC::Open3;
use Symbol qw(gensym);
use File::Temp qw(tempfile);
use File::Spec;
use FindBin;

# Create a temporary filter file
my ($fh, $filter_path) = tempfile();
print {$fh} ".users[]\n";
close $fh;

# Prepare stderr handle
my $err = gensym;

# Path to the users.json test fixture (relative to test directory)
my $users_file = File::Spec->catfile($FindBin::Bin, '..', 'users.json');

# Execute jq-lite using Perl's open3 to capture stdout and stderr
my $pid = open3(my $in, my $out, $err, $^X, 'bin/jq-lite', '-c', '-f', $filter_path, $users_file);
close $in;

# Read stdout and stderr
my $stdout = do { local $/; <$out> } // '';
my $stderr = do { local $/; <$err> } // '';

# Wait for the jq-lite process to finish
waitpid($pid, 0);

# Verify output content
is(
    $stdout,
    "{\"age\":30,\"name\":\"Alice\",\"profile\":{\"active\":true,\"country\":\"US\"}}\n"
    . "{\"age\":25,\"name\":\"Bob\",\"profile\":{\"active\":false,\"country\":\"JP\"}}\n",
    'filters loaded from files emit expected JSON'
);

# Ensure there are no warnings on stderr
like($stderr, qr/^\s*\z/, 'no warnings emitted when using --from-file');

# Verify exit code is 0
my $exit_code = $? >> 8;
is($exit_code, 0, 'process exits successfully with --from-file');

# Clean up temporary filter file
unlink $filter_path;

done_testing;
