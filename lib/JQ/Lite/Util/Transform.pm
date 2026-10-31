package JQ::Lite::Util;

use strict;
use warnings;

use JSON::PP ();
use JQ::Lite::Value ();
use List::Util qw(sum min max);
use Scalar::Util qw(looks_like_number);
use MIME::Base64 qw(encode_base64 decode_base64);
use Encode qw(encode is_utf8);
use B ();

our ($JSON_DECODER, $FROMJSON_DECODER, $TOJSON_ENCODER);

sub _apply_tostring {
    my ($value) = @_;

    if (!defined $value) {
        return 'null';
    }

    if (JSON::PP::is_bool($value)) {
        return $value ? 'true' : 'false';
    }

    if (!ref $value) {
        return "$value";
    }

    return _apply_tojson($value);
}

sub _apply_tojson {
    my ($value) = @_;

    return Encode::decode('UTF-8', $TOJSON_ENCODER->encode($value));
}

sub _apply_fromjson {
    my ($value) = @_;

    return undef if !defined $value;

    if (ref $value eq 'ARRAY') {
        return [ map { _apply_fromjson($_) } @$value ];
    }

    return $value if ref $value;

    my $text = "$value";
    $text = encode('UTF-8', $text) if is_utf8($text, 1);
    my $decoded = eval { $FROMJSON_DECODER->decode($text) };

    return $@ ? $value : $decoded;
}

sub _apply_numeric_function {
    my ($value, $callback) = @_;

    return undef if !defined $value;

    if (JSON::PP::is_bool($value)) {
        my $numeric = $value ? 1 : 0;
        return $callback->($numeric);
    }

    if (!ref $value) {
        return looks_like_number($value) ? $callback->($value) : $value;
    }

    if (ref $value eq 'ARRAY') {
        return [ map { _apply_numeric_function($_, $callback) } @$value ];
    }

    return $value;
}

sub _apply_clamp {
    my ($value, $min, $max) = @_;

    return _apply_numeric_function($value, sub {
        return _clamp_scalar($_[0], $min, $max);
    });
}

sub _normalize_numeric_bound {
    my ($value) = @_;

    return undef if !defined $value;

    if (JSON::PP::is_bool($value)) {
        return $value ? 1 : 0;
    }

    return looks_like_number($value) ? 0 + $value : undef;
}

sub _clamp_scalar {
    my ($value, $min, $max) = @_;

    return $value unless looks_like_number($value);

    my $numeric = 0 + $value;
    $numeric = $min if defined $min && $numeric < $min;
    $numeric = $max if defined $max && $numeric > $max;

    return $numeric;
}

sub _apply_to_number {
    my ($value) = @_;

    return _apply_numeric_function($value, sub { 0 + $_[0] });
}

sub _extract_numeric_values {
    my ($values) = @_;

    return () unless ref $values eq 'ARRAY';

    # Filter and coerce in one traversal; the result list is still needed
    # by callers, but the intermediate grep list is not.
    my @numbers;
    for my $value (@$values) {
        next unless defined $value
            && (JSON::PP::is_bool($value)
                || (!ref $value && looks_like_number($value)));
        push @numbers, JSON::PP::is_bool($value)
            ? ($value ? 1 : 0) : 0 + $value;
    }
    return @numbers;
}

# Share only the numeric median; callers retain their own input policies.
sub _median_value {
    return undef unless @_;
    my @numbers = sort { $a <=> $b } @_;
    my $middle = int(@numbers / 2);
    return @numbers % 2 ? $numbers[$middle]
        : ($numbers[$middle - 1] + $numbers[$middle]) / 2;
}

sub _normalize_percentile {
    my ($value) = @_;

    return undef if !defined $value;

    if (JSON::PP::is_bool($value)) {
        $value = $value ? 1 : 0;
    }

    return undef if ref $value;
    return undef unless looks_like_number($value);

    my $fraction = 0 + $value;

    return undef if $fraction != $fraction;             # NaN
    return undef if ($fraction * 0) != ($fraction * 0); # infinity

    if ($fraction > 1) {
        $fraction /= 100 if $fraction <= 100;
    }

    $fraction = 0 if $fraction < 0;
    $fraction = 1 if $fraction > 1;

    return $fraction;
}

sub _percentile_value {
    my ($numbers, $fraction) = @_;

    return undef unless ref $numbers eq 'ARRAY';
    return undef unless @$numbers;

    $fraction = 0 if $fraction < 0;
    $fraction = 1 if $fraction > 1;

    return $numbers->[0] if @$numbers == 1;

    my $rank        = $fraction * (@$numbers - 1);
    my $lower_index = int($rank);
    my $upper_index = $lower_index == @$numbers - 1 ? $lower_index : $lower_index + 1;
    my $weight      = $rank - $lower_index;

    return $numbers->[$lower_index] if $upper_index == $lower_index;

    my $lower = $numbers->[$lower_index];
    my $upper = $numbers->[$upper_index];

    return $lower + ($upper - $lower) * $weight;
}

sub _apply_merge_objects {
    my ($value) = @_;

    if (ref $value eq 'ARRAY') {
        my %merged;

        for my $element (@$value) {
            next unless ref $element eq 'HASH';
            # Only copy fields from the next object, not the full result.
            for my $key (keys %$element) {
                $merged{$key} = $element->{$key};
            }
        }

        return \%merged;
    }

    if (ref $value eq 'HASH') {
        return { %$value };
    }

    return $value;
}

sub _to_entries {
    my ($value) = @_;

    if (ref $value eq 'HASH') {
        return [ map { { key => $_, value => $value->{$_} } } sort keys %$value ];
    }

    if (ref $value eq 'ARRAY') {
        my @entries;
        for (my $index = 0; $index < @$value; $index++) {
            push @entries, { key => $index, value => $value->[$index] };
        }
        return \@entries;
    }

    return $value;
}

# Preserve scalar type flags; numeric-looking JSON strings are strings.
sub _scalar_flags {
    my ($value) = @_;
    return 0 if !defined $value || ref $value;
    return B::svref_2object(\$value)->FLAGS;
}

sub _is_string_scalar {
    return (_scalar_flags($_[0]) & B::SVp_POK()) ? 1 : 0;
}

sub _from_entries {
    my ($value) = @_;

    die 'from_entries(): argument must be an array' unless ref $value eq 'ARRAY';

    my %result;
    my @numeric_keys;
    my $saw_non_numeric_key = 0;
    for my $entry (@$value) {
        my ($key, $val);

        if (ref $entry eq 'HASH') {
            die 'from_entries(): entry is missing key'    if !exists $entry->{key};
            die 'from_entries(): entry is missing value'  if !exists $entry->{value};
            ($key, $val) = ($entry->{key}, $entry->{value});
        }
        elsif (ref $entry eq 'ARRAY') {
            die 'from_entries(): entry must have a key and value' if @$entry < 2;
            ($key, $val) = @{$entry}[0, 1];
        }
        else {
            die 'from_entries(): entry must be an object or [key, value] tuple';
        }

        if (!defined $key || ref $key) {
            die 'from_entries(): key must be a string';
        }

        $key = "$key";

        die 'from_entries(): key must be a string' if !_is_string_scalar($key);

        $result{$key} = $val;

        if ($key =~ /^(?:0|[1-9]\d*)$/) {
            push @numeric_keys, 0 + $key;
        }
        else {
            $saw_non_numeric_key = 1;
        }
    }

    if (@numeric_keys && !$saw_non_numeric_key) {
        my %seen;
        my $max_index = -1;
        for my $index (@numeric_keys) {
            next if $seen{$index}++;
            $max_index = $index if $index > $max_index;
        }

        if ($max_index + 1 == scalar(keys %result) && $max_index + 1 == scalar(@numeric_keys)) {
            my @array;
            for (my $index = 0; $index <= $max_index; $index++) {
                push @array, $result{$index};
            }
            return \@array;
        }
    }

    return \%result;
}

sub _apply_with_entries {
    my ($self, $value, $filter) = @_;

    return $value unless ref $value eq 'HASH' || ref $value eq 'ARRAY';

    my $entries = _to_entries($value);
    return $value unless ref $entries eq 'ARRAY';

    my @transformed;
    for my $entry (@$entries) {
        my @results = $self->run_query(_encode_json($entry), $filter);
        for my $result (@results) {
            my $normalized = _normalize_entry($result);
            push @transformed, $normalized if $normalized;
        }
    }

    return _from_entries(\@transformed);
}

sub _apply_map_values {
    my ($self, $value, $filter) = @_;

    return $value if !defined $value;

    if (ref $value eq 'HASH') {
        my %result;
        for my $key (keys %$value) {
            my $original = $value->{$key};
            my @outputs  = $self->run_query(_encode_json($original), $filter);
            next unless @outputs;
            $result{$key} = $outputs[0];
        }
        return \%result;
    }

    if (ref $value eq 'ARRAY') {
        my @result;
        for my $original (@$value) {
            if (ref $original eq 'HASH' || ref $original eq 'ARRAY') {
                push @result, _apply_map_values($self, $original, $filter);
                next;
            }

            my @outputs = $self->run_query(_encode_json($original), $filter);
            push @result, $outputs[0] if @outputs;
        }
        return \@result;
    }

    return $value;
}

sub _apply_walk {
    my ($self, $value, $filter) = @_;

    if (ref $value eq 'HASH') {
        my %copy;
        for my $key (keys %$value) {
            $copy{$key} = _apply_walk($self, $value->{$key}, $filter);
        }
        $value = \%copy;
    }
    elsif (ref $value eq 'ARRAY') {
        my @copy = map { _apply_walk($self, $_, $filter) } @$value;
        $value   = \@copy;
    }

    my @results = $self->run_query(_encode_json($value), $filter);
    return @results ? $results[0] : undef;
}

