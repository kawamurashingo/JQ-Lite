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
            ? sum(map { 0 + $_ } @$value) : $value;
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
            ? sum(map { 0 + $_ } @$value) / scalar(@$value) : 0;
    }));
    $register->('median', $map->(sub {
        my ($value) = @_;
        return $value unless ref($value) eq 'ARRAY' && @$value;
        return JQ::Lite::Util::_median_value(
            JQ::Lite::Util::_extract_numeric_values($value)
        );
    }));
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
