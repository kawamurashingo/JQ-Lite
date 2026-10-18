package JQ::Lite::Util;

use strict;
use warnings;

use JSON::PP ();
use Scalar::Util qw(looks_like_number);

# v3: a scoped jq-compatible update assignment for simple object/array paths.
# RHS evaluation occurs on the *old leaf*, never on the original root.
sub _apply_update_assignment {
    my ($self, $input, $path, $rhs) = @_;

    # Expand array/object iterators recursively into selected update paths.
    # Array indices are visited in reverse so '|= empty' can splice elements
    # without shifting lower original indices.
    if (defined($path) && index($path, '[]') >= 0) {
        return _apply_container_iterator_update_assignment(
            $self, $input, $path, $rhs
        );
    }

    # Do not silently reinterpret unsupported iterator/computed paths as
    # ordinary object keys. Their path streams need a separate design.
    unless (defined($path)
        && $path =~ /\A(?:[A-Za-z_]\w*|\[\d+\])(?:\.[A-Za-z_]\w*|\[\d+\])*\z/)
    {
        die JQ::Lite::Error::Parse->new(
            message => 'Update assignment requires a simple field/index path'
        );
    }

    my @segments = _parse_path_segments($path);
    die JQ::Lite::Error::Parse->new(
        message => 'Update assignment requires a target path'
    ) unless @segments;

    # Construct a new root on a null input as jq does. Copy other roots
    # before mutation so the library does not modify its decoded inputs.
    my $root = _clone_for_assignment($input);
    if (!defined $root) {
        $root = $segments[0]{type} eq 'index' ? [] : {};
    }

    # Validate the path types explicitly: the existing plain-assignment
    # setter intentionally ignores invalid intermediates, but |= must not
    # report a successful update where no mutation occurred.
    my $cursor = $root;
    for my $i (0 .. $#segments) {
        my $segment = $segments[$i];
        my $type = $segment->{type};

        if ($type eq 'key') {
            if (ref($cursor) ne 'HASH') {
                die JQ::Lite::Error::Evaluation->new(
                    message => 'Cannot index non-object with string key'
                );
            }
            $cursor = $cursor->{$segment->{value}};
        }
        else {
            if (ref($cursor) ne 'ARRAY') {
                die JQ::Lite::Error::Evaluation->new(
                    message => 'Cannot index non-array with number'
                );
            }
            my $index = _normalize_path_array_index(
                $segment->{value}, scalar @$cursor
            );
            if ($index < 0) {
                die JQ::Lite::Error::Evaluation->new(
                    message => 'Array update index is out of range'
                );
            }
            $cursor = $cursor->[$index];
        }

        # A missing or null intermediate is created by _set_path_value.
        # Model it here only to validate the remaining path's types.
        if ($i < $#segments && !defined $cursor) {
            $cursor = $segments[$i + 1]{type} eq 'index' ? [] : {};
        }
    }

    my $old = _clone_for_assignment(_get_path_value($root, $path));
    my ($has_replacement, $replacement)
        = _first_update_rhs_result($self, $old, $rhs);
    if (!$has_replacement) {
        # jq 1.7 deletes the selected path when the RHS emits no values.
        # Do not materialize a missing intermediate just to delete it.
        # In particular, a JSON null input remains null on deletion.
        return undef unless defined $input;
        _delete_update_assignment_path($root, \@segments);
        return $root;
    }
    # A defined JSON null or false is still a value; only an entirely
    # empty result stream deletes the target above.
    _set_path_value($root, $path, $replacement);
    return $root;
}

# jq's |= takes only the first output of its RHS.  A visitor keeps
# comma alternatives and pipeline stages in source order, passing values
# downstream one at a time.  The first completed output stops the traversal,
# so later upstream values and alternatives never run their remaining filters.
#
# Most leaf filters still use the ordinary eager engine.  recurse/0,
# recurse/1, and range(...) are handled as on-demand generators.  recurse
# emits its current value before exploring children and now streams its
# custom child-filter outputs depth-first, skipping unused siblings; range
# emits only as many numbers as the downstream pipeline needs.
# This is intentionally not a general-purpose streaming evaluator.
# The explicit found flag preserves the difference between JSON null and
# a zero-result RHS (which deletes the selected assignment path).
sub _first_update_rhs_result {
    my ($self, $old, $rhs) = @_;

    my ($found, $first) = (0, undef);
    _visit_update_rhs_results($self, $old, $rhs, sub {
        ($first) = @_;
        $found = 1;
        return 1;
    });
    return ($found, $first);
}

