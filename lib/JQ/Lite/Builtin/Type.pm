package JQ::Lite::Builtin::Type;

use strict;
use warnings;

use JQ::Lite::Value ();

sub register {
    my ($class, $register) = @_;

    $register->('length', sub {
        my ($owner, $inputs) = @_;
        return [ map {
            !defined($_) ? 0
                : ref($_) eq 'ARRAY' ? scalar(@{$_})
                : ref($_) eq 'HASH' ? scalar(keys %{$_})
                : (!ref($_) || ref($_) eq 'JSON::PP::Boolean') ? length("$_")
                : 0
        } @{$inputs} ];
    });

    $register->(['type', 'type()'], sub {
        my ($owner, $inputs) = @_;
        return [ map { JQ::Lite::Value::type_of($_) } @{$inputs} ];
    });

    $register->(['arrays', 'arrays()'], sub {
        my ($owner, $inputs) = @_;
        return [ grep { ref($_) eq 'ARRAY' } @{$inputs} ];
    });
    $register->(['objects', 'objects()'], sub {
        my ($owner, $inputs) = @_;
        return [ grep { ref($_) eq 'HASH' } @{$inputs} ];
    });
    $register->(['scalars', 'scalars()'], sub {
        my ($owner, $inputs) = @_;
        return [ grep { !defined($_) || !ref($_) || ref($_) eq 'JSON::PP::Boolean' } @{$inputs} ];
    });
    $register->('values', sub {
        my ($owner, $inputs) = @_;
        return [ map { ref($_) eq 'HASH' ? [ values %{$_} ] : $_ } @{$inputs} ];
    });
    $register->('count', sub {
        my ($owner, $inputs) = @_;
        return [ map { ref($_) eq 'ARRAY' ? scalar(@{$_}) : defined($_) ? 1 : 0 } @{$inputs} ];
    });
    $register->('empty', sub { return [] });
}

1;
