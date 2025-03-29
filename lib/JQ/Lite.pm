package JQ::Lite;

use strict;
use warnings;
use JSON::PP;

our $VERSION = '0.05';

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
    
    if (!defined $query || $query =~ /^\s*\.\s*$/) {
        return ($data);
    }
    
    my @parts = split /\|/, $query;
    @parts = map {
        s/^\s+|\s+$//g;
        s/^\.//;
        $_;
    } @parts;

    my @results = ($data);
    for my $part (@parts) {
        my @next_results;

        # select(...) 対応
        if ($part =~ /^select\((.+)\)$/) {
            my $cond = $1;
            @next_results = grep { _evaluate_condition($_, $cond) } @results;
            @results = @next_results;
            next;
        }

        # length 対応
        if ($part eq 'length') {
            @next_results = map {
                ref $_ eq 'ARRAY' ? scalar(@$_) :
                ref $_ eq 'HASH'  ? scalar(keys %$_) :
                0
            } @results;
            @results = @next_results;
            next;
        }

        # keys 対応
        if ($part eq 'keys') {
            @next_results = map {
                ref $_ eq 'HASH' ? [ sort keys %$_ ] : undef
            } @results;
            @results = @next_results;
            next;
        }

        # 通常トラバース
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
        my $optional = ($step =~ s/\?$//);
        my @new_stack;

        if ($step =~ /^(.*?)\[(\d+)\]$/) {
            my ($key, $index) = ($1, $2);
            for my $item (@stack) {
                if (ref $item eq 'HASH' && exists $item->{$key}) {
                    my $val = $item->{$key};
                    if (ref $val eq 'ARRAY' && defined $val->[$index]) {
                        push @new_stack, $val->[$index];
                    }
                } elsif ($optional) {
                    next;
                }
            }
        }
        elsif ($step =~ /^(.*?)\[\]$/) {
            my $key = $1;
            for my $item (@stack) {
                if (ref $item eq 'HASH' && exists $item->{$key}) {
                    my $val = $item->{$key};
                    push @new_stack, @$val if ref $val eq 'ARRAY';
                } elsif ($optional) {
                    next;
                }
            }
        }
        else {
            for my $item (@stack) {
                if (ref $item eq 'HASH') {
                    if (exists $item->{$step}) {
                        push @new_stack, $item->{$step};
                    } elsif ($optional) {
                        next;
                    }
                } elsif (ref $item eq 'ARRAY') {
                    for my $sub (@$item) {
                        if (ref $sub eq 'HASH') {
                            if (exists $sub->{$step}) {
                                push @new_stack, $sub->{$step};
                            } elsif ($optional) {
                                next;
                            }
                        }
                    }
                } elsif ($optional) {
                    next;
                }
            }
        }

        @stack = @new_stack;
    }

    return @stack;
}

sub _evaluate_condition {
    my ($item, $cond) = @_;

    # 複数条件対応：分割して再帰評価
    if ($cond =~ /\s+and\s+/i) {
        my @conds = split /\s+and\s+/i, $cond;
        for my $c (@conds) {
            return 0 unless _evaluate_condition($item, $c);
        }
        return 1;
    }
    if ($cond =~ /\s+or\s+/i) {
        my @conds = split /\s+or\s+/i, $cond;
        for my $c (@conds) {
            return 1 if _evaluate_condition($item, $c);
        }
        return 0;
    }

    # 単一条件パターン
    if ($cond =~ /^\s*\.(.+?)\s*(==|!=|>=|<=|>|<)\s*(.+?)\s*$/) {
        my ($path, $op, $value_raw) = ($1, $2, $3);

        my $value;
        if ($value_raw =~ /^"(.*)"$/) {
            $value = $1;
        } elsif ($value_raw eq 'true') {
            $value = JSON::PP::true;
        } elsif ($value_raw eq 'false') {
            $value = JSON::PP::false;
        } elsif ($value_raw =~ /^-?\d+(\.\d+)?$/) {
            $value = 0 + $value_raw;
        } else {
            $value = $value_raw;
        }

        my @values = _traverse($item, $path);
        my $field_val = $values[0];

        return eval {
            return 0 unless defined $field_val;
            my $is_number = ($field_val =~ /^-?\d+(\.\d+)?$/) && ($value =~ /^-?\d+(\.\d+)?$/);

            if ($op eq '==') {
                return $is_number ? $field_val == $value : $field_val eq $value;
            } elsif ($op eq '!=') {
                return $is_number ? $field_val != $value : $field_val ne $value;
            } elsif ($op eq '>') {
                return $field_val > $value;
            } elsif ($op eq '>=') {
                return $field_val >= $value;
            } elsif ($op eq '<') {
                return $field_val < $value;
            } elsif ($op eq '<=') {
                return $field_val <= $value;
            }
            return 0;
        } || 0;
    }

    return 0;
}

1;
__END__

=encoding utf-8

=head1 NAME

JQ::Lite - A lightweight jq-like JSON query engine in Perl

=head1 VERSION

Version 0.05

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

Currently supported features:

=over 4

=item * Dot-based key access (e.g. .users[].name)

=item * Optional key access with ? (e.g. .nickname?)

=item * Array indexing and flattening (e.g. .users[0], .users[])

=item * Built-in functions: length, keys

=item * select(...) filters with comparison and logical operators

=back

=head1 METHODS

=head2 new

  my $jq = JQ::Lite->new;

Creates a new JQ::Lite instance.

=head2 run_query

  my @results = $jq->run_query($json_text, $query);

Runs a query string against the given JSON text.

=head1 REQUIREMENTS

This module uses only core Perl modules:

=over 4

=item * JSON::PP

=back

=head1 SEE ALSO

L<JSON::PP>

=head1 AUTHOR

Kawamura Shingo <pannakoota1@gmail.com>

=head1 LICENSE

Same as Perl itself.

=cut

