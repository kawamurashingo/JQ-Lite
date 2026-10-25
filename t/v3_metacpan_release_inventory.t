use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;
use File::Temp qw(tempfile);
use JSON::PP ();
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my $tool = File::Spec->catfile($FindBin::Bin, '..', 'ci',
    'inventory-metacpan-jq-lite-releases.pl');
ok(-f $tool, 'offline MetaCPAN inventory tool is shipped');

sub saved {
    my ($bytes) = @_;
    my ($fh, $path) = tempfile(UNLINK => 1);
    binmode $fh;
    print {$fh} $bytes or die "Cannot write fixture: $!";
    close $fh or die "Cannot close fixture: $!";
    return $path;
}
sub json_file {
    return saved(JSON::PP->new->canonical->encode(shift));
}
sub invoke {
    my (@args) = @_;
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $^X, $tool, @args);
    close $in;
    my $stdout = do { local $/; <$out> };
    my $stderr = do { local $/; <$err> };
    close $out;
    close $err;
    waitpid($pid, 0);
    return { rc => $? >> 8, stdout => $stdout || '', stderr => $stderr || '' };
}
sub hit {
    my ($name, $date, $status) = @_;
    return { _source => {
        distribution => 'JQ-Lite', name => $name, author => 'SHINGO',
        date => $date, status => $status || 'backpan',
    }};
}
sub data {
    my (@hits) = @_;
    return { hits => { total => { value => scalar(@hits), relation => 'eq' },
        hits => \@hits }, _shards => { failed => 0 } };
}

my $sample = data(
    hit('JQ-Lite-2.59', '2026-09-20T10:59:07Z', 'latest'),
    hit('JQ-Lite-0.100', '2025-10-13T03:50:00Z'),
    hit('JQ-Lite-0.99', '2025-10-13T01:26:00Z'),
);
my $a = invoke('--input', json_file($sample));
is($a->{rc}, 0, 'saved full release search accepted');
like($a->{stdout}, qr/\Arelease\tversion\tmetacpan_date\tauthor\tstatus\tclassification\n/,
    'exact six-column observational TSV header');
like($a->{stdout}, qr/JQ-Lite-0\.99.*\n.*JQ-Lite-0\.100.*\n.*JQ-Lite-2\.59/s,
    'sorted by MetaCPAN observed date');
is(scalar(() = $a->{stdout} =~ /JQ-Lite-/g), 3, 'three observed archives');
unlike($a->{stdout}, qr/INTERNAL-DEVELOPER-ARTIFACT-ALERT/,
    'ordinary stable observations do not trigger alert');

my $old_total = data(hit('JQ-Lite-2.59', '2026-09-20T10:59:07'));
$old_total->{hits}{total} = 1;
is(invoke('--input', json_file($old_total))->{rc}, 0,
    'older numeric total representation accepted');

my $fields = { hits => { total => 1, hits => [
    { fields => { distribution => ['JQ-Lite'], name => ['JQ-Lite-2.59'],
        date => ['2026-09-20T10:59:07'], author => ['SHINGO'],
        status => ['latest'] } },
] }};
is(invoke('--input', json_file($fields))->{rc}, 0,
    'single-valued fields representation accepted');

my $trunc = data(hit('JQ-Lite-2.59', '2026-09-20T10:59:07Z'));
$trunc->{hits}{total}{value} = 257;
my $t = invoke('--input', json_file($trunc));
ok($t->{rc} != 0, 'partial search response rejected');
like($t->{stderr}, qr/truncated or incomplete/, 'partial-response diagnostic');
is($t->{stdout}, '', 'incomplete response produces no misleading TSV');

my $lower = data(hit('JQ-Lite-2.59', '2026-09-20T10:59:07Z'));
$lower->{hits}{total}{relation} = 'gte';
ok(invoke('--input', json_file($lower))->{rc} != 0, 'approximate total rejected');

my $dupe = data(
    hit('JQ-Lite-2.59', '2026-09-20T10:59:07Z'),
    hit('JQ-Lite-2.59', '2026-09-20T10:59:08Z'),
);
ok(invoke('--input', json_file($dupe))->{rc} != 0, 'duplicate releases rejected');

my $internal = data(
    hit('JQ-Lite-2.59', '2026-09-20T10:59:07Z'),
    hit('JQ-Lite-v3.00_03', '2026-10-25T10:01:01Z'),
);
my $d = invoke('--input', json_file($internal));
ok($d->{rc} != 0, 'internal developer release forces failure');
like($d->{stdout}, qr/JQ-Lite-v3\.00_03.*INTERNAL-DEVELOPER-ARTIFACT-ALERT/,
    'developer artifact retained in evidence TSV');
like($d->{stderr}, qr/INTERNAL-DEVELOPER-ARTIFACT-ALERT/,
    'explicit developer artifact warning');

my $unprefixed = data(hit('JQ-Lite-3.00_01', '2026-10-25T10:01:01Z'));
ok(invoke('--input', json_file($unprefixed))->{rc} != 0,
    'non-v-prefixed internal build also rejected');

my $wrong = data(hit('JQ-Lite-2.59', '2026-09-20T10:59:07Z'));
$wrong->{hits}{hits}[0]{_source}{distribution} = 'Not-JQ-Lite';
ok(invoke('--input', json_file($wrong))->{rc} != 0,
    'foreign distributions cannot contaminate release observations');

my $bad_date = data(hit('JQ-Lite-2.59', 'unknown'));
ok(invoke('--input', json_file($bad_date))->{rc} != 0,
    'missing or malformed dates rejected');
my $bad_name = data(hit('JQ-Lite-beta', '2026-09-20T10:59:07Z'));
ok(invoke('--input', json_file($bad_name))->{rc} != 0,
    'unexpected JQ-Lite release names rejected');
my $bad_author = data(hit('JQ-Lite-2.59', '2026-09-20T10:59:07Z'));
$bad_author->{hits}{hits}[0]{_source}{author} = "../bad";
ok(invoke('--input', json_file($bad_author))->{rc} != 0,
    'invalid author provenance rejected');
my $failed = data(hit('JQ-Lite-2.59', '2026-09-20T10:59:07Z'));
$failed->{_shards}{failed} = 1;
ok(invoke('--input', json_file($failed))->{rc} != 0,
    'partial failed-shards response rejected');
my $api_error = { error => 'upstream error' };
ok(invoke('--input', json_file($api_error))->{rc} != 0,
    'API error response rejected');
ok(invoke('--input', json_file(data()))->{rc} != 0,
    'zero-release response rejected');
ok(invoke('--input', saved('truncated json'))->{rc} != 0,
    'corrupt JSON rejected');
ok(invoke('--input', saved(''))->{rc} != 0,
    'empty file rejected');
ok(invoke('--input', 'does-not-exist.json')->{rc} != 0,
    'missing saved source rejected');
ok(invoke()->{rc} != 0, 'input is required');
my $help = invoke('--help');
is($help->{rc}, 0, '--help succeeds');
like($help->{stdout}, qr/does not query the network/, 'offline and non-attestation limitation documented');

done_testing;
