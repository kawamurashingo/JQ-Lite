#!/usr/bin/env perl

use strict;
use warnings;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use JQ::Lite;

my $query = shift or die "Usage: $0 '.query'\n";
my $json_text = do { local $/; <STDIN> };

my $jq = JQ::Lite->new;
my @results = $jq->run_query($json_text, $query);

my $pp = JSON::PP->new->utf8->canonical->pretty;

for my $r (@results) {
    if (!defined $r) {
        print "null\n";
    } else {
        print $pp->encode($r);  # ← すべて pretty print
    }
}
