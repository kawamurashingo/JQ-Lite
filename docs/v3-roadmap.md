# JQ::Lite 3.0 roadmap

## Purpose

JQ::Lite 3.0 is the compatibility boundary for correcting selected runtime
semantics that cannot change safely in the stable 2.x series. Its goal is not
to implement every jq feature. It is to make the supported language more
predictable, move deliberately toward jq 1.7 where that benefits portable
filters, and preserve the lightweight, pure-Perl deployment model.

The current behaviour and the decision status of every known difference are
recorded in the [2.x semantic differences inventory](jq-semantics-differences.md).
That inventory is the source of truth for scope: this roadmap does not silently
turn an `undecided` item into a commitment.

## Compatibility policy

- The 2.x CLI and Library API contracts remain unchanged. Semantic corrections
  listed here are 3.0 changes and must not be backported to 2.x.
- The documented public Library API (`new` and `run_query`) remains supported.
  Version 3 changes query-language semantics, not the shape of those entry
  points.
- jq 1.7 is the comparison baseline for changes marked **change in v3**.
  Exact jq diagnostic text and unsupported jq facilities are not compatibility
  promises.
- Existing JQ::Lite extensions remain available unless a separate proposal
  documents their replacement and migration path.
- Every intentional incompatibility requires focused tests for both the new
  result and the migration guidance described below.

## Committed semantic changes

The following inventory items are approved for the 3.0 compatibility break.
They should be implemented as independently reviewable changes rather than as
one parser rewrite.

### Containment

- Make `contains(value)` use jq-style recursive containment for arrays and
  objects.
- Keep 2.x `contains_subset(value)` unchanged until its **undecided** status is
  resolved. It must not be presented as an exact alias for the new `contains`.

### Null, fallback, and paths

- Treat both `false` and `null` as absent for the `//` alternative operator.
- Emit `null` for a missing object field and for continued traversal through a
  missing field.
- Reject a numeric index applied to an object instead of returning `null`.

The direct-path missing-field correction is implemented by the scoped v3
path change: `.missing` and `.missing.value` yield one JSON null instead
of an empty output stream. This applies to straightforward dot-separated,
unquoted field paths only; quoted/optional paths and internal traversal
consumers keep their earlier behavior pending separate audits. A genuine
empty iterator (`.[]` on `[]`) still produces no output.
Numeric indices applied to objects now produce a structured evaluation
error instead of silently yielding null, including the direct `.[5]` form and
nested `.a[5]` where `a` holds an object. Numeric indexing into arrays
continues to work. This change is limited to numeric object indices; the
broader invalid-path policy remains a separate work item.

Numeric indexing on JSON null, null-valued array elements, and array
out-of-bounds slots now produces one JSON null rather than an empty result
stream in 3.x. This includes direct `null | .[5]`, nested
`{"a":null} | .a[5]`, and `[10] | .[5]` queries. A true empty iterator
(`[] | .[]`) continues to produce no output. The change is limited to
numeric-index query paths; it does not imply a decision on other invalid
path types or internal helper traversal.

The error policy for other invalid paths remains undecided and is not implied
by these changes.

### Arithmetic and comparison

- Reject boolean operands in arithmetic expressions.
- Keep JSON scalar types distinct for equality, so a numeric-looking string is
  not equal to a number.
- Compare arrays lexicographically using jq-compatible value ordering.

Numeric-looking strings are now rejected by numeric arithmetic in the 3.x
developer-release series; callers that intend conversion should use
`tonumber()` or `to_number()` explicitly. Regex scalar coercion remains
undecided and is not changed by the arithmetic work.

### Assignment and update

- Make update assignment (`|=`) emit the updated root value.
- Allow update assignment to create a missing target using the same input
  semantics as jq.

The supported `path |= filter` form now evaluates the right-hand filter against
the **old target value** (JSON null for missing targets), writes that value to
the target, and emits the entire updated root. The first implementation is
intentionally restricted to simple dotted object keys and nonnegative literal
array indices, including nested combinations. A null root can grow into the
required object or array. Invalid intermediate container types raise structured
runtime errors rather than silently dropping the update.

The update operator now also supports jq 1.7's zero-result deletion: when
the RHS produces no values (such as `empty` or `select(false)`), it deletes
the selected object key or splices out the selected array element, then emits
the updated root. Missing targets and out-of-range indices are no-ops; no
intermediate objects or arrays are created solely to delete a path, and
`null | .a |= empty` continues to produce `null`. This differs from
`path |= null`, which **retains** the field or array slot with JSON null.

