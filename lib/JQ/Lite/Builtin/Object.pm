package JQ::Lite::Builtin::Object;

use strict;
use warnings;

use JQ::Lite::Util ();

sub register {
    my ($class, $register) = @_;
    my $map = \&JQ::Lite::Util::_stream_map;

    # Only hash key order and invalid-input behavior differ.
    for my $sorted (1, 0) {
        my $name = $sorted ? 'keys' : 'keys_unsorted';
        $register->($sorted ? $name : [$name, "$name()"], $map->(sub {
            my ($value) = @_;
            return [ $sorted ? sort(keys %$value) : keys %$value ]
                if ref($value) eq 'HASH';
            return [ 0 .. $#$value ] if ref($value) eq 'ARRAY';
            die 'keys(): argument must be an object or array' if $sorted;
            return undef;
        }));
    }
    for my $spec (
        [to_entries    => \&JQ::Lite::Util::_to_entries],
        [from_entries  => \&JQ::Lite::Util::_from_entries],
        [merge_objects => \&JQ::Lite::Util::_apply_merge_objects],
    ) {
        my ($name, $function) = @$spec;
        $register->([$name, "$name()"], JQ::Lite::Util::_stream_map($function));
    }
    $register->(qr/^has\((.+)\)$/, sub {
        my ($owner, $inputs, $arguments) = @_;
        my @args = JQ::Lite::Util::_parse_arguments($arguments);
        my $needle = @args ? $args[0] : undef;
        my $handler = $map->(sub {
            JQ::Lite::Util::_apply_has($_[0], $needle)
        });
        return $handler->($owner, $inputs);
    });
    # Share literal argument decoding, not containment semantics:
    # contains is jq-style, contains_subset counts duplicates, and inside
    # retains the legacy membership direction and coercion.
    $register->(qr/^(contains|contains_subset|inside)\((.+)\)$/, sub {
        my ($owner, $inputs, $name, $argument) = @_;
        my $needle = JQ::Lite::Util::_parse_literal_argument($argument);
        my $apply = $name eq 'contains'
            ? \&JQ::Lite::Util::_apply_contains
            : $name eq 'contains_subset'
                ? \&JQ::Lite::Util::_apply_contains_subset
                : \&JQ::Lite::Util::_apply_inside;
        my $handler = $map->(sub { $apply->($_[0], $needle) });
        return $handler->($owner, $inputs);
    });
}

1;
