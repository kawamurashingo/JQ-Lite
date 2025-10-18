package JQ::Lite::Parser;

use strict;
use warnings;

sub parse_query {
    my ($query) = @_;

    return () unless defined $query;
    return () if $query =~ /^\s*\.\s*$/;

    my @parts = map {
        my $part = $_;
        $part =~ s/^\s+|\s+$//g;
        $part;
    } split /\|/, $query;

    @parts = map {
        if ($_ eq '.[]') {
            'flatten';
        }
        elsif ($_ =~ /^\.(.+)$/) {
            my $rest = $1;
            if ($rest =~ /^\s*[+\-*\/]/) {
                $_;
            }
            else {
                $rest;
            }
        }
        else {
            $_;
        }
    } @parts;

    return @parts;
}

1;
