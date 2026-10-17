package JQ::Lite::Builtin::String;

use strict;
use warnings;

use JQ::Lite::Util ();

sub register {
    my ($class, $register) = @_;

    for my $spec (
        [titlecase => \&JQ::Lite::Util::_apply_case_transform, 'titlecase'],
        [upper     => \&JQ::Lite::Util::_apply_case_transform, 'upper'],
        [lower     => \&JQ::Lite::Util::_apply_case_transform, 'lower'],
        [ascii_upcase   => \&JQ::Lite::Util::_apply_ascii_case_transform, 'upper'],
        [ascii_downcase => \&JQ::Lite::Util::_apply_ascii_case_transform, 'lower'],
    ) {
        my ($name, $function, $mode) = @{$spec};
        $register->([$name, "$name()"],
            _map(sub { $function->($_[0], $mode) }));
    }
    $register->(['trim', 'trim()'], _map(\&JQ::Lite::Util::_apply_trim));
    $register->(['explode', 'explode()'], _map(\&JQ::Lite::Util::_apply_explode));
    $register->(['implode', 'implode()'], _map(\&JQ::Lite::Util::_apply_implode));
    $register->(['tostring', 'tostring()'], _map(\&JQ::Lite::Util::_apply_tostring));
    $register->(['tojson', 'tojson()'], _map(\&JQ::Lite::Util::_apply_tojson));
    $register->(['fromjson', 'fromjson()'], _map(\&JQ::Lite::Util::_apply_fromjson));
    $register->(qr/^ltrimstr\((.+)\)$/, _string_argument(\&JQ::Lite::Util::_apply_trimstr, 'left'));
    $register->(qr/^rtrimstr\((.+)\)$/, _string_argument(\&JQ::Lite::Util::_apply_trimstr, 'right'));
    $register->(qr/^startswith\((.+)\)$/, _string_argument(\&JQ::Lite::Util::_apply_string_predicate, 'start'));
    $register->(qr/^endswith\((.+)\)$/, _string_argument(\&JQ::Lite::Util::_apply_string_predicate, 'end'));
    $register->(qr/^split\((.+)\)$/, _string_argument(\&JQ::Lite::Util::_apply_split, undef));
    $register->(qr/^substr(?:\((.*)\))?$/, sub {
        my ($owner, $inputs, $arguments) = @_;
        my @args = JQ::Lite::Util::_parse_arguments($arguments);
        return [ map { JQ::Lite::Util::_apply_substr($_, @args) } @{$inputs} ];
    });
    $register->(qr/^replace\((.+)\)$/, sub {
        my ($owner, $inputs, $arguments) = @_;
        my ($search, $replacement) = JQ::Lite::Util::_parse_arguments($arguments);
        $search = '' unless defined $search;
        $replacement = '' unless defined $replacement;
        return [ map { JQ::Lite::Util::_apply_replace($_, $search, $replacement) } @{$inputs} ];
    });
}

# Only the existing trim/predicate implementation and direction vary.
sub _string_argument {
    my ($function, $mode) = @_;
    return sub {
        my ($owner, $inputs, $argument) = @_;
        my $needle = JQ::Lite::Util::_parse_string_argument($argument);
        return [ map { $function->($_, $needle, $mode) } @{$inputs} ];
    };
}

sub _map {
    my ($function) = @_;
    return sub {
        my ($owner, $inputs) = @_;
        return [ map { $function->($_) } @{$inputs} ];
    };
}

1;
