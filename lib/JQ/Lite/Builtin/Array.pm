package JQ::Lite::Builtin::Array;

use strict;
use warnings;

use JQ::Lite::Util ();
use Scalar::Util qw(looks_like_number);

sub register {
    my ($class, $register) = @_;

    for my $spec (['first', 0], ['last', -1]) {
        my ($name, $index) = @$spec;
        $register->($name, sub { my ($o, $i) = @_; return [ map { ref($_) eq 'ARRAY' && @$_ ? $_->[$index] : undef } @$i ] });
    }
    $register->('rest', sub { my ($o, $i) = @_; return [ map { ref($_) eq 'ARRAY' ? (@{$_} ? [ @{$_}[1 .. $#{$_}] ] : []) : $_ } @{$i} ] });
    $register->('reverse', sub { my ($o, $i) = @_; return [ map { ref($_) eq 'ARRAY' ? [ reverse @{$_} ] : JQ::Lite::Util::_is_string_scalar($_) ? scalar(reverse $_) : $_ } @{$i} ] });
    for my $spec (['flatten', 1], ['flatten_all', undef]) {
        my ($name, $depth) = @$spec;
        $register->([$name, "$name()"], sub {
            my ($owner, $inputs) = @_;
            return [ map { JQ::Lite::Util::_flatten_depth($_, $depth) } @$inputs ];
        });
    }
    $register->(['compact', 'compact()'], sub {
        my ($owner, $inputs) = @_;
        return [ map { ref($_) eq 'ARRAY' ? [ grep { defined $_ } @{$_} ] : $_ } @{$inputs} ];
    });
    $register->(qr/^flatten_depth(?:\((.*)\))?$/, sub {
        my ($owner, $inputs, $arguments) = @_;
        my @args = JQ::Lite::Util::_parse_arguments($arguments);
        my $depth = @args ? $args[0] : 1;
        $depth = 1 unless defined($depth) && looks_like_number($depth);
        $depth = int($depth);
        $depth = 0 if $depth < 0;
        return [ map { JQ::Lite::Util::_flatten_depth($_, $depth) } @{$inputs} ];
    });
    $register->(qr/^nth\((\d+)\)$/, sub {
        my ($owner, $inputs, $index) = @_;
        return [ map { ref($_) eq 'ARRAY' && $index < @{$_} ? $_->[$index] : undef } @{$inputs} ];
    });
}

1;
