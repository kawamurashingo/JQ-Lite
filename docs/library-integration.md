# Using JQ::Lite as a Perl Library

`JQ::Lite` can be used directly by applications and CPAN distributions that need jq-like JSON querying without invoking an external `jq` binary.

## Minimal example

```perl
use strict;
use warnings;
use JQ::Lite;

my $json = <<'JSON';
{"users":[{"name":"Alice"},{"name":"Bob"}]}
JSON

my $jq = JQ::Lite->new;
my @names = $jq->run_query($json, '.users[].name');

print "$_\n" for @names;
```

`run_query` returns a Perl list. JSON objects are returned as hash references and JSON arrays as array references.

## Filtering data

```perl
use JQ::Lite;

my $jq = JQ::Lite->new;
my @names = $jq->run_query(
    $json,
    '.users[] | select(.active == true) | .name'
);
```

This is useful inside API clients, importers, CI helpers, log processors, and other modules that already receive JSON text.

## Working with structured results

```perl
my ($user) = $jq->run_query(
    $json,
    '.users[] | select(.id == 42)'
);

if (ref $user eq 'HASH') {
    print $user->{name}, "\n";
}
```

Callers should use list context deliberately because one query may emit zero, one, or multiple results.

## Constructor variables

Predeclared jq-style variables can be supplied with `vars`:

```perl
my $jq = JQ::Lite->new(
    vars => {
        wanted_id => 42,
    },
);
```

Only documented constructor options are part of the stable Library API contract.

## Declaring JQ::Lite as a dependency

For a distribution using `ExtUtils::MakeMaker`:

```perl
WriteMakefile(
    NAME => 'My::Module',
    PREREQ_PM => {
        'JQ::Lite' => '2.49',
    },
);
```

Choose the minimum JQ::Lite version that provides the behavior your distribution actually requires rather than automatically pinning to the newest release.

For `cpanfile`:

```perl
requires 'JQ::Lite', '>= 2.49';
```

## Error handling

Library calls may throw exceptions for invalid JSON, invalid query syntax, or evaluation failures.

Until a structured exception API is explicitly documented as stable, downstream code should treat exception text as human-readable diagnostics rather than parse exact strings as a machine-readable interface.

```perl
my @results;
my $ok = eval {
    @results = $jq->run_query($json, $query);
    1;
};

if (!$ok) {
    my $error = $@;
    # Log or surface the diagnostic. Do not depend on exact message text.
}
```

See [`library-contract.md`](library-contract.md) for the compatibility guarantees that apply to Library API callers.

## Public API boundary

Downstream distributions should depend on the `JQ::Lite` package itself:

```perl
use JQ::Lite;
```

Implementation packages such as `JQ::Lite::Parser`, `JQ::Lite::Filters`, and `JQ::Lite::Util` are internal unless explicitly promoted to public API in the Library API contract.

## Recommended integration checklist

- Depend on `JQ::Lite`, not internal submodules.
- Use `run_query` in list context and handle zero or multiple results.
- Choose a minimum dependency version based on features actually used.
- Do not parse undocumented exception strings.
- Review the Library API contract before relying on newly introduced public behavior.
