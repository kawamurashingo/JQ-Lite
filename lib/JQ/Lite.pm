package JQ::Lite;

use strict;
use warnings;

use JSON::PP;

use JQ::Lite::Filters;
use JQ::Lite::Parser;
use JQ::Lite::Util ();

our $VERSION = '1.02';

sub new {
    my ($class, %opts) = @_;
    my $self = {
        raw => $opts{raw} || 0,
    };
    return bless $self, $class;
}

sub run_query {
    my ($self, $json_text, $query) = @_;
    my $data = decode_json($json_text);

    return ($data) if !defined $query || $query =~ /^\s*\.\s*$/;

    my @parts = JQ::Lite::Parser::parse_query($query);

    my @results = ($data);
    for my $part (@parts) {
        my @next_results;

        if (JQ::Lite::Filters::apply($self, $part, \@results, \@next_results)) {
            @results = @next_results;
            next;
        }

        for my $item (@results) {
            push @next_results, JQ::Lite::Util::_traverse($item, $part);
        }
        @results = @next_results;
    }

    return @results;
}

1;
