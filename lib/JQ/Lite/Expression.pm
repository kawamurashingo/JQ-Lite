package JQ::Lite::Expression;

use strict;
use warnings;

use JSON::PP ();    # lightweight decoder for string literals
use Scalar::Util qw(looks_like_number);
use B qw(SVp_IOK SVp_NOK SVp_POK);

# Internal constant used to signal that parsing failed and callers should
# silently fall back to other heuristics.
my $PARSE_ERROR = "__JQ_LITE_EXPR_PARSE_ERROR__";

sub evaluate {
    my (%opts) = @_;

    my $expr          = $opts{expr};
    my $context       = $opts{context};
    my $resolve_path  = $opts{resolve_path}  || sub { return undef };
    my $coerce_number = $opts{coerce_number} || \&_default_coerce_number;
    my $builtins      = $opts{builtins}      || {};

    return (0, undef) unless defined $expr;

    my $tokens = _tokenize($expr) or return (0, undef);
    my $state  = {
        tokens => $tokens,
        pos    => 0,
    };

    my $ast = eval { _parse_expression($state, 0) };
    if ($@) {
        return (0, undef) if $@ =~ /\Q$PARSE_ERROR\E/;
        die $@;
    }

    my $next = _peek($state);
    return (0, undef) unless $next->{type} eq 'EOF';

    my $value = eval {
        _eval_node(
            $ast,
            {
                context       => $context,
                resolve_path  => $resolve_path,
                coerce_number => $coerce_number,
                builtins      => $builtins,
            }
        );
    };

    if ($@) {
        return (0, undef) if $@ =~ /\Q$PARSE_ERROR\E/;
        die $@;
    }

    return (1, $value);
}

sub _tokenize {
    my ($expr) = @_;

    my @tokens;
    my $len = length $expr;
    my $i   = 0;

    while ($i < $len) {
        my $char = substr($expr, $i, 1);

        if ($char =~ /\s/) {
            $i++;
            next;
        }

        my $comparison = substr($expr, $i, 2);
        if ($comparison =~ /^(?:==|!=|>=|<=)$/) {
            push @tokens, { type => 'OP', value => $comparison };
            $i += 2;
            next;
        }

        if ($char =~ /[+\-*\/%<>]/) {
            push @tokens, { type => 'OP', value => $char };
            $i++;
            next;
        }

        if ($char eq '(') {
            push @tokens, { type => 'LPAREN', value => '(' };
            $i++;
            next;
        }

        if ($char eq ')') {
            push @tokens, { type => 'RPAREN', value => ')' };
            $i++;
            next;
        }

        if ($char eq ',') {
            push @tokens, { type => 'COMMA', value => ',' };
            $i++;
            next;
        }

        if ($char eq '.') {
            my ($consumed, $path) = _consume_path($expr, $i);
            return unless defined $consumed;
            $i += $consumed;
            if (!defined $path || $path eq '') {
                push @tokens, { type => 'CURRENT' };
            }
            else {
                push @tokens, { type => 'PATH', value => $path };
            }
            next;
        }

        if ($char eq '"') {
            my ($consumed, $value) = _consume_json_string($expr, $i);
            return unless defined $consumed;
            $i += $consumed;
            push @tokens, { type => 'STRING', value => $value };
            next;
        }

        if ($char eq "'") {
            my ($consumed, $value) = _consume_single_string($expr, $i);
            return unless defined $consumed;
            $i += $consumed;
            push @tokens, { type => 'STRING', value => $value };
            next;
        }

        if (substr($expr, $i) =~ /\G(-?\d+(?:\.\d+)?)/) {
            my $match = $1;
            my $len_match = length $match;
            push @tokens, { type => 'NUMBER', value => 0 + $match };
            $i += $len_match;
            next;
        }

        if (substr($expr, $i) =~ /\G([A-Za-z_][A-Za-z0-9_]*)/) {
            my $ident = $1;
            push @tokens, { type => 'IDENT', value => $ident };
            $i += length $ident;
            next;
        }

        return;
    }

    push @tokens, { type => 'EOF', value => undef };
    return \@tokens;
}

sub _consume_path {
    my ($expr, $start) = @_;

    my $len   = length $expr;
    my $i     = $start + 1;    # skip the leading '.'
    my $depth = 0;
    my $path  = '';

    while ($i < $len) {
        my $char = substr($expr, $i, 1);

        last if $depth == 0 && $char =~ /[+\-*\/%(),\s]/;

        if ($char eq '[') {
            $depth++;
        }
        elsif ($char eq ']') {
            $depth-- if $depth;
        }

        $path .= $char;
        $i++;
    }

    $path =~ s/\s+$//;

    return ($i - $start, $path);
}