When the RHS produces multiple values, update assignment now takes the **first
emitted result** and returns one updated root, matching jq 1.7 for the supported
simple-path expressions. JSON `null` and `false` are valid first results and
are not confused with an empty result stream. For example, `.a |= (10,20)`
updates `a` to `10`; `.a |= (empty,5)` uses `5`; only an entirely empty
RHS deletes the path.

The current engine still eagerly evaluates the RHS before selecting its first
result, unlike jq's streaming evaluation: a later result that raises an error
may affect a query even when jq would have stopped at the first result.
Iterator/computed update paths and the relationship with compound `+=` and
other operators require separate audits under #626. Do not assume complete jq
assignment compatibility.

Multi-result **plain** assignment remains undecided and requires a separate design.

## Explicitly preserved scope

The following choices continue in 3.0 unless separately reconsidered:

- vectorised `floor`, `ceil`, `round`, `fromjson`, and related lossless helpers;
- array path projection;
- JQ::Lite convenience and statistical functions;
- truncating jagged `transpose` behaviour;
- the absence of modules/imports and jq's streaming parser mode; and
- the pure-Perl implementation and Perl 5.14 minimum.

Iterator suffixes, plain assignment, cross-type ordering, and missing-value
comparison already match the audited jq cases and are regression guards, not
3.0 work items.

## Undecided items and decision gates

An undecided behaviour may enter 3.0 only after a focused proposal includes:

1. examples of jq 1.7 and JQ::Lite 2.x behaviour;
2. known compatibility impact on existing filters;
3. the proposed result and error policy;
4. migration guidance; and
5. dependency-free regression tests.

This gate applies to numeric-string arithmetic, regex scalar coercion, invalid
path errors, mixed iterator pipelines, multi-result assignment, unsupported
parser syntax, control flow, and the future role of `contains_subset`.
Unresolved items retain their 2.x behaviour in 3.0.

## Delivery sequence

1. **Freeze the baseline.** Keep the 2.x inventory and regression tests intact.
2. **Build shared semantics.** Use the internal `JQ::Lite::Value` type and
   comparison primitives, then introduce path-result primitives, without
   changing public behaviour.
3. **Land isolated changes.** Implement containment, fallback/path,
   arithmetic/comparison, and update-assignment changes in separate reviews.
4. **Publish migration notes.** Provide before/after examples and replacements
   for filters whose output or failure mode changes.
   Differential fixture format, compatibility statuses, and opt-in execution
   are documented in [jq differential testing](jq-differential-testing.md).
5. **Validate the release candidate.** Run the full Perl test suite on all
   supported Perl versions and differential tests against jq 1.7 for every
   committed compatibility case.

## Migration guidance

Applications that need one code path across 2.x and 3.x should avoid relying
on the changed edge cases until they can require 3.0. Some changed semantics,
including the result of update assignment, cannot be normalized by appending a
filter that works in both major versions; those cases require version-aware
application logic. In particular:

| 2.x-dependent filter | 3.0-safe migration approach |
| --- | --- |
| `contains(...)` expecting exact array elements or nested object equality | express exact equality explicitly before upgrading |
| `false // fallback` expecting `false` | use an explicit null test when `false` is data; in v3 `false // 9` returns `9` |
| a missing path as an empty output stream | use `empty`/selection explicitly rather than relying on implicit dropping |
| arithmetic with booleans | convert the boolean to the intended number explicitly |
| arithmetic with numeric-looking strings | convert explicitly with `tonumber()` or `to_number()` before using `- * / %` or numeric `+` |
| equality between numeric strings and numbers | normalize both sides explicitly with `tonumber` or `tostring` |
| `path |= filter` expecting only the updated leaf | no single appended filter preserves this result in both versions; keep the original filter on 2.x, and only after requiring 3.0 append the path projection or select the leaf in version-aware application code |

Release notes must include concrete, executable examples for each committed
change. Library consumers should also review code that assumes `run_query`
returns no value for a missing field; in 3.0 that query returns one JSON null.

## 3.0 release criteria

JQ::Lite 3.0 is ready only when:

- every **change in v3** inventory row is implemented or explicitly deferred
  with a documented reason;
- every changed behaviour has jq 1.7 differential coverage and a direct
  JQ::Lite regression test;
- all preserved and still-undecided inventory rows remain covered;
- CLI and Library API contract suites pass unchanged;
- migration notes cover every intentional output or error change; and
- the complete distribution test suite passes on the supported Perl range.
