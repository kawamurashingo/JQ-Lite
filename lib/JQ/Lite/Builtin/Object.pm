package JQ::Lite::Builtin::Object;

use strict;
use warnings;

use JQ::Lite::Util ();

sub register {
    my ($class, $register) = @_;

    # Only hash key order and invalid-input behavior differ.
    for my $sorted (1, 0) {
        my $name = $sorted ? 'keys' : 'keys_unsorted';
        $register->($sorted ? $name : [$name, "$name()"], sub {
            my ($owner, $inputs) = @_;
            return [ map {
                ref($_) eq 'HASH' ? [ $sorted ? sort(keys %{$_}) : keys %{$_} ]
                    : ref($_) eq 'ARRAY' ? [ 0 .. $#{$_} ]
                    : $sorted ? die 'keys(): argument must be an object or array' : undef
            } @{$inputs} ];
        });
    }
    for my $spec (
        [to_entries    => \&JQ::Lite::Util::_to_entries],
        [from_entries  => \&JQ::Lite::Util::_from_entries],
        [merge_objects => \&JQ::Lite::Util::_apply_merge_objects],
    ) {
        my ($name, $function) = @$spec;
        $register->([$name, "$name()"], sub {
            my ($owner, $inputs) = @_;
            return [ map { $function->($_) } @$inputs ];
        });
    }
    $register->(qr/^has\((.+)\)$/, sub {
        my ($owner, $inputs, $arguments) = @_;
        my @args = JQ::Lite::Util::_parse_arguments($arguments);
        my $needle = @args ? $args[0] : undef;
        return [ map { JQ::Lite::Util::_apply_has($_, $needle) } @{$inputs} ];
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
        return [ map { $apply->($_, $needle) } @{$inputs} ];
    });
}

1;