sub _apply_recurse {
    my ($self, $value, $filter) = @_;

    # Plain recurse walks only containers and stops at scalar leaves, just
    # like jq's optional child iterator.  An *explicit* .[] child filter is
    # different: jq raises an error when it tries to iterate a scalar/null.
    # Keep this scoped to recurse rather than changing legacy .[] filters.
    my $explicit_iterator = defined($filter)
        && _strip_wrapping_parens($filter) =~ /\A\s*\.\[\]\s*(?:\||\z)/;

    my @stack   = ($value);
    my @outputs;

    while (@stack) {
        my $current = pop @stack;
        push @outputs, $current;

        if ($explicit_iterator
            && ref($current) ne 'ARRAY' && ref($current) ne 'HASH')
        {
            my $type = !defined($current) ? 'null'
                : JSON::PP::is_bool($current) ? 'boolean'
                : _is_string_scalar($current) ? 'string'
                : 'number';
            die JQ::Lite::Error::Evaluation->new(
                message => 'Cannot iterate over ' . $type
                    . ' (' . _encode_json($current) . ')'
            );
        }

        next unless defined $current;

        my @children;
        if (defined $filter) {
            my $json = _encode_json($current);
            @children = $self->run_query($json, $filter);
        }
        elsif (ref $current eq 'ARRAY') {
            @children = @$current;
        }
        elsif (ref $current eq 'HASH') {
            @children = map { $current->{$_} } sort keys %$current;
        }

        next unless @children;

        # Push in reverse for depth-first, left-to-right traversal.
        push @stack, reverse @children;
    }

    return @outputs;
}

sub _apply_delpaths {
    my ($self, $value, $filter) = @_;

    return $value if !defined $value;
    return $value if !ref $value || JSON::PP::is_bool($value);

    $filter //= '';
    $filter =~ s/^\s+|\s+$//g;
    return $value if $filter eq '';

    my @paths;
    my $decoded_paths = eval { _decode_json($filter) };
    if (!$@ && defined $decoded_paths) {
        if (ref $decoded_paths eq 'ARRAY') {
            if (grep { ref($_) ne 'ARRAY' } @$decoded_paths) {
                die 'delpaths(): paths must be an array of path arrays';
            }

            push @paths, map { _validate_path_array($_, 'delpaths') } @$decoded_paths;
        }
        else {
            die 'delpaths(): paths must be an array of path arrays';
        }
    }

    if (!@paths) {
        my @outputs = $self->run_query(_encode_json($value), $filter);
        for my $output (@outputs) {
            next unless defined $output;

            if (ref $output eq 'ARRAY') {
                if (grep { ref($_) ne 'ARRAY' } @$output) {
                    die 'delpaths(): paths must be an array of path arrays';
                }

                push @paths, map { _validate_path_array($_, 'delpaths') } @$output;
            }
            else {
                die 'delpaths(): paths must be an array of path arrays';
            }
        }
    }

    return $value unless @paths;

    if (grep { ref $_ eq 'ARRAY' && !@$_ } @paths) {
        return undef;
    }

    my $clone = _deep_clone($value);
    my @ordered = _sort_paths_for_deletion(@paths);

    for my $path (@ordered) {
        next unless ref $path eq 'ARRAY';
        next unless @$path;
        # The callee already makes a private segment list before popping.
        # Pass the original validated path, avoiding a second array copy.
        _delete_path_inplace($clone, $path);
    }

    return $clone;
}

sub _sort_paths_for_deletion {
    my (@paths) = @_;

    # Sorting compares each path repeatedly. Cache the depth and parent
    # signature once per path, preserving the existing comparison rules.
    my @decorated = map {
        {
            path   => $_,
            depth  => scalar(@$_),
            prefix => _path_prefix_key($_),
        }
    } @paths;

    # A sort comparator must yield its value as the final expression:
    # explicit "return" here can leave sort with an undefined comparator
    # result on older Perls, emitting warnings even when tests pass.
    return map { $_->{path} } sort {
        ($b->{depth} <=> $a->{depth})
            || ($a->{prefix} cmp $b->{prefix})
            || _compare_path_segments(
                $b->{path}[-1], $a->{path}[-1]
            );
    } @decorated;
}

sub _path_prefix_key {
    my ($path) = @_;

    return '' if !$path || @$path < 2;

    # Keep the original delimiter and segment encoding without building
    # a temporary array of parent segments or their encoded counterparts.
    my $prefix = _path_segment_key($path->[0]);
    for (my $i = 1; $i < $#$path; $i++) {
        $prefix .= "\x1f" . _path_segment_key($path->[$i]);
    }
    return $prefix;
}

sub _path_segment_key {
    my ($segment) = @_;

    return 'undef' if !defined $segment;

    if (JSON::PP::is_bool($segment)) {
        return $segment ? 'bool:true' : 'bool:false';
    }

    return ref $segment ? 'ref:' . ref($segment) : "scalar:$segment";
}

sub _compare_path_segments {
    my ($left, $right) = @_;

    if (_is_numeric_segment($left) && _is_numeric_segment($right)) {
        return _numeric_segment_value($left) <=> _numeric_segment_value($right);
    }

    return _path_segment_key($left) cmp _path_segment_key($right);
}

sub _numeric_segment_value {
    my ($segment) = @_;

    if (JSON::PP::is_bool($segment)) {
        return $segment ? 1 : 0;
    }

    return int($segment);
}

sub _deep_clone {
    my ($value) = @_;

    return $value if !defined $value;
    return $value if !ref $value || JSON::PP::is_bool($value);

    my $json = _encode_json($value);
    return _decode_json($json);
}

sub _delete_path_inplace {
    my ($value, $path) = @_;

    return unless ref $value eq 'HASH' || ref $value eq 'ARRAY';
    return unless ref $path eq 'ARRAY';
    return unless @$path;

    # Walk all but the final segment without cloning the path array.
    # Only the target container is modified; the path stays read-only.
    my $last   = $path->[-1];
    my $cursor = $value;
    for my $index (0 .. $#$path - 1) {
        my $segment = $path->[$index];
        if (ref $cursor eq 'HASH') {
            my $key = _coerce_hash_key($segment);
            return unless defined $key;
            return unless exists $cursor->{$key};
            $cursor = $cursor->{$key};
            next;
        }

        if (ref $cursor eq 'ARRAY') {
            my $index = _normalize_array_index($segment, scalar @$cursor);
            return if !defined $index;
            $cursor = $cursor->[$index];
            next;
        }

        return;
    }

    if (ref $cursor eq 'HASH') {
        my $key = _coerce_hash_key($last);
        return unless defined $key;
        delete $cursor->{$key};
        return;
    }

    if (ref $cursor eq 'ARRAY') {
        my $index = _normalize_array_index($last, scalar @$cursor);
        return if !defined $index;
        splice @$cursor, $index, 1;
    }
}

sub _normalize_array_index {
    my ($value, $length) = @_;

    return if !defined $value;

    if (JSON::PP::is_bool($value)) {
        $value = $value ? 1 : 0;
    }

    return if ref $value;

    return if $value !~ /^-?\d+$/;

    my $index = int($value);
    $index += $length if $index < 0;

    return if $index < 0 || $index >= $length;

    return $index;
}

sub _normalize_entry {
    my ($entry) = @_;

    if (ref $entry eq 'HASH') {
        return unless exists $entry->{key};
        return { key => $entry->{key}, value => $entry->{value} };
    }

    if (ref $entry eq 'ARRAY') {
        return unless @$entry >= 2;
        return { key => $entry->[0], value => $entry->[1] };
    }

    return;
}

sub _apply_coalesce {
    my ($self, $value, $lhs_expr, $rhs_expr) = @_;

    my @lhs_values = _evaluate_coalesce_operand($self, $value, $lhs_expr);
    for my $candidate (@lhs_values) {
        # jq's alternative operator discards only null and JSON false.
        # In particular, numeric zero, empty strings and empty containers
        # remain valid left-hand results.
        next unless defined $candidate;
        next if JSON::PP::is_bool($candidate) && !$candidate;
        return $candidate;
    }

    my @rhs_values = _evaluate_coalesce_operand($self, $value, $rhs_expr);
    for my $candidate (@rhs_values) {
        return $candidate if defined $candidate;
    }

    return undef;
}

sub _evaluate_coalesce_operand {
    my ($self, $context, $expr) = @_;

    return () unless defined $expr;

    my $copy = $expr;
    $copy =~ s/^\s+|\s+$//g;
    return () if $copy eq '';

    while ($copy =~ /^\((.*)\)$/) {
        $copy = $1;
        $copy =~ s/^\s+|\s+$//g;
    }

    if ($copy =~ /^(.*?)\s*\/\/\s*(.+)$/) {
        my ($lhs, $rhs) = ($1, $2);
        my $result = _apply_coalesce($self, $context, $lhs, $rhs);
        return ($result);
    }

    if ($copy eq '.') {
        return ($context);
    }

    my $decoded = eval { _decode_json($copy) };
    if (!$@) {
        return ($decoded);
    }

    if ($copy =~ /^'(.*)'$/) {
        my $text = $1;
        $text =~ s/\\'/'/g;
        return ($text);
    }

    return () unless defined $context;

    my $path = $copy;
    $path =~ s/^\.//;

    return _traverse($context, $path);
}

