package JQ::Lite;

use strict;
use warnings;
use JSON::PP;
use List::Util qw(sum min max);
use Scalar::Util qw(looks_like_number);

our $VERSION = '0.62';

sub new {
    my ($class, %opts) = @_;
    my $self = {
        raw => $opts{raw} || 0,
    };
    return bless $self, $class;
}

sub run_query {
    my ($self, $json_text, $query) = @_;
    my $data = decode_json($json_text);
    
    if (!defined $query || $query =~ /^\s*\.\s*$/) {
        return ($data);
    }
    
    # instead of: my @parts = split /\|/, $query;
    my @parts = map { s/^\s+|\s+$//gr } split /\|/, $query;
    
    # detect .[] and convert to pseudo-command
    @parts = map {
        if ($_ eq '.[]') {
            'flatten'
        } elsif ($_ =~ /^\.(.+)$/) {
            $1
        } else {
            $_
        }
    } @parts;

    my @results = ($data);
    for my $part (@parts) {
        my @next_results;

        # support for flatten (alias for .[])
        if ($part eq 'flatten') {
            @next_results = map {
                ref $_ eq 'ARRAY' ? @$_ : ()
            } @results;
            @results = @next_results;
            next;
        }

        # support for select(...)
        if ($part =~ /^select\((.+)\)$/) {
            my $cond = $1;
            @next_results = grep { _evaluate_condition($_, $cond) } @results;
            @results = @next_results;
            next;
        }

        # support for length
        if ($part eq 'length') {
            @next_results = map {
                if (!defined $_) {
                    0;
                }
                elsif (ref $_ eq 'ARRAY') {
                    scalar(@$_);
                }
                elsif (ref $_ eq 'HASH') {
                    scalar(keys %$_);
                }
                elsif (!ref $_ || ref($_) eq 'JSON::PP::Boolean') {
                    length("$_");
                }
                else {
                    0;
                }
            } @results;
            @results = @next_results;
            next;
        }

        # support for keys
        if ($part eq 'keys') {
            @next_results = map {
                ref $_ eq 'HASH' ? [ sort keys %$_ ] : undef
            } @results;
            @results = @next_results;
            next;
        }

        # support for sort
        if ($part eq 'sort') {
            @next_results = map {
                ref $_ eq 'ARRAY' ? [ sort { _smart_cmp()->($a, $b) } @$_ ] : $_
            } @results;
            @results = @next_results;
            next;
        }

        # support for sort_desc
        if ($part eq 'sort_desc') {
            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my $cmp = _smart_cmp();
                    [ sort { $cmp->($b, $a) } @$_ ];
                }
                else {
                    $_;
                }
            } @results;
            @results = @next_results;
            next;
        }

        # support for unique
        if ($part eq 'unique') {
            @next_results = map {
                ref $_ eq 'ARRAY' ? [ _uniq(@$_) ] : $_
            } @results;
            @results = @next_results;
            next;
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
                            my @values = _traverse($element, $key_path);
                            $key_value = @values ? $values[0] : undef;
                        }

                        my $signature;
                        if (defined $key_value) {
                            $signature = _key($key_value);
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

            @results = @next_results;
            next;
        }

        # support for first
        if ($part eq 'first') {
            @next_results = map {
                ref $_ eq 'ARRAY' && @$_ ? $$_[0] : undef
            } @results;
            @results = @next_results;
            next;
        }

        # support for last
        if ($part eq 'last') {
            @next_results = map {
                ref $_ eq 'ARRAY' && @$_ ? $$_[-1] : undef
            } @results;
            @results = @next_results;
            next;
        }

        # support for reverse
        if ($part eq 'reverse') {
            @next_results = map {
                ref $_ eq 'ARRAY' ? [ reverse @$_ ] : $_
            } @results;
            @results = @next_results;
            next;
        }

        # support for limit(n)
        if ($part =~ /^limit\((\d+)\)$/) {
            my $limit = $1;
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
            @results = @next_results;
            next;
        }

        # support for map(...)
        if ($part =~ /^map\((.+)\)$/) {
            my $filter = $1;
            @next_results = map {
                ref $_ eq 'ARRAY'
                    ? [ grep { defined($_) } map { $self->run_query(encode_json($_), $filter) } @$_ ]
                    : $_
            } @results;
            @results = @next_results;
            next;
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
                        my @values = _traverse($item, $key_path);
                        @values ? $values[0] : undef;
                    } @$_;
                    \@collected;
                } else {
                    $_;
                }
            } @results;

            @results = @next_results;
            next;
        }

        # support for add
        if ($part eq 'add') {
            @next_results = map {
                ref $_ eq 'ARRAY' ? sum(map { 0 + $_ } @$_) : $_
            } @results;
            @results = @next_results;
            next;
        }

        # support for sum (alias for add)
        if ($part eq 'sum') {
            @next_results = map {
                ref $_ eq 'ARRAY' ? sum(map { 0 + $_ } @$_) : $_
            } @results;
            @results = @next_results;
            next;
        }

        # support for product
        if ($part eq 'product') {
            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my $product    = 1;
                    my $has_values = 0;
                    for my $val (@$_) {
                        next unless defined $val;
                        $product *= (0 + $val);
                        $has_values = 1;
                    }
                    $has_values ? $product : 1;
                } else {
                    $_;
                }
            } @results;
            @results = @next_results;
            next;
        }

        # support for min
        if ($part eq 'min') {
            @next_results = map {
                ref $_ eq 'ARRAY' ? min(map { 0 + $_ } @$_) : $_
            } @results;
            @results = @next_results;
            next;
        }

        # support for max
        if ($part eq 'max') {
            @next_results = map {
                ref $_ eq 'ARRAY' ? max(map { 0 + $_ } @$_) : $_
            } @results;
            @results = @next_results;
            next;
        }

        # support for avg
        if ($part eq 'avg') {
            @next_results = map {
                ref $_ eq 'ARRAY' && @$_ ? sum(map { 0 + $_ } @$_) / scalar(@$_) : 0
            } @results;
            @results = @next_results;
            next;
        }

        # support for abs
        if ($part eq 'abs') {
            @next_results = map {
                if (!defined $_) {
                    undef;
                }
                elsif (!ref $_) {
                    looks_like_number($_) ? abs($_) : $_;
                }
                elsif (ref $_ eq 'ARRAY') {
                    [ map { looks_like_number($_) ? abs($_) : $_ } @$_ ];
                }
                else {
                    $_;
                }
            } @results;
            @results = @next_results;
            next;
        }

        # support for ceil()
        if ($part eq 'ceil()' || $part eq 'ceil') {
            @next_results = map { _apply_numeric_function($_, \&_ceil) } @results;
            @results = @next_results;
            next;
        }

        # support for floor()
        if ($part eq 'floor()' || $part eq 'floor') {
            @next_results = map { _apply_numeric_function($_, \&_floor) } @results;
            @results = @next_results;
            next;
        }

        # support for round()
        if ($part eq 'round()' || $part eq 'round') {
            @next_results = map { _apply_numeric_function($_, \&_round) } @results;
            @results = @next_results;
            next;
        }

        # support for median
        if ($part eq 'median') {
            @next_results = map {
                if (ref $_ eq 'ARRAY' && @$_) {
                    my @numbers = sort { $a <=> $b }
                        map { 0 + $_ }
                        grep { looks_like_number($_) }
                        @$_;

                    if (@numbers) {
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
                } else {
                    $_;
                }
            } @results;
            @results = @next_results;
            next;
        }

        # support for stddev
        if ($part eq 'stddev') {
            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    my @numbers = map { 0 + $_ }
                        grep { looks_like_number($_) }
                        @$_;

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

            @results = @next_results;
            next;
        }

        # support for group_count(key)
        if ($part =~ /^group_count\((.+)\)$/) {
            my $key_path = $1;
            @next_results = map {
                _group_count($_, $key_path)
            } @results;
            @results = @next_results;
            next;
        }

        # support for group_by(key)
        if ($part =~ /^group_by\((.+)\)$/) {
            my $key_path = $1;
            @next_results = map {
                _group_by($_, $key_path)
            } @results;
            @results = @next_results;
            next;
        }

        # support for count
        if ($part eq 'count') {
            my $n = 0;
            for my $item (@results) {
                if (ref $item eq 'ARRAY') {
                    $n += scalar(@$item);
                } else {
                    $n += 1;  # count as 1 item
                }
            }
            @results = ($n);
            next;
        }

        # support for join(", ")
        if ($part =~ /^join\((.*?)\)$/) {
            my $sep = $1;
            $sep =~ s/^['"](.*?)['"]$/$1/;  # remove quotes around separator

            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    join($sep, map { defined $_ ? $_ : '' } @$_)
                } else {
                    ''
                }
            } @results;
            @results = @next_results;
            next;
        }

        # support for sort_by(key)
        if ($part =~ /^sort_by\((.+?)\)$/) {
            my $key_path = $1;
            $key_path =~ s/^\.//;  # Remove leading dot
        
            my $cmp = _smart_cmp();
            @next_results = ();
        
            for my $item (@results) {
                if (ref $item eq 'ARRAY') {
                    my @sorted = sort {
                        my $a_val = (_traverse($a, $key_path))[0] // '';
                        my $b_val = (_traverse($b, $key_path))[0] // '';
        
                        warn "[DEBUG] a=$a_val, b=$b_val => cmp=" . $cmp->($a_val, $b_val) . "\n";
        
                        $cmp->($a_val, $b_val);
                    } @$item;
        
                    push @next_results, \@sorted;
                } else {
                    push @next_results, $item;
                }
            }
        
            @results = @next_results;
            next;
        }

        # support for empty
        if ($part eq 'empty') {
            @results = ();  # discard all results
            next;
        }

        # support for values
        if ($part eq 'values') {
            @next_results = map {
                ref $_ eq 'HASH' ? [ values %$_ ] : $_
            } @results;
            @results = @next_results;
            next;
        }

        # support for flatten()
        if ($part eq 'flatten()' || $part eq 'flatten') {
            @next_results = map {
                (ref $_ eq 'ARRAY') ? @$_ : ()
            } @results;
            @results = @next_results;
            next;
        }

        # support for type()
        if ($part eq 'type()' || $part eq 'type') {
            @next_results = map {
                if (!defined $_) {
                    'null';
                }
                elsif (ref($_) eq 'ARRAY') {
                    'array';
                }
                elsif (ref($_) eq 'HASH') {
                    'object';
                }
                elsif (ref($_) eq '') {
                    if (/^-?\d+(?:\.\d+)?$/) {
                        'number';
                    } else {
                        'string';
                    }
                }
                elsif (ref($_) eq 'JSON::PP::Boolean') {
                    'boolean';
                }
                else {
                    'unknown';
                }
            } (@results ? @results : (undef)); 
            @results = @next_results;
            next;
        }

        # support for nth(n)
        if ($part =~ /^nth\((\d+)\)$/) {
            my $index = $1;
            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    $_->[$index]
                } else {
                    undef
                }
            } @results;
            @results = @next_results;
            next;
        }

        # support for del(key)
        if ($part =~ /^del\((.+?)\)$/) {
            my $key = $1;
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
            @results = @next_results;
            next;
        }

        # support for compact()
        if ($part eq 'compact()' || $part eq 'compact') {
            @next_results = map {
                if (ref $_ eq 'ARRAY') {
                    [ grep { defined $_ } @$_ ]
                } else {
                    $_
                }
            } @results;
            @results = @next_results;
            next;
        }

        # support for upper()
        if ($part eq 'upper()' || $part eq 'upper') {
            @next_results = map { _apply_case_transform($_, 'upper') } @results;
            @results = @next_results;
            next;
        }

        # support for lower()
        if ($part eq 'lower()' || $part eq 'lower') {
            @next_results = map { _apply_case_transform($_, 'lower') } @results;
            @results = @next_results;
            next;
        }

        # support for trim()
        if ($part eq 'trim()' || $part eq 'trim') {
            @next_results = map { _apply_trim($_) } @results;
            @results = @next_results;
            next;
        }

        # support for contains(value)
        if ($part =~ /^contains\((.+)\)$/) {
            my $needle = _parse_string_argument($1);
            @next_results = map { _apply_contains($_, $needle) } @results;
            @results = @next_results;
            next;
        }

        # support for startswith("prefix")
        if ($part =~ /^startswith\((.+)\)$/) {
            my $needle = _parse_string_argument($1);
            @next_results = map { _apply_string_predicate($_, $needle, 'start') } @results;
            @results = @next_results;
            next;
        }

        # support for endswith("suffix")
        if ($part =~ /^endswith\((.+)\)$/) {
            my $needle = _parse_string_argument($1);
            @next_results = map { _apply_string_predicate($_, $needle, 'end') } @results;
            @results = @next_results;
            next;
        }

        # support for replace(old, new)
        if ($part =~ /^replace\((.+)\)$/) {
            my ($search, $replacement) = _parse_arguments($1);
            $search      = defined $search      ? $search      : '';
            $replacement = defined $replacement ? $replacement : '';

            @next_results = map { _apply_replace($_, $search, $replacement) } @results;
            @results = @next_results;
            next;
        }

        # support for split("separator")
        if ($part =~ /^split\((.+)\)$/) {
            my $separator = _parse_string_argument($1);
            @next_results = map { _apply_split($_, $separator) } @results;
            @results = @next_results;
            next;
        }

        # support for substr(start[, length])
        if ($part =~ /^substr(?:\((.*)\))?$/) {
            my $args_raw = defined $1 ? $1 : '';
            my @args = _parse_arguments($args_raw);
            @next_results = map { _apply_substr($_, @args) } @results;
            @results = @next_results;
            next;
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
            @results = @next_results;
            next;
        }

        # support for is_empty
        if ($part eq 'is_empty') {
            @next_results = map {
                (ref $_ eq 'ARRAY' && !@$_) || (ref $_ eq 'HASH' && !%$_)
                    ? JSON::PP::true
                    : JSON::PP::false
            } @results;
            @results = @next_results;
            next;
        }

        # support for default(value)
        if ($part =~ /^default\((.+)\)$/) {
            my $default_value = $1;
            $default_value =~ s/^['"](.*?)['"]$/$1/; 
        
            @results = @results ? @results : (undef);
        
            @next_results = map {
                defined($_) ? $_ : $default_value
            } @results;
            @results = @next_results;
            next;
        }

        # standard traversal
        for my $item (@results) {
            push @next_results, _traverse($item, $part);
        }
        @results = @next_results;
    }

    return @results;
}