sub _visit_update_rhs_results {
    my ($self, $input, $raw, $accept) = @_;

    my $expr = _strip_wrapping_parens($raw);

    # jq's comma operator has lower precedence than a pipeline.
    my @alternatives = _split_top_level_commas($expr);
    if (@alternatives > 1) {
        for my $alternative (@alternatives) {
            return 1 if _visit_update_rhs_results(
                $self, $input, $alternative, $accept
            );
        }
        return 0;
    }

    my @stages = _split_top_level_pipes($expr);
    if (@stages > 1) {
        my $head = shift @stages;
        my $tail = join(' | ', @stages);

        # For each produced input, recursively evaluate the rest of the
        # pipeline.  An empty downstream stage tries the next upstream
        # value; the first downstream output halts the whole pipeline.
        return _visit_update_rhs_results($self, $input, $head, sub {
            my ($value) = @_;
            return _visit_update_rhs_results($self, $value, $tail, $accept);
        });
    }

    # The recurse generator emits its current value before exploring the
    # next level.  Using run_query for this leaf would eagerly traverse
    # *all* descendants, including branches never consumed by |=.
    if ($expr =~ /\Arecurse(?:\((.*)\))?\z/s) {
        my $child_filter = defined($1) ? $1 : '';
        $child_filter =~ s/^\s+|\s+$//g;
        $child_filter = undef unless length $child_filter;
        return _visit_update_rhs_recurse(
            $self, $input, $child_filter, $accept
        );
    }

    # Reuse the regular range argument decoder and numeric validation, but
    # emit values one at a time.  The callback stops generation at the first
    # completed RHS output (or keeps going if downstream filters reject it).
    if ($expr =~ /\Arange\((.*)\)\z/s) {
        my @args = _parse_range_arguments($1);
        return _visit_range_sequence(\@args, $accept);
    }

    my @outputs = $self->run_query(_encode_json($input), $expr);
    for my $value (@outputs) {
        return 1 if $accept->($value);
    }
    return 0;
}

# Produce recurse values on demand in the same depth-first order as
# _apply_recurse.  In particular, only expand children when the current
# value was not accepted by the remaining RHS pipeline.
sub _visit_update_rhs_recurse {
    my ($self, $input, $child_filter, $accept) = @_;

    if (defined $child_filter) {
        return _visit_update_rhs_recurse_filtered(
            $self, $input, $child_filter, $accept
        );
    }

    # Keep the original iterative traversal for default recurse: it avoids
    # Perl call-stack growth for deeply nested JSON structures.
    my @stack = ($input);
    while (@stack) {
        my $current = pop @stack;
        return 1 if $accept->($current);

        next unless defined $current;

        my @children;
        if (ref $current eq 'ARRAY') {
            @children = @$current;
        }
        elsif (ref $current eq 'HASH') {
            @children = map { $current->{$_} } sort keys %$current;
        }

        push @stack, reverse @children if @children;
    }
    return 0;
}

# Share the audited computed child-iterator grammar between the nested
# try dispatcher and the recurse visitor's null-node expansion guard.
# Single selectors may have up to four literal numeric indices; each of
# two to four selectors may have one. No arbitrary computed expressions.
sub _v3_scoped_computed_recurse_pattern {
    # Each named/quoted stage may be independently optional.
    # The optional flag applies to that stage, not to the outer []?.
    # A separate ? after the outer [selector] suppresses only
    # errors from that computed-index lookup, not selector evaluation.
    my $quoted = qr/"(?:\\.|[^"\\])*"/s;
    my $prefix = qr/\.[A-Za-z_]\w*\??(?:\.[A-Za-z_]\w*\??)*/s;
    my $quoted_end = qr/(?:\[\s*$quoted\s*\]\??|\.$quoted\??)?/s;
    my $numeric = qr/\[\s*-?\d+\s*\]\??\s*/s;
    my $single = qr/$prefix$quoted_end\s*(?:$numeric){0,4}/s;
    my $paired = qr/$prefix$quoted_end\s*(?:$numeric)?/s;

    return qr/(?:\.\[\s*$single\s*\]\??\[\s*\]\??|\.(?:\[\s*$paired\s*\]\??\s*){2,4}\[\s*\]\??)/s;
}

sub _has_scoped_computed_recurse_child {
    my ($child_filter) = @_;
    return 0 unless defined $child_filter;
    my $path = _v3_scoped_computed_recurse_pattern();
    return $child_filter =~ /\A$path\s*(?:\||\z)/s ? 1 : 0;
}

