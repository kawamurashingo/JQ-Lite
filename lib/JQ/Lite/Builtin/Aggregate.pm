package JQ::Lite::Builtin::Aggregate;

use strict;
use warnings;

use List::Util qw(sum min max);
use JQ::Lite::Util ();

sub register {
    my ($class, $register) = @_;
    my $map = \&JQ::Lite::Util::_stream_map;

    $register->(['add', 'sum'], $map->(sub {
        my ($value) = @_;
        return ref($value) eq 'ARRAY'
            ? _coerced_sum($value) : $value;
    }));
    $register->('product', $map->(sub {
        my ($value) = @_;
        return $value unless ref $value eq 'ARRAY';

        my $product = 1;
        for my $item (@$value) {
            next unless defined $item;
            $product *= 0 + $item;
        }
        return $product;
    }));
    $register->('min', _extreme(\&min));
    $register->('max', _extreme(\&max));
    $register->('avg', $map->(sub {
        my ($value) = @_;
        return ref($value) eq 'ARRAY' && @$value
            ? _coerced_sum($value) / scalar(@$value) : 0;
    }));
    $register->('median', $map->(sub {
        my ($value) = @_;
        return $value unless ref($value) eq 'ARRAY' && @$value;
        return JQ::Lite::Util::_median_value(
            JQ::Lite::Util::_extract_numeric_values($value)
        );
    }));
}

# Coerce a local copy so JSON numeric strings keep their scalar flags.
# Sum pairwise with List::Util to preserve its integer-overflow promotion
# (plain += can retain a wider integer instead of promoting to a float).
# For add/sum, the empty array still produces undef (JSON null).
sub _coerced_sum {
    my ($values) = @_;
    return undef unless @$values;

    my $total;
    for my $value (@$values) {
        # A JSON null contributes numeric zero, not an undef warning.
        # Coerce a copy to keep numeric-string input types unchanged.
        my $number = defined($value) ? 0 + $value : 0;
        $total = defined($total) ? sum($total, $number) : sum($number);
    }
    return $total;
}

sub _extreme {
    my ($function) = @_;
    return JQ::Lite::Util::_stream_map(sub {
        my ($value) = @_;
        return $value unless ref $value eq 'ARRAY';

        my @numbers = JQ::Lite::Util::_extract_numeric_values($value);
        return @numbers ? $function->(@numbers) : undef;
    });
}

1;
