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

    # Expand jq's iterator suffix before path normalization. This preserves
    # existing dotted path traversal such as .values[] while allowing any
    # non-path filter that produces an array or object (for example keys,
    # split(","), or an array constructor) to reuse the existing .[] logic.
    my @iterator_expanded;
    for my $part (@parts) {
        my @sequence_parts = JQ::Lite::Util::_split_top_level_commas($part);
        if (@sequence_parts > 1) {
            for my $sequence_part (@sequence_parts) {
                $sequence_part =~ s/^\s+|\s+$//g;
                next if $sequence_part =~ /^\./s;
                my (undef, $comparison_operator)
                    = JQ::Lite::Util::_split_top_level_comparison($sequence_part);
                next if defined $comparison_operator;
                if ($sequence_part =~ /^(.*?)\s*\[\s*\](\?)?\s*$/s) {
                    my ($filter, $optional) = ($1, $2);
                    $filter =~ s/\s+$//;
                    my $iterator = defined $optional ? '.[]?' : '.[]';
                    # Keep a try expression's iterator suffix INSIDE
                    # its error handler. Moving try .[] into
                    # '(try . | .[])' exposes the strict iterator error
                    # outside try. This also preserves try [] and
                    # try [ ] array constructors from the prior audit.
                    $sequence_part = "($filter | $iterator)"
                        if $filter =~ /\S/ && $filter !~ /\Atry\b/
                        && $filter !~ /[=!<>]\z/;
                }
            }
            push @iterator_expanded, join(', ', @sequence_parts);
            next;
        }

        # A comparison's trailing iterator belongs to its right operand.
        my (undef, $comparison_operator)
            = JQ::Lite::Util::_split_top_level_comparison($part);
        if (!defined($comparison_operator) && $part !~ /^\s*\./s
            && $part =~ /^(.*?)\s*\[\s*\](\?)?\s*$/s) {
            my ($filter, $optional) = ($1, $2);
            $filter =~ s/\s+$//;
            # A comparison ending in [] has an empty-array operand,
            # not an iterator suffix: stripping [] leaves an operator.
            if ($filter =~ /\S/ && $filter !~ /\Atry\b/
                && $filter !~ /[=!<>]\z/) {
                push @iterator_expanded, $filter,
                    (defined $optional ? '.[]?' : '.[]');
            }
            else {
                # try .[] must retain the strict iterator inside try's
                # error handling, and try [] must remain an array
                # constructor. Both are distinct from keys[] or
                # other value-producing iterator suffixes.
                push @iterator_expanded, $part;
            }
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
            # Strict root dot-quoted fields must retain their leading
            # dot. Dropping it would turn ."a.b" into a JSON string
            # literal "a.b", or accidentally let the literal parser
            # treat that standalone string as a field path.
            elsif ($rest =~ /\A"/
                && JQ::Lite::Util::_parse_v3_literal_iterator_path($_))
            {
                $_;
            }
            # After a dotted suffix the jq grammar also allows
            # whitespace before a literal bracket:
            #   .items[0] . [1] / .items[0] . ["a.b"]
            # Retain the explicit root dot before attempting the
            # dotless-path normalization. Otherwise the ordered
            # visitor never sees the full rooted path; its literal
            # numeric/quoted index stages already handle this spacing.
            elsif ($rest =~ /\.\s+\[/
                && JQ::Lite::Util::_parse_v3_literal_iterator_path($_))
            {
                $_;
            }
            # A dotted suffix with preceding whitespace must keep
            # its leading root dot; otherwise a dotless path could
            # collide with non-path literal/try expression handling.
            elsif ($rest =~ /\s+\.(?:[A-Za-z_]|"|\[)/
                && JQ::Lite::Util::_parse_v3_literal_iterator_path($_))
            {
                $_;
            }
            # Scoped computed selectors preceded by whitespace must
            # retain the explicit leading dot, including .obj [.key].
            # This keeps dotless try [.key] and array constructors on
            # their existing expression paths.
            elsif ($rest =~ /\s+\[\s*\./
                && JQ::Lite::Util::_parse_v3_literal_iterator_path($_))
            {
                $_;
            }
            # Brackets containing only whitespace, or iterator
            # brackets separated from a field by whitespace, require
            # the leading dot. Do not reinterpret 'try [ ]' as a
            # dotless field traversal or interfere with bare [ ].
            elsif ($rest =~ /\[\s+\]|\s+\[\s*\]/
                && JQ::Lite::Util::_parse_v3_literal_iterator_path($_))
            {
                $_;
            }
            # Unlike older unspaced paths, a field followed by
            # whitespace and a quoted bracket must retain its dot,
            # or the scoped scanner cannot distinguish it from
            # 'try ["literal"]' and other non-path filters.
            elsif ($rest =~ /\s+\[\s*"/
                && JQ::Lite::Util::_parse_v3_literal_iterator_path($_))
            {
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