sub _is_nested_scoped_computed_recurse {
    my ($expression) = @_;
    return 0 unless defined $expression;
    my $path = _v3_scoped_computed_recurse_pattern();
    return $expression =~ /\(\s*recurse\(\s*$path\s*\|/s ? 1 : 0;
}

# A custom recurse child filter may itself emit comma or pipeline streams.
# Visit each child immediately, including its descendants, before requesting
# the next sibling.  A successful downstream result propagates a stop signal
# all the way up, so an unused sibling's error or unbounded range is skipped.
# This deliberately uses recursion only for the custom-filter case.
sub _visit_update_rhs_recurse_filtered {
    my ($self, $current, $child_filter, $accept) = @_;

    return 1 if $accept->($current);

    # A null node is already emitted above. Optional/custom child
    # filters may stop at null, but strict .[] must still attempt
    # expansion: jq raises an iteration error *after* emitting null.
    # |= short-circuits at the accepted first output before reaching
    # this expansion, so existing first-result semantics are retained.
    # A strict named-field iterator must attempt expansion even after
    # emitting a null node. Its field lookup produces null, and the
    # following strict [] then raises (unlike []?). Keep the optional
    # and other custom-filter null short-circuit unchanged.
    my $strict_named_iterator = $child_filter =~
        /\A\.(?:[A-Za-z_]\w*|\[\s*"(?:\\.|[^"\\])*"\s*\]|"(?:\\.|[^"\\])*")\[\s*\]\s*(?:\||\z)/s;
    # .[.field][], .[.cfg.key][]?, .[.cfg["selected"]][]?,
    # .[.cfg."selected"][]?, .[.keys[0]][]?, and
    # .[.cfg.names[0][0]][]?, and .[.cfg["names"][0][0]][]?
    # and two simple or quoted computed stages like
    # .[.cfg["first"][0]][.cfg."second"[-1]][]? evaluate on null nodes. A null
    # computed key raises before optional child iteration can run.
    # The final scoped branch permits two or three selectors.
    # Keep strict and optional child iteration semantics unchanged.
    # Other optional/custom children keep their null short-circuit.
    my $computed_child_iterator =
        _has_scoped_computed_recurse_child($child_filter);
    return 0 if !defined($current)
        && $child_filter !~ /\A\.\[\s*\]\z/
        && !$strict_named_iterator
        && !$computed_child_iterator;

    return _visit_update_rhs_results($self, $current, $child_filter, sub {
        my ($child) = @_;
        return _visit_update_rhs_recurse_filtered(
            $self, $child, $child_filter, $accept
        );
    });
}

# Delete only an existing leaf; do not create containers along the path.
# Array deletion must splice (shifting later elements), not replace with null.
sub _delete_update_assignment_path {
    my ($root, $segments) = @_;

    my $cursor = $root;
    for my $i (0 .. $#$segments - 1) {
        my $segment = $segments->[$i];
        if ($segment->{type} eq 'key') {
            return unless ref($cursor) eq 'HASH'
                && exists $cursor->{$segment->{value}};
            $cursor = $cursor->{$segment->{value}};
        }
        else {
            return unless ref($cursor) eq 'ARRAY';
            my $index = _normalize_path_array_index(
                $segment->{value}, scalar @$cursor
            );
            return if $index < 0 || $index > $#$cursor;
            $cursor = $cursor->[$index];
        }
        return unless defined $cursor;
    }

    my $last = $segments->[-1];
    if ($last->{type} eq 'key') {
        delete $cursor->{$last->{value}} if ref($cursor) eq 'HASH';
    }
    elsif (ref($cursor) eq 'ARRAY') {
        my $index = _normalize_path_array_index(
            $last->{value}, scalar @$cursor
        );
        splice(@$cursor, $index, 1) if $index >= 0 && $index <= $#$cursor;
    }
}

# Evaluate iterator steps recursively in a simple literal path. Both arrays
# and objects may be visited at each step. Computed/quoted paths and streaming
# path engines need a separate audit under #626.
sub _apply_container_iterator_update_assignment {
    my ($self, $input, $path, $rhs) = @_;

    my @parts = split /\[\]/, $path, -1;
    unless (@parts >= 2
        && $path =~ /\A(?:[A-Za-z_]\w*|\[\d+\]|\[\])(?:\.[A-Za-z_]\w*|\[\d+\]|\[\])*\z/)
    {
        die JQ::Lite::Error::Parse->new(
            message => 'Update assignment requires simple field/index/iterator paths'
        );
    }
    # Split at the first iterator only.  The remaining suffix keeps its
    # iterators so _apply_update_assignment recursively handles the next one
    # within each originally selected member (including special object keys).
    my $prefix = shift @parts;
    my $suffix = join '[]', @parts;

    my $root = _clone_for_assignment($input);
    my $selected = length($prefix)
        ? _get_path_value($root, $prefix)
        : $root;

    unless (ref($selected) eq 'ARRAY' || ref($selected) eq 'HASH') {
        die JQ::Lite::Error::Evaluation->new(
            message => 'Cannot iterate over non-array/object update target'
        );
    }

    if (ref($selected) eq 'HASH') {
        # Iterate the existing keys, not synthetic dotted paths: JSON object
        # keys may contain dots, spaces, brackets, or be the empty string.
        # Each member recursively processes any remaining iterator suffix.
        # Sort for deterministic execution; RHS filters which depend on key
        # evaluation order are outside this scoped implementation.
        my $relative = $suffix;
        $relative =~ s/^\.//;
        for my $key (sort keys %$selected) {
            if (length $relative) {
                # The suffix is a normal simple field/index path evaluated
                # relative to the selected object's old member value.
                $selected->{$key} = _apply_update_assignment(
                    $self, $selected->{$key}, $relative, $rhs
                );
                next;
            }

            my $old = _clone_for_assignment($selected->{$key});
            my ($found, $replacement)
                = _first_update_rhs_result($self, $old, $rhs);
            if ($found) {
                $selected->{$key} = _clone_for_assignment($replacement);
            }
            else {
                # No RHS values means deletion; unlike array deletion, this
                # does not shift any other key's position.
                delete $selected->{$key};
            }
        }
        return $root;
    }

    # Starting from the highest original array index keeps lower index paths
    # stable when an RHS emits no values and deletes the selected element.
    # Every concrete update continues to use the original leaf as its RHS
    # input; later updates to higher indices cannot change that leaf.
    for (my $index = $#$selected; $index >= 0; --$index) {
        my $concrete = $prefix . "[$index]" . $suffix;
        $root = _apply_update_assignment($self, $root, $concrete, $rhs);
    }
    return $root;
}

sub _apply_assignment {
    my ($self, $item, $path, $value_spec, $operator) = @_;

    # The legacy setter only supports literal numeric brackets. Reject
    # other selectors or suffixes after a numeric bracket before the
    # parser can silently assign a truncated prefix or a synthetic key.
    if (defined($path) &&
        ($path =~ /\[(?!-?\d+\])/ || $path =~ /\[-?\d+\](?![.\[]|\z)/)) {
        die JQ::Lite::Error::Evaluation->new(
            message => 'Plain/compound assignment requires literal numeric indices'
        );
    }

    return $item unless defined $item;
    return $item unless defined $path && length $path;

    $operator //= '=';

    my $value = _resolve_assignment_value($self, $item, $value_spec);

    if ($operator ne '=') {
        my $current = _clone_for_assignment(_get_path_value($item, $path));
        my $current_num = _coerce_number($current);
        my $value_num   = _coerce_number($value);

        return $item unless defined $current_num && defined $value_num;

        my $result;
        if ($operator eq '+=') {
            $result = $current_num + $value_num;
        }
        elsif ($operator eq '-=') {
            $result = $current_num - $value_num;
        }
        elsif ($operator eq '*=') {
            $result = $current_num * $value_num;
        }
        elsif ($operator eq '/=') {
            return $item if $value_num == 0;
            $result = $current_num / $value_num;
        }
        else {
            return $item;
        }

        $value = $result;
    }

    _set_path_value($item, $path, $value);

    return $item;
}

sub _get_path_value {
    my ($target, $path) = @_;

    return undef unless defined $target;
    return undef unless defined $path && length $path;

    my @segments = _parse_path_segments($path);
    return undef unless @segments;

    my $cursor = $target;
    for my $index (0 .. $#segments) {
        my $segment = $segments[$index];
        my $is_last = ($index == $#segments);

        if ($segment->{type} eq 'key') {
            return undef unless ref $cursor eq 'HASH';
            my $key = $segment->{value};

            return $cursor->{$key} if $is_last;

            return undef unless exists $cursor->{$key};
            $cursor = $cursor->{$key};
            next;
        }

        if ($segment->{type} eq 'index') {
            return undef unless ref $cursor eq 'ARRAY';

            my $numeric = _normalize_path_array_index($segment->{value}, scalar @$cursor);

            return undef if $numeric < 0 || $numeric > $#$cursor;

            return $cursor->[$numeric] if $is_last;

            $cursor = $cursor->[$numeric];
            next;
        }
    }

    return undef;
}

sub _coerce_number {
    my ($value) = @_;

    return 0 if !defined $value;

    if (JSON::PP::is_bool($value)) {
        return $value ? 1 : 0;
    }

    return 0 + $value if looks_like_number($value);

    return undef;
}

sub _resolve_assignment_value {
    my ($self, $item, $value_spec) = @_;

    return undef unless defined $value_spec;

    if ($value_spec->{type} && $value_spec->{type} eq 'path') {
        my $path = $value_spec->{value} // '';
        $path =~ s/^\.//;

        my @values = _traverse($item, $path);
        return _clone_for_assignment($values[0]);
    }

    if ($value_spec->{type} && $value_spec->{type} eq 'expression') {
        my $expr = $value_spec->{value} // '';

        my ($values, $ok) = _evaluate_value_expression($self, $item, $expr);
        if ($ok) {
            return _clone_for_assignment(@$values ? $values->[0] : undef);
        }

        if (defined $self && $self->can('run_query')) {
            my @outputs = $self->run_query(_encode_json($item), $expr);
            return _clone_for_assignment($outputs[0]) if @outputs;
        }

        return _clone_for_assignment($expr);
    }

    return _clone_for_assignment($value_spec->{value});
}

sub _set_path_value {
    my ($target, $path, $value) = @_;

    return unless defined $target;

    my @segments = _parse_path_segments($path);
    return unless @segments;

    my $cursor = $target;
    for my $index (0 .. $#segments) {
        my $segment = $segments[$index];
        my $is_last = ($index == $#segments);

        if ($segment->{type} eq 'key') {
            return unless ref $cursor eq 'HASH';
            my $key = $segment->{value};

            if ($is_last) {
                $cursor->{$key} = $value;
                last;
            }

            if (!exists $cursor->{$key} || !defined $cursor->{$key}) {
                my $next = $segments[$index + 1];
                $cursor->{$key} = ($next->{type} eq 'index') ? [] : {};
            }

            $cursor = $cursor->{$key};
            next;
        }

        if ($segment->{type} eq 'index') {
            return unless ref $cursor eq 'ARRAY';

            my $numeric = _normalize_path_array_index($segment->{value}, scalar @$cursor);

            return if $numeric < 0;

            if ($is_last) {
                $cursor->[$numeric] = $value;
                last;
            }

            if (!defined $cursor->[$numeric]) {
                my $next = $segments[$index + 1];
                $cursor->[$numeric] = ($next->{type} eq 'index') ? [] : {};
            }

            $cursor = $cursor->[$numeric];
            next;
        }
    }

    return;
}

sub _normalize_path_array_index {
    my ($idx, $array_size) = @_;

    my $numeric = int($idx);
    if ($idx =~ /^-?\d+$/) {
        $numeric += $array_size if $numeric < 0;
    }

    return $numeric;
}

sub _parse_path_segments {
    my ($path) = @_;

    $path //= '';
    $path =~ s/^\s+|\s+$//g;

    my @segments;
    for my $chunk (split /\./, $path) {
        next if $chunk eq '';

        while (length $chunk) {
            if ($chunk =~ s/^\[(\-?\d+)\]//) {
                push @segments, { type => 'index', value => $1 };
                next;
            }

            if ($chunk =~ s/^([^\[]+)//) {
                push @segments, { type => 'key', value => $1 };
                next;
            }

            last;
        }
    }

    return @segments;
}

sub _clone_for_assignment {
    my ($value) = @_;

    return undef unless defined $value;
    return $value unless ref $value;

    my $json = _encode_json($value);
    return _decode_json($json);
}

sub _map {
    my ($self, $data, $filter) = @_;

    if (ref $data ne 'ARRAY') {
        warn "_map expects array reference";
        return ();
    }

    my @mapped;
    for my $item (@$data) {
        push @mapped, $self->run_query(_encode_json($item), $filter);
    }

    return @mapped;
}

sub _apply_quantifier {
    my ($self, $value, $expr, $all) = @_;

    my $is_array = ref $value eq 'ARRAY';
    my @items = $is_array ? @$value : ($value);

    # An empty array is vacuously true for all(), false for any().
    return $all ? JSON::PP::true : JSON::PP::false
        if $is_array && !@items;

    for my $item (@items) {
        my @evaluated = defined $expr
            ? $self->run_query(_encode_json($item), $expr)
            : ($item);

        if ($all) {
            # Preserve the v2 rule: a nonempty input element with no
            # expression outputs makes all(expr) false.
            return JSON::PP::false unless @evaluated;
            return JSON::PP::false if grep { !_is_truthy($_) } @evaluated;
        }
        else {
            return JSON::PP::true if grep { _is_truthy($_) } @evaluated;
        }
    }

    return $all ? JSON::PP::true : JSON::PP::false;
}

sub _apply_all {
    return _apply_quantifier(@_, 1);
}

sub _apply_any {
    return _apply_quantifier(@_, 0);
}

sub _is_truthy {
    my ($value) = @_;

    return 0 unless defined $value;

    if (JSON::PP::is_bool($value)) {
        return $value ? 1 : 0;
    }

    if (ref $value eq 'ARRAY') {
        return @$value ? 1 : 0;
    }

    if (ref $value eq 'HASH') {
        return scalar(keys %$value) ? 1 : 0;
    }

    if (!ref $value) {
        return 0 if $value eq '';
        if (looks_like_number($value)) {
            return $value != 0 ? 1 : 0;
        }
        return 1;
    }

    return 1;
}

sub _apply_case_transform {
    my ($value, $mode) = @_;

    if (!defined $value) {
        return undef;
    }

    if (ref $value eq 'ARRAY') {
        return [ map { _apply_case_transform($_, $mode) } @$value ];
    }

    if (!ref $value) {
        return uc $value      if $mode eq 'upper';
        return lc $value      if $mode eq 'lower';
        return _to_titlecase($value);
    }

    return $value;
}

sub _apply_ascii_case_transform {
    my ($value, $mode) = @_;

    if (!defined $value) {
        return undef;
    }

    if (ref $value eq 'ARRAY') {
        return [ map { _apply_ascii_case_transform($_, $mode) } @$value ];
    }

    if (!ref $value) {
        my $copy = $value;
        if ($mode eq 'upper') {
            $copy =~ tr/a-z/A-Z/;
        }
        elsif ($mode eq 'lower') {
            $copy =~ tr/A-Z/a-z/;
        }
        return $copy;
    }

    return $value;
}

sub _to_titlecase {
    my ($value) = @_;

    my $result = lc $value;
    $result =~ s/(^|[^\p{L}\p{N}])(\p{L})/$1 . uc($2)/ge;
    return $result;
}

sub _apply_trim {
    my ($value) = @_;

    if (!defined $value) {
        return undef;
    }

    if (!ref $value) {
        my $copy = $value;
        $copy =~ s/^\s+//;
        $copy =~ s/\s+$//;
        return $copy;
    }

    if (ref $value eq 'ARRAY') {
        return [ map { _apply_trim($_) } @$value ];
    }

    return $value;
}

sub _apply_trimstr {
    my ($value, $needle, $mode) = @_;

    if (!defined $value) {
        return undef;
    }

    if (ref $value eq 'ARRAY') {
        return [ map { _apply_trimstr($_, $needle, $mode) } @$value ];
    }

    if (ref $value) {
        return $value;
    }

    return $value if !_is_string_scalar($value);

    $needle = '' unless defined $needle;
    my $target = "$value";
    my $pattern = "$needle";
    my $len = length $pattern;

    return $target if $len == 0;

    if ($mode eq 'left') {
        return $target if index($target, $pattern) != 0;
        return substr($target, $len);
    }

    if ($mode eq 'right') {
        return $target if $len > length($target);
        return $target unless substr($target, -$len) eq $pattern;
        return substr($target, 0, length($target) - $len);
    }

    return $target;
}

sub _apply_paths {
    my ($value) = @_;

    if (!ref $value || JSON::PP::is_bool($value)) {
        return [];
    }

    my @paths;
    _collect_paths($value, [], \@paths);
    return \@paths;
}

sub _apply_scalar_paths {
    my ($value) = @_;

    my @paths;
    _collect_scalar_paths($value, [], \@paths);
    return \@paths;
}

sub _apply_leaf_paths {
    my ($value) = @_;

    if (_is_leaf_value($value)) {
        return [ [] ];
    }

    my @paths;
    _collect_leaf_paths($value, [], \@paths);
    return \@paths;
}

sub _validate_path_array {
    my ($path, $caller) = @_;

    $caller //= 'getpath';

    die "$caller(): path must be an array" if ref($path) ne 'ARRAY';

    for my $segment (@$path) {
        my $is_boolean = ref($segment) && JSON::PP::is_bool($segment);

        die "$caller(): path elements must be defined" if !defined $segment;
        die "$caller(): path elements must be scalars" if ref($segment) && !$is_boolean;
    }

    return [ @$path ];
}

# Literal getpath/setpath operands share the same array validation.
# Stream-produced operands retain their separate legacy error/skip rules.
sub _validate_literal_paths {
    my ($decoded, $caller) = @_;

    die "$caller(): path must be an array" unless ref $decoded eq 'ARRAY';
    return map { _validate_path_array($_, $caller) } @$decoded
        if @$decoded && ref $decoded->[0] eq 'ARRAY';
    return (_validate_path_array($decoded, $caller));
}

sub _apply_getpath {
    my ($self, $value, $expr) = @_;

    return undef unless defined $value;

    $expr //= '';
    $expr =~ s/^\s+|\s+$//g;
    return undef if $expr eq '';

    my @paths;

    my $decoded = eval { _decode_json($expr) };
    if (!$@ && defined $decoded) {
        push @paths, _validate_literal_paths($decoded, 'getpath');
    }

    if (!@paths) {
        my @outputs = $self->run_query(_encode_json($value), $expr);
        for my $output (@outputs) {
            next unless defined $output;

            if (ref $output eq 'ARRAY') {
                if (@$output && ref $output->[0] eq 'ARRAY') {
                    for my $path (@$output) {
                        push @paths, _validate_path_array($path, 'getpath');
                    }
                }
                else {
                    push @paths, _validate_path_array($output, 'getpath');
                }
            }
            else {
                die 'getpath(): path must be an array';
            }
        }
    }

    return undef unless @paths;

    my @values = map { _traverse_path_array($value, $_) } @paths;
    return @values == 1 ? $values[0] : \@values;
}

sub _apply_setpath {
    my ($self, $value, $paths_expr, $value_expr) = @_;

    return $value unless defined $value;

    $paths_expr //= '';
    $paths_expr =~ s/^\s+|\s+$//g;
    return $value if $paths_expr eq '';

    my @paths = _resolve_paths_from_expr($self, $value, $paths_expr);
    return $value unless @paths;

    my $replacement = _evaluate_setpath_value($self, $value, $value_expr);
    my $result      = $value;

    for my $path (@paths) {
        $result = _set_value_at_path($result, [@$path], $replacement);
    }

    return $result;
}

sub _resolve_paths_from_expr {
    my ($self, $value, $expr) = @_;

    return () unless defined $expr;

    my $clean = $expr;
    $clean =~ s/^\s+|\s+$//g;
    return () if $clean eq '';

    my @paths;

    my $decoded = eval { _decode_json($clean) };
    if (!$@ && defined $decoded) {
        push @paths, _validate_literal_paths($decoded, 'setpath');
    }

    if (!@paths) {
        my @outputs = $self->run_query(_encode_json($value), $clean);
        for my $output (@outputs) {
            next unless defined $output;

            if (ref $output eq 'ARRAY') {
                if (@$output && ref $output->[0] eq 'ARRAY') {
                    push @paths, map { _validate_path_array($_, 'setpath') } @$output;
                }
                elsif (!@$output || !ref $output->[0]) {
                    push @paths, _validate_path_array($output, 'setpath');
                }
            }
            elsif (!ref $output || JSON::PP::is_bool($output)) {
                die 'setpath(): path must be an array';
            }
        }
    }

    return @paths;
}

sub _evaluate_setpath_value {
    my ($self, $context, $expr) = @_;

    return undef unless defined $expr;

    my $clean = $expr;
    $clean =~ s/^\s+|\s+$//g;
    return undef if $clean eq '';

    my $decoded = eval { _decode_json($clean) };
    if (!$@) {
        return $decoded;
    }

    if ($clean =~ /^'(.*)'$/) {
        my $text = $1;
        $text =~ s/\\'/'/g;
        return $text;
    }

    if ($clean =~ /^\.(.+)$/) {
        my $path = $1;
        my @values = _traverse($context, $path);
        return @values ? $values[0] : undef;
    }

    my @outputs = $self->run_query(_encode_json($context), $clean);
    return @outputs ? $outputs[0] : undef;
}

sub _set_value_at_path {
    my ($current, $path, $replacement) = @_;

    return _deep_clone($replacement) unless @$path;

    my ($segment, @rest) = @$path;

    if (ref $current eq 'HASH') {
        my $key = _coerce_hash_key($segment);
        return $current unless defined $key;

        my %copy = %$current;
        if (@rest) {
            my $next_value = exists $copy{$key} ? $copy{$key} : _guess_container_for_segment($rest[0]);
            $copy{$key} = _set_value_at_path($next_value, \@rest, $replacement);
        }
        else {
            $copy{$key} = _deep_clone($replacement);
        }

        return \%copy;
    }

    if (ref $current eq 'ARRAY') {
        my $index = _normalize_array_index_segment($segment, scalar @$current);
        return $current unless defined $index;

        my @copy = @$current;
        _ensure_array_length(\@copy, $index);

        if (@rest) {
            my $next_value = defined $copy[$index] ? $copy[$index] : _guess_container_for_segment($rest[0]);
            $copy[$index] = _set_value_at_path($next_value, \@rest, $replacement);
        }
        else {
            $copy[$index] = _deep_clone($replacement);
        }

        return \@copy;
    }

    my $container = _guess_container_for_segment($segment);
    return _set_value_at_path($container, $path, $replacement);
}

sub _coerce_hash_key {
    my ($segment) = @_;

    return undef if !defined $segment;

    if (JSON::PP::is_bool($segment)) {
        return $segment ? 'true' : 'false';
    }

    return undef if ref $segment;

    return "$segment";
}

sub _guess_container_for_segment {
    my ($segment) = @_;

    return [] if _is_numeric_segment($segment);
    return {};
}

sub _is_numeric_segment {
    my ($segment) = @_;

    return 0 if !defined $segment;

    if (JSON::PP::is_bool($segment)) {
        return 1;
    }

    return 0 if ref $segment;

    return ($segment =~ /^-?\d+$/) ? 1 : 0;
}

# Read and write share coercion and negative-index rules. Bounds stay
# caller-specific: get returns null past end; set may grow arrays.
sub _normalize_array_index_segment {
    my ($segment, $length) = @_;

    return undef if !defined $segment;

    if (JSON::PP::is_bool($segment)) {
        $segment = $segment ? 1 : 0;
    }

    return undef if ref $segment;
    return undef if $segment !~ /^-?\d+$/;

    my $index = int($segment);
    $index += $length if $index < 0;

    return undef if $index < 0;

    return $index;
}

sub _ensure_array_length {
    my ($array_ref, $index) = @_;

    return unless ref $array_ref eq 'ARRAY';

    while (@$array_ref <= $index) {
        push @$array_ref, undef;
    }
}

sub _collect_paths {
    my ($value, $current_path, $paths) = @_;

    if (ref $value eq 'HASH') {
        for my $key (sort keys %$value) {
            my $child = $value->{$key};
            my @next  = (@$current_path, $key);
            push @$paths, [@next];

            if (ref $child eq 'HASH' || ref $child eq 'ARRAY') {
                _collect_paths($child, \@next, $paths);
            }
        }
        return;
    }

    if (ref $value eq 'ARRAY') {
        for (my $index = 0; $index < @$value; $index++) {
            my $child = $value->[$index];
            my @next  = (@$current_path, $index);
            push @$paths, [@next];

            if (ref $child eq 'HASH' || ref $child eq 'ARRAY') {
                _collect_paths($child, \@next, $paths);
            }
        }
        return;
    }

    push @$paths, [@$current_path];
}

# Both public path enumerators walk container leaves identically. Preserve the
# historical internal scalar-root no-output contract; leaf_paths on the root
# intentionally differs and is handled by _apply_leaf_paths.
sub _collect_scalar_paths {
    my ($value) = @_;
    return if _is_leaf_value($value);
    return _collect_leaf_paths(@_);
}

sub _traverse_path_array {
    my ($value, $path) = @_;

    return undef unless defined $value;
    return $value unless defined $path;
    return $value if ref($path) ne 'ARRAY';

    my $cursor = $value;
    for my $segment (@$path) {
        return undef unless defined $cursor;

        if (ref $cursor eq 'HASH') {
            my $key = _coerce_hash_key($segment);
            return undef unless defined $key;
            return undef unless exists $cursor->{$key};
            $cursor = $cursor->{$key};
            next;
        }

        if (ref $cursor eq 'ARRAY') {
            my $index = _normalize_array_index_segment($segment, scalar @$cursor);
            return undef unless defined $index;

            return undef if $index > $#$cursor;

            $cursor = $cursor->[$index];
            next;
        }

        return undef;
    }

    return $cursor;
}

sub _collect_leaf_paths {
    my ($value, $current_path, $paths) = @_;

    if (ref $value eq 'HASH') {
        for my $key (sort keys %$value) {
            my $child = $value->{$key};
            my @next  = (@$current_path, $key);

            if (_is_leaf_value($child)) {
                push @$paths, [@next];
            }
            else {
                _collect_leaf_paths($child, \@next, $paths);
            }
        }
        return;
    }

    if (ref $value eq 'ARRAY') {
        for (my $index = 0; $index < @$value; $index++) {
            my $child = $value->[$index];
            my @next  = (@$current_path, $index);

            if (_is_leaf_value($child)) {
                push @$paths, [@next];
            }
            else {
                _collect_leaf_paths($child, \@next, $paths);
            }
        }
        return;
    }

    push @$paths, [@$current_path];
}

sub _is_leaf_value {
    my ($value) = @_;

    return 1 unless ref $value;
    return 1 if JSON::PP::is_bool($value);
    return 0 if ref($value) eq 'ARRAY';
    return 0 if ref($value) eq 'HASH';
    return 1;
}

1;
