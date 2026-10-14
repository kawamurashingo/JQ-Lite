package JQ::Lite::Parser;

use strict;
use warnings;

use JQ::Lite::Util ();
use JQ::Lite::Error ();
use JQ::Lite::AST ();
use JQ::Lite::Tokenizer ();
use JSON::PP ();

sub _parse_error {
    my ($message) = @_;
    die JQ::Lite::Error::Parse->new(message => $message);
}

sub _validate_query_syntax {
    my ($query) = @_;

    return if !defined $query || $query eq '';

    my @stack;
    my $string;
    my $escape = 0;
    my %pairs = (')' => '(', ']' => '[', '}' => '{');

    for my $char (split //, $query) {
        if (defined $string) {
            if ($escape) {
                $escape = 0;
                next;
            }
            if ($char eq '\\') {
                $escape = 1;
                next;
            }
            if ($char eq $string) {
                undef $string;
            }
            next;
        }

        if ($char eq "'" || $char eq '"') {
            $string = $char;
            next;
        }

        if ($char eq '(' || $char eq '[' || $char eq '{') {
            push @stack, $char;
            next;
        }

        if (exists $pairs{$char}) {
            my $open = pop @stack;
            _parse_error('Invalid query syntax: unmatched brackets')
                if !defined $open || $open ne $pairs{$char};
        }
    }

    _parse_error('Invalid query syntax: unmatched brackets')
        if defined $string || @stack;

    my @pipeline_parts = JQ::Lite::Util::_split_top_level_pipes($query);
    _parse_error('Invalid query syntax: empty filter segment')
        if grep { !defined $_ || $_ !~ /\S/ } @pipeline_parts;

    for my $segment (@pipeline_parts) {
        my @comma_parts = JQ::Lite::Util::_split_top_level_commas($segment);
        _parse_error('Invalid query syntax: empty filter segment')
            if grep { !defined $_ || $_ !~ /\S/ } @comma_parts;
    }
}

sub parse_ast {
    my ($query) = @_;

    my @parts = parse_query($query);
    my @filters = map { JQ::Lite::AST->filter($_) } @parts;
    return JQ::Lite::AST->pipeline(@filters);
}