# Parse the subset of jq paths consisting of literal unquoted field names,
# JSON-string bracket keys (or ."key"), signed numeric indices (with
# optional [N]? in scoped ordered paths), []/[]?,
# and simple computed selectors [.key] / [.parent."quoted.key"] /
# [.parent["quoted.key"]], optionally ?. Quoted names stay literal.
# Signed numeric array indices are accepted inside selector paths, e.g.
# [.keys[0]] or [.cfg["names"][-1]].
# Paths with an iterator, an audited computed selector, an optional
# literal numeric index/field, a strict negative literal numeric
# index, or a strict JSON-quoted field are accepted. Strict positive
# literal numeric stages now also enter the visitor. Strict-only
# unquoted paths otherwise keep their legacy dispatch. A bare "string"
# must remain a JSON string literal.
# Decode a computed selector made only of dot-separated unquoted names or
# JSON-quoted field names.  Parsing rather than split /\./ preserves literal
# periods, escaped quotes/backslashes, empty names and Unicode escapes.
# Numeric index steps are represented as ['index', N] or
# ['index', N, 1] for an optional lookup; optional named fields use
# ['field', NAME, 1]. Existing strict string field steps keep their
# scalar representation for compatibility.
# Dynamic expressions, iterator stages and generators remain separate audits.
sub _parse_v3_computed_selector_fields {
    my ($selector) = @_;
    return undef unless defined($selector) && $selector =~ /\A\./;

    my $rest = substr($selector, 1);
    my @fields;
    while (length $rest) {
        my $field;
        if ($rest =~ s/\A([A-Za-z_]\w*)(\?)?//) {
            my $name = $1;
            my $optional = defined($2) ? 1 : 0;
            $field = $optional ? ['field', $name, 1] : $name;
        }
        elsif ($rest =~ s/\A("(?:[^"\\]|\\.)*")(\?)?//s) {
            my $json_name = $1;
            my $optional = defined($2) ? 1 : 0;
            my $name = eval { _decode_json($json_name) };
            return undef if $@ || !defined($name) || ref($name);
            $field = $optional ? ['field', $name, 1] : $name;
        }
        elsif ($rest =~ s/\A\[\s*("(?:[^"\\]|\\.)*")\s*\](\?)?//s) {
            my $json_name = $1;
            my $optional = defined($2) ? 1 : 0;
            my $name = eval { _decode_json($json_name) };
            return undef if $@ || !defined($name) || ref($name);
            $field = $optional ? ['field', $name, 1] : $name;
        }
        elsif ($rest =~ s/\A\[\s*(-?\d+)\s*\](\?)?//) {
            # The '?' belongs to the selector's numeric index, not to
            # the outer computed index, and only suppresses its own
            # invalid target types. Existing strict steps keep their shape.
            my $index = 0 + $1;
            my $optional = defined($2) ? 1 : 0;
            $field = ['index', $index];
            push @{$field}, 1 if $optional;
        }
        else {
            return undef;
        }

        push @fields, $field;
        last unless length $rest;
        # Bracket-quoted and numeric-index steps can follow a field
        # directly (.cfg["selected"][0]) or follow an explicit dot.
        if ($rest =~ s/\A\.//) {
            return undef unless length $rest;
        }
        elsif ($rest =~ /\A\[\s*(?:"|-?\d+\s*\])/s) {
            # Leave a quoted field / numeric index for the next stage.
        }
        else {
            return undef;
        }
    }

    return @fields ? \@fields : undef;
}

# Consume a complete [.selector] or [.selector]? prefix. An inner
# ["field"] has its own brackets, and literal ] inside JSON strings must
# not close the outer selector. Never treat arbitrary [expression] as a
# path: validate the extracted selector with the restricted field parser.
sub _parse_v3_computed_selector_prefix {
    my ($text) = @_;
    return undef unless defined($text) && $text =~ /\A\[\s*\./s;

    my $depth = 0;
    my $in_string = 0;
    my $escaped = 0;
    my $close;
    for (my $i = 0; $i < length($text); ++$i) {
        my $char = substr($text, $i, 1);
        if ($in_string) {
            if ($escaped) {
                $escaped = 0;
            }
            elsif ($char eq '\\') {
                $escaped = 1;
            }
            elsif ($char eq '"') {
                $in_string = 0;
            }
            next;
        }

        if ($char eq '"') {
            $in_string = 1;
        }
        elsif ($char eq '[') {
            ++$depth;
        }
        elsif ($char eq ']') {
            --$depth;
            return undef if $depth < 0;
            if ($depth == 0) {
                $close = $i;
                last;
            }
        }
    }

    return undef unless defined $close;
    my $selector = substr($text, 1, $close - 1);
    $selector =~ s/\A\s+|\s+\z//g;
    return undef unless _parse_v3_computed_selector_fields($selector);

    my $consumed = $close + 1;
    my $optional = substr($text, $consumed, 1) eq '?' ? 1 : 0;
    ++$consumed if $optional;
    return [$selector, $optional, $consumed];
}

sub _parse_v3_literal_iterator_path {
    my ($path) = @_;
    return undef unless defined($path) && length($path);

    my $rest = $path;
    $rest =~ s/\A\.//;  # jq's leading dot is retained for bracket paths.

    my @steps;
    my $has_iterator = 0;
    my $has_computed_key = 0;
    my $has_optional_numeric_index = 0;
    my $has_optional_field = 0;
    my $has_strict_negative_index = 0;
    my $has_strict_positive_index = 0;
    my $has_strict_bracket_quoted_field = 0;
    my $has_strict_dot_quoted_field = 0;
    my $after_step = 0;

    while (length $rest) {
        # jq permits spaces before a dotted suffix when there is
        # already a literal path stage: .items[0] .name, .items[]
        # ."field", and .obj["key"] .[0]. A bracket may also follow
        # whitespace AFTER the dot: .items[0] . [1]. A dot followed
        # by whitespace and a bare unquoted name is still invalid.
        # Require a rooted path, and parse the full next stage below.
        $rest =~ s/\A\s+(?=\.(?:[A-Za-z_]|"|\[|\s+\[))//
            if @steps && $path =~ /\A\./;
        if ($rest =~ s/\A\.//) {
            return undef unless $after_step && length($rest);
            $after_step = 0;
        }

        # jq permits whitespace between a literal path stage (or
        # root dot) and a following numeric/JSON-quoted bracket.
        # Only consume this gap when the next *entire bracket* is a
        # literal signed integer or quoted string. In particular do
        # not route slices, computed expressions or bare constructors.
        $rest =~ s/\A\s+(?=\[\s*-?\d+\s*\])//;
        # A simple computed selector may follow whitespace after a
        # rooted literal stage: .obj [.key] and . [.key]. Do not
        # interpret dotless expressions such as try [.key] as paths.
        # _parse_v3_computed_selector_prefix performs the full
        # restricted selector validation after this lexical gap.
        $rest =~ s/\A\s+(?=\[\s*\.)//
            if $path =~ /\A\./;
        # Spaced iterator syntax also requires the explicit root dot.
        # Otherwise 'try [ ]' could be misread as a field and iterator.
        $rest =~ s/\A\s+(?=\[\s*\])//
            if $path =~ /\A\./;
        # Require the explicit root dot for this new whitespace form:
        # otherwise 'try ["catch me"]' would be mistaken for a
        # dotless literal path rather than a try/array expression.
        $rest =~ s/\A\s+(?=\[\s*"(?:[^"\\]|\\.)*"\s*\])//s
            if $path =~ /\A\./;

        if ($rest =~ s/\A([A-Za-z_]\w*)(\?)?//) {
            # An optional field is distinct from an optional index and
            # suppresses only its own invalid lookup target type.
            my $name = $1;
            my $optional = defined($2) ? 1 : 0;
            return undef if $after_step;
            my @field_step = ('field', $name);
            push @field_step, 1 if $optional;
            push @steps, \@field_step;
            $has_optional_field = 1 if $optional;
        }
        # A simple computed selector [.key] can follow literal fields,
        # indices, or iterators. jq evaluates the selector against the
        # filter's ORIGINAL input, not against the intermediate value being
        # indexed. Keep the existing computed_root step for compatibility
        # with callers that inspect parsed paths.
        elsif (my $computed = _parse_v3_computed_selector_prefix($rest))
        {
            # Keep previous computed_root / computed_context step shapes.
            # A balanced prefix is consumed only after restricted validation.
            my ($selector, $optional, $consumed) = @{$computed};
            return undef unless @steps || $path =~ /\A\.\s*\[/;
            substr($rest, 0, $consumed, '');
            my @computed_step = (
                @steps ? 'computed_context' : 'computed_root', $selector
            );
            push @computed_step, 1 if $optional;
            push @steps, \@computed_step;
            $has_computed_key = 1;
        }
        elsif ($rest =~ s/\A\[\s*("(?:[^"\\]|\\.)*")\s*\](\?)?//s) {
            # Bare ["key"] is a jq array constructor. Only a rooted
            # .["key"] or a bracket stage after an existing path field
            # can be treated as a literal field lookup.
            my $quoted = $1;
            my $optional = defined($2) ? 1 : 0;
            return undef unless @steps || $path =~ /\A\.\s*\[/;
            my $name = eval { _decode_json($quoted) };
            return undef if $@ || !defined($name) || ref($name);
            my @field_step = ('field', $name);
            push @field_step, 1 if $optional;
            push @steps, \@field_step;
            $has_optional_field = 1 if $optional;
            $has_strict_bracket_quoted_field = 1 unless $optional;
        }
        elsif ($rest =~ s/\A("(?:[^"\\]|\\.)*")(\?)?//s) {
            my $quoted = $1;
            my $optional = defined($2) ? 1 : 0;
            return undef if $after_step;
            # Only ."...", or a quoted stage after another path
            # step, can enable the strict visitor. A bare "..." is
            # a JSON string literal, not a field lookup.
            my $is_strict_dot_field = !$optional
                && (@steps || $path =~ /\A\./);
            my $name = eval { _decode_json($quoted) };
            return undef if $@ || !defined($name) || ref($name);
            my @field_step = ('field', $name);
            push @field_step, 1 if $optional;
            push @steps, \@field_step;
            $has_optional_field = 1 if $optional;
            $has_strict_dot_quoted_field = 1 if $is_strict_dot_field;
        }
        elsif ($rest =~ s/\A\[(\s*)\](\?)?//) {
            # A bracket containing only whitespace is the same jq
            # iterator as []; optional ? belongs to this stage.
            # Rooted . [ ] and .[ ] are valid, but bare [ ] constructs
            # an empty array, and try [ ] is not a field path.
            my $inner_space = $1;
            my $optional = defined($2) ? 1 : 0;
            return undef unless @steps || $path =~ /\A\.\s*\[/;
            # Legacy dotless .name[] normalizations still work as
            # before, but new whitespace forms must retain the dot.
            return undef if length($inner_space) && $path !~ /\A\./;
            push @steps, ['iterator', $optional];
            $has_iterator = 1;
        }
        elsif ($rest =~ s/\A\[\s*(-?\d+)\s*\](\?)?//) {
            # jq permits whitespace on either side of a literal numeric
            # bracket index, including when the stage is optional.
            # Capture both matches before checking the root path:
            # a second regex on $path would clear $1 and $2.
            my $index = 0 + $1;
            my $optional = defined($2) ? 1 : 0;
            # A root bracket numeric lookup must start with an explicit
            # dot; bare [ 0 ] is an array constructor, not a path.
            return undef unless @steps || $path =~ /\A\.\s*\[/;
            my @index_step = ('index', $index);
            push @index_step, 1 if $optional;
            push @steps, \@index_step;
            $has_optional_numeric_index = 1 if $optional;
            $has_strict_negative_index = 1 if $index < 0 && !$optional;
            $has_strict_positive_index = 1 if $index >= 0 && !$optional;
        }
        else {
            return undef;
        }

        $after_step = 1;
        # A bare name or quoted name after a prior step must be separated
        # by '.', except for bracket-form access, indices, and iterators.
        return undef if $rest =~ /\A[A-Za-z_"']/
            && $after_step;
    }

    return ($has_iterator || $has_computed_key
        || $has_optional_numeric_index || $has_optional_field
        || $has_strict_negative_index || $has_strict_positive_index
        || $has_strict_bracket_quoted_field || $has_strict_dot_quoted_field)
        ? \@steps : undef;
}

# The simple selector expression inside [.key] is evaluated against the
# full input for this filter, never against an intermediate path result.
# Resolve selectors before visiting path stages: jq evaluates a malformed
# selector field lookup even if a preceding [] would emit no values.
sub _resolve_v3_computed_key_selector {
    my ($input, $selector, $no_output_ref) = @_;
    my $fields = _parse_v3_computed_selector_fields($selector);
    die JQ::Lite::Error::Parse->new(
        message => 'Invalid simple computed-key selector'
    ) unless $fields;

    my $selected = $input;
    for my $field (@{$fields}) {
        if (ref($field) eq 'ARRAY' && $field->[0] eq 'index') {
            # jq numeric indexing: arrays accept signed indices, null
            # produces one null, and other types are runtime errors.
            if (!defined $selected) {
                $selected = undef;
            }
            elsif (ref($selected) eq 'ARRAY') {
                my $index = $field->[1];
                $index += scalar(@{$selected}) if $index < 0;
                $selected = $index >= 0 && $index < @{$selected}
                    ? $selected->[$index] : undef;
            }
            else {
                # Optional selector stages emit *no result* for invalid
                # types. They do not convert such failures to JSON null.
                # Do not suppress failures from earlier strict stages.
                if ($field->[2]) {
                    if ($no_output_ref) {
                        $$no_output_ref = 1;
                        return undef;
                    }
                    return undef;  # only the streaming caller tracks empty
                }
                my $type = JQ::Lite::Value::type_of($selected);
                die JQ::Lite::Error::Evaluation->new(
                    message => 'Cannot index ' . $type . ' with number'
                );
            }
            next;
        }
        my $optional_field = ref($field) eq 'ARRAY'
            && $field->[0] eq 'field' && $field->[2];
        my $name = $optional_field ? $field->[1] : $field;
        if (!defined $selected) {
            $selected = undef;
        }
        elsif (ref($selected) eq 'HASH') {
            $selected = exists($selected->{$name})
                ? $selected->{$name} : undef;
        }
        else {
            # Optional named-field lookup suppresses its own type error,
            # but a missing field/null source is still a JSON null result.
            if ($optional_field) {
                if ($no_output_ref) {
                    $$no_output_ref = 1;
                }
                return undef;
            }
            my $type = JQ::Lite::Value::type_of($selected);
            die JQ::Lite::Error::Evaluation->new(
                message => 'Cannot index ' . $type
                    . ' with string "' . $name . '"'
            );
        }
    }
    return $selected;
}

# Visit each literal field, numeric index, computed key, and strict/optional
# iterator in source order. Computed selectors refer to the original input,
# while each subsequent index operates on the current intermediate stream.
# The compatibility-sensitive general _traverse is deliberately unchanged.
# Bound normalization for confirmed arrays, shared by literal/computed paths.
sub _v3_array_index_or_null {
    my ($array, $index) = @_;
    $index += @$array if $index < 0;
    return $index >= 0 && $index < @$array ? $array->[$index] : undef;
}

# Array/object stream expansion, shared by standalone and path-local [].
# Optional []? only drops scalar targets; strict [] keeps its error class.
sub _v3_iterate_values {
    my ($value, $optional) = @_;
    return @$value if ref $value eq 'ARRAY';
    return values %$value if ref $value eq 'HASH';
    return if $optional;
    my $type = JQ::Lite::Value::type_of($value);
    die JQ::Lite::Error::Evaluation->new(
        message => 'Cannot iterate over ' . $type . ' ('
            . _encode_json($value) . ')'
    );
}

sub _traverse_v3_field_iterator {
    my ($input, $path, $steps) = @_;
    $steps ||= _parse_v3_literal_iterator_path($path);
    die JQ::Lite::Error::Parse->new(
        message => 'Invalid literal iterator/index path'
    ) unless $steps;

    my @selected_keys;
    # jq resolves nested computed selectors from the rightmost bracket
    # inward. An optional numeric selector which emits no results drops
    # this filter input before evaluating selectors further to its left.
    # This still resolves selector errors before a preceding [] traversal.
    for (my $i = $#{$steps}; $i >= 0; --$i) {
        my $step = $steps->[$i];
        if ($step->[0] eq 'computed_root'
            || $step->[0] eq 'computed_context')
        {
            my $no_output = 0;
            $selected_keys[$i] = _resolve_v3_computed_key_selector(
                $input, $step->[1], \$no_output
            );
            return () if $no_output;
        }
    }

    my @stream = ($input);
    my $step_index = 0;
    for my $step (@{$steps}) {
        my $selector_value = $selected_keys[$step_index++];
        my @next;

        for my $value (@stream) {
            if ($step->[0] eq 'computed_root'
                || $step->[0] eq 'computed_context')
            {
                # Both .[.key] and .obj[.key] evaluate .key against the
                # original filter input. After .obj, only the *lookup
                # target* is the intermediate object; the selector is not
                # rebound to that object or to an iterator's element.
                my $selected = $selector_value;

                my $input_type = JQ::Lite::Value::type_of($value);
                my $key_type = JQ::Lite::Value::type_of($selected);
                if ($key_type eq 'string' && $input_type eq 'object') {
                    push @next, exists($value->{$selected})
                        ? $value->{$selected} : undef;
                }
                elsif ($key_type eq 'number' && $input_type eq 'array') {
                    push @next, _v3_array_index_or_null($value, int($selected));
                }
                elsif (($key_type eq 'string' || $key_type eq 'number')
                    && $input_type eq 'null')
                {
                    push @next, undef;
                }
                else {
                    # jq's trailing ? suppresses this invalid index only.
                    # Selector expressions have already been evaluated.
                    next if $step->[2];
                    my $diagnostic = 'Cannot index ' . $input_type
                        . ' with ' . $key_type;
                    $diagnostic .= ' "' . $selected . '"'
                        if $key_type eq 'string';
                    die JQ::Lite::Error::Evaluation->new(
                        message => $diagnostic
                    );
                }
                next;
            }

            if ($step->[0] eq 'field') {
                my $field = $step->[1];

                if (!defined $value) {
                    # Reading a named field from null also yields null.
                    push @next, undef;
                }
                elsif (ref($value) eq 'HASH') {
                    push @next, exists($value->{$field})
                        ? $value->{$field} : undef;
                }
                else {
                    # jq's field? omits only this invalid type lookup.
                    # A missing object key and a null input still produce
                    # one null; earlier or later strict steps may error.
                    next if $step->[2];
                    my $type = JQ::Lite::Value::type_of($value);
                    die JQ::Lite::Error::Evaluation->new(
                        message => 'Cannot index ' . $type
                            . ' with string "' . $field . '"'
                    );
                }
                next;
            }

            if ($step->[0] eq 'index') {
                if (!defined $value) {
                    # Numeric indexing null emits one JSON null, even
                    # when this index has a trailing optional marker.
                    push @next, undef;
                }
                elsif (ref($value) eq 'ARRAY') {
                    push @next, _v3_array_index_or_null($value, $step->[1]);
                }
                else {
                    # [N]? drops precisely this invalid numeric lookup.
                    # An earlier strict field/index/iterator error remains
                    # visible, as does a later strict suffix error.
                    next if $step->[2];
                    my $type = JQ::Lite::Value::type_of($value);
                    die JQ::Lite::Error::Evaluation->new(
                        message => 'Cannot index ' . $type . ' with number'
                    );
                }
                next;
            }

            # []? suppresses only iteration errors for the current stage.
            push @next, _v3_iterate_values($value, $step->[1]);
        }

        @stream = @next;
        last unless @stream;
    }

    return @stream;
}

sub _traverse {
    my ($data, $query, $options) = @_;
    my $numeric_object_index_error = $options && $options->{numeric_object_index_error};
    my $numeric_null_index = $options && $options->{numeric_null_index};
    # Numeric null/index parity is opt-in for query paths, not helper traversals.
    # This option is enabled only for direct query-path evaluation in 3.x.
    # Internal callers (select, aggregates, assignment, etc.) retain their
    # established no-result semantics until independently audited.
    my $missing_object_null = $options && $options->{missing_object_null};
    my @steps = split /\./, $query;
    my @stack = ($data);

    for my $step (@steps) {
        my $optional = ($step =~ s/\?$//);
        my @next_stack;

        for my $item (@stack) {
            if (!defined $item) {
                # A chain of object-field reads through JSON null remains
                # null in jq, rather than dropping its output stream.
                push @next_stack, undef
                    if ($missing_object_null && $step !~ /\[/)
                    || ($numeric_null_index && (
                        $step =~ /\[\d+\]$/ || $step =~ /^[A-Za-z_]\w*$/
                    ));
                next;
            }

            # array slice access: [start:end]
            if ($step =~ /^\[(.*):(.*)\]$/s) {
                my @args = _parse_bracket_slice_arguments($1, $2);
                push @next_stack, _apply_bracket_slice($item, @args);
            }
            # array slice access: key[start:end]
            elsif ($step =~ /^(.*?)\[(.*):(.*)\]$/s) {
                my ($key, $raw_start, $raw_end) = ($1, $2, $3);
                if (ref $item eq 'HASH' && exists $item->{$key}) {
                    my @args = _parse_bracket_slice_arguments($raw_start, $raw_end);
                    push @next_stack, _apply_bracket_slice($item->{$key}, @args);
                }
            }
            # direct index access: [index]
            elsif ($step =~ /^\[(\d+)\]$/) {
                my $index = $1;
                if ($numeric_object_index_error && ref $item eq 'HASH') {
                    die JQ::Lite::Error::Evaluation->new(
                        message => 'Cannot index object with number'
                    );
                }
                if (ref $item eq 'ARRAY') {
                    # jq emits null both for null-valued and out-of-range slots.
                    push @next_stack, $item->[$index]
                        if $numeric_null_index || defined $item->[$index];
                }
            }
            # array expansion without key: []
            elsif ($step eq '[]') {
                if (ref $item eq 'ARRAY') {
                    push @next_stack, @$item;
                }
                elsif (ref $item eq 'HASH') {
                    push @next_stack, values %$item;
                }
            }
            # index access: key[index]
            elsif ($step =~ /^(.*?)\[(\d+)\]$/) {
                my ($key, $index) = ($1, $2);
                if (ref $item eq 'HASH' && exists $item->{$key}) {
                    my $val = $item->{$key};
                    if ($numeric_object_index_error && ref $val eq 'HASH') {
                        die JQ::Lite::Error::Evaluation->new(
                            message => 'Cannot index object with number'
                        );
                    }
                    if (ref $val eq 'ARRAY') {
                        push @next_stack, $val->[$index]
                            if $numeric_null_index || defined $val->[$index];
                    }
                    elsif ($numeric_null_index && !defined $val) {
                        push @next_stack, undef;
                    }
                }
                elsif ($numeric_null_index && ref $item eq 'HASH') {
                    # Missing object key followed by an array index is null.
                    push @next_stack, undef;
                }
            }
            # array expansion: key[]
            elsif ($step =~ /^(.*?)\[\]$/) {
                my $key = $1;
                if (ref $item eq 'HASH' && exists $item->{$key}) {
                    my $val = $item->{$key};
                    if (ref $val eq 'ARRAY') {
                        push @next_stack, @$val;
                    }
                    elsif (ref $val eq 'HASH') {
                        push @next_stack, values %$val;
                    }
                }
                elsif (ref $item eq 'ARRAY') {
                    for my $sub (@$item) {
                        if (ref $sub eq 'HASH' && exists $sub->{$key}) {
                            my $val = $sub->{$key};
                            if (ref $val eq 'ARRAY') {
                                push @next_stack, @$val;
                            }
                            elsif (ref $val eq 'HASH') {
                                push @next_stack, values %$val;
                            }
                        }
                    }
                }
            }
            # standard access: key
            else {
                if (ref $item eq 'HASH') {
                    if (exists $item->{$step}) {
                        push @next_stack, $item->{$step};
                    }
                    elsif ($missing_object_null) {
                        push @next_stack, undef;
                    }
                }
                elsif (ref $item eq 'ARRAY') {
                    for my $sub (@$item) {
                        if (ref $sub eq 'HASH' && exists $sub->{$step}) {
                            push @next_stack, $sub->{$step};
                        }
                    }
                }
            }
        }

        # allow empty results if optional
        @stack = @next_stack;
        last if !@stack && !$optional;
    }

    return @stack;
}

sub _evaluate_condition {
    my ($item, $cond) = @_;

    $cond = _strip_wrapping_parens($cond);
    $cond =~ s/^\s+|\s+$//g;

    # Split only top-level logical operators.  Evaluating `or` first gives
    # `and` the tighter binding used by jq, while recursive calls remove
    # parentheses around individual operands.
    my @or_conditions = _split_top_level_keyword($cond, 'or');
    if (@or_conditions > 1) {
        for my $condition (@or_conditions) {
            return 1 if _evaluate_condition($item, $condition);
        }
        return 0;
    }

    my @and_conditions = _split_top_level_keyword($cond, 'and');
    if (@and_conditions > 1) {
        for my $condition (@and_conditions) {
            return 0 unless _evaluate_condition($item, $condition);
        }
        return 1;
    }

    # A comparison of the current scalar (for example select(. > 1))
    # has no named field path.  Treat '.' as the value itself, including
    # JSON null and booleans, instead of looking up a nonexistent field.
    if ($cond =~ /^\s*\.\s*(==|!=|>=|<=|>|<)\s*(.+?)\s*$/s) {
        my ($operator, $literal) = ($1, $2);
        my ($right, $parsed);
        {
            local $@;
            $parsed = eval { $right = _decode_json($literal); 1 };
        }
        return _compare_values($item, $operator, $right) if $parsed;
    }

    # Keep the v2 predicate spelling, but share v3 arithmetic type/errors.
    if ($cond =~ /^\s*(\.\w+)\s*([\+\-\*\/%])\s*(-?\d+(?:\.\d+)?)\s*(==|!=|>=|<=|>|<)\s*(-?\d+(?:\.\d+)?)\s*$/) {
        my ($path, $op1, $rhs1, $cmp, $rhs2) = ($1, $2, $3, $4, $5);
        my ($values, $ok) = _evaluate_value_expression(
            undef, $item, "$path $op1 $rhs1"
        );
        return $ok && @$values
            && _compare_values($values->[0], $cmp, 0 + $rhs2);
    }

    # support for the contains operator: select(.tags contains "perl")
    if ($cond =~ /^\s*\.(.+?)\s+contains\s+"(.*?)"\s*$/) {
        my ($path, $want) = ($1, $2);
        my @vals = _traverse($item, $path);

        for my $val (@vals) {
            if (ref $val eq 'ARRAY') {
                return 1 if grep { $_ eq $want } @$val;
            }
            elsif (!ref $val && index($val, $want) >= 0) {
                return 1;
            }
        }
        return 0;
    }

    # support for the has operator: select(.meta has "key")
    if ($cond =~ /^\s*\.(.+?)\s+has\s+"(.*?)"\s*$/) {
        my ($path, $key) = ($1, $2);
        my @vals = _traverse($item, $path);

        for my $val (@vals) {
            if (ref $val eq 'HASH' && exists $val->{$key}) {
                return 1;
            }
        }
        return 0;
    }

    # support for the match operator (with optional 'i' flag)
    if ($cond =~ /^\s*\.(.+?)\s+match\s+"(.*?)"(i?)\s*$/) {
        my ($path, $pattern, $ignore_case) = ($1, $2, $3);
        my ($re, $error) = _build_regex($pattern, $ignore_case);
        if ($error) {
            $error =~ s/[\r\n]+$//;
            die "match(): invalid regular expression - $error";
        }

        my @vals = _traverse($item, $path);
        for my $val (@vals) {
            next if ref $val;
            return 1 if $val =~ $re;
        }
        return 0;
    }

    # support for the =~ operator: select(. =~ "pattern")
    if ($cond =~ /^\s*\.(.+?)\s*=~\s*"(.*?)"(i?)\s*$/) {
        my ($path, $pattern, $ignore_case) = ($1, $2, $3);
        my ($re, $error) = _build_regex($pattern, $ignore_case);
        if ($error) {
            $error =~ s/[\r\n]+$//;
            die "=~: invalid regular expression - $error";
        }

        my @vals = _traverse($item, $path);
        for my $val (@vals) {
            next if ref $val;
            return 1 if $val =~ $re;
        }

        return 0;
    }
 
    # pattern for a single condition
    if ($cond =~ /^\s*\.(.+?)\s*(==|!=|>=|<=|>|<)\s*(.+?)\s*$/) {
        my ($path, $op, $value_raw) = ($1, $2, $3);

        my $value = _parse_literal_argument($value_raw);
        my @values = _traverse($item, $path, { missing_object_null => 1 });
        for my $field_val (@values) {
            return 1 if _compare_values($field_val, $op, $value);
        }
    }

    return 0;
}

sub _compare_values {
    my ($left, $operator, $right) = @_;
    my $ordering = JQ::Lite::Value::compare($left, $right);

    return $ordering == 0 if $operator eq '==';
    return $ordering != 0 if $operator eq '!=';
    return $ordering >= 0 if $operator eq '>=';
    return $ordering <= 0 if $operator eq '<=';
    return $ordering >  0 if $operator eq '>';
    return $ordering <  0 if $operator eq '<';
    return 0;
}

# This comparison has no captured state; reuse one callback across
# min_by/max_by and group_by instead of allocating it on every call.
my $SMART_CMP = sub {
    my ($a, $b) = @_;

    my $num_a = ($a =~ /^-?\d+(?:\.\d+)?$/);
    my $num_b = ($b =~ /^-?\d+(?:\.\d+)?$/);

    if ($num_a && $num_b) {
        return $a <=> $b;
    } else {
        return "$a" cmp "$b";  # explicitly perform string comparison
    }
};

sub _smart_cmp { return $SMART_CMP; }

sub _extreme_by {
    my ($array_ref, $key_path, $use_entire_item, $mode) = @_;

    return undef unless ref $array_ref eq 'ARRAY';
    return undef unless @$array_ref;

    my $cmp = _smart_cmp();
    my ($best_item, $best_key);

    for my $element (@$array_ref) {
        my $candidate = _value_to_comparable(
            _first_projected_key($element, $key_path, $use_entire_item)
        );
        next unless defined $candidate;

        if (!defined $best_item) {
            ($best_item, $best_key) = ($element, $candidate);
            next;
        }

        my $comparison = $cmp->($candidate, $best_key);
        if (($mode eq 'max' && $comparison > 0)
            || ($mode eq 'min' && $comparison < 0)) {
            ($best_item, $best_key) = ($element, $candidate);
        }
    }

    return defined $best_item ? $best_item : undef;
}

sub _value_to_comparable {
    my ($value) = @_;

    return undef unless defined $value;

    if (JSON::PP::is_bool($value)) {
        return $value ? 1 : 0;
    }

    if (!ref $value) {
        return $value;
    }

    if (ref($value) eq 'HASH' || ref($value) eq 'ARRAY') {
        return _encode_json($value);
    }

    return undef;
}

sub _normalize_path_argument {
    my ($raw_path) = @_;

    $raw_path = '' unless defined $raw_path;
    $raw_path =~ s/^\s+|\s+$//g;
    $raw_path =~ s/^['"](.*)['"]$/$1/;

    my $use_entire_item = ($raw_path eq '' || $raw_path eq '.');
    my $key_path        = $raw_path;
    $key_path =~ s/^\.// unless $use_entire_item;

    return ($key_path, $use_entire_item);
}

sub _project_numeric_values {
    my ($element, $key_path, $use_entire_item) = @_;

    my @values = $use_entire_item
        ? ($element)
        : _traverse($element, $key_path);

    return _extract_numeric_values(\@values);
}

sub _uniq {
    my %seen;
    return grep { !$seen{_key($_)}++ } @_;
}

# generate a unique key for hash, array, or scalar values
sub _key {
    my ($val) = @_;
    if (ref $val eq 'HASH') {
        return join(",", sort map { "$_=" . _key($val->{$_}) } keys %$val);
    } elsif (ref $val eq 'ARRAY') {
        return join(",", map { _key($_) } @$val);
    } else {
        return "$val";
    }
}

# Share first-result path projection; key signatures remain filter-specific.
sub _first_projected_key {
    my ($item, $key_path, $whole_item) = @_;
    return $item if $whole_item;
    my @values = _traverse($item, $key_path);
    return @values ? $values[0] : undef;
}

sub _group_by {
    my ($array_ref, $path) = @_;
    die 'group_by(): input must be an array' unless ref $array_ref eq 'ARRAY';

    my ($key_path, $use_entire_item) = _normalize_path_argument($path);

    my @entries;
    my $index = 0;
    for my $item (@$array_ref) {
        my $key_value = _first_projected_key($item, $key_path, $use_entire_item);

        my $signature = defined $key_value ? _key($key_value) : "\0__JQ_LITE_UNDEF__";
        push @entries, {
            item      => $item,
            signature => $signature,
            index     => $index++,
        };
    }

    my $cmp = _smart_cmp();
    my @sorted = sort {
        my $order = $cmp->($a->{signature}, $b->{signature});
        $order = $a->{index} <=> $b->{index} if $order == 0;
        $order;
    } @entries;

    my @groups;
    my $current_signature;
    for my $entry (@sorted) {
        if (!defined $current_signature || $entry->{signature} ne $current_signature) {
            push @groups, [];
            $current_signature = $entry->{signature};
        }
        push @{ $groups[-1] }, $entry->{item};
    }

    return \@groups;
}

# An undefined depth means unlimited recursion; numeric depths retain
# the existing zero/negative stopping rule.
sub _flatten_all {
    return _flatten_depth($_[0], undef);
}

sub _flatten_depth {
    my ($value, $depth) = @_;

    return $value unless ref $value eq 'ARRAY';
    return $value if defined($depth) && $depth <= 0;

    my @flattened;
    for my $item (@$value) {
        if (ref $item eq 'ARRAY') {
            push @flattened, @{ _flatten_depth(
                $item, defined($depth) ? $depth - 1 : undef
            ) };
        } else {
            push @flattened, $item;
        }
    }

    return \@flattened;
}

sub _apply_string_predicate {
    my ($value, $needle, $mode) = @_;

    if (ref $value eq 'ARRAY') {
        return [ map { _apply_string_predicate($_, $needle, $mode) } @$value ];
    }

    return JSON::PP::false if !_is_string_scalar($needle);

    return _string_predicate_result($value, $needle, $mode);
}

sub _string_predicate_result {
    my ($value, $needle, $mode) = @_;

    return JSON::PP::false if !defined $value;
    return JSON::PP::false if ref $value;
    return JSON::PP::false if !_is_string_scalar($value);

    $needle //= '';
    my $len = length $needle;

    if ($mode eq 'start') {
        return JSON::PP::true if $len == 0 || index($value, $needle) == 0;
        return JSON::PP::false;
    }

    if ($mode eq 'end') {
        return JSON::PP::true if $len == 0;
        return JSON::PP::false if length($value) < $len;
        return JSON::PP::true if substr($value, -$len) eq $needle;
        return JSON::PP::false;
    }

    return JSON::PP::false;
}

sub _apply_regex_filter {
    my ($value, $pattern, $flags, $name) = @_;

    my ($regex, $error) = _build_regex($pattern, $flags);
    if ($error) {
        $error =~ s/[\r\n]+$//;
        die "$name(): invalid regular expression - $error";
    }

    return $name eq 'test'
        ? _test_against_regex($value, $regex)
        : _match_against_regex($value, $regex);
}


sub _apply_test {
    return _apply_regex_filter(@_, 'test');
}


sub _apply_match {
    return _apply_regex_filter(@_, 'match');
}


sub _test_against_regex {
    my ($value, $regex) = @_;

    if (ref $value eq 'ARRAY') {
        return [ map { _test_against_regex($_, $regex) } @$value ];
    }

    return JSON::PP::false if !defined $value;

    if (JSON::PP::is_bool($value)) {
        $value = $value ? 'true' : 'false';
    }

    return JSON::PP::false if ref $value;

    return $value =~ $regex ? JSON::PP::true : JSON::PP::false;
}

sub _match_against_regex {
    my ($value, $regex) = @_;

    if (ref $value eq 'ARRAY') {
        return [ map { _match_against_regex($_, $regex) } @$value ];
    }

    return undef if !defined $value;

    if (JSON::PP::is_bool($value)) {
        $value = $value ? 'true' : 'false';
    }

    return undef if ref $value;

    my $text = "$value";
    return undef unless $text =~ $regex;

    my $offset = $-[0];
    my $length = $+[0] - $-[0];
    my $string = substr($text, $offset, $length);

    my @captures;
    my $capture_count = $#-;
    for my $index (1 .. $capture_count) {
        if (defined $-[$index] && $-[$index] >= 0) {
            my $capture_offset = $-[$index];
            my $capture_length = $+[$index] - $-[$index];
            my $capture_string = substr($text, $capture_offset, $capture_length);
            push @captures, {
                offset => $capture_offset,
                length => $capture_length,
                string => $capture_string,
            };
        } else {
            push @captures, {
                offset => undef,
                length => undef,
                string => undef,
            };
        }
    }

    return {
        offset   => $offset,
        length   => $length,
        string   => $string,
        captures => \@captures,
    };
}

# The supported modifier alphabet never changes between calls. Keep the
# membership table outside _build_regex instead of rebuilding it for each
# test()/match() invocation.
my %REGEX_ALLOWED_FLAGS = map { $_ => 1 } qw(i m s x);

sub _build_regex {
    my ($pattern, $flags) = @_;

    $pattern = '' unless defined $pattern;
    $flags   = '' unless defined $flags;

    my %enabled;
    for my $flag (split //, $flags) {
        return (undef, "unknown regex flag '$flag'")
            unless $REGEX_ALLOWED_FLAGS{$flag};
        $enabled{$flag} = 1;
    }

    my $modifiers = join '', grep { $enabled{$_} } qw(i m s x);

    my $regex = eval {
        $modifiers eq ''     ? qr/$pattern/
      : $modifiers eq 'i'    ? qr/$pattern/i
      : $modifiers eq 'm'    ? qr/$pattern/m
      : $modifiers eq 's'    ? qr/$pattern/s
      : $modifiers eq 'x'    ? qr/$pattern/x
      : $modifiers eq 'im'   ? qr/$pattern/im
      : $modifiers eq 'is'   ? qr/$pattern/is
      : $modifiers eq 'ix'   ? qr/$pattern/ix
      : $modifiers eq 'ms'   ? qr/$pattern/ms
      : $modifiers eq 'mx'   ? qr/$pattern/mx
      : $modifiers eq 'sx'   ? qr/$pattern/sx
      : $modifiers eq 'ims'  ? qr/$pattern/ims
      : $modifiers eq 'imx'  ? qr/$pattern/imx
      : $modifiers eq 'isx'  ? qr/$pattern/isx
      : $modifiers eq 'msx'  ? qr/$pattern/msx
      :                         qr/$pattern/imsx;
    };
    if ($@) {
        return (undef, $@);
    }

    return ($regex, undef);
}

sub _parse_string_argument {
    my $parsed = _parse_literal_argument($_[0]);
    return defined($parsed) ? $parsed : '';
}

sub _parse_literal_argument {
    my ($raw) = @_;

    return undef if !defined $raw;

    my $parsed = eval { _decode_json($raw) };
    return $parsed if !$@;

    $raw =~ s/^\s+|\s+$//g;
    $raw =~ s/^['"]//;
    $raw =~ s/['"]$//;
    return $raw;
}

sub _apply_delimited {
    my ($value, $delimiter, $format) = @_;

    if (ref $value eq 'ARRAY') {
        return join $delimiter, map { $format->($_) } @$value;
    }

    return $format->($value);
}

sub _apply_csv {
    return _apply_delimited($_[0], ',', \&_format_csv_field);
}

sub _apply_tsv {
    return _apply_delimited($_[0], "\t", \&_format_tsv_field);
}

sub _encoding_input_text {
    my ($value, $decoding) = @_;

    return $decoding ? '' : 'null' if !defined $value;
    return $value ? 'true' : 'false' if JSON::PP::is_bool($value);
    return "$value" if !ref $value;
    return _encode_json($value) if ref $value eq 'ARRAY' || ref $value eq 'HASH';
    return "$value";
}

sub _apply_base64 {
    return encode_base64(_encoding_input_text($_[0], 0), '');
}

sub _apply_base64d {
    my ($value) = @_;

    # Keep scalar type validation local, before coercion changes SV flags.
    die '@base64d(): input must be base64 text'
        if defined($value) && !JSON::PP::is_bool($value)
            && !ref($value) && !_is_string_scalar($value);

    my $text = _encoding_input_text($value, 1);

    $text =~ s/\s+//g;

    die '@base64d(): input must be base64 text'
        if length($text) % 4 != 0;

    die '@base64d(): input must be base64 text'
        if $text !~ /^[A-Za-z0-9+\/]*={0,2}$/;

    die '@base64d(): input must be base64 text'
        if $text =~ /=/ && $text !~ /=+$/;

    my $decoded = decode_base64($text);
    my $reencoded = encode_base64($decoded, '');

    die '@base64d(): input must be base64 text'
        if $reencoded ne $text;

    return Encode::decode('UTF-8', $decoded);
}

sub _apply_uri {
    my ($value) = @_;

    my $text = _encoding_input_text($value, 0);
    my $encoded = is_utf8($text, 1)
        ? encode('UTF-8', $text)
        : $text;
    $encoded =~ s/([^A-Za-z0-9\-._~])/sprintf('%%%02X', ord($1))/ge;
    return $encoded;
}

sub _format_delimited_field {
    my ($value, $csv) = @_;

    return '' if !defined $value;

    if (JSON::PP::is_bool($value)) {
        return $value ? 'true' : 'false';
    }

    # Preserve the numeric SV flag before any stringification.
    if ($csv && !ref($value) && _is_unquoted_csv_number($value)) {
        return "$value";
    }

    my $text = (ref $value eq 'ARRAY' || ref $value eq 'HASH')
        ? _apply_tojson($value) : "$value";

    return $csv ? _quote_csv_text($text) : _escape_tsv_text($text);
}

sub _format_csv_field {
    return _format_delimited_field($_[0], 1);
}

sub _format_tsv_field {
    return _format_delimited_field($_[0], 0);
}

sub _quote_csv_text {
    my ($text) = @_;

    $text = '' unless defined $text;
    $text =~ s/"/""/g;
    return '"' . $text . '"';
}

sub _escape_tsv_text {
    my ($text) = @_;

    $text = '' unless defined $text;
    $text =~ s/\\/\\\\/g;
    $text =~ s/\t/\\t/g;
    $text =~ s/\r/\\r/g;
    $text =~ s/\n/\\n/g;
    return $text;
}

sub _is_unquoted_csv_number {
    return (_scalar_flags($_[0]) & (B::SVp_IOK() | B::SVp_NOK())) ? 1 : 0;
}

sub _apply_split {
    my ($value, $separator, $prepared) = @_;

    if (ref $value eq 'ARRAY') {
        # Share the literal separator and compiled pattern across child
        # arrays. Leave preparation lazy for null/object-only branches.
        $prepared ||= [];
        my @parts;

        for my $element (@$value) {
            my $result = _apply_split($element, $separator, $prepared);
            push @parts, ref($result) eq 'ARRAY' ? @$result : $result;
        }

        return \@parts;
    }

    return undef if !defined $value;
    if (JSON::PP::is_bool($value)) {
        $value = $value ? 'true' : 'false';
    }
    elsif (ref $value) {
        return $value;
    }

    my $pattern;
    if ($prepared && @$prepared) {
        ($separator, $pattern) = @$prepared;
    }
    else {
        $separator = defined $separator ? "$separator" : '';
        $pattern = $separator eq '' ? undef : qr/\Q$separator\E/;
        @$prepared = ($separator, $pattern) if $prepared;
    }

    return [ split(//, $value) ] if $separator eq '';
    return [ split($pattern, $value, -1) ];
}

sub _apply_explode {
    my ($value) = @_;

    if (ref $value eq 'ARRAY') {
        return [ map { _apply_explode($_) } @$value ];
    }

    return undef if !defined $value;

    if (JSON::PP::is_bool($value)) {
        $value = $value ? 'true' : 'false';
    }

    return $value if ref $value;

    # unpack emits Unicode code points directly, without building a
    # temporary character list before mapping ord() over it.
    return [ unpack('U*', "$value") ];
}

sub _apply_implode {
    my ($value) = @_;

    return undef if !defined $value;

    if (ref $value eq 'ARRAY') {
        # Only presence of a reference matters: stop at the first one
        # instead of counting every referenced array element with grep.
        for my $item (@$value) {
            return [ map { _apply_implode($_) } @$value ] if ref $item;
        }

        my $string = '';
        for my $code (@$value) {
            next unless defined $code;
            next unless looks_like_number($code);
            $string .= chr(int($code));
        }
        return $string;
    }

    return $value;
}

sub _apply_substr {
    my ($value, @args) = @_;
    # Extra user arguments are intentionally ignored, as in v2. Keep the
    # internal recursion cache separate from the public positional arguments.
    my ($start, $length) = @args;
    return _apply_substr_cached($value, $start, $length,
        ref $value eq 'ARRAY' ? [] : undef);
}

sub _apply_substr_cached {
    my ($value, $start, $length, $prepared) = @_;

    if (ref $value eq 'ARRAY') {
        # The bounds are constant for all leaves. Prepare them only on the
        # first scalar leaf, preserving passthrough-only array behavior.
        return [ map { _apply_substr_cached($_, $start, $length, $prepared) } @$value ];
    }

    return undef if !defined $value;
    if (JSON::PP::is_bool($value)) {
        $value = $value ? 'true' : 'false';
    }
    elsif (ref $value) {
        return $value;
    }

    if ($prepared && @$prepared) {
        ($start, $length) = @$prepared;
    }
    else {
        if (defined $start && !looks_like_number($start)) {
            die 'substr(): start index must be numeric';
        }
        $start = 0 unless defined $start;
        $start = int($start);

        if (defined $length) {
            if (!looks_like_number($length)) {
                die 'substr(): length must be numeric';
            }
            $length = int($length);
        }

        @$prepared = ($start, $length) if $prepared;
    }

    return defined $length
        ? substr($value, $start, $length)
        : substr($value, $start);
}

# Both forms reject text/invalid numeric bounds, but preserve their separate
# length-vs-end calculations and legacy error labels.
sub _slice_numeric_bound {
    my ($raw, $name) = @_;

    return undef unless defined $raw;
    die "slice(): $name must be numeric"
        if _is_string_scalar($raw) || !looks_like_number($raw);
    return int($raw);
}

sub _apply_slice {
    my ($value, @args) = @_;

    return undef if !defined $value;

    if (ref $value eq 'ARRAY') {
        my $array = $value;
        my $size  = @$array;

        my $raw_start = @args ? $args[0] : 0;
        my $start = _slice_numeric_bound($raw_start, 'start');
        $start = 0 unless defined $start;

        $start += $size if $start < 0;
        $start = 0       if $start < 0;
        return []        if $start >= $size;

        # The original slice(start, length) validates length only after
        # returning an empty result for a start beyond the array.
        my $length = @args > 1
            ? _slice_numeric_bound($args[1], 'length') : undef;

        return [] if $size == 0;

        my $end;
        if (defined $length) {
            return [] if $length <= 0;
            $end = $start + $length;
        }
        else {
            $end = $size;
        }

        $end = $size if $end > $size;

        return [] if $end <= $start;

        return [ @$array[$start .. $end - 1] ];
    }

    return $value;
}

sub _apply_bracket_slice {
    my ($value, $raw_start, $raw_end) = @_;

    return _apply_slice($value, $raw_start, $raw_end)
        if ref $value ne 'ARRAY';

    # Bracket slices validate the end even when start is out of range,
    # and retain the v2 error text "length" for an invalid end.
    my $start = _slice_numeric_bound($raw_start, 'start');
    my $end   = _slice_numeric_bound($raw_end, 'length');

    my $size = scalar @$value;
    $start = 0 unless defined $start;
    $start += $size if $start < 0;
    $start = 0       if $start < 0;

    return _apply_slice($value, $start) unless defined $end;

    $end += $size if $end < 0;
    return _apply_slice($value, $start, $end - $start);
}

sub _apply_replace {
    my ($value, $search, $replacement, $prepared) = @_;

    if (ref $value eq 'ARRAY') {
        # Reuse literal search/replacement preparation across nested arrays.
        # It stays lazy: passthrough-only arrays need no string conversion.
        $prepared ||= [];
        return [ map { _apply_replace($_, $search, $replacement, $prepared) } @$value ];
    }

    return $value if !defined $value;
    return $value if ref $value;

    return $value if looks_like_number($value);

    my ($pattern, $replacement_text);
    if ($prepared && @$prepared) {
        ($pattern, $replacement_text) = @$prepared;
    }
    else {
        my $search_text = defined $search ? "$search" : '';
        $replacement_text = defined $replacement ? "$replacement" : '';
        $pattern = $search_text eq '' ? undef : quotemeta $search_text;
        @$prepared = ($pattern, $replacement_text) if $prepared;
    }

    return $value unless defined $pattern;

    (my $copy = "$value") =~ s/$pattern/$replacement_text/g;
    return $copy;
}

sub _apply_pick {
    my ($value, $keys) = @_;

    return $value unless @$keys;

    if (ref $value eq 'HASH') {
        my %subset;
        for my $key (@$keys) {
            next unless defined $key;
            next unless exists $value->{$key};
            $subset{$key} = $value->{$key};
        }
        return \%subset;
    }

    if (ref $value eq 'ARRAY') {
        return [ map { _apply_pick($_, $keys) } @$value ];
    }

    return $value;
}

sub _parse_arguments {
    my ($raw) = @_;

    return () unless defined $raw;

    my $parsed = eval { _decode_json("[$raw]") };
    if (!$@ && ref $parsed eq 'ARRAY') {
        return @$parsed;
    }

    my @parts = split /,/, $raw;
    return map {
        my $part = $_;
        $part =~ s/^\s+|\s+$//g;
        $part;
    } @parts;
}

sub _parse_slice_arguments {
    my ($raw) = @_;

    return () unless defined $raw;

    my @parts = _split_semicolon_arguments($raw);
    return _parse_arguments($raw) if @parts == 1;

    return map { _parse_slice_argument($_) } @parts;
}

sub _parse_bracket_slice_arguments {
    my ($raw_start, $raw_length) = @_;

    return map { _parse_slice_argument($_) } ($raw_start, $raw_length);
}

sub _parse_slice_argument {
    my ($raw) = @_;

    return undef unless defined $raw;
    $raw =~ s/^\s+|\s+$//g;
    return undef if $raw eq '';

    my $decoded = eval { _decode_json($raw) };
    return $decoded unless $@;

    return $raw;
}

sub _split_semicolon_arguments {
    my ($raw, $expected) = @_;

    $raw //= '';

    my @segments;
    my $current   = '';
    my $depth     = 0;
    my $in_single = 0;
    my $in_double = 0;
    my $escape    = 0;

    for my $char (split //, $raw) {
        if ($escape) {
            $current .= $char;
            $escape = 0;
            next;
        }

        if ($char eq '\\' && $in_double) {
            $current .= $char;
            $escape = 1;
            next;
        }

        if ($char eq '"' && !$in_single) {
            $in_double = !$in_double;
            $current  .= $char;
            next;
        }

        if ($char eq "'" && !$in_double) {
            $in_single = !$in_single;
            $current  .= $char;
            next;
        }

        if (!$in_single && !$in_double) {
            if ($char =~ /[\[\{\(]/) {
                $depth++;
            }
            elsif ($char =~ /[\]\}\)]/ && $depth > 0) {
                $depth--;
            }
            elsif ($char eq ';' && $depth == 0) {
                my $segment = $current;
                $segment =~ s/^\s+|\s+$//g;
                push @segments, length $segment ? $segment : undef;
                $current = '';
                next;
            }
        }

        $current .= $char;
    }

    my $final = $current;
    $final =~ s/^\s+|\s+$//g;
    push @segments, length $final ? $final : undef;

    if (defined $expected) {
        $expected = int($expected);
        if ($expected > @segments) {
            push @segments, (undef) x ($expected - @segments);
        }
    }

    return @segments;
}

# Reuse the balanced semicolon scanner already used by slice() and regex
# arguments. Keep range()'s legacy first-value-per-argument and empty-slot
# handling unchanged for the practical v2 range grammar.
sub _parse_range_arguments {
    my ($raw) = @_;

    return () unless defined $raw;
    $raw =~ s/^\s+|\s+$//g;
    return () if $raw eq '';

    my @args;
    for my $segment (_split_semicolon_arguments($raw)) {
        next unless defined $segment;
        my @values = _parse_arguments($segment);
        push @args, @values ? $values[0] : undef;
    }
    return @args;
}

sub _apply_range {
    my ($value, $args_ref) = @_;

    my $sequence = _build_range_sequence($args_ref);
    return @$sequence;
}

# Produce range values through a visitor, allowing update assignment to stop
# at the first accepted value instead of allocating the entire range.  The
# regular range() filter uses the same iterator but collects every result.
sub _build_range_sequence {
    my ($args_ref) = @_;

    my @sequence;
    _visit_range_sequence($args_ref, sub {
        push @sequence, $_[0];
        return 0;
    });
    return \@sequence;
}

sub _visit_range_sequence {
    my ($args_ref, $accept) = @_;

    my @args = @$args_ref;
    die 'range(): bounds must be numeric' unless @args;

    @args = @args[0 .. 2] if @args > 3;

    my ($start, $end, $step);

    if (@args == 1) {
        $start = 0;
        $end   = _coerce_range_number($args[0]);
        $step  = 1;
    }
    elsif (@args == 2) {
        $start = _coerce_range_number($args[0]);
        $end   = _coerce_range_number($args[1]);
        $step  = 1;
    }
    else {
        $start = _coerce_range_number($args[0]);
        $end   = _coerce_range_number($args[1]);
        $step  = _coerce_range_number($args[2]);
    }

    die 'range(): bounds must be numeric' unless defined $start && defined $end;
    die 'range(): step must be numeric'    if !defined $step;
    return 0 if $step == 0;

    if ($step > 0) {
        return 0 if $start >= $end;
        for (my $current = $start; $current < $end; $current += $step) {
            return 1 if $accept->(0 + $current);
        }
        return 0;
    }

    return 0 if $start <= $end;
    for (my $current = $start; $current > $end; $current += $step) {
        return 1 if $accept->(0 + $current);
    }
    return 0;
}

sub _coerce_range_number {
    my ($value) = @_;

    return undef if !defined $value;
    return undef if ref $value;
    return undef if _is_string_scalar($value);

    return looks_like_number($value) ? 0 + $value : undef;
}

sub _apply_contains {
    my ($value, $needle) = @_;

    my $type = JQ::Lite::Value::type_of($value);
    my $needle_type = JQ::Lite::Value::type_of($needle);
    die JQ::Lite::Error::Evaluation->new(
        message => "Cannot check whether $type contains $needle_type"
    ) if $type ne $needle_type
        || ($type eq 'boolean' && !JQ::Lite::Value::equal($value, $needle));

    return _deep_contains($value, $needle, 'jq') ? JSON::PP::true : JSON::PP::false;
}

sub _apply_contains_subset {
    my ($value, $needle) = @_;

    return _deep_contains($value, $needle, 'subset') ? JSON::PP::true : JSON::PP::false;
}

sub _apply_inside {
    my ($value, $container) = @_;

    # Keep inside()'s v2 membership behavior pending its own compatibility audit.
    return _deep_contains($container, $value, 'legacy') ? JSON::PP::true : JSON::PP::false;
}

# Share first/last search without allocating all match positions.
# Array searches use jq value identity: a numeric 1 is not string "1".
# Keep the existing legacy equality helper for v2 membership functions.
# jq 1.7 string search offsets count UTF-8 bytes rather than characters.
sub _apply_index {
    my ($value, $needle, $last) = @_;

    if (ref $value eq 'ARRAY') {
        my $step = $last ? -1 : 1;
        for (my $i = $last ? $#$value : 0; $i >= 0 && $i < @$value; $i += $step) {
            return $i if JQ::Lite::Value::equal($value->[$i], $needle);
        }
        return undef;
    }

    return undef if !defined $value || !defined $needle;
    return undef if ref($value) && ref($value) ne 'JSON::PP::Boolean';
    my $fragment = encode('UTF-8', "$needle");
    return undef if $fragment eq '';
    my $haystack = encode('UTF-8', "$value");
    my $position = $last ? CORE::rindex($haystack, $fragment) : CORE::index($haystack, $fragment);
    return $position >= 0 ? $position : undef;
}

sub _apply_indices {
    my ($value, $needle) = @_;

    if (ref $value eq 'ARRAY') {
        my @matches;
        for (my $i = 0; $i < @$value; $i++) {
            push @matches, $i if JQ::Lite::Value::equal($value->[$i], $needle);
        }
        return \@matches;
    }

    # Retain v2 coercion and invalid-target fallbacks outside string search.
    return [] if !defined $needle;
    return JQ::Lite::Value::type_of($needle) eq 'string' ? undef : []
        if !defined $value;
    return [] if ref($value) && !JSON::PP::is_bool($value);

    my $haystack = encode('UTF-8', "$value");
    my $fragment = encode('UTF-8', "$needle");
    return [] if $fragment eq '';

    my @positions;
    for (my $pos = CORE::index($haystack, $fragment); $pos >= 0;
        $pos = CORE::index($haystack, $fragment, $pos + 1)) {
        push @positions, $pos;
    }
    return \@positions;
}

sub _apply_has {
    my ($value, $needle) = @_;

    return JSON::PP::false if !defined $needle;

    if (ref $value eq 'HASH') {
        return exists $value->{$needle} ? JSON::PP::true : JSON::PP::false;
    }

    if (ref $value eq 'ARRAY') {
        return JSON::PP::false if ref $needle;

        my $sv = B::svref_2object(\$needle);
        my $flags = $sv->FLAGS;
        return JSON::PP::false unless ($flags & (B::SVp_IOK() | B::SVp_NOK()));

        my $index = int($needle);
        return ($index >= 0 && $index < @$value)
            ? JSON::PP::true
            : JSON::PP::false;
    }

    return JSON::PP::false;
}

sub _values_equal {
    my ($left, $right) = @_;

    return 1 if !defined $left && !defined $right;
    return 0 if !defined $left || !defined $right;

    if (JSON::PP::is_bool($left) && JSON::PP::is_bool($right)) {
        return (!!$left) == (!!$right);
    }

    if (!ref $left && !ref $right) {
        if (looks_like_number($left) && looks_like_number($right)) {
            return $left == $right;
        }
        return "$left" eq "$right";
    }

    if (ref $left eq 'ARRAY' && ref $right eq 'ARRAY') {
        return 0 if @$left != @$right;
        for (my $i = 0; $i < @$left; $i++) {
            return 0 unless _values_equal($left->[$i], $right->[$i]);
        }
        return 1;
    }

    if (ref $left eq 'HASH' && ref $right eq 'HASH') {
        return 0 if keys(%$left) != keys(%$right);
        for my $key (keys %$left) {
            return 0 unless exists $right->{$key} && _values_equal($left->{$key}, $right->{$key});
        }
        return 1;
    }

    return 0;
}

sub _deep_contains {
    my ($value, $needle, $mode) = @_;

    $mode ||= 'legacy';

    if ($mode eq 'jq') {
        my $type = JQ::Lite::Value::type_of($value);
        return 0 if $type ne JQ::Lite::Value::type_of($needle);
        return _scalar_contains($value, $needle) if $type eq 'string';
        return JQ::Lite::Value::equal($value, $needle)
            unless $type eq 'array' || $type eq 'object';
    }

    return 1 if !defined $value && !defined $needle;
    return 0 if !defined $value;

    if (ref $value eq 'ARRAY') {
        return _array_contains($value, $needle, $mode);
    }

    if (ref $value eq 'HASH') {
        return _hash_contains($value, $needle, $mode);
    }

    return _scalar_contains($value, $needle);
}

sub _array_contains {
    my ($haystack, $needle, $mode) = @_;

    if (($mode eq 'subset' || $mode eq 'jq') && ref $needle eq 'ARRAY') {
        my @used;
        NEEDLE: for my $expected (@$needle) {
            for (my $i = 0; $i < @$haystack; $i++) {
                next if $mode eq 'subset' && $used[$i];
                if (_deep_contains($haystack->[$i], $expected, $mode)) {
                    $used[$i] = 1 if $mode eq 'subset';
                    next NEEDLE;
                }
            }
            return 0;
        }
        return 1;
    }

    for my $item (@$haystack) {
        return 1 if _values_equal($item, $needle);
    }

    return 0;
}

sub _hash_contains {
    my ($value, $needle, $mode) = @_;

    if (ref $needle eq 'HASH') {
        for my $key (keys %$needle) {
            return 0 unless exists $value->{$key};

            if ($mode eq 'legacy') {
                return 0 unless _values_equal($value->{$key}, $needle->{$key});
            }
            else {
                return 0 unless _deep_contains($value->{$key}, $needle->{$key}, $mode);
            }
        }
        return 1;
    }

    return exists $value->{$needle} ? 1 : 0;
}

sub _scalar_contains {
    my ($value, $needle) = @_;

    return 0 if !defined $value;
    return 0 if !defined $needle;

    if (!ref $value || JSON::PP::is_bool($value)) {
        my $haystack = "$value";
        my $fragment = "$needle";
        return index($haystack, $fragment) >= 0 ? 1 : 0;
    }

    return 0;
}

sub _ceil {
    my ($number) = @_;

    return $number if int($number) == $number;
    return $number > 0 ? int($number) + 1 : int($number);
}

sub _floor {
    my ($number) = @_;

    return $number if int($number) == $number;
    return $number > 0 ? int($number) : int($number) - 1;
}

sub _round {
    my ($number) = @_;

    return $number if int($number) == $number;
    return $number >= 0 ? int($number + 0.5) : int($number - 0.5);
}

sub _group_count {
    my ($array_ref, $path) = @_;
    return {} unless ref $array_ref eq 'ARRAY';

    my ($key_path, $use_entire_item) = _normalize_path_argument($path);

    my %counts;
    for my $item (@$array_ref) {
        my $key_value = _first_projected_key($item, $key_path, $use_entire_item);

        my $key = defined $key_value ? _key($key_value) : 'null';
        $counts{$key}++;
    }

    return \%counts;
}

1;
