use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;
use File::Temp qw(tempfile);
use JSON::PP ();
use Digest::SHA qw(sha256_hex);
use IO::Compress::Zip qw($ZipError);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my $tool = File::Spec->catfile($FindBin::Bin, '..', 'ci',
    'verify-actions-exposure-snapshot.pl');
# The test may also be run standalone beside a downloaded verifier.
$tool = File::Spec->catfile($FindBin::Bin, 'verify-actions-exposure-snapshot.pl')
    unless -f $tool;
ok(-f $tool, 'offline verifier is present');

my $json = JSON::PP->new->canonical;
sub record {
    my ($id, $name, $expired) = @_;
    return { id => $id, name => $name,
        expired => $expired ? JSON::PP::true : JSON::PP::false,
        created_at => '2026-10-25T13:55:39Z',
        workflow_run => { id => 40207717858 } };
}
sub sample {
    my @rows = (record(5,'v3-unreleased-source-40',0),
        record(6,'other-workflow',0));
    return {
        'artifact-page-1.json' => $json->encode({total_count=>2,artifacts=>\@rows}),
        'developer-artifacts.tsv' => "5\tv3-unreleased-source-40\tfalse\t2026-10-25T13:55:39Z\t40207717858\n",
        'provenance.txt' => join("\n",
            'captured_utc=2026-10-25T15:36:15Z',
            'repository=kawamurashingo/JQ-Lite',
            'event=pull_request',
            'checkout_sha=fc21de3feafd34c13be6138cf1da6893ba28c8a4',
            'workflow_run=https://github.com/kawamurashingo/JQ-Lite/actions/runs/40207717858',
            'scope=read-only GitHub Actions artifact API metadata; NOT a publication ledger',
            'missing=deleted/expired entries, archive bytes, downloads, original PAUSE chronology',
            ''),
    };
}
sub snapshot_file {
    my ($members,$opts) = @_;
    my %included = %$members;
    unless ($opts && $opts->{omit_manifest}) {
        $included{'manifest-sha256.txt'} = join '',
            map { sha256_hex($included{$_}) . "  $_\n" }
            sort keys %included;
    }
    my ($fh,$path) = tempfile(UNLINK=>1);
    binmode $fh;
    my $zip = IO::Compress::Zip->new($fh, Name=>'artifact-page-1.json')
        or die "Cannot create ZIP: $ZipError";
    $zip->print($included{'artifact-page-1.json'});
    for my $name (sort grep { $_ ne 'artifact-page-1.json' } keys %included) {
        $zip->newStream(Name=>$name) or die "Cannot append ZIP entry: $ZipError";
        $zip->print($included{$name});
    }
    $zip->close or die "Cannot finalize ZIP: $ZipError";
    close $fh or die "Cannot close fixture: $!";
    open my $read,'<',$path or die $!;
    binmode $read;
    my $bytes=do {local $/; <$read>};
    close $read;
    return ($path,sha256_hex($bytes));
}
sub invoke {
    my ($path,$sha) = @_;
    my $err=gensym;
    my $pid=open3(my $in,my $out,$err,$^X,$tool,
        '--input',$path,'--expected-sha256',$sha);
    close $in;
    my $stdout=do {local $/; <$out>} || '';
    my $stderr=do {local $/; <$err>} || '';
    close $out; close $err;
    waitpid($pid,0);
    return {rc=>$? >> 8,stdout=>$stdout,stderr=>$stderr};
}
sub run_sample {
    my ($members,$opts) = @_;
    my ($path,$sha)=snapshot_file($members,$opts);
    return invoke($path,$sha);
}

my $good=run_sample(sample());
is($good->{rc},0,'complete one-page metadata snapshot passes');
like($good->{stdout},qr/2 unique artifacts; 1 matching source names; 1 not-expired/, 'summary states bounded metadata counts');
like($good->{stdout},qr/NOT|no historic downloads/i,'passing snapshot does not authorize publication');

my ($path,$sha)=snapshot_file(sample());
my $wrong=invoke($path,'0'x64);
ok($wrong->{rc} != 0,'expected ZIP digest mismatch fails');
like($wrong->{stderr},qr/ZIP SHA-256 differs/,'ZIP digest failure is explicit');

my $incorrect=sample();
$incorrect->{'developer-artifacts.tsv'}=~s/false/true/;
my $wrong_tsv=run_sample($incorrect);
ok($wrong_tsv->{rc} != 0,'TSV that differs from saved JSON fails');
like($wrong_tsv->{stderr},qr/TSV does not match/, 'JSON-to-TSV mismatch diagnosed');

my $partial=sample();
$partial->{'artifact-page-1.json'} = $json->encode({total_count=>3,artifacts=>[
    record(5,'v3-unreleased-source-40',0),record(6,'other-workflow',0)]});
my $bad_partial=run_sample($partial);
ok($bad_partial->{rc} != 0,'incomplete API page cannot pass');
like($bad_partial->{stderr},qr/incomplete/, 'truncation clearly indicated');

my $duplicate=sample();
$duplicate->{'artifact-page-1.json'}=$json->encode({total_count=>2,artifacts=>[
    record(5,'v3-unreleased-source-40',0),record(5,'other-workflow',0)]});
my $bad_duplicate=run_sample($duplicate);
ok($bad_duplicate->{rc} != 0,'duplicate artifact ID rejected');
like($bad_duplicate->{stderr},qr/duplicate row/, 'duplicate ID error explicit');

my $extra=sample();
$extra->{'JQ-Lite-3.00_03.tar.gz'}='NOT A TARBALL';
my $bad_extra=run_sample($extra);
ok($bad_extra->{rc} != 0,'developer archive member prohibited');
like($bad_extra->{stderr},qr/Unsafe\/extra snapshot member/, 'foreign member rejected without extraction');

my $missing=run_sample(sample(),{omit_manifest=>1});
ok($missing->{rc} != 0,'missing hash manifest cannot pass');
like($missing->{stderr},qr/Missing required snapshot member/, 'missing manifest rejected');

my $two=sample();
$two->{'artifact-page-1.json'}=$json->encode({total_count=>2,artifacts=>[
    record(5,'v3-unreleased-source-40',0)]});
$two->{'artifact-page-2.json'}=$json->encode({total_count=>2,artifacts=>[
    record(6,'other-workflow',0)]});
my $two_result=run_sample($two);
is($two_result->{rc},0,'two-page response accepted with matching complete count');
like($two_result->{stdout},qr/2 API pages/, 'two-page audit counted correctly');

my $gap=sample();
$gap->{'artifact-page-3.json'}=$json->encode({total_count=>2,artifacts=>[]});
my $gap_result=run_sample($gap);
ok($gap_result->{rc} != 0,'missing intermediate page rejected');
like($gap_result->{stderr},qr/page numbering/, 'nonconsecutive pages diagnosed');

my $invalid=sample();
$invalid->{'artifact-page-1.json'}=$json->encode({total_count=>2,artifacts=>[
    { %{record(5,'v3-unreleased-source-40',0)}, expired=>0 },
    record(6,'other-workflow',0)]});
my $invalid_bool=run_sample($invalid);
ok($invalid_bool->{rc} != 0,'non-boolean expired field rejected');
like($invalid_bool->{stderr},qr/expired boolean/, 'malformed Boolean diagnosed');

my $not_reviewed=invoke($path,$sha);
like($not_reviewed->{stdout},qr/PAUSE history, version approval or publication asserted/, 'success explicitly limits conclusions');

done_testing;
