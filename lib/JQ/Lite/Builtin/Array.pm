package JQ::Lite::Builtin::Array;

use strict;
use warnings;

use JQ::Lite::Util ();
use Scalar::Util qw(looks_like_number);

sub register {
    my ($class, $register) = @_;
    my $map = \&JQ::Lite::Util::_stream_map;

    for my $spec (['first', 0], ['last', -1]) {
        my ($name, $index) = @$spec;
        $register->($name, $map->(sub {
            my ($value) = @_;
            return ref($value) eq 'ARRAY' && @$value ? $value->[$index] : undef;
        }));
    }
    $register->('rest', $map->(sub {
        my ($value) = @_;
        return $value unless ref($value) eq 'ARRAY';
        my @tail = @$value;
        shift @tail;
        return \@tail;
    }));
    $register->('reverse', $map->(sub {
        my ($value) = @_;
        return ref($value) eq 'ARRAY' ? [ reverse @$value ]
            : JQ::Lite::Util::_is_string_scalar($value)
                ? scalar(reverse $value) : $value;
    }));
    for my $spec (['flatten', 1], ['flatten_all', undef]) {
        my ($name, $depth) = @$spec;
        $register->([$name, "$name()"],
            $map->(sub { JQ::Lite::Util::_flatten_depth($_[0], $depth) }));
    }
    $register->(['compact', 'compact()'], $map->(sub {
        my ($value) = @_;
        return ref($value) eq 'ARRAY'
            ? [ grep { defined $_ } @$value ] : $value;
    }));
    $register->(qr/^flatten_depth(?:\((.*)\))?$/, sub {
        my ($owner, $inputs, $arguments) = @_;
        my @args = JQ::Lite::Util::_parse_arguments($arguments);
        my $depth = @args ? $args[0] : 1;
        $depth = 1 unless defined($depth) && looks_like_number($depth);
        $depth = int($depth);
        $depth = 0 if $depth < 0;
        my $handler = $map->(sub {
            JQ::Lite::Util::_flatten_depth($_[0], $depth)
        });
        return $handler->($owner, $inputs);
    });
    $register->(qr/^nth\((\d+)\)$/, sub {
        my ($owner, $inputs, $index) = @_;
        my $handler = $map->(sub {
            ref($_[0]) eq 'ARRAY' && $index < @{$_[0]}
                ? $_[0]->[$index] : undef
        });
        return $handler->($owner, $inputs);
    });
}

1;
