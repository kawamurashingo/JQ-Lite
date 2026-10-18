package JQ::Lite::Builtin::Type;

use strict;
use warnings;

use JQ::Lite::Value ();
use JQ::Lite::Util ();

sub register {
    my ($class, $register) = @_;
    my $map = \&JQ::Lite::Util::_stream_map;

    $register->('length', $map->(sub {
        my ($value) = @_;
        return !defined($value) ? 0
            : ref($value) eq 'ARRAY' ? scalar(@$value)
            : ref($value) eq 'HASH' ? scalar(keys %$value)
            : (!ref($value) || ref($value) eq 'JSON::PP::Boolean')
                ? length("$value") : 0;
    }));

    $register->(['type', 'type()'],
        $map->(\&JQ::Lite::Value::type_of));

    for my $spec (['arrays', 'ARRAY'], ['objects', 'HASH'], ['scalars', '']) {
        my ($name, $type) = @$spec;
        $register->([$name, "$name()"], sub {
            my ($owner, $inputs) = @_;
            return [ grep {
                $type ? ref($_) eq $type
                    : !defined($_) || !ref($_) || ref($_) eq 'JSON::PP::Boolean'
            } @$inputs ];
        });
    }
    $register->('values', $map->(sub {
        my ($value) = @_;
        return ref($value) eq 'HASH' ? [ values %$value ] : $value;
    }));
    $register->('count', $map->(sub {
        my ($value) = @_;
        return ref($value) eq 'ARRAY' ? scalar(@$value)
            : defined($value) ? 1 : 0;
    }));
    $register->('empty', sub { return [] });
}

1;
