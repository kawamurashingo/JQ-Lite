#!/usr/bin/env perl

use strict;
use warnings;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use JQ::Lite;

# クエリをコマンドライン引数から取得
my $query = shift or die "Usage: $0 '.query'\n";

# 標準入力からJSONを読み込む
my $json_text = do { local $/; <STDIN> };

# JQ::Lite を使ってクエリを実行
my $jq = JQ::Lite->new;
my @results = $jq->run_query($json_text, $query);

# JSONエンコーダー（整形用）
my $pp = JSON::PP->new->utf8->canonical->pretty;

# 出力
for my $r (@results) {
    if (!defined $r) {
        print "null\n";
    } elsif ($query =~ /^\s*\.\s*$/) {
        # `.` のときは pretty print
        print $pp->encode($r);
    } elsif (ref $r eq '') {
        print "$r\n";
    } else {
        print encode_json($r), "\n";
    }
}
