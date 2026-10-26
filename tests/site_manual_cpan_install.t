use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;
use File::Temp qw(tempdir tempfile);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my $page=File::Spec->catfile($FindBin::Bin,'..','index-en.html');
open my $fh,'<',$page or die "Cannot open $page: $!";
my $html=do {local $/; <$fh>};
close $fh or die "Cannot close $page: $!";

my ($snippet)=$html =~ m{<h3>Manual install \(stable CPAN tarball\)</h3>.*?<pre><code>(.*?)</code></pre>}s;
ok(defined $snippet,'manual stable CPAN example exists');
if(!defined $snippet){done_testing;exit 0;}
$snippet =~ s/&amp;/&/g;

unlike($snippet,qr{http://}i,'no plaintext HTTP remains in example');
unlike($html,qr{http://fastapi\.metacpan\.org|http://cpan\.metacpan\.org}i,
    'HTML never advertises old HTTP URLs');
like($snippet,qr/^set -euo pipefail/m,'Bash fails closed on metadata fetch errors');
my $https_flags=()=$snippet =~ /--proto '=https' --proto-redir '=https'/g;
is($https_flags,2,'both curl requests restrict redirects to HTTPS');
like($snippet,qr/perl -MJSON::PP/,'uses core JSON::PP');
like($snippet,qr/ref\(\$release\) eq "HASH"/,'rejects malformed API response');
like($snippet,qr/\$version =~ \/\\A\[0-9\]\+\\\.\[0-9\]\+/,
    'numeric stable-only version checked before URL');
like($snippet,qr{https://cpan\.metacpan\.org/authors/id/S/SH/SHINGO/JQ-Lite-\$ver\.tar\.gz},
    'download URL remains on expected CPAN author path');
like($html,qr/internal developer builds are\s+not public install targets/,
    'documentation explicitly excludes internal developer builds');

my $tmp=tempdir(CLEANUP=>1);
my ($f,$script)=tempfile(DIR=>$tmp,SUFFIX=>'.sh',UNLINK=>0);
print {$f} $snippet or die "Cannot write shell example: $!";
close $f or die $!;
is(system('bash','-n',$script),0,'rendered example has valid Bash syntax');

# Never access the network: substitute a fake curl and execute only
# the download calls, excluding tar extraction and PATH mutation.
my ($download_only)=$snippet =~ /\A(.*?)^tar xzf /ms;
ok(defined $download_only,'download-only portion isolated for offline testing');
if(defined $download_only) {
    my ($sf,$script_only)=tempfile(DIR=>$tmp,SUFFIX=>'.sh',UNLINK=>0);
    print {$sf} $download_only or die $!;
    close $sf;
    my $curl=File::Spec->catfile($tmp,'curl');
    open my $mf,'>',$curl or die $!;
    print {$mf} <<'MOCK';
#!/bin/sh
case "$*" in
  *https://fastapi.metacpan.org/v1/release/JQ-Lite*)
    if [ "$MOCK_FAIL" = "yes" ]; then exit 22; fi
    printf '%s\n' "$MOCK_RELEASE"
    ;;
  *https://cpan.metacpan.org/authors/id/S/SH/SHINGO/*)
    printf '%s\n' "$*" >> "$MOCK_LOG"
    ;;
  *) exit 78 ;;
esac
MOCK
    close $mf;
    chmod 0755,$curl or die $!;
    my $log=File::Spec->catfile($tmp,'curl-downloads.log');

    sub run_fixture {
        my ($script_path,$mock_dir,$log_path,$release,$fail)=@_;
        unlink $log_path if -e $log_path;
        local $ENV{PATH}=$mock_dir.':'.$ENV{PATH};
        local $ENV{MOCK_LOG}=$log_path;
        local $ENV{MOCK_RELEASE}=$release;
        local $ENV{MOCK_FAIL}=$fail ? 'yes' : '';
        my $err=gensym;
        my $pid=open3(my $in,my $out,$err,'bash',$script_path);
        close $in;
        my $stdout=do {local $/; <$out>};
        my $stderr=do {local $/; <$err>};
        close $out; close $err;
        waitpid($pid,0);
        my $logs='';
        if(-e $log_path){
            open my $lf,'<',$log_path or die $!;
            $logs=do {local $/; <$lf>};
            close $lf;
        }
        return {rc=>($? >> 8),logs=>$logs,stderr=>$stderr||''};
    }
    my $good=run_fixture($script_only,$tmp,$log,'{"version":"2.59"}',0);
    is($good->{rc},0,'valid stable release metadata succeeds');
    like($good->{logs},qr/JQ-Lite-2\.59\.tar\.gz/,'correct stable tarball URL generated');
    for my $value ('{"version":"3.00_03"}','{"version":"../../evil"}',
        '{"version":{"number":"2.59"}}','{}','not-json') {
        my $bad=run_fixture($script_only,$tmp,$log,$value,0);
        ok($bad->{rc} != 0,"reject untrusted release metadata: $value");
        is($bad->{logs},'', 'invalid metadata cannot fetch a tarball');
    }
    my $failed=run_fixture($script_only,$tmp,$log,'',1);
    ok($failed->{rc} != 0,'failed metadata HTTP request halts pipeline');
    is($failed->{logs},'', 'failed metadata fetch never downloads tarball');
}
done_testing;