sub _map {
    my ($self, $data, $filter) = @_;

    if (ref $data ne 'ARRAY') {
        warn "_map expects array reference";
        return ();
    }

    my @mapped;
    for my $item (@$data) {
        push @mapped, $self->run_query(encode_json($item), $filter);
    }

    return @mapped;
}

sub _apply_case_transform {
    my ($value, $mode) = @_;

    if (!defined $value) {
        return undef;
    }

    if (!ref $value) {
        return $mode eq 'upper' ? uc $value : lc $value;
    }

    if (ref $value eq 'ARRAY') {
        return [ map { _apply_case_transform($_, $mode) } @$value ];
    }

    return $value;
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

sub _apply_numeric_function {
    my ($value, $callback) = @_;

    return undef if !defined $value;

    if (!ref $value) {
        return looks_like_number($value) ? $callback->($value) : $value;
    }

    if (ref $value eq 'ARRAY') {
        return [ map { _apply_numeric_function($_, $callback) } @$value ];
    }

    return $value;
}

sub _traverse {
    my ($data, $query) = @_;
    my @steps = split /\./, $query;
    my @stack = ($data);

    for my $step (@steps) {
        my $optional = ($step =~ s/\?$//);
        my @next_stack;

        for my $item (@stack) {
            next if !defined $item;

            # index access: key[index]
            if ($step =~ /^(.*?)\[(\d+)\]$/) {
                my ($key, $index) = ($1, $2);
                if (ref $item eq 'HASH' && exists $item->{$key}) {
                    my $val = $item->{$key};
                    push @next_stack, $val->[$index]
                        if ref $val eq 'ARRAY' && defined $val->[$index];
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
                }
                elsif (ref $item eq 'ARRAY') {
                    for my $sub (@$item) {
                        if (ref $sub eq 'HASH' && exists $sub->{$key}) {
                            my $val = $sub->{$key};
                            push @next_stack, @$val if ref $val eq 'ARRAY';
                        }
                    }
                }
            }
            # standard access: key
            else {
                if (ref $item eq 'HASH' && exists $item->{$step}) {
                    push @next_stack, $item->{$step};
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

    # support for numeric expressions like: select(.a + 5 > 10)
    if ($cond =~ /^\s*(\.\w+)\s*([\+\-\*\/%])\s*(-?\d+(?:\.\d+)?)\s*(==|!=|>=|<=|>|<)\s*(-?\d+(?:\.\d+)?)\s*$/) {
        my ($path, $op1, $rhs1, $cmp, $rhs2) = ($1, $2, $3, $4, $5);
        my @values = _traverse($item, substr($path, 1));
        my $lhs = $values[0];
    
        return 0 unless defined $lhs && $lhs =~ /^-?\d+(?:\.\d+)?$/;
    
        my $expr = eval "$lhs $op1 $rhs1";
        return eval "$expr $cmp $rhs2";
    }

    # support for multiple conditions: split and evaluate recursively
    if ($cond =~ /\s+and\s+/i) {
        my @conds = split /\s+and\s+/i, $cond;
        for my $c (@conds) {
            return 0 unless _evaluate_condition($item, $c);
        }
        return 1;
    }
    if ($cond =~ /\s+or\s+/i) {
        my @conds = split /\s+or\s+/i, $cond;
        for my $c (@conds) {
            return 1 if _evaluate_condition($item, $c);
        }
        return 0;
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
        my $re = eval {
            $ignore_case eq 'i' ? qr/$pattern/i : qr/$pattern/
        };
        return 0 unless $re;

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

        my $value;
        if ($value_raw =~ /^"(.*)"$/) {
            $value = $1;
        } elsif ($value_raw eq 'true') {
            $value = JSON::PP::true;
        } elsif ($value_raw eq 'false') {
            $value = JSON::PP::false;
        } elsif ($value_raw =~ /^-?\d+(?:\.\d+)?$/) {
            $value = 0 + $value_raw;
        } else {
            $value = $value_raw;
        }

        my @values = _traverse($item, $path);
        my $field_val = $values[0];

        return 0 unless defined $field_val;

        my $is_number = (!ref($field_val) && $field_val =~ /^-?\d+(?:\.\d+)?$/)
                     && (!ref($value)     && $value     =~ /^-?\d+(?:\.\d+)?$/);

        if ($op eq '==') {
            return $is_number ? ($field_val == $value) : ($field_val eq $value);
        } elsif ($op eq '!=') {
            return $is_number ? ($field_val != $value) : ($field_val ne $value);
        } elsif ($is_number) {
            # perform numeric comparisons only when applicable
            if ($op eq '>') {
                return $field_val > $value;
            } elsif ($op eq '>=') {
                return $field_val >= $value;
            } elsif ($op eq '<') {
                return $field_val < $value;
            } elsif ($op eq '<=') {
                return $field_val <= $value;
            }
        }
    }

    return 0;
}

sub _smart_cmp {
    return sub {
        my ($a, $b) = @_;

        my $num_a = ($a =~ /^-?\d+(?:\.\d+)?$/);
        my $num_b = ($b =~ /^-?\d+(?:\.\d+)?$/);

        if ($num_a && $num_b) {
            return $a <=> $b;
        } else {
            return "$a" cmp "$b";  # explicitly perform string comparison
        }
    };
}

sub _uniq {
    my %seen;
    return grep { !$seen{_key($_)}++ } @_;
}

# generate a unique key for hash, array, or scalar values
sub _key {
    my ($val) = @_;
    if (ref $val eq 'HASH') {
        return join(",", sort map { "$_=$val->{$_}" } keys %$val);
    } elsif (ref $val eq 'ARRAY') {
        return join(",", map { _key($_) } @$val);
    } else {
        return "$val";
    }
}

sub _group_by {
    my ($array_ref, $path) = @_;
    return {} unless ref $array_ref eq 'ARRAY';

    my %groups;
    for my $item (@$array_ref) {
        my @keys = _traverse($item, $path);
        my $key = defined $keys[0] ? "$keys[0]" : 'null';
        push @{ $groups{$key} }, $item;
    }
    return \%groups;
}

sub _apply_string_predicate {
    my ($value, $needle, $mode) = @_;

    if (ref $value eq 'ARRAY') {
        return [ map { _apply_string_predicate($_, $needle, $mode) } @$value ];
    }

    return _string_predicate_result($value, $needle, $mode);
}

sub _string_predicate_result {
    my ($value, $needle, $mode) = @_;

    return JSON::PP::false if !defined $value;
    return JSON::PP::false if ref $value;

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

sub _parse_string_argument {
    my ($raw) = @_;

    return '' if !defined $raw;

    my $parsed = eval { decode_json($raw) };
    if (!$@) {
        $parsed = '' if !defined $parsed;
        return $parsed;
    }

    $raw =~ s/^\s+|\s+$//g;
    $raw =~ s/^['"]//;
    $raw =~ s/['"]$//;
    return $raw;
}

sub _apply_split {
    my ($value, $separator) = @_;

    if (ref $value eq 'ARRAY') {
        return [ map { _apply_split($_, $separator) } @$value ];
    }

    return [] if !defined $value;
    return $value if ref $value;

    $separator = '' unless defined $separator;

    if ($separator eq '') {
        return [ split(//, $value) ];
    }

    my $pattern = quotemeta $separator;
    my @parts = split /$pattern/, $value, -1;
    return [ @parts ];
}

sub _apply_substr {
    my ($value, @args) = @_;

    if (ref $value eq 'ARRAY') {
        return [ map { _apply_substr($_, @args) } @$value ];
    }

    return undef if !defined $value;
    return $value if ref $value;

    my ($start, $length) = @args;
    $start = 0 unless defined $start;
    $start = int($start);

    if (defined $length) {
        $length = int($length);
        return substr($value, $start, $length);
    }

    return substr($value, $start);
}

sub _apply_replace {
    my ($value, $search, $replacement) = @_;

    if (ref $value eq 'ARRAY') {
        return [ map { _apply_replace($_, $search, $replacement) } @$value ];
    }

    return $value if !defined $value;
    return $value if ref $value;

    return $value if looks_like_number($value);

    $search      = defined $search      ? "$search"      : '';
    $replacement = defined $replacement ? "$replacement" : '';

    return $value if $search eq '';

    my $pattern = quotemeta $search;
    (my $copy = "$value") =~ s/$pattern/$replacement/g;
    return $copy;
}

sub _parse_arguments {
    my ($raw) = @_;

    return () unless defined $raw;

    my $parsed = eval { decode_json("[$raw]") };
    if (!$@ && ref $parsed eq 'ARRAY') {
        return @$parsed;
    }

    my @parts = split /,/, $raw;
    return map { s/^\s+|\s+$//gr } @parts;
}

sub _apply_contains {
    my ($value, $needle) = @_;

    if (ref $value eq 'ARRAY') {
        for my $item (@$value) {
            return JSON::PP::true if _values_equal($item, $needle);
        }
        return JSON::PP::false;
    }

    if (ref $value eq 'HASH') {
        return exists $value->{$needle} ? JSON::PP::true : JSON::PP::false;
    }

    return JSON::PP::false if !defined $value;

    if (!ref $value || ref($value) eq 'JSON::PP::Boolean') {
        my $haystack = "$value";
        my $fragment = defined $needle ? "$needle" : '';
        return index($haystack, $fragment) >= 0 ? JSON::PP::true : JSON::PP::false;
    }

    return JSON::PP::false;
}

sub _values_equal {
    my ($left, $right) = @_;

    return 1 if !defined $left && !defined $right;
    return 0 if !defined $left || !defined $right;

    if (ref($left) eq 'JSON::PP::Boolean' && ref($right) eq 'JSON::PP::Boolean') {
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

    my %counts;
    for my $item (@$array_ref) {
        my @keys = _traverse($item, $path);
        my $key = defined $keys[0] ? "$keys[0]" : 'null';
        $counts{$key}++;
    }

    return \%counts;
}

1;
__END__

=encoding utf-8

=head1 NAME

JQ::Lite - A lightweight jq-like JSON query engine in Perl

=head1 VERSION

Version 0.62

=head1 SYNOPSIS

  use JQ::Lite;
  
  my $jq = JQ::Lite->new;
  my @results = $jq->run_query($json_text, '.users[].name');
  
  for my $r (@results) {
      print encode_json($r), "\n";
  }

=head1 DESCRIPTION

JQ::Lite is a lightweight, pure-Perl JSON query engine inspired by the
L<jq|https://stedolan.github.io/jq/> command-line tool.

It allows you to extract, traverse, and filter JSON data using a simplified
jq-like syntax — entirely within Perl, with no external binaries or XS modules.

=head1 FEATURES

=over 4

=item * Pure Perl (no XS, no external binaries required)

=item * Dot notation traversal (e.g. .users[].name)

=item * Optional key access using '?' (e.g. .nickname?)

=item * Array indexing and flattening (.users[0], .users[])

=item * Boolean filters via select(...) with ==, !=, <, >, and, or

=item * Pipe-style query chaining using | operator

=item * Built-in functions: length, keys, values, first, last, reverse, sort, sort_desc, sort_by, unique, unique_by, has, contains, group_by, group_count, join, split, count, empty, type, nth, del, compact, upper, lower, abs, ceil, floor, trim, substr, startswith, endswith, add, sum, product, min, max, avg, median, stddev

=item * Supports map(...) and limit(n) style transformations

=item * Interactive mode for exploring queries line-by-line

=item * Command-line interface: C<jq-lite> (compatible with stdin or file)

=item * Decoder selection via C<--use> (JSON::PP, JSON::XS, etc.)

=item * Debug output via C<--debug>

=item * List all functions with C<--help-functions>

=back

=head1 CONSTRUCTOR

=head2 new

  my $jq = JQ::Lite->new;

Creates a new instance. Options may be added in future versions.

=head1 METHODS

=head2 run_query

  my @results = $jq->run_query($json_text, $query);

Runs a jq-like query against the given JSON string.
Returns a list of matched results. Each result is a Perl scalar
(string, number, arrayref, hashref, etc.) depending on the query.

=head1 SUPPORTED SYNTAX

=over 4

=item * .key.subkey

=item * .array[0] (index access)

=item * .array[] (flattening arrays)

=item * .key? (optional key access)

=item * select(.key > 1 and .key2 == "foo") (boolean filters)

=item * group_by(.field) (group array items by key)

=item * group_count(.field) (tally items by key)

=item * sort_desc()

Sort array elements in descending order using smart numeric/string comparison.

Example:

  .scores | sort_desc

Returns:

  [100, 75, 42, 12]

=item * sort_by(.key) (sort array of objects by key)

=item * unique_by(.key) (remove duplicates based on a projected key)

=item * .key | count (count items or fields)

=item * .[] | select(...) | count (combine flattening + filter + count)

=item * .array | map(.field) | join(", ")

Concatenates array elements with a custom separator string.
Example:

  .users | map(.name) | join(", ")

Results in:

  "Alice, Bob, Carol"

=item * split(separator)

Split string values (and arrays of strings) using a literal separator.
Example:

  .users[0].name | split("")

Results in:

  ["A", "l", "i", "c", "e"]

=item * values()

Returns all values of a hash as an array.
Example:

  .profile | values

=item * empty()

Discards all output. Compatible with jq.
Useful when only side effects or filtering is needed without output.

Example:

  .users[] | select(.age > 25) | empty

=item * .[] as alias for flattening top-level arrays

=item * type()

Returns the type of the value as a string:
"string", "number", "boolean", "array", "object", or "null".

Example:

  .name | type     # => "string"
  .tags | type     # => "array"
  .profile | type  # => "object"

=item * nth(n)

Returns the nth element (zero-based) from an array.

Example:

  .users | nth(0)   # first user
  .users | nth(2)   # third user

=item * del(key)

Deletes a specified key from a hash object and returns a new hash without that key.

Example:

  .profile | del("password")

If the key does not exist, returns the original hash unchanged.

If applied to a non-hash object, returns the object unchanged.

=item * compact()

Removes undef and null values from an array.

Example:

  .data | compact()

Before: [1, null, 2, null, 3]

After:  [1, 2, 3]

=item * upper()

Converts strings to uppercase. When applied to arrays, each scalar element
is uppercased recursively, leaving nested hashes or booleans untouched.

Example:

  .title | upper      # => "HELLO WORLD"
  .tags  | upper      # => ["PERL", "JSON"]

=item * lower()

Converts strings to lowercase. When applied to arrays, each scalar element
is lowercased recursively, leaving nested hashes or booleans untouched.

Example:

  .title | lower      # => "hello world"
  .tags  | lower      # => ["perl", "json"]

=item * contains(value)

Checks whether the current value includes the supplied fragment.

* For strings, returns true when the substring exists.
* For arrays, returns true if any element equals the supplied value.
* For hashes, returns true when the key is present.

Example:

  .title | contains("perl")     # => true
  .tags  | contains("json")     # => true
  .meta  | contains("lang")     # => true

=item * unique_by(".key")

Removes duplicate objects (or values) from an array by projecting each entry to
the supplied key path and keeping only the first occurrence of each signature.
Use C<.> to deduplicate by the entire value.

Example:

  .users | unique_by(.name)      # => keeps first record for each name
  .tags  | unique_by(.)          # => removes duplicate scalars

=item * startswith("prefix")

Returns true if the current string (or each string inside an array) begins with
the supplied prefix. Non-string values yield C<false>.

Example:

  .title | startswith("Hello")   # => true
  .tags  | startswith("j")       # => [false, true, false]

=item * endswith("suffix")

Returns true if the current string (or each string inside an array) ends with
the supplied suffix. Non-string values yield C<false>.

Example:

  .title | endswith("World")     # => true
  .tags  | endswith("n")         # => [false, true, false]

=item * substr(start[, length])

Extracts a substring from the current string using zero-based indexing.
When applied to arrays, each scalar element receives the same slicing
arguments recursively.

Examples:

  .title | substr(0, 5)       # => "Hello"
  .tags  | substr(-3)         # => ["erl", "SON"]

=item * abs()

Returns absolute values for numbers. Scalars are converted directly, while
arrays are processed element-by-element with non-numeric entries preserved.

Example:

  .temperature | abs      # => 12
  .deltas      | abs      # => [3, 4, 5, "n/a"]

=item * ceil()

Rounds numbers up to the nearest integer. Scalars and array elements that look
like numbers are rounded upward, while other values pass through unchanged.

Example:

  .price   | ceil     # => 20
  .changes | ceil     # => [2, -1, "n/a"]

=item * floor()

Rounds numbers down to the nearest integer. Scalars and array elements that
look like numbers are rounded downward, leaving non-numeric values untouched.

Example:

  .price   | floor    # => 19
  .changes | floor    # => [1, -2, "n/a"]

=item * round()

Rounds numbers to the nearest integer using standard rounding (half up for
positive values, half down for negatives). Scalars and array elements that look
like numbers are adjusted, while other values pass through unchanged.

Example:

  .price   | round    # => 19
  .changes | round    # => [1, -2, "n/a"]

=item * trim()

Removes leading and trailing whitespace from strings. Arrays are processed
recursively, while hashes and other references are left untouched.

Example:

  .title | trim          # => "Hello World"
  .tags  | trim          # => ["perl", "json"]

=back

=head1 COMMAND LINE USAGE

C<jq-lite> is a CLI wrapper for this module.

  cat data.json | jq-lite '.users[].name'
  jq-lite '.users[] | select(.age > 25)' data.json
  jq-lite -r '.users[].name' data.json
  jq-lite '.[] | select(.active == true) | .name' data.json
  jq-lite '.users[] | select(.age > 25) | count' data.json
  jq-lite '.users | map(.name) | join(", ")'
  jq-lite '.users[] | select(.age > 25) | empty'
  jq-lite '.profile | values'

=head2 Interactive Mode

Omit the query to enter interactive mode:

  jq-lite data.json

You can then type queries line-by-line against the same JSON input.

=head2 Decoder Selection and Debug

  jq-lite --use JSON::PP --debug '.users[0].name' data.json

=head2 Show Supported Functions

  jq-lite --help-functions

Displays all built-in functions and their descriptions.

=head1 REQUIREMENTS

Uses only core modules:

=over 4

=item * JSON::PP

=back

Optional: JSON::XS, Cpanel::JSON::XS, JSON::MaybeXS

=head1 SEE ALSO

L<JSON::PP>, L<jq|https://stedolan.github.io/jq/>

=head1 AUTHOR

Kawamura Shingo E<lt>pannakoota1@gmail.comE<gt>

=head1 LICENSE

Same as Perl itself.

=cut

