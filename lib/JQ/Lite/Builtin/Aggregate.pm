package JQ::Lite::Builtin::Aggregate;

use strict;
use warnings;

use List::Util qw(min max);
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

# Consume each value in input order without a temporary numeric map list.
# Coerce a local copy so numeric-looking JSON strings keep their flags.
# For add/sum, the empty array must still produce undef (JSON null).
sub _coerced_sum {
    my ($values) = @_;
    return undef unless @$values;

    my $total = 0;
    for my $value (@$values) {
        my $number = $value;
        $total += 0 + $number;
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
