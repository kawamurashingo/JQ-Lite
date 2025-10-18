use strict;
use warnings;
use Test::More;
use IPC::Open3;
use Symbol qw(gensym);
use File::Temp qw(tempfile);

my ($fh, $filter_path) = tempfile();
print {$fh} ".users[]\n";
close $fh;

my $err = gensym;
my $pid = open3(my $in, my $out, $err, $^X, 'bin/jq-lite', '-c', '-f', $filter_path, 'users.json');
close $in;

my $stdout = do { local $/; <$out> } // '';
my $stderr = do { local $/; <$err> } // '';

waitpid($pid, 0);

is($stdout, "{\"age\":30,\"name\":\"Alice\",\"profile\":{\"active\":true,\"country\":\"US\"}}\n{\"age\":25,\"name\":\"Bob\",\"profile\":{\"active\":false,\"country\":\"JP\"}}\n", 'filters loaded from files emit expected JSON');
like($stderr, qr/^\s*\z/, 'no warnings emitted when using --from-file');

my $exit_code = $? >> 8;
is($exit_code, 0, 'process exits successfully with --from-file');

unlink $filter_path;

done_testing;
