use strict;
use warnings;
use Test::More;
use IPC::Open3;
use Symbol qw(gensym);
use File::Temp qw(tempfile tempdir);
use File::Spec;
use Cwd qw(abs_path);
use FindBin;
use CPAN::Meta::YAML;         # コア同梱
use JSON::PP qw(encode_json); # コア同梱

my $tmpdir = tempdir(CLEANUP => 1);
my $exe = abs_path(File::Spec->catfile($FindBin::Bin, '..', 'bin', 'jq-lite'));
ok(-x $exe, "jq-lite found at $exe") or plan skip_all => "jq-lite not found/executable";

sub yaml_to_json {
    my ($yaml_text) = @_;
    my $docs = CPAN::Meta::YAML->read_string($yaml_text);
    # 旧Perlでも常に ARRAY リファレンス（YAMLドキュメント列）になる想定
    die "YAML parse failed" unless $docs && ref($docs) eq 'ARRAY' && @$docs;
    my $data = $docs->[0];            # 最初のドキュメント（Hash/Array）
    return encode_json($data);        # JSON::PP は Hash/Array リファレンスを期待
}

# --- Case 1: YAMLファイル → (テスト側でJSON化) → jq-lite にファイルで渡す ---
my $yaml1 = <<'YAML';
users:
  - name: Alice
    age: 30
  - name: Bob
    age: 25
YAML
my $json1 = yaml_to_json($yaml1);

my ($fh_json, $json_path) = tempfile(DIR => $tmpdir, SUFFIX => '.json', UNLINK => 1);
print {$fh_json} $json1;
close $fh_json;

my $err1 = gensym;
my $pid1 = open3(my $in1, my $out1, $err1,
    $^X, $exe, '.users[].name', $json_path);
close $in1;

my $stdout1 = do { local $/; <$out1> } // '';
my $stderr1 = do { local $/; <$err1> } // '';
waitpid($pid1, 0);
my $exit1 = $? >> 8;

is($stdout1, qq("Alice"\n"Bob"\n), 'names extracted from JSON converted from YAML (file input)');
like($stderr1, qr/^\s*\z/, 'no warnings emitted (file input)');
is($exit1, 0, 'exit 0 (file input)');

# --- Case 2: YAML (テスト側でJSON化) を STDIN で渡す ---
my $yaml2 = <<'YAML';
users:
  - name: Carol
  - name: Dave
YAML
my $json2 = yaml_to_json($yaml2);

my $err2 = gensym;
my $pid2 = open3(my $in2, my $out2, $err2,
    $^X, $exe, '.users | length');  # STDINからJSONを供給
print {$in2} $json2;
close $in2;

my $stdout2 = do { local $/; <$out2> } // '';
my $stderr2 = do { local $/; <$err2> } // '';
waitpid($pid2, 0);
my $exit2 = $? >> 8;

is($stdout2, "2\n", 'count from JSON piped via STDIN');
like($stderr2, qr/^\s*\z/, 'no warnings emitted (stdin)');
is($exit2, 0, 'exit 0 (stdin)');

done_testing;
