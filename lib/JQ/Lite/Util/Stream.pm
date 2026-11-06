package JQ::Lite::Util::Stream;

use strict;
use warnings;

# Unary builtins emit one output per input, preserving input order.
# Keep this dependency-free so standalone builtin modules can use it.
sub _stream_map {
    my ($function) = @_;
    return sub {
        my ($owner, $inputs) = @_;
        return [ map { $function->($_) } @$inputs ];
    };
}

1;