sub _consume_json_string {
    my ($expr, $start) = @_;

    my $i   = $start;
    my $len = length $expr;
    my $end = $i + 1;
    my $escaped = 0;

    while ($end < $len) {
        my $char = substr($expr, $end, 1);
        if ($escaped) {
            $escaped = 0;
            $end++;
            next;
        }

        if ($char eq '\\') {
            $escaped = 1;
            $end++;
            next;
        }

        if ($char eq '"') {
            my $text = substr($expr, $i, $end - $i + 1);
            my $decoded = eval { JSON::PP::decode_json($text) };
            return unless defined $decoded && !$@;
            return ($end - $i + 1, $decoded);
        }

        $end++;
    }

    return;
}

sub _consume_single_string {
    my ($expr, $start) = @_;

    my $i   = $start + 1;
    my $len = length $expr;
    my $value = '';
    my $escaped = 0;

    while ($i < $len) {
        my $char = substr($expr, $i, 1);

        if ($escaped) {
            $value .= $char;
            $escaped = 0;
            $i++;
            next;
        }

        if ($char eq '\\') {
            $escaped = 1;
            $i++;
            next;
        }

        if ($char eq "'") {
            return ($i - $start + 1, $value);
        }

        $value .= $char;
        $i++;
    }

    return;
}

my %LBP = (
    '==' => 5,
    '!=' => 5,
    '>=' => 5,
    '<=' => 5,
    '>'  => 5,
    '<'  => 5,
    '+' => 10,
    '-' => 10,
    '*' => 20,
    '/' => 20,
    '%' => 20,
);

sub _parse_expression {
    my ($state, $min_bp) = @_;

    my $token = _next($state) or _parse_error();
    my $lhs   = _nud($state, $token);

    while (1) {
        my $next = _peek($state);
        last unless $next;

        if ($next->{type} eq 'LPAREN' && _is_callable($lhs)) {
            _next($state);    # consume '('
            my @args;
            if (_peek($state)->{type} ne 'RPAREN') {
                push @args, _parse_expression($state, 0);
                while (_peek($state)->{type} eq 'COMMA') {
                    _next($state);    # consume ','
                    push @args, _parse_expression($state, 0);
                }
            }
            my $closing = _next($state);
            _parse_error() unless $closing->{type} eq 'RPAREN';
            $lhs = {
                type   => 'CALL',
                name   => $lhs->{name},
                args   => \@args,
            };
            next;
        }

        last unless $next->{type} eq 'OP';
        my $op  = $next->{value};
        my $lbp = $LBP{$op} || 0;
        last if $lbp < $min_bp;

        _next($state);    # consume operator
        my $rhs = _parse_expression($state, $lbp + 1);
        $lhs = {
            type  => 'BINARY',
            op    => $op,
            left  => $lhs,
            right => $rhs,
        };
    }

    return $lhs;
}

sub _nud {
    my ($state, $token) = @_;

    if ($token->{type} eq 'NUMBER') {
        return { type => 'NUMBER', value => $token->{value} };
    }

    if ($token->{type} eq 'STRING') {
        return { type => 'STRING', value => $token->{value} };
    }

    if ($token->{type} eq 'CURRENT') {
        return { type => 'CURRENT' };
    }

    if ($token->{type} eq 'PATH') {
        return { type => 'PATH', value => $token->{value} };
    }

    if ($token->{type} eq 'IDENT') {
        if ($token->{value} eq 'true') {
            return { type => 'BOOLEAN', value => JSON::PP::true };
        }
        if ($token->{value} eq 'false') {
            return { type => 'BOOLEAN', value => JSON::PP::false };
        }
        if ($token->{value} eq 'null') {
            return { type => 'NULL', value => undef };
        }
        if ($token->{value} eq 'length') {
            return {
                type => 'CALL',
                name => 'length',
                args => [ { type => 'CURRENT' } ],
            };
        }
        return { type => 'IDENT', name => $token->{value} };
    }

    if ($token->{type} eq 'OP' && $token->{value} eq '-') {
        my $rhs = _parse_expression($state, $LBP{'-'} + 1);
        return { type => 'UNARY', op => '-', expr => $rhs };
    }

    if ($token->{type} eq 'LPAREN') {
        my $expr = _parse_expression($state, 0);
        my $closing = _next($state);
        _parse_error() unless $closing->{type} eq 'RPAREN';
        return $expr;
    }

    _parse_error();
}

sub _is_callable {
    my ($node) = @_;
    return $node->{type} eq 'IDENT';
}

sub _peek {
    my ($state) = @_;
    return $state->{tokens}[ $state->{pos} ] // { type => 'EOF', value => undef };
}

sub _next {
    my ($state) = @_;
    return $state->{tokens}[ $state->{pos}++ ];
}

sub _parse_error {
    die $PARSE_ERROR;
}

