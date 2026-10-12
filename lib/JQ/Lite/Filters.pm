package JQ::Lite::Filters;

use strict;
use warnings;

use List::Util qw(sum min);
use Scalar::Util qw(looks_like_number);
use JQ::Lite::Util ();
use JQ::Lite::Value ();
use JQ::Lite::Builtin ();

sub apply {
    my ($self, $part, $results_ref, $out_ref) = @_;

    my @results = @$results_ref;
    my @next_results;

    my $normalized = JQ::Lite::Util::_strip_wrapping_parens($part);

    # Whitespace immediately before an audited dotted suffix belongs
    # to the same literal path, e.g. .items[0] .name or .items[] .name.
    # Only complete rooted paths use the ordered v3 visitor; a bare
    # ". name" remains outside this syntax.
    if ($normalized =~ /\s+\.(?:[A-Za-z_]|"|\[)/
        && JQ::Lite::Util::_parse_v3_literal_iterator_path($normalized))
    {
        return 0;
    }

    # New whitespace forms of [] / []? must enter the ordered v3
    # path visitor, not legacy arithmetic/array-expression shortcuts.
    # The entire rooted path must parse: 'try [ ]' and bare [ ] are
    # array expressions, not literal iterator paths.
    if ($normalized =~ /\[\s+\]|\s+\[\s*\]/
        && JQ::Lite::Util::_parse_v3_literal_iterator_path($normalized))
    {
        return 0;
    }

    # A full literal numeric path can also contain whitespace before
    # the bracket: . [0], .items [ 0 ], or .items[0] [1].
    # Keep this check before legacy numeric/arithmetic shortcuts.
    # Do not match bare array constructors or nonliteral bracket forms.
    if ($normalized =~ /\s+\[\s*-?\d+\s*\]/
        && JQ::Lite::Util::_parse_v3_literal_iterator_path($normalized))
    {
        return 0;
    }

    # jq allows spaces inside literal numeric brackets: [ 0 ], [-1 ],
    # and [ 0 ]?. Route only fully parsed literal paths to the
    # ordered visitor, before legacy index/value-expression shortcuts.
    # Bare [ 0 ] constructors and arithmetic/slice brackets are excluded.
    if ($normalized =~ /\[(?:\s+-?\d+\s*|-?\d+\s+)\]/
        && JQ::Lite::Util::_parse_v3_literal_iterator_path($normalized))
    {
        return 0;
    }

    # Standalone strict positive literal numeric stages use the ordered
    # v3 visitor for index type errors, null propagation and subsequent
    # strict suffixes. Require a fully parsed literal path rather than
    # routing arbitrary computed bracket expressions.
    if ($normalized =~ /\[\d+\]/
        && JQ::Lite::Util::_parse_v3_literal_iterator_path($normalized))
    {
        return 0;
    }

    # Strict signed negative literal indices also need the scoped v3
    # visitor even without an iterator or optional step. Legacy
    # arithmetic/field shortcuts can mistake [-N] for subtraction or
    # return null rather than an indexed value. Require a complete
    # recognized path, not merely a bracket fragment.
    if ($normalized =~ /\[-[1-9]\d*\]/
        && JQ::Lite::Util::_parse_v3_literal_iterator_path($normalized))
    {
        return 0;
    }

    # Standalone optional literal named-field paths must reach the
    # scoped visitor before legacy path/value shortcuts. A full parser
    # match keeps arbitrary expressions and other '?' uses untouched.
    if (index($normalized, '?') >= 0
        && JQ::Lite::Util::_parse_v3_literal_iterator_path($normalized))
    {
        return 0;
    }

    # Standalone optional literal numeric paths are also scoped to the
    # ordered v3 visitor. Without this guard, the legacy value-expression
    # shortcut can convert .[0]? or .items[0]? into null instead of
    # emitting no results on scalar/object index targets. Match only
    # complete, audited paths, not arbitrary []-based expressions.
    if ($normalized =~ /\[-?\d+\]\?/
        && JQ::Lite::Util::_parse_v3_literal_iterator_path($normalized))
    {
        return 0;
    }

    # Root and intermediate simple computed selectors also allow
    # whitespace before the bracket: . [.key], .obj [ .key ].
    # Require the *complete rooted literal path* before bypassing
    # expression handling. In particular, try [.key] and bare [.key]
    # are array constructors and not computed path selectors.
    if ($normalized =~ /\s+\[\s*\./
        && JQ::Lite::Util::_parse_v3_literal_iterator_path($normalized))
    {
        return 0;
    }

    # A root .[.key] selector is a computed *path*, not an ordinary
    # bracket expression.  Let the scoped v3 visitor resolve the selector
    # against each current input before the legacy expression shortcuts
    # turn it into a null or malformed lookup.  A complete simple
    # computed-root path is required: arbitrary jq expressions stay here.
    # Numeric/quoted nested selector steps also need this bypass, e.g.
    # .[.[0]], or the legacy root-bracket shortcut returns null.
    if ($normalized =~ /\A\.\[\s*\./
        && JQ::Lite::Util::_parse_v3_literal_iterator_path($normalized))
    {
        return 0;
    }

    # A computed selector following a literal field or iterator, as in
    # .obj[.key] or .items[][.key], must be evaluated in the original
    # filter context. Route only complete, scoped path expressions to the
    # v3 visitor, including optional selector fields; arbitrary computed
    # expressions keep the legacy path.
    if ($normalized =~ /\[\s*\./
        && JQ::Lite::Util::_parse_v3_literal_iterator_path($normalized))
    {
        return 0;
    }

    # Legacy filter shortcuts can mistake quoted-key iterator paths for
    # arithmetic, assignment, or a root bracket expression when the key
    # contains punctuation such as '=', '|=', or a literal dot.  Yield
    # *complete, recognized quoted literal iterator paths* to the scoped
    # v3 runtime visitor before those shortcuts.  Bare quoted lookups and
    # computed expressions remain on their original evaluation paths.
    if (index($normalized, '"') >= 0
        && JQ::Lite::Util::_parse_v3_literal_iterator_path($normalized))
    {
        return 0;
    }

    # v3 update assignment must run before expression/arithmetic shortcuts.
    # The RHS is a filter on the *old target value*, not the input root.
    if (index($normalized, '|=') >= 0) {
        my ($path, $spec, $operator, $rhs)
            = JQ::Lite::Util::_parse_assignment_expression($normalized);
        if ($operator ne '|=' || $normalized !~ /^\s*\./
            || !defined($rhs) || $rhs !~ /\S/)
        {
            die JQ::Lite::Error::Parse->new(
                message => 'Invalid update-assignment syntax'
            );
        }

        @next_results = map {
            JQ::Lite::Util::_apply_update_assignment($self, $_, $path, $rhs)
        } @results;

        @$out_ref = @next_results;
        return 1;
    }

        my @sequence_parts = JQ::Lite::Util::_split_top_level_commas($normalized);
        if (@sequence_parts > 1) {
            @next_results = ();

            for my $item (@results) {
                my $json = JQ::Lite::Util::_encode_json($item);

                for my $segment (@sequence_parts) {
                    next unless defined $segment;
                    my $filter = $segment;
                    $filter =~ s/^\s+|\s+$//g;
                    $filter = JQ::Lite::Util::_strip_wrapping_parens($filter);
                    next if $filter eq '';

                    # An audited ordered iterator/computed path must
                    # run through the scoped path visitor, not the
                    # legacy expression shortcut. In comma alternatives
                    # that shortcut can return an incorrect null for
                    # e.g. .items[][0]? before the visitor sees it.
                    if ($filter !~ /^\s*[\[{(]/
                        && !JQ::Lite::Util::_parse_v3_literal_iterator_path($filter))
                    {
                        my ($values, $ok) = JQ::Lite::Util::_evaluate_value_expression($self, $item, $filter);
                        if ($ok) {
                            if (@$values) {
                                push @next_results, @$values;
                                next;
                            }
                            # fall through to the full evaluator when the shortcut produced no
                            # values so we don't accidentally drop a legitimate branch
                        }
                    }

                    my @outputs = $self->run_query($json, $filter);
                    push @next_results, @outputs;
                }
            }

            @$out_ref = @next_results;
            return 1;
        }

        # support for variable references like $var or $var.path
        if ($normalized =~ /^\$(\w+)(.*)$/s) {
            my ($var_name, $suffix) = ($1, $2 // '');
            for my $item (@results) {
                my @values = JQ::Lite::Util::_evaluate_variable_reference($self, $var_name, $suffix);
                if (@values) {
                    push @next_results, @values;
                } else {
                    push @next_results, undef;
                }
            }
            @$out_ref = @next_results;
            return 1;
        }

        # support for binding the current value to a variable: . as $x | ...
        if ($normalized =~ /^as\s+\$(\w+)$/) {
            my $var_name = $1;
            @next_results = ();

            for my $item (@results) {
                $self->{_vars}{$var_name} = $item;
                push @next_results, $item;
            }

            @$out_ref = @next_results;
            return 1;
        }

        if ($normalized =~ /^try\b/) {
            my $body = $normalized;
            $body =~ s/^try\s*//;

            my ($try_expr, $catch_expr) = ($body, '');

            my %pairs = (
                '(' => ')',
                '[' => ']',
                '{' => '}',
            );
            my %closing = reverse %pairs;

            my @stack;
            my $string;
            my $escape = 0;
            my $catch_index = undef;
            my $nested_try_depth = 0;
            for (my $i = 0; $i < length $body; $i++) {
                my $ch = substr($body, $i, 1);

                if (defined $string) {
                    if ($escape) {
                        $escape = 0;
                        next;
                    }

                    if ($ch eq '\\') {
                        $escape = 1;
                        next;
                    }

                    if ($ch eq $string) {
                        undef $string;
                    }

                    next;
                }

                if ($ch eq "'" || $ch eq '"') {
                    $string = $ch;
                    next;
                }

                if (exists $pairs{$ch}) {
                    push @stack, $ch;
                    next;
                }

                if (exists $closing{$ch}) {
                    last unless @stack;
                    my $open = pop @stack;
                    last unless $pairs{$open} eq $ch;
                    next;
                }

                next if @stack;

                if (substr($body, $i) =~ /^try\b/) {
                    if ($i > 0) {
                        my $prev = substr($body, $i - 1, 1);
                        next unless $prev =~ /[\s\(\[\{\|,]/;
                    }
                    $nested_try_depth++;
                    next;
                }

                if (substr($body, $i) =~ /^catch\b/) {
                    if ($i > 0) {
                        my $prev = substr($body, $i - 1, 1);
                        next unless $prev =~ /[\s\)\]\}\|,]/;
                    }

                    if ($nested_try_depth > 0) {
                        $nested_try_depth--;
                        next;
                    }

                    $catch_index = $i;
                    last;
                }
            }

            if (defined $catch_index) {
                $try_expr   = substr($body, 0, $catch_index);
                $catch_expr = substr($body, $catch_index + 5);
            }

            $try_expr   = JQ::Lite::Util::_strip_wrapping_parens($try_expr // '');
            $catch_expr = JQ::Lite::Util::_strip_wrapping_parens($catch_expr // '');
            $catch_expr =~ s/^\s+// if defined $catch_expr;

            @next_results = ();

            VALUE: for my $value (@results) {
                my $json   = JQ::Lite::Util::_encode_json($value);
                my @outputs;
                my $error;

                # jq retains the outputs of completed comma branches
                # before a later branch fails inside try. The evaluator
                # returns eagerly, so evaluate each top-level alternative
                # independently and retain its completed output stream.
                # This does not preserve partial output from a failure
                # within one branch (general streaming is a separate audit).
                for my $branch (JQ::Lite::Util::_split_top_level_commas($try_expr)) {
                    my @branch_outputs;
                    {
                        local $@;
                        eval {
                            # A leading root/named-field iterator (or
                            # multiple nested iterators) can supply several
                            # pipeline inputs or be a bare nested try
                            # expression. Visit each member in depth-first
                            # source order; retain earlier completed
                            # results if a subsequent member fails.
                            # Simple range(...) and default/optional
                            # recurse generators reuse existing on-demand
                            # visitors; strict recurse(.[]) has a scoped
                            # yield-then-expand visitor, and custom recurse
                            # child filters use the update-RHS visitor.
                            # Other paths and failing leaf filters stay eager.
                            my $unwrapped =
                                JQ::Lite::Util::_strip_wrapping_parens($branch);
                            my @stages =
                                JQ::Lite::Util::_split_top_level_pipes($unwrapped);

                            # Fully parenthesized comma stages, including
                            # consecutive stages, retain each completed
                            # alternative's downstream output before trying
                            # the next one. Prefixes and individual filter
                            # leaves retain their existing eager evaluator.
                            my @pipeline_comma_parts;
                            if (@stages > 1) {
                                for (my $i = 1; $i < @stages; $i++) {
                                    next unless $stages[$i] =~ /\A\s*\(/s;
                                    my $inner =
                                        JQ::Lite::Util::_strip_wrapping_parens(
                                            $stages[$i]
                                        );
                                    my @alternatives =
                                        JQ::Lite::Util::_split_top_level_commas(
                                            $inner
                                        );
                                    if (@alternatives > 1) {
                                        @pipeline_comma_parts = @alternatives;
                                        last;
                                    }
                                }
                            }
                            my $emit_tail = sub {
                                my ($tail_json, $tail) = @_;
                                my @parts =
                                    JQ::Lite::Util::_split_top_level_pipes($tail);
                                my ($comma_index, @alternatives);
                                for (my $i = 0; $i < @parts; $i++) {
                                    next unless $parts[$i] =~ /\A\s*\(/s;
                                    my $inner =
                                        JQ::Lite::Util::_strip_wrapping_parens(
                                            $parts[$i]
                                        );
                                    my @candidates =
                                        JQ::Lite::Util::_split_top_level_commas(
                                            $inner
                                        );
                                    if (@candidates > 1) {
                                        $comma_index = $i;
                                        @alternatives = @candidates;
                                        last;
                                    }
                                }
                                # Iterative continuation stack keeps
                                # outputs in jq's depth-first stream order
                                # across multiple comma stages. Each stage
                                # is evaluated only after the preceding
                                # alternative's entire suffix completes.
                                # This also avoids a self-capturing closure.
                                my @pending = (
                                    ['pipeline', $tail_json, $tail]
                                );
                                while (@pending) {
                                    my $task = pop @pending;
                                    if ($task->[0] eq 'alternative') {
                                        my ($kind, $stage_json, $alternative,
                                            $suffix) = @$task;
                                        my @values = $self->run_query(
                                            $stage_json, $alternative
                                        );
                                        if (length $suffix) {
                                            push @pending, map {
                                                ['pipeline',
                                                    JQ::Lite::Util::_encode_json($_),
                                                    $suffix]
                                            } reverse @values;
                                        }
                                        else {
                                            push @branch_outputs, @values;
                                        }
                                        next;
                                    }

                                    my ($kind, $input_json, $remaining) = @$task;
                                    my @parts =
                                        JQ::Lite::Util::_split_top_level_pipes(
                                            $remaining
                                        );
                                    my ($comma_index, @alternatives);
                                    for (my $i = 0; $i < @parts; $i++) {
                                        next unless $parts[$i] =~ /\A\s*\(/s;
                                        my $inner =
                                            JQ::Lite::Util::_strip_wrapping_parens(
                                                $parts[$i]
                                            );
                                        my @candidates =
                                            JQ::Lite::Util::_split_top_level_commas(
                                                $inner
                                            );
                                        if (@candidates > 1) {
                                            $comma_index = $i;
                                            @alternatives = @candidates;
                                            last;
                                        }
                                    }
                                    if (!defined $comma_index) {
                                        push @branch_outputs,
                                            $self->run_query(
                                                $input_json, $remaining
                                            );
                                        next;
                                    }

                                    my @prefix = $comma_index > 0
                                        ? @parts[0 .. $comma_index - 1] : ();
                                    my @suffix = $comma_index < $#parts
                                        ? @parts[$comma_index + 1 .. $#parts]
                                        : ();
                                    my @prefix_values = @prefix
                                        ? $self->run_query(
                                            $input_json, join(' | ', @prefix)
                                        )
                                        : ();
                                    my @input_jsons = @prefix
                                        ? map {
                                            JQ::Lite::Util::_encode_json($_)
                                        } @prefix_values
                                        : ($input_json);
                                    my $suffix = join(' | ', @suffix);
                                    # LIFO: push inputs and alternatives
                                    # in reverse, but evaluate them in
                                    # original left-to-right order.
                                    for my $stage_json (reverse @input_jsons) {
                                        push @pending, map {
                                            ['alternative',
                                                $stage_json, $_, $suffix]
                                        } reverse @alternatives;
                                    }
                                }
                            };

                            # A parenthesized comma expression can
                            # generate multiple inputs for one pipeline,
                            # for example (0, 1/0) | . + 1. Run its
                            # alternatives in source order so a later
                            # failing alternative cannot erase outputs
                            # from earlier completed alternatives.
                            my @comma_head_parts;
                            if (@stages > 1) {
                                my $head = $stages[0];
                                my $inner =
                                    JQ::Lite::Util::_strip_wrapping_parens($head);
                                if ($inner ne $head) {
                                    @comma_head_parts =
                                        JQ::Lite::Util::_split_top_level_commas(
                                            $inner
                                        );
                                }
                            }
                            my @iterator_heads;
                            if (@stages) {
                                my $head = $stages[0];
                                if (@stages > 1 && $head =~
                                    /\A\s*\.(?:\[\s*\]|[A-Za-z_]\w*\[\s*\])\??\s*\z/s)
                                {
                                    @iterator_heads = ($head);
                                }
                                elsif ($head =~
                                    /\A\s*(\.(?:\[\s*\]|[A-Za-z_]\w*\[\s*\])\??)((?:\[\s*\]\??)+)\s*\z/s)
                                {
                                    # A simple iterator head can contain
                                    # two or more nested stages, e.g.
                                    # .[][][], .items[][], or .[][][]?.
                                    # Split only complete literal suffixes:
                                    # evaluate every level independently,
                                    # so a later inner error cannot erase
                                    # already completed member outputs.
                                    my ($first, $suffixes) = ($1, $2);
                                    @iterator_heads = ($first);
                                    while ($suffixes =~ /(\[\s*\]\??)/g) {
                                        push @iterator_heads, '.' . $1;
                                    }
                                }
                            }
                            if (@comma_head_parts > 1) {
                                shift @stages;
                                my $tail = join(' | ', @stages);
                                for my $alternative (@comma_head_parts) {
                                    # A completed alternative is a stream.
                                    # Feed each emitted value through the
                                    # tail immediately, before attempting
                                    # the next alternative. Exceptions
                                    # propagate to the surrounding try.
                                    my @head_values = $self->run_query(
                                        $json, $alternative
                                    );
                                    for my $head_value (@head_values) {
                                        $emit_tail->(
                                            JQ::Lite::Util::_encode_json(
                                                $head_value
                                            ),
                                            $tail
                                        );
                                    }
                                }
                            }
                            elsif (@stages > 1 && $stages[0] =~
                                /\A\s*range\(([^()]*)\)\s*\z/s)
                            {
                                # Reuse the update-RHS range visitor to
                                # generate each number on demand. A later
                                # tail error terminates this visitor before
                                # generating unused numbers, while retaining
                                # outputs from already completed numbers.
                                # Scope this to simple range(...) heads;
                                # more complex argument filters need their
                                # own semantic audit.
                                my @args =
                                    JQ::Lite::Util::_parse_range_arguments($1);
                                shift @stages;
                                my $tail = join(' | ', @stages);
                                JQ::Lite::Util::_visit_range_sequence(
                                    \@args, sub {
                                        my ($number) = @_;
                                        $emit_tail->(
                                            JQ::Lite::Util::_encode_json($number),
                                            $tail
                                        );
                                        return 0;
                                    }
                                );
                            }
                            elsif (@stages > 1 && $stages[0] =~
                                /\A\s*recurse(?:\(\s*(\.\[\s*\]\?)\s*\))?\s*\z/s)
                            {
                                # Reuse the update RHS depth-first recurse
                                # visitor for the default generator and its
                                # optional child iterator, recurse(.[]?).
                                # Pass each emitted value directly to the
                                # remaining try pipeline before expanding
                                # any unneeded descendants. A later tail
                                # error leaves earlier completed outputs
                                # intact and stops traversal immediately.
                                my $child_filter = defined($1) ? $1 : undef;
                                shift @stages;
                                my $tail = join(' | ', @stages);
                                JQ::Lite::Util::_visit_update_rhs_recurse(
                                    $self, $value, $child_filter, sub {
                                        my ($recur_value) = @_;
                                        $emit_tail->(
                                            JQ::Lite::Util::_encode_json($recur_value),
                                            $tail
                                        );
                                        return 0;
                                    }
                                );
                            }
                            elsif (@stages && $stages[0] =~
                                /\A\s*recurse\(\s*\.\[\s*\]\s*\)\s*\z/s)
                            {
                                # Strict recurse(.[]) yields the current
                                # node before attempting its child iterator.
                                # A scalar/null leaf therefore remains a
                                # completed output, then triggers an error
                                # when its strict .[] expansion is required.
                                # An explicit iterative enter/expand stack
                                # preserves that jq order and avoids adding
                                # call-stack depth for nested arrays.
                                shift @stages;
                                my $tail = @stages
                                    ? join(' | ', @stages) : '.';
                                my @pending = ([$value, 0]);
                                while (@pending) {
                                    my ($node, $expand) = @{ pop @pending };
                                    my $node_json =
                                        JQ::Lite::Util::_encode_json($node);
                                    if (!$expand) {
                                        $emit_tail->($node_json, $tail);
                                        push @pending, [$node, 1];
                                        next;
                                    }
                                    my @children = $self->run_query(
                                        $node_json, '.[]'
                                    );
                                    push @pending, map {
                                        [$_, 0]
                                    } reverse @children;
                                }
                            }
                            elsif (@stages && $stages[0] =~
                                /\A\s*recurse\((.+)\)\s*\z/s)
                            {
                                # Custom recurse child filters have the
                                # same yield-then-expand ordering as jq.
                                # Reuse the existing update-RHS visitor:
                                # it evaluates each child filter output,
                                # recursively emits the child's subtree,
                                # and only then requests the next sibling.
                                # An error in the custom filter or tail
                                # keeps all previously completed results.
                                my $child_filter = $1;
                                $child_filter =~ s/^\s+|\s+$//g;
                                shift @stages;
                                my $tail = @stages
                                    ? join(' | ', @stages) : '.';
                                JQ::Lite::Util::_visit_update_rhs_recurse(
                                    $self, $value, $child_filter, sub {
                                        my ($node) = @_;
                                        $emit_tail->(
                                            JQ::Lite::Util::_encode_json($node),
                                            $tail
                                        );
                                        return 0;
                                    }
                                );
                            }
                            elsif (@iterator_heads) {
                                shift @stages;
                                # With no downstream pipeline, each nested
                                # iterator value is itself the final result.
                                # Evaluating a complete nested head eagerly
                                # used to yield synthetic null instead.
                                my $tail = @stages
                                    ? join(' | ', @stages) : '.';
                                # Explicit DFS stack retains stream order
                                # without a self-referential callback and
                                # stops before visiting later members when
                                # an inner iterator or tail raises an error.
                                my @pending = ([$value, 0]);
                                while (@pending) {
                                    my ($current, $depth) =
                                        @{ pop @pending };
                                    my $current_json =
                                        JQ::Lite::Util::_encode_json($current);
                                    if ($depth == @iterator_heads) {
                                        $emit_tail->($current_json, $tail);
                                        next;
                                    }
                                    my @members = $self->run_query(
                                        $current_json,
                                        $iterator_heads[$depth]
                                    );
                                    push @pending, map {
                                        [$_, $depth + 1]
                                    } reverse @members;
                                }
                            }
                            elsif (@pipeline_comma_parts > 1) {
                                # For a general non-generator head, feed
                                # its values to the streaming comma stage
                                # and its remaining downstream stages.
                                my $head = shift @stages;
                                my @head_values = $self->run_query(
                                    $json, $head
                                );
                                my $tail = join(' | ', @stages);
                                for my $head_value (@head_values) {
                                    $emit_tail->(
                                        JQ::Lite::Util::_encode_json($head_value),
                                        $tail
                                    );
                                }
                            }
                            else {
                                @branch_outputs = $self->run_query($json, $branch);
                            }
                            1;
                        } or $error = $@;
                    }
                    # A failed member leaves its preceding, already
                    # completed member results intact; do not discard
                    # those just because the branch later threw.
                    push @outputs, @branch_outputs;
                    last if $error;
                }

                if (!$error) {
                    push @next_results, @outputs;
                    next VALUE;
                }

                # Successful branches remain visible before a later
                # failure is dropped or replaced by a catch handler.
                push @next_results, @outputs;

                # Structured evaluation errors are blessed references.
                # Explicitly stringify before passing their diagnostics
                # as jq catch input or storing the legacy $error variable.
                my $message = "$error";
                $message =~ s/\s+$// if defined $message;

                if (defined $catch_expr && length $catch_expr) {
                    my %existing = %{ $self->{_vars} || {} };
                    local $self->{_vars} = { %existing, error => $message };

                    # A catch handler is a filter, so its result is a stream.
                    # Evaluating it through the scalar expression shortcut
                    # turned a legitimate empty result into JSON null.
                    # Running the filter directly preserves empty/null/false
                    # outputs and lets errors propagate to an enclosing try.
                    # jq evaluates a catch handler on the error message,
                    # not on the input which caused the failure. Preserve
                    # the historical $error variable as a compatibility
                    # alias, but use the message as the filter input.
                    my $error_json = JQ::Lite::Util::_encode_json($message);
                    my @catch_outputs = $self->run_query($error_json, $catch_expr);
                    push @next_results, @catch_outputs;

                    next VALUE;
                }

                # jq 1.7 defines 'try f' as 'try f catch empty'.
                # Without an explicit catch, an error drops only this
                # input's results; do not turn it into JSON null.
                # Explicit 'catch null' still emits a real null value.
                next VALUE;
            }

            @$out_ref = @next_results;
            return 1;
        }

        # Comparisons treat each operand as a filter evaluated against the
        # current input.  This is important after a pipe, where `length > 0`
        # must compare the length of the piped array rather than look for a
        # field named "length" on the original document.
        my ($comparison_lhs, $comparison_operator, $comparison_rhs)
            = JQ::Lite::Util::_split_top_level_comparison($normalized);
        if (defined($comparison_operator)
            && $comparison_lhs !~ /\b(?:if|then|elif|else|end|try|catch)\b/)
        {
            my ($lhs_expr, $operator, $rhs_expr)
                = ($comparison_lhs, $comparison_operator, $comparison_rhs);
            $lhs_expr =~ s/^\s+|\s+$//g;
            $rhs_expr =~ s/^\s+|\s+$//g;

            if (length($lhs_expr) && length($rhs_expr)) {
                @next_results = ();
                for my $item (@results) {
                    my $json = JQ::Lite::Util::_encode_json($item);
                    my ($lhs_values, $lhs_ok) = JQ::Lite::Util::_evaluate_value_expression($self, $item, $lhs_expr);
                    my ($rhs_values, $rhs_ok) = JQ::Lite::Util::_evaluate_value_expression($self, $item, $rhs_expr);
                    if (!$lhs_ok) {
                        my @values = $self->run_query($json, $lhs_expr);
                        $lhs_values = \@values;
                    }
                    if (!$rhs_ok) {
                        my @values = $self->run_query($json, $rhs_expr);
                        $rhs_values = \@values;
                    }

                    # A missing path participates in a comparison as null;
                    # it must not turn the comparison into an empty stream.
                    # This also preserves the expected result for `!=` and
                    # comparisons against an explicit null literal.
                    $lhs_values = [undef] unless @$lhs_values;
                    $rhs_values = [undef] unless @$rhs_values;

                    for my $lhs (@$lhs_values) {
                        for my $rhs (@$rhs_values) {
                            push @next_results,
                                JQ::Lite::Util::_compare_values($lhs, $operator, $rhs)
                                ? JSON::PP::true
                                : JSON::PP::false;
                        }
                    }
                }
                @$out_ref = @next_results;
                return 1;
            }
        }

        if (JQ::Lite::Util::_looks_like_expression($normalized)) {
            my @evaluated;
            my $all_ok = 1;

            for my $item (@results) {
                my ($values, $ok) = JQ::Lite::Util::_evaluate_value_expression($self, $item, $normalized);
                if ($ok) {
                    if (@$values) {
                        push @evaluated, $values->[0];
                    }
                    else {
                        push @evaluated, undef;
                    }
                }
                else {
                    $all_ok = 0;
                    last;
                }
            }

            if ($all_ok) {
                @$out_ref = @evaluated;
                return 1;
            }
        }

        # support for addition (. + expr)
        if ($normalized =~ /^\.\s*\+\s*(.+)$/s) {
            my $rhs_expr = $1;
            @next_results = map {
                my $lhs = $_;
                my ($rhs_values, $rhs_ok) = JQ::Lite::Util::_evaluate_value_expression($self, $lhs, $rhs_expr);
                my $rhs = ($rhs_ok && @$rhs_values) ? $rhs_values->[0] : undef;
                JQ::Lite::Util::_apply_addition($lhs, $rhs);
            } @results;
            @$out_ref = @next_results;
            return 1;
        }

        my ($add_lhs, $add_rhs) = JQ::Lite::Util::_split_top_level_operator($normalized, '+');
        if (defined $add_lhs && defined $add_rhs) {
            @next_results = map {
                my ($values, $ok) = JQ::Lite::Util::_evaluate_value_expression($self, $_, $normalized);
                ($ok && @$values) ? $values->[0] : undef;
            } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for array constructors [expr, expr, ...]
        if ($normalized =~ /^\[(.*)\]$/s) {
            my $inner = $1;
            my @elements = ();
            if ($inner =~ /\S/) {
                @elements = JQ::Lite::Util::_split_top_level_commas($inner);
            }

            for my $item (@results) {
                my @built;

                for my $element (@elements) {
                    next if !defined $element;
                    $element =~ s/^\s+|\s+$//g;
                    next if $element eq '';

                    my ($values, $ok) = JQ::Lite::Util::_evaluate_value_expression($self, $item, $element);
                    if ($ok) {
                        if (@$values) {
                            push @built, @$values;
                        } else {
                            push @built, undef;
                        }
                        next;
                    }

                    my $json = JQ::Lite::Util::_encode_json($item);
                    my @outputs = $self->run_query($json, $element);
                    if (@outputs) {
                        push @built, @outputs;
                    } else {
                        push @built, undef;
                    }
                }

                push @next_results, \@built;
            }

            # handle empty [] constructor
            if (!@elements) {
                @next_results = map { [] } @results;
            }

            @$out_ref = @next_results;
            return 1;
        }

        # support for object constructors {key: expr, ...}
        if ($normalized =~ /^\{(.*)\}$/s) {
            my $inner = $1;
            my @pairs = ();
            if ($inner =~ /\S/) {
                @pairs = JQ::Lite::Util::_split_top_level_commas($inner);
            }

            for my $item (@results) {
                my %built;

                for my $pair (@pairs) {
                    next if !defined $pair;

                    my ($raw_key, $raw_expr) = JQ::Lite::Util::_split_top_level_colon($pair);
                    next if !defined $raw_key;

                    my $key = JQ::Lite::Util::_interpret_object_key($raw_key);
                    next if !defined $key;

                    my $value_expr = defined $raw_expr ? $raw_expr : '';
                    $value_expr =~ s/^\s+|\s+$//g;
                    next if $value_expr eq '';

                    my $value;

                    my ($values, $ok) = JQ::Lite::Util::_evaluate_value_expression($self, $item, $value_expr);
                    if ($ok) {
                        $value = @$values ? $values->[0] : undef;
                    }
                    else {
                        my $json = JQ::Lite::Util::_encode_json($item);
                        my @outputs = $self->run_query($json, $value_expr);
                        $value = @outputs ? $outputs[0] : undef;
                    }

                    $built{$key} = $value;
                }

                push @next_results, \%built;
            }

            if (!@pairs) {
                @next_results = map { {} } @results;
            }

            @$out_ref = @next_results;
            return 1;
        }

        if (my $foreach = JQ::Lite::Util::_parse_foreach_expression($normalized)) {
            @next_results = ();

            for my $value (@results) {
                my $json = JQ::Lite::Util::_encode_json($value);
                my @items = $self->run_query($json, $foreach->{generator});

                my ($init_values, $init_ok) = JQ::Lite::Util::_evaluate_value_expression($self, $value, $foreach->{init_expr});
                my $acc;
                if ($init_ok) {
                    $acc = @$init_values ? $init_values->[0] : undef;
                }
                else {
                    my @init_outputs = $self->run_query(JQ::Lite::Util::_encode_json($value), $foreach->{init_expr});
                    $acc = @init_outputs ? $init_outputs[0] : undef;
                }

                for my $element (@items) {
                    my %existing = %{ $self->{_vars} || {} };
                    local $self->{_vars} = { %existing, $foreach->{var_name} => $element };

                    my ($updated_values, $updated_ok) = JQ::Lite::Util::_evaluate_value_expression($self, $acc, $foreach->{update_expr});
                    my $next;
                    if ($updated_ok) {
                        $next = @$updated_values ? $updated_values->[0] : undef;
                    }
                    else {
                        my @outputs = $self->run_query(JQ::Lite::Util::_encode_json($acc), $foreach->{update_expr});
                        $next = @outputs ? $outputs[0] : undef;
                    }

                    $acc = $next;

                    if (defined $foreach->{extract_expr} && length $foreach->{extract_expr}) {
                        my ($extract_values, $extract_ok) = JQ::Lite::Util::_evaluate_value_expression($self, $acc, $foreach->{extract_expr});
                        my $output;
                        if ($extract_ok) {
                            $output = @$extract_values ? $extract_values->[0] : undef;
                        }
                        else {
                            my @extracted = $self->run_query(JQ::Lite::Util::_encode_json($acc), $foreach->{extract_expr});
                            $output = @extracted ? $extracted[0] : undef;
                        }

                        push @next_results, $output;
                    }
                    else {
                        push @next_results, $acc;
                    }
                }
            }

            @$out_ref = @next_results;
            return 1;
        }

        if (my $if_expr = JQ::Lite::Util::_parse_if_expression($normalized)) {
            @next_results = ();

            for my $value (@results) {
                my $json     = JQ::Lite::Util::_encode_json($value);
                my $matched  = 0;

                BRANCH: for my $branch (@{ $if_expr->{branches} }) {
                    my @cond_results = $self->run_query($json, $branch->{condition});
                    my $truthy       = 0;

                    for my $cond_value (@cond_results) {
                        if (JQ::Lite::Util::_is_truthy($cond_value)) {
                            $truthy = 1;
                            last;
                        }
                    }

                    if (!$truthy && !@cond_results) {
                        $truthy = JQ::Lite::Util::_evaluate_condition($value, $branch->{condition}) ? 1 : 0;
                    }

                    next BRANCH unless $truthy;

                    my ($branch_values, $branch_ok) = JQ::Lite::Util::_evaluate_value_expression($self, $value, $branch->{then});

                    if ($branch_ok) {
                        push @next_results, @$branch_values;
                    }
                    else {
                        my @outputs = $self->run_query($json, $branch->{then});
                        push @next_results, @outputs;
                    }

                    $matched = 1;
                    last BRANCH;
                }

                next if $matched;

                if (defined $if_expr->{else}) {
                    my ($else_values, $else_ok) = JQ::Lite::Util::_evaluate_value_expression($self, $value, $if_expr->{else});

                    if ($else_ok) {
                        push @next_results, @$else_values;
                    }
                    else {
                        my @else_outputs = $self->run_query($json, $if_expr->{else});
                        push @next_results, @else_outputs;
                    }
                }
            }

            @$out_ref = @next_results;
            return 1;
        }

        if (my $reduce = JQ::Lite::Util::_parse_reduce_expression($normalized)) {
            @next_results = ();

            for my $value (@results) {
                my $json = JQ::Lite::Util::_encode_json($value);
                my @items = $self->run_query($json, $reduce->{generator});

                my ($init_values, $init_ok) = JQ::Lite::Util::_evaluate_value_expression($self, $value, $reduce->{init_expr});
                my $acc;
                if ($init_ok) {
                    $acc = @$init_values ? $init_values->[0] : undef;
                }
                else {
                    my @init_outputs = $self->run_query(JQ::Lite::Util::_encode_json($value), $reduce->{init_expr});
                    $acc = @init_outputs ? $init_outputs[0] : undef;
                }

                for my $element (@items) {
                    my %existing = %{ $self->{_vars} || {} };
                    local $self->{_vars} = { %existing, $reduce->{var_name} => $element };

                    my ($updated_values, $updated_ok) = JQ::Lite::Util::_evaluate_value_expression($self, $acc, $reduce->{update_expr});
                    my $next;
                    if ($updated_ok) {
                        $next = @$updated_values ? $updated_values->[0] : undef;
                    }
                    else {
                        my @outputs = $self->run_query(JQ::Lite::Util::_encode_json($acc), $reduce->{update_expr});
                        $next = @outputs ? $outputs[0] : undef;
                    }

                    $acc = $next;
                }

                push @next_results, $acc;
            }

            @$out_ref = @next_results;
            return 1;
        }

        # jq 1.7: .[] iterates arrays and objects, but raises a structured
        # type error on scalars.  Its optional counterpart .[]? suppresses
        # *only that iterator error*: it emits nothing on a scalar, not its
        # string characters.  Both forms retain the same container stream.
        if ($part eq '.[]' || $part eq '.[]?') {
            my $optional = $part eq '.[]?';
            @next_results = ();
            for my $item (@results) {
                if (ref($item) eq 'ARRAY') {
                    push @next_results, @$item;
                    next;
                }
                if (ref($item) eq 'HASH') {
                    # Preserve the existing object-value traversal order.
                    push @next_results, values %$item;
                    next;
                }

                next if $optional;

                my $type = JQ::Lite::Value::type_of($item);
                die JQ::Lite::Error::Evaluation->new(
                    message => 'Cannot iterate over ' . $type
                        . ' (' . JQ::Lite::Util::_encode_json($item) . ')'
                );
            }
            @$out_ref = @next_results;
            return 1;
        }

        # support for select(...)
        if ($part =~ /^select\((.+)\)$/) {
            my $cond = $1;
            @next_results = ();

            my $has_wildcard_array = index($cond, '[]') != -1;
            my $has_comparison = ($cond =~ /(==|!=|>=|<=|>|<|\band\b|\bor\b|\bcontains\b|\bhas\b|\bmatch\b)/i);
            my $use_streaming_eval = $has_wildcard_array || !$has_comparison;

            # allow built-in filters like match() and test() to run so their errors surface
            $use_streaming_eval ||= ($cond =~ /^\s*(match|test)\s*\(/);

            VALUE: for my $value (@results) {
                my $simple = JQ::Lite::Util::_evaluate_condition($value, $cond) ? 1 : 0;

                if ($use_streaming_eval) {
                    my $json = JQ::Lite::Util::_encode_json($value);
                    my $error;
                    my @cond_results;

                    {
                        local $@;
                        @cond_results = eval { $self->run_query($json, $cond) };
                        $error = $@;
                    }

                    die $error if $error;

                    if (@cond_results) {
                        my $truthy = 0;

                        for my $cond_value (@cond_results) {
                            if (JQ::Lite::Util::_is_truthy($cond_value)) {
                                $truthy++;
                            }
                        }

                        if ($truthy) {
                            push @next_results, (($value) x $truthy);
                        }

                        next VALUE;
                    }
                }

                if ($simple) {
                    push @next_results, $value;
                }
            }

            @$out_ref = @next_results;
            return 1;
        }

        my ($builtin_matched, $builtin_outputs)
            = JQ::Lite::Builtin->dispatch($self, $part, \@results);
        if ($builtin_matched) {
            @$out_ref = @{$builtin_outputs};
            return 1;
        }

        # Legacy built-in implementations below are retained temporarily while
        # parameterized handlers move to the registry. Exact-name built-ins are
        # dispatched by their category modules above.

        # support for assignment (e.g., .spec.replicas = 3)
        if (JQ::Lite::Util::_looks_like_assignment($part)) {
            my ($path, $value_spec, $operator) = JQ::Lite::Util::_parse_assignment_expression($part);

            @next_results = map {
                JQ::Lite::Util::_apply_assignment($self, $_, $path, $value_spec, $operator)
            } @results;

            @$out_ref = @next_results;
            return 1;
        }

        # support for sort
        if ($part eq 'sort') {
            @next_results = map {
                ref $_ eq 'ARRAY' ? [ sort { JQ::Lite::Util::_smart_cmp()->($a, $b) } @$_ ] : $_
            } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for sort_desc
        if ($part eq 'sort_desc') {
            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my $cmp = JQ::Lite::Util::_smart_cmp();
                    [ sort { $cmp->($b, $a) } @$_ ];
                }
                else {
                    $_;
                }
            } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for unique
        if ($part eq 'unique') {
            @next_results = map {
                ref $_ eq 'ARRAY' ? [ JQ::Lite::Util::_uniq(@$_) ] : $_
            } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for unique_by(path)
        if ($part =~ /^unique_by\((.+?)\)$/) {
            my $raw_path = $1;
            $raw_path =~ s/^\s+|\s+$//g;

            my $key_path = $raw_path;
            $key_path =~ s/^['"](.*)['"]$/$1/;

            my $use_entire_item = ($key_path eq '' || $key_path eq '.');
            $key_path =~ s/^\.// unless $use_entire_item;

            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my %seen;
                    my @deduped;

                    for my $element (@$_) {
                        my $key_value;

                        if ($use_entire_item) {
                            $key_value = $element;
                        } else {
                            my @values = JQ::Lite::Util::_traverse($element, $key_path);
                            $key_value = @values ? $values[0] : undef;
                        }

                        my $signature;
                        if (defined $key_value) {
                            $signature = JQ::Lite::Util::_key($key_value);
                        } else {
                            $signature = "\0__JQ_LITE_UNDEF__";
                        }

                        next if $seen{$signature}++;
                        push @deduped, $element;
                    }

                    \@deduped;
                } else {
                    $_;
                }
            } @results;

            @$out_ref = @next_results;
            return 1;
        }

        # support for limit(n)
        if ($part =~ /^limit\((.+)\)$/) {
            my $limit_str = $1;
            $limit_str =~ s/^\s+|\s+$//g;

            if ($limit_str !~ /^\d+$/) {
                die "limit(): count must be a non-negative integer";
            }

            my $limit = $limit_str + 0;

            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my $arr = $_;
                    my $end = $limit - 1;
                    $end = $#$arr if $end > $#$arr;
                    [ @$arr[0 .. $end] ]
                } else {
                    $_
                }
            } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for drop(n)
        if ($part =~ /^drop\((.+)\)$/) {
            my $count_str = $1;
            $count_str =~ s/^\s+|\s+$//g;

            if ($count_str !~ /^\d+$/) {
                die "drop(): count must be a non-negative integer";
            }

            my $count = $count_str + 0;
            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my $arr = $_;
                    if ($count >= @$arr) {
                        [];
                    } else {
                        [ @$arr[$count .. $#$arr] ];
                    }
                } else {
                    $_;
                }
            } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for tail(n)
        if ($part =~ /^tail\((.+)\)$/) {
            my $count_str = $1;
            $count_str =~ s/^\s+|\s+$//g;

            if ($count_str !~ /^\d+$/) {
                die "tail(): count must be a non-negative integer";
            }

            my $count = $count_str + 0;
            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my $arr = $_;

                    if ($count == 0 || !@$arr) {
                        [];
                    } else {
                        my $start = @$arr - $count;
                        $start = 0 if $start < 0;

                        [ @$arr[$start .. $#$arr] ];
                    }
                } else {
                    $_;
                }
            } @results;

            @$out_ref = @next_results;
            return 1;
        }

        # support for chunks(n)
        if ($part =~ /^chunks\((.+)\)$/) {
            my $size_str = $1;
            $size_str =~ s/^\s+|\s+$//g;

            if ($size_str !~ /^\d+$/) {
                die "chunks(): size must be a non-negative integer";
            }

            my $size = $size_str + 0;
            $size = 1 if $size < 1;

            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my $arr = $_;
                    if (!@$arr) {
                        [];
                    } else {
                        my @chunks;
                        for (my $i = 0; $i < @$arr; $i += $size) {
                            my $end = $i + $size - 1;
                            $end = $#$arr if $end > $#$arr;
                            push @chunks, [ @$arr[$i .. $end] ];
                        }
                        \@chunks;
                    }
                } else {
                    $_;
                }
            } @results;

            @$out_ref = @next_results;
            return 1;
        }

        # support for range(...)
        if ($part =~ /^range\((.*)\)$/) {
            my $args_raw = $1;
            my @args     = JQ::Lite::Util::_parse_range_arguments($args_raw);

            @next_results = ();
            for my $value (@results) {
                push @next_results, JQ::Lite::Util::_apply_range($value, \@args);
            }

            @$out_ref = @next_results;
            return 1;
        }

        # support for map(...)
        if ($part =~ /^map\((.+)\)$/) {
            my $filter = $1;
            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my @mapped;

                    for my $element (@$_) {
                        my @outputs = $self->run_query(JQ::Lite::Util::_encode_json($element), $filter);
                        push @mapped, @outputs if @outputs;
                    }

                    \@mapped;
                } else {
                    $_;
                }
            } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for map_values(filter)
        if ($part =~ /^map_values\((.+)\)$/) {
            my $filter = $1;
            @next_results = map { JQ::Lite::Util::_apply_map_values($self, $_, $filter) } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for walk(filter)
        if ($part =~ /^walk\((.+)\)$/) {
            my $filter = $1;
            @next_results = map { JQ::Lite::Util::_apply_walk($self, $_, $filter) } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for recurse([filter])
        if ($part =~ /^recurse(?:\((.*)\))?$/) {
            my $filter = defined $1 ? $1 : '';
            $filter =~ s/^\s+|\s+$//g;
            $filter = undef if $filter eq '';

            @next_results = map { JQ::Lite::Util::_apply_recurse($self, $_, $filter) } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for enumerate()
        if ($part =~ /^enumerate(?:\(\))?$/) {
            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my $arr = $_;
                    my @pairs;
                    for my $idx (0 .. $#$arr) {
                        push @pairs, { index => $idx, value => $arr->[$idx] };
                    }
                    \@pairs;
                } else {
                    $_;
                }
            } @results;

            @$out_ref = @next_results;
            return 1;
        }

        # support for with_entries(filter)
        if ($part =~ /^with_entries\((.+)\)$/) {
            my $filter = $1;
            @next_results = map { JQ::Lite::Util::_apply_with_entries($self, $_, $filter) } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for transpose()
        if ($part eq 'transpose()' || $part eq 'transpose') {
            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my $outer = $_;

                    if (!@$outer) {
                        [];
                    }
                    elsif (grep { ref $_ ne 'ARRAY' } @$outer) {
                        $_;
                    }
                    else {
                        my @lengths = map { scalar(@$_) } @$outer;
                        my $limit   = @lengths ? min(@lengths) : 0;

                        if ($limit <= 0) {
                            [];
                        } else {
                            my @transposed;
                            for my $idx (0 .. $limit - 1) {
                                push @transposed, [ map { $_->[$idx] } @$outer ];
                            }
                            \@transposed;
                        }
                    }
                } else {
                    $_;
                }
            } @results;

            @$out_ref = @next_results;
            return 1;
        }

        # support for slice(start[, length])
        if ($part =~ /^slice(?:\((.*)\))?$/) {
            my $args_raw = defined $1 ? $1 : '';
            my @args     = JQ::Lite::Util::_parse_slice_arguments($args_raw);

            @next_results = map { JQ::Lite::Util::_apply_slice($_, @args) } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for pluck(key)
        if ($part =~ /^pluck\((.+)\)$/) {
            my $key_path = $1;
            $key_path =~ s/^['"](.*)['"]$/$1/;
            $key_path =~ s/^\.//;

            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my @collected = map {
                        my $item = $_;
                        my @values = JQ::Lite::Util::_traverse($item, $key_path);
                        @values ? $values[0] : undef;
                    } @$_;
                    \@collected;
                } else {
                    $_;
                }
            } @results;

            @$out_ref = @next_results;
            return 1;
        }

        # support for pick(key1, key2, ...)
        if ($part =~ /^pick\((.*)\)$/) {
            my @keys = map { defined $_ ? "$_" : undef } JQ::Lite::Util::_parse_arguments($1);
            @keys = grep { defined $_ } @keys;

            @next_results = map { JQ::Lite::Util::_apply_pick($_, \@keys) } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for sum_by(path)
        if ($part =~ /^sum_by\((.+)\)$/) {
            my $raw_path = $1;
            $raw_path =~ s/^\s+|\s+$//g;
            $raw_path =~ s/^['"](.*)['"]$/$1/;

            my $use_entire_item = ($raw_path eq '' || $raw_path eq '.');
            my $key_path        = $raw_path;
            $key_path =~ s/^\.// unless $use_entire_item;

            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my $sum        = 0;
                    my $has_number = 0;

                    for my $element (@$_) {
                        my @values = $use_entire_item
                            ? ($element)
                            : JQ::Lite::Util::_traverse($element, $key_path);

                        for my $value (@values) {
                            next unless defined $value;

                            my $num = $value;
                            if (ref($num) eq 'JSON::PP::Boolean') {
                                $num = $num ? 1 : 0;
                            }

                            next if ref $num;
                            next unless looks_like_number($num);
                            $sum += $num;
                            $has_number = 1;
                        }
                    }

                    $has_number ? $sum : 0;
                }
                else {
                    $_;
                }
            } @results;

            @$out_ref = @next_results;
            return 1;
        }

        # support for median_by(path)
        if ($part =~ /^median_by\((.+)\)$/) {
            my ($key_path, $use_entire_item) = JQ::Lite::Util::_normalize_path_argument($1);

            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my @numbers;
                    for my $element (@$_) {
                        push @numbers, JQ::Lite::Util::_project_numeric_values($element, $key_path, $use_entire_item);
                    }

                    if (@numbers) {
                        @numbers = sort { $a <=> $b } @numbers;
                        my $count  = @numbers;
                        my $middle = int($count / 2);
                        if ($count % 2) {
                            $numbers[$middle];
                        } else {
                            ($numbers[$middle - 1] + $numbers[$middle]) / 2;
                        }
                    } else {
                        undef;
                    }
                }
                else {
                    $_;
                }
            } @results;

            @$out_ref = @next_results;
            return 1;
        }

        # support for avg_by(path)
        if ($part =~ /^avg_by\((.+)\)$/) {
            my ($key_path, $use_entire_item) = JQ::Lite::Util::_normalize_path_argument($1);

            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my $sum   = 0;
                    my $count = 0;

                    for my $element (@$_) {
                        my @values = $use_entire_item
                            ? ($element)
                            : JQ::Lite::Util::_traverse($element, $key_path);

                        for my $value (@values) {
                            next unless defined $value;

                            my $num = $value;
                            if (ref($num) eq 'JSON::PP::Boolean') {
                                $num = $num ? 1 : 0;
                            }

                            next if ref $num;
                            next unless looks_like_number($num);
                            $sum   += $num;
                            $count += 1;
                        }
                    }

                    $count ? $sum / $count : 0;
                }
                else {
                    $_;
                }
            } @results;

            @$out_ref = @next_results;
            return 1;
        }

        # support for max_by(path)
        if ($part =~ /^max_by\((.+)\)$/) {
            my ($key_path, $use_entire_item) = JQ::Lite::Util::_normalize_path_argument($1);

            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    JQ::Lite::Util::_extreme_by($_, $key_path, $use_entire_item, 'max');
                } else {
                    $_;
                }
            } @results;

            @$out_ref = @next_results;
            return 1;
        }

        # support for min_by(path)
        if ($part =~ /^min_by\((.+)\)$/) {
            my ($key_path, $use_entire_item) = JQ::Lite::Util::_normalize_path_argument($1);

            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    JQ::Lite::Util::_extreme_by($_, $key_path, $use_entire_item, 'min');
                } else {
                    $_;
                }
            } @results;

            @$out_ref = @next_results;
            return 1;
        }

        if ($part eq 'tonumber()' || $part eq 'tonumber') {
            @next_results = map { JQ::Lite::Util::_tonumber($_) } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for percentile(p)
        if ($part =~ /^percentile(?:\((.*)\))?$/) {
            my $args_raw = defined $1 ? $1 : '';
            my @args     = length $args_raw ? JQ::Lite::Util::_parse_arguments($args_raw) : ();
            my $fraction = @args ? JQ::Lite::Util::_normalize_percentile($args[0]) : 0.5;

            @next_results = map {
                if (ref $_ eq 'ARRAY' && @$_) {
                    my @numbers = sort { $a <=> $b }
                        JQ::Lite::Util::_extract_numeric_values($_);

                    if (@numbers) {
                        defined $fraction ? JQ::Lite::Util::_percentile_value(\@numbers, $fraction) : undef;
                    }
                    else {
                        undef;
                    }
                }
                else {
                    $_;
                }
            } @results;

            @$out_ref = @next_results;
            return 1;
        }

        # support for mode
        if ($part eq 'mode') {
            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    if (!@$_) {
                        undef;
                    } else {
                        my %counts;
                        my %values;
                        my %first_index;
                        my $max_count  = 0;
                        my $best_index = undef;
                        my $mode_key;

                        for (my $i = 0; $i < @{$_}; $i++) {
                            my $item = $_->[$i];
                            next unless defined $item;

                            my $key = JQ::Lite::Util::_key($item);
                            next unless defined $key;

                            $counts{$key}++;
                            $values{$key}      //= $item;
                            $first_index{$key} //= $i;

                            my $count = $counts{$key};
                            my $index = $first_index{$key};

                            if (!defined $mode_key
                                || $count > $max_count
                                || ($count == $max_count
                                    && (!defined $best_index || $index < $best_index))) {
                                $mode_key   = $key;
                                $max_count  = $count;
                                $best_index = $index;
                            }
                        }

                        defined $mode_key ? $values{$mode_key} : undef;
                    }
                } else {
                    $_;
                }
            } @results;

            @$out_ref = @next_results;
            return 1;
        }

        # support for variance
        if ($part eq 'variance') {
            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my @numbers = JQ::Lite::Util::_extract_numeric_values($_);

                    if (@numbers) {
                        my $mean = sum(@numbers) / @numbers;
                        sum(map { ($_ - $mean) ** 2 } @numbers) / @numbers;
                    }
                    else {
                        undef;
                    }
                }
                else {
                    $_;
                }
            } @results;

            @$out_ref = @next_results;
            return 1;
        }

        # support for stddev
        if ($part eq 'stddev') {
            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my @numbers = JQ::Lite::Util::_extract_numeric_values($_);

                    if (@numbers) {
                        my $mean = sum(@numbers) / @numbers;
                        my $variance = sum(map { ($_ - $mean) ** 2 } @numbers) / @numbers;
                        sqrt($variance);
                    }
                    else {
                        undef;
                    }
                }
                else {
                    $_;
                }
            } @results;

            @$out_ref = @next_results;
            return 1;
        }

        # support for group_count(key)
        if ($part =~ /^group_count\((.+)\)$/) {
            my $key_path = $1;
            @next_results = map {
                JQ::Lite::Util::_group_count($_, $key_path)
            } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for group_by(key)
        if ($part =~ /^group_by\((.+)\)$/) {
            my $key_path = $1;
            @next_results = map {
                JQ::Lite::Util::_group_by($_, $key_path)
            } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for all() / all(expr)
        if ($part =~ /^all(?:\((.*)\))?$/) {
            my $expr = defined $1 ? $1 : undef;
            $expr = undef if defined($expr) && $expr eq '';

            @next_results = map { JQ::Lite::Util::_apply_all($self, $_, $expr) } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for any() / any(expr)
        if ($part =~ /^any(?:\((.*)\))?$/) {
            my $expr = defined $1 ? $1 : undef;
            $expr = undef if defined($expr) && $expr eq '';

            @next_results = map { JQ::Lite::Util::_apply_any($self, $_, $expr) } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for join(", ")
        if ($part =~ /^join\((.*?)\)$/) {
            my $sep = JQ::Lite::Util::_parse_string_argument($1);

            @next_results = map {
                die 'join(): input must be an array' if ref($_) ne 'ARRAY';
                my @parts;
                for my $item (@$_) {
                    if (!defined $item) {
                        push @parts, '';
                        next;
                    }

                    if (ref($item) eq 'JSON::PP::Boolean') {
                        push @parts, $item ? 'true' : 'false';
                        next;
                    }

                    if (ref $item) {
                        die 'join(): array elements must be scalars';
                    }

                    push @parts, "$item";
                }

                join($sep, @parts)
            } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for sort_by(key)
        if ($part =~ /^sort_by\((.+?)\)$/) {
            my $key_path = $1;
            $key_path =~ s/^\.//;  # Remove leading dot
        
            my $cmp = JQ::Lite::Util::_smart_cmp();
            @next_results = ();
        
            for my $item (@results) {
                if (ref $item eq 'ARRAY') {
                    my @sorted = sort {
                        my $a_val = (JQ::Lite::Util::_traverse($a, $key_path))[0] // '';
                        my $b_val = (JQ::Lite::Util::_traverse($b, $key_path))[0] // '';

                        $cmp->($a_val, $b_val);
                    } @$item;
        
                    push @next_results, \@sorted;
                } else {
                    push @next_results, $item;
                }
            }
        
            @$out_ref = @next_results;
            return 1;
        }

        # support for del(key)
        if ($part =~ /^del\((.+?)\)$/) {
            my $key = $1;
            $key =~ s/^\s+|\s+$//g;             # allow whitespace around argument
            $key =~ s/^['"](.*?)['"]$/$1/;  # remove quotes

            @next_results = map {
                if (ref $_ eq 'HASH') {
                    my %copy = %$_;  # shallow copy
                    delete $copy{$key};
                    \%copy
                } else {
                    $_
                }
            } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for delpaths(paths_expr)
        if ($part =~ /^delpaths\((.*)\)$/) {
            my $filter = $1;
            $filter =~ s/^\s+|\s+$//g;

            @next_results = map { JQ::Lite::Util::_apply_delpaths($self, $_, $filter) } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for test("pattern"[, "flags"])
        if ($part =~ /^test\((.+)\)$/) {
            my ($pattern_expr, $flags_expr) = JQ::Lite::Util::_split_semicolon_arguments($1, 2);
            my $pattern = defined $pattern_expr ? JQ::Lite::Util::_parse_string_argument($pattern_expr) : '';
            my $flags   = defined $flags_expr   ? JQ::Lite::Util::_parse_string_argument($flags_expr)   : '';

            @next_results = map { JQ::Lite::Util::_apply_test($_, $pattern, $flags) } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for match("pattern"[, "flags"])
        if ($part =~ /^match\((.+)\)$/) {
            my ($pattern_expr, $flags_expr) = JQ::Lite::Util::_split_semicolon_arguments($1, 2);
            my $pattern = defined $pattern_expr ? JQ::Lite::Util::_parse_string_argument($pattern_expr) : '';
            my $flags   = defined $flags_expr   ? JQ::Lite::Util::_parse_string_argument($flags_expr)   : '';

            @next_results = map { JQ::Lite::Util::_apply_match($_, $pattern, $flags) } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for indices(value)
        if ($part =~ /^indices\((.*)\)$/) {
            my @args   = JQ::Lite::Util::_parse_arguments($1);
            my $needle = @args ? $args[0] : undef;

            @next_results = map { JQ::Lite::Util::_apply_indices($_, $needle) } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for index(value)
        if ($part =~ /^index\((.*)\)$/) {
            my @args   = JQ::Lite::Util::_parse_arguments($1);
            my $needle = @args ? $args[0] : undef;

            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my $array = $_;
                    my $found;
                    for my $i (0 .. $#$array) {
                        if (JQ::Lite::Util::_values_equal($array->[$i], $needle)) {
                            $found = $i;
                            last;
                        }
                    }
                    defined $found ? $found : undef;
                }
                elsif (!ref $_ || ref($_) eq 'JSON::PP::Boolean') {
                    if (!defined $_ || !defined $needle) {
                        undef;
                    }
                    else {
                        my $haystack = "$_";
                        my $fragment = "$needle";
                        my $pos      = index($haystack, $fragment);
                        $pos >= 0 ? $pos : undef;
                    }
                }
                else {
                    undef;
                }
            } @results;

            @$out_ref = @next_results;
            return 1;
        }

        # support for rindex(value)
        if ($part =~ /^rindex\((.*)\)$/) {
            my @args   = JQ::Lite::Util::_parse_arguments($1);
            my $needle = @args ? $args[0] : undef;

            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my $array = $_;
                    my $found;
                    for (my $i = $#$array; $i >= 0; $i--) {
                        if (JQ::Lite::Util::_values_equal($array->[$i], $needle)) {
                            $found = $i;
                            last;
                        }
                    }
                    defined $found ? $found : undef;
                }
                elsif (!ref $_ || ref($_) eq 'JSON::PP::Boolean') {
                    if (!defined $_ || !defined $needle) {
                        undef;
                    }
                    else {
                        my $haystack = "$_";
                        my $fragment = "$needle";
                        my $pos      = rindex($haystack, $fragment);
                        $pos >= 0 ? $pos : undef;
                    }
                }
                else {
                    undef;
                }
            } @results;

            @$out_ref = @next_results;
            return 1;
        }

        # support for paths()
        if ($part eq 'paths()' || $part eq 'paths') {
            @next_results = ();

            for my $value (@results) {
                my $paths = JQ::Lite::Util::_apply_paths($value);
                push @next_results, @$paths;
            }

            @$out_ref = @next_results;
            return 1;
        }

        # support for paths(scalars)
        if ($part =~ /^paths\(\s*scalars\s*\)$/) {
            @next_results = ();

            for my $value (@results) {
                my $paths = JQ::Lite::Util::_apply_scalar_paths($value);
                push @next_results, @$paths;
            }

            @$out_ref = @next_results;
            return 1;
        }

        # support for leaf_paths()
        if ($part eq 'leaf_paths()' || $part eq 'leaf_paths') {
            @next_results = map { JQ::Lite::Util::_apply_leaf_paths($_) } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for getpath(path_expr)
        if ($part =~ /^getpath\((.*)\)$/) {
            my $path_expr = defined $1 ? $1 : '';

            @next_results = map { JQ::Lite::Util::_apply_getpath($self, $_, $path_expr) } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for setpath(path_expr; value_expr)
        if ($part =~ /^setpath\((.*)\)$/) {
            my $args_raw = defined $1 ? $1 : '';
            my ($paths_expr, $value_expr) = JQ::Lite::Util::_split_semicolon_arguments($args_raw, 2);

            @next_results = map { JQ::Lite::Util::_apply_setpath($self, $_, $paths_expr, $value_expr) } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for path()
        if ($part eq 'path') {
            @next_results = map {
                if (ref $_ eq 'HASH') {
                    [ sort keys %$_ ]
                }
                elsif (ref $_ eq 'ARRAY') {
                    [ 0..$#$_ ]
                }
                else {
                    ''
                }
            } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for is_empty
        if ($part eq 'is_empty') {
            @next_results = map {
                (ref $_ eq 'ARRAY' && !@$_) || (ref $_ eq 'HASH' && !%$_)
                    ? JSON::PP::true
                    : JSON::PP::false
            } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for not (logical negation)
        if ($part eq 'not' || $part eq 'not()') {
            @next_results = map {
                JQ::Lite::Util::_is_truthy($_) ? JSON::PP::false : JSON::PP::true
            } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # support for jq's alternative operator: lhs // rhs
        my $coalesce_expr = $part;
        if (defined $coalesce_expr) {
            my $stripped = $coalesce_expr;
            while ($stripped =~ /^\((.*)\)$/) {
                $stripped = $1;
                $stripped =~ s/^\s+|\s+$//g;
            }

            if ($stripped =~ /^(.*?)\s*\/\/\s*(.+)$/) {
                my ($lhs_raw, $rhs_raw) = ($1, $2);
                my $lhs_expr = $lhs_raw;
                my $rhs_expr = $rhs_raw;
                $lhs_expr =~ s/^\s+|\s+$//g;
                $rhs_expr =~ s/^\s+|\s+$//g;

                @next_results = map { JQ::Lite::Util::_apply_coalesce($self, $_, $lhs_expr, $rhs_expr) } @results;
                @$out_ref = @next_results;
                return 1;
            }
        }

        # support for default(value)
        if ($part =~ /^default\((.+)\)$/) {
            my $default_value = $1;
            $default_value =~ s/^['"](.*?)['"]$/$1/;

            @results = @results ? @results : (undef);

            @next_results = map {
                defined($_) ? $_ : $default_value
            } @results;
            @$out_ref = @next_results;
            return 1;
        }

        # Fallback: value expressions (including literals like null/0/"text")
        {
            my $all_ok = 1;
            @next_results = ();

            for my $item (@results) {
                my ($values, $ok) = JQ::Lite::Util::_evaluate_value_expression($self, $item, $part);
                if ($ok) {
                    if (@$values) {
                        push @next_results, @$values;
                    }
                    else {
                        push @next_results, undef;
                    }
                }
                else {
                    $all_ok = 0;
                    last;
                }
            }

            if ($all_ok) {
                @$out_ref = @next_results;
                return 1;
            }
        }

    return 0;
}

1;
