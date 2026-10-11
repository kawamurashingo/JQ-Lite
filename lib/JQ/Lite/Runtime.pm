package JQ::Lite::Runtime;

use strict;
use warnings;

use JQ::Lite::Error ();
use JQ::Lite::Filters ();
use JQ::Lite::Util ();

sub new {
    my ($class, %opts) = @_;
    die 'runtime owner is required' unless $opts{owner};
    return bless { owner => $opts{owner} }, $class;
}

sub decode_input {
    my ($self, $json_text) = @_;

    my ($value, $ok, $error);
    {
        local $@;
        $ok = eval {
            $value = JQ::Lite::Util::_decode_json($json_text);
            1;
        };
        $error = $@;
    }

    return $value if $ok;
    die $error if ref($error) && eval { $error->isa('JQ::Lite::Error') };
    die JQ::Lite::Error::Input->new(message => $error);
}

sub evaluate_filter {
    my ($self, $filter, $inputs) = @_;

    my @outputs;
    if (JQ::Lite::Filters::apply(
            $self->{owner}, $filter->source, $inputs, \@outputs
        ))
    {
        return @outputs;
    }

    # Scoped v3 field/iterator paths are evaluated step by step.  Parse
    # literal JSON-quoted keys without splitting on the dots inside them.
    # Only paths containing [] or []? are intercepted; existing bare
    # field/index and compatibility-sensitive computed-path behavior stays.
    my $source = $filter->source;
    my $path_steps = JQ::Lite::Util::_parse_v3_literal_iterator_path(
        $source
    );
    if ($path_steps) {
        for my $input (@{$inputs}) {
            push @outputs, JQ::Lite::Util::_traverse_v3_field_iterator(
                $input, $source, $path_steps
            );
        }
        return @outputs;
    }

    # Only direct unquoted field paths have an approved v3 null-on-missing
    # contract. Do not reclassify unrecognized expressions/assignments as
    # missing object fields; their behavior has separate roadmap decisions.
    my $is_direct_field_path = $source =~
        /\A[A-Za-z_][A-Za-z_0-9]*(?:\[\d+\]|\[\])*(?:\.[A-Za-z_][A-Za-z_0-9]*(?:\[\d+\]|\[\])*)*\z/;

    for my $input (@{$inputs}) {
        push @outputs, JQ::Lite::Util::_traverse(
            $input, $source,
            {
                missing_object_null => $is_direct_field_path ? 1 : 0,
                numeric_object_index_error => $source =~ /\[\d+\]/ ? 1 : 0,
                numeric_null_index => $source =~ /\[\d+\]/ ? 1 : 0,
            }
        );
    }

    return @outputs;
}

1;