sub _eval_node {
    my ($node, $opts) = @_;

    if ($node->{type} eq 'NUMBER') {
        return $node->{value};
    }

    if ($node->{type} eq 'STRING') {
        return $node->{value};
    }

    if ($node->{type} eq 'BOOLEAN') {
        return $node->{value};
    }

    if ($node->{type} eq 'NULL') {
        return undef;
    }

    if ($node->{type} eq 'CURRENT') {
        return $opts->{context};
    }

    if ($node->{type} eq 'PATH') {
        return $opts->{resolve_path}->($opts->{context}, $node->{value});
    }

    if ($node->{type} eq 'UNARY') {
        my $value = _eval_node($node->{expr}, $opts);
        my $num   = $opts->{coerce_number}->($value, 'unary - operand');
        return -$num;
    }

    if ($node->{type} eq 'BINARY') {
        my $left_value  = _eval_node($node->{left},  $opts);
        my $right_value = _eval_node($node->{right}, $opts);

        if ($node->{op} eq '==' || $node->{op} eq '!=') {
            my $equal = _compare_values($left_value, $right_value) == 0;
            $equal = !$equal if $node->{op} eq '!=';
            return $equal ? JSON::PP::true : JSON::PP::false;
        }

        if ($node->{op} =~ /^(?:>=|<=|>|<)$/) {
            my $comparison = _compare_values($left_value, $right_value);
            my $result = $node->{op} eq '>=' ? $comparison >= 0
                       : $node->{op} eq '<=' ? $comparison <= 0
                       : $node->{op} eq '>'  ? $comparison >  0
                       :                       $comparison <  0;
            return $result ? JSON::PP::true : JSON::PP::false;
        }

        my $left_num  = $opts->{coerce_number}->($left_value,  'left operand');
        my $right_num = $opts->{coerce_number}->($right_value, 'right operand');

        if ($node->{op} eq '+') {
            return $left_num + $right_num;
        }
        if ($node->{op} eq '-') {
            return $left_num - $right_num;
        }
        if ($node->{op} eq '*') {
            return $left_num * $right_num;
        }
        if ($node->{op} eq '/') {
            die 'Division by zero' if $right_num == 0;
            return $left_num / $right_num;
        }
        if ($node->{op} eq '%') {
            die 'Modulo by zero' if $right_num == 0;
            return $left_num % $right_num;
        }
    }

    if ($node->{type} eq 'CALL') {
        my $name = $node->{name};
        my $func = $opts->{builtins}{$name};
        _parse_error() unless $func;
        my @args = map { _eval_node($_, $opts) } @{ $node->{args} };
        return $func->(@args);
    }

    _parse_error();
}

sub compare_values {
    my ($left, $right, $operator) = @_;
    my $comparison = _compare_values($left, $right);
    my $result = $operator eq '==' ? $comparison == 0
               : $operator eq '!=' ? $comparison != 0
               : $operator eq '>=' ? $comparison >= 0
               : $operator eq '<=' ? $comparison <= 0
               : $operator eq '>'  ? $comparison >  0
               : $operator eq '<'  ? $comparison <  0
               : 0;
    return $result ? JSON::PP::true : JSON::PP::false;
}

sub _compare_values {
    my ($left, $right) = @_;

    my $left_type  = _value_type($left);
    my $right_type = _value_type($right);
    return $left_type <=> $right_type if $left_type != $right_type;

    return 0 if $left_type == 0;
    return (!!$left) <=> (!!$right) if $left_type == 1;
    return $left <=> $right if $left_type == 2;
    return "$left" cmp "$right" if $left_type == 3;

    if ($left_type == 4) {
        my $limit = @$left < @$right ? @$left : @$right;
        if ($limit) {
            for my $i (0 .. $limit - 1) {
                my $comparison = _compare_values($left->[$i], $right->[$i]);
                return $comparison if $comparison;
            }
        }
        return @$left <=> @$right;
    }

    if ($left_type == 5) {
        my @left_keys  = sort keys %$left;
        my @right_keys = sort keys %$right;
        my $keys_comparison = _compare_values(\@left_keys, \@right_keys);
        return $keys_comparison if $keys_comparison;
        for my $key (@left_keys) {
            my $comparison = _compare_values($left->{$key}, $right->{$key});
            return $comparison if $comparison;
        }
        return 0;
    }

    return 0;
}

sub _value_type {
    my ($value) = @_;
    return 0 unless defined $value;                    # null
    return 1 if JSON::PP::is_bool($value);             # false, true
    return 4 if ref $value eq 'ARRAY';
    return 5 if ref $value eq 'HASH';
    return 6 if ref $value;

    my $flags = B::svref_2object(\$value)->FLAGS;
    return 2 if ($flags & (SVp_IOK | SVp_NOK)) && !($flags & SVp_POK);
    return 3;
}

sub _default_coerce_number {
    my ($value, $label) = @_;

    $label ||= 'value';

    die "$label must be a number" unless defined $value;

    if (ref($value) eq 'JSON::PP::Boolean') {
        return $value ? 1 : 0;
    }

    die "$label must be a number" if ref $value;
    die "$label must be a number" unless looks_like_number($value);

    return 0 + $value;
}

1;
