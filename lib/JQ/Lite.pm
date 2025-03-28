package JQ::Lite;

use strict;
use warnings;
use JSON::PP;

our $VERSION = '0.01';

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

    my @parts = split /\|/, $query;
    @parts = map {
        s/^\s+|\s+$//g;   # 前後の空白削除 (誤: \s+\$ → 正: \s+\$)
        s/^\.//;           # 先頭のドット削除
        $_;
    } @parts;

    my @results = ($data);
    for my $part (@parts) {
        my @next_results;
        for my $item (@results) {
            push @next_results, _traverse($item, $part);
        }
        @results = @next_results;
    }

    return @results;
}

sub _traverse {
    my ($data, $query) = @_;
    my @steps = split /\./, $query;
    my @stack = ($data);

    for my $step (@steps) {
        my @new_stack;
        if ($step =~ /^(.*?)\[\]$/) {
            my $key = $1;
            for my $item (@stack) {
                if (ref $item eq 'HASH' && exists $item->{$key}) {
                    my $val = $item->{$key};
                    push @new_stack, @$val if ref $val eq 'ARRAY';
                }
            }
        } else {
            for my $item (@stack) {
                if (ref $item eq 'HASH' && exists $item->{$step}) {
                    push @new_stack, $item->{$step};
                } elsif (ref $item eq 'ARRAY') {
                    for my $sub (@$item) {
                        push @new_stack, $sub->{$step} if ref $sub eq 'HASH' && exists $sub->{$step};
                    }
                }
            }
        }
        @stack = @new_stack;
    }
    return @stack;
}

1;
__END__

=encoding utf-8

=head1 NAME

JQ::Lite - A lightweight jq-like JSON query engine in Perl

=head1 SYNOPSIS

  use JQ::Lite;
  
  my $jq = JQ::Lite->new;
  my @results = $jq->run_query($json_text, '.domain[] | .name');
  
  for my $r (@results) {
      print encode_json($r), "\n";
  }

=head1 DESCRIPTION

JQ::Lite is a minimal Perl module that allows querying JSON data
using a simplified jq-like syntax.

=head1 AUTHOR

Kawamura Shingo <pannakoota1@gmail.com>

=head1 LICENSE

Same as Perl itself.

=cut