# Keep suffix eligibility identical for standalone filters and comma branches.
# Dotted paths own their iterators; comparisons/alternatives may have [] as
# their right operand rather than as a suffix.
sub _nonpath_iterator_suffix {
    my ($part) = @_;
    return if $part =~ /^\s*\./s;
    my (undef, $comparison_operator)
        = JQ::Lite::Util::_split_top_level_comparison($part);
    return if defined $comparison_operator;
    return unless $part =~ /^(.*?)\s*\[\s*\](\?)?\s*$/s;
    my ($filter, $optional) = ($1, $2);
    $filter =~ s/\s+$//;
    return if $filter !~ /\S/ || $filter =~ /\Atry\b/
        || $filter =~ m{(?:[=!<>]|//)\z};
    return ($filter, defined $optional ? '.[]?' : '.[]');
}

sub parse_query {
    my ($query) = @_;

    return () unless defined $query;
    return () if $query =~ /^\s*\.\s*$/;

    _validate_query_syntax($query);

    my $tokens = JQ::Lite::Tokenizer::tokenize($query);
    my @parts = map { $_->{value} } grep { $_->{type} eq 'FILTER' } @{$tokens};
    @parts = map {
        my $part = $_;
        $part =~ s/^\s+|\s+$//g;
        $part;
    } @parts;

    # Expand non-path iterator suffixes before path normalization. Comma
    # branches keep their iterator local; standalone filters append .[].
    my @iterator_expanded;
    for my $part (@parts) {
        my @sequence_parts = JQ::Lite::Util::_split_top_level_commas($part);
        if (@sequence_parts > 1) {
            for my $sequence_part (@sequence_parts) {
                $sequence_part =~ s/^\s+|\s+$//g;
                my ($filter, $iterator)
                    = _nonpath_iterator_suffix($sequence_part);
                $sequence_part = "($filter | $iterator)"
                    if defined $iterator;
            }
            push @iterator_expanded, join(', ', @sequence_parts);
            next;
        }

        my ($filter, $iterator) = _nonpath_iterator_suffix($part);
        if (defined $iterator) {
            push @iterator_expanded, $filter, $iterator;
        }
        else {
            push @iterator_expanded, $part;
        }
    }
    @parts = @iterator_expanded;

    @parts = map {
        if ($_ eq '.[]' || $_ eq '.[]?') {
            $_;
        }
        elsif ($_ =~ /^\.(.+)$/) {
            my $rest = $1;
            # Rooted ordinary field paths must stay distinct from builtin
            # names and literals, e.g. .type, .length, .empty and .null.
            if ($rest =~ /\A[A-Za-z_][A-Za-z_0-9]*(?:\.[A-Za-z_][A-Za-z_0-9]*)*\z/) {
                $_;
            }
            elsif ($rest =~ /,/ || $rest =~ /\|=/) {
                # Keep the dot on update-assignment paths, including .a |= .
                $_;
            }
            elsif ($rest =~ /^\s*\[/) {
                $_;
            }
            # Keep the leading dot for supported literal, optional and
            # whitespace-separated path stages. Each shape uses the same
            # full-path validator, so call it once after the cheap checks.
            elsif (
                (
                    $rest =~ /\A"/
                    || $rest =~ /\.\s+\[/
                    || $rest =~ /\s+\.(?:[A-Za-z_]|"|\[)/
                    || $rest =~ /\s+\[\s*\./
                    || $rest =~ /\[\s+\]|\s+\[\s*\]/
                    || $rest =~ /\s+\[\s*"/
                )
                && JQ::Lite::Util::_parse_v3_literal_iterator_path($_)
            ) {
                $_;
            }
            # Literal iterator paths with signed indices or JSON-quoted
            # field names can contain '-', '+', '/', or even '=' INSIDE
            # a quoted key.  Detect them before arithmetic heuristics and
            # decode their fields only in the scoped path evaluator.
            elsif (JQ::Lite::Util::_parse_v3_literal_iterator_path($rest))
            {
                $rest;
            }
            elsif ($rest =~ /^\s*[+\-*\/%]/
                || $rest =~ /[+\-*\/%]/
                || $rest =~ /(?:==|!=|>=|<=|>|<|\band\b|\bor\b)/i
                || $rest =~ /\b(?:floor|ceil|round|tonumber)\b/)
            {
                $_;
            }
            else {
                my $trimmed = $rest;
                $trimmed =~ s/^\s+|\s+$//g;
                if ($trimmed =~ /^"(?:[^"\\]|\\.)*"$/s) {
                    my $decoded = eval { JQ::Lite::Util::_decode_json($trimmed) };
                    return $decoded if defined $decoded && !$@;
                }
                $rest;
            }
        }
        else {
            $_;
        }
    } @parts;

    @parts = map { _lower_object_shorthand($_) } @parts;

    my @expanded;
    for my $part (@parts) {
        next unless defined $part;

        my $trimmed = $part;
        $trimmed =~ s/^\s+|\s+$//g;

        if ($trimmed =~ /^\(.*\)$/s) {
            my $inner = JQ::Lite::Util::_strip_wrapping_parens($trimmed);
            if (defined $inner && length $inner && $inner ne $trimmed) {
                my @inner_parts = parse_query($inner);
                if (@inner_parts) {
                    push @expanded, @inner_parts;
                    next;
                }
            }
        }

        push @expanded, $trimmed;
    }

    return @expanded;
}

sub _lower_object_shorthand {
    my ($text) = @_;

    return $text unless defined $text;
    return $text if index($text, '{') == -1;

    my $result = '';
    my $len    = length $text;
    my $i      = 0;
    my $string;
    my $escape = 0;

    while ($i < $len) {
        my $char = substr($text, $i, 1);

        if (defined $string) {
            $result .= $char;
            if ($escape) {
                $escape = 0;
            }
            elsif ($char eq '\\') {
                $escape = 1;
            }
            elsif ($char eq $string) {
                undef $string;
            }
            $i++;
            next;
        }

        if ($char eq "'" || $char eq '"') {
            $string = $char;
            $result .= $char;
            $i++;
            next;
        }

        if ($char eq '{') {
            my ($body, $consumed) = _extract_object_body($text, $i);
            if (defined $body) {
                my $lowered = _lower_object_constructor($body);
                $result .= '{' . $lowered . '}';
                $i += $consumed;
                next;
            }
        }

        $result .= $char;
        $i++;
    }

    return $result;
}

sub _extract_object_body {
    my ($text, $start) = @_;

    my $len     = length $text;
    my $depth   = 0;
    my $string;
    my $escape  = 0;

    for (my $i = $start; $i < $len; $i++) {
        my $char = substr($text, $i, 1);

        if (defined $string) {
            if ($escape) {
                $escape = 0;
                next;
            }

            if ($char eq '\\') {
                $escape = 1;
                next;
            }

            if ($char eq $string) {
                undef $string;
            }

            next;
        }

        if ($char eq "'" || $char eq '"') {
            $string = $char;
            next;
        }

        if ($char eq '{') {
            $depth++;
            next;
        }

        if ($char eq '}') {
            $depth--;
            if ($depth == 0) {
                my $body = substr($text, $start + 1, $i - $start - 1);
                return ($body, $i - $start + 1);
            }
            next;
        }
    }

    return (undef, 1);
}

sub _lower_object_constructor {
    my ($inner) = @_;

    return $inner unless defined $inner;

    my @parts = JQ::Lite::Util::_split_top_level_commas($inner);
    return $inner unless @parts;

    my @transformed;
    for my $part (@parts) {
        next unless defined $part;

        my $trimmed = $part;
        $trimmed =~ s/^\s+|\s+$//g;
        next if $trimmed eq '';

        my ($lhs, $rhs) = JQ::Lite::Util::_split_top_level_colon($part);

        if (defined $lhs && defined $rhs) {
            my $key = $lhs;
            $key =~ s/^\s+|\s+$//g;

            my $value = _lower_object_shorthand($rhs);
            $value =~ s/^\s+|\s+$//g;

            push @transformed, "$key: $value";
            next;
        }

        if (!defined $lhs && $trimmed =~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
            push @transformed, "$trimmed: .$trimmed";
            next;
        }

        if (defined $lhs && !defined $rhs) {
            my $key = $lhs;
            $key =~ s/^\s+|\s+$//g;
            next if $key eq '';
            push @transformed, "$key: .$key";
            next;
        }

        my $lowered = _lower_object_shorthand($trimmed);
        $lowered =~ s/^\s+|\s+$//g;
        push @transformed, $lowered if length $lowered;
    }

    return join(', ', @transformed);
}

1;
