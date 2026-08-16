# JQ::Lite Library API Contract

This document defines the backward-compatibility contract for applications and CPAN distributions that use `JQ::Lite` as a Perl library.

The goal is to make it safe for downstream code to depend on the documented public API while still allowing JQ::Lite internals to evolve.

## Stable public API

For the 2.x series, the following entry points are part of the stable Library API:

```perl
use JQ::Lite;

my $jq = JQ::Lite->new(%options);
my @results = $jq->run_query($json_text, $query);
```

The compatibility guarantees in this document apply only to behavior documented as public. Internal packages, private methods, undocumented object fields, and implementation details are not covered by this contract.

## Constructor contract

`JQ::Lite->new(%options)` returns a `JQ::Lite` object.

The currently documented constructor options are:

- `raw` — enables raw-output behavior where applicable.
- `vars` — accepts a hash reference of predeclared jq-style variables.

Within a major release series, documented option names and their meanings will not be removed or changed incompatibly.

New optional constructor arguments may be added in minor releases when they do not alter the behavior of existing calls.

## `run_query` contract

`$jq->run_query($json_text, $query)`:

- accepts JSON text as its first argument;
- accepts a jq-like query string as its second argument;
- returns zero or more results as a Perl list;
- represents object results as hash references and array results as array references;
- returns scalar JSON values as the corresponding Perl scalar representation.

The number and ordering of results are part of the observable behavior of a documented query feature and will not be changed incompatibly within the same major release series.

A query that is undefined or consists only of `.` returns the decoded input value.

## Compatibility policy

Within a major release series, JQ::Lite will preserve compatibility for the documented Library API in the following areas:

- public method names;
- documented argument meanings;
- documented return-value semantics;
- documented constructor options;
- documented error categories and observable error behavior once explicitly covered by this contract.

Bug fixes may change behavior when the previous behavior was incorrect, unsafe, or inconsistent with documented jq-lite semantics. Such changes should be called out in the changelog when they may affect downstream callers.

Adding new methods, options, supported jq syntax, or result types that do not change existing documented behavior is considered backward compatible.

## Breaking changes

A deliberate incompatible change to this stable Library API requires a major version bump.

Examples include:

- removing or renaming a documented public method;
- changing the meaning of an existing documented argument;
- changing `run_query` from list-returning semantics to a different return contract;
- removing a documented constructor option;
- changing documented error behavior in a way that requires downstream code changes.

When a breaking change is unavoidable, it should be documented in `Changes` together with a migration path where practical.

## Errors

At the time this contract was introduced, JQ::Lite does not yet promise a structured exception-class API for library callers.

Callers should therefore not parse exact exception text as a stable machine-readable interface unless that text is explicitly documented elsewhere as contractual.

A future structured error API may strengthen this section without weakening the compatibility guarantees above.

## Public versus internal modules

`JQ::Lite` is the supported library entry point.

Submodules used by the implementation, including parser, filter, expression, and utility packages, are not automatically part of the public compatibility contract merely because they are installed with the distribution. Any submodule that becomes public will be documented explicitly.

## Testing expectations

Behavior covered by this contract should be protected by regression tests where practical. New stable public APIs should include tests for their documented argument and return-value semantics.

The existing test suite already exercises `JQ::Lite->new` and `run_query` extensively through supported query behavior; dedicated Library API compatibility tests may be added as the public surface grows.

## Versioning principle

The Library API follows the same general stability principle as the CLI contract: downstream users should not need to rewrite working integrations because of a minor release.

In short:

> Documented public Library API behavior is stable within a major release series; intentional breaking changes require a major version bump.
