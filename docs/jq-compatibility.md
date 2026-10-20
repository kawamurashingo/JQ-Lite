# jq 1.7 compatibility guide for JQ::Lite 3.x

This guide describes the **practical JQ::Lite v3 developer-branch subset**,
not a released 3.0 compatibility guarantee and not general jq conformance.
Stable `main` continues to carry 2.x. The v3 baseline is the useful
functionality already available in v2; extra jq syntax and unusually deep
computed selectors are not release goals. jq **1.7.x** is the reference
version for the differential fixtures.

Use this guide together with the [v2-to-v3 migration guide](v3-migration.md).
The [v3 roadmap](v3-roadmap.md), [practical path inventory](v3-practical-path-audit.md),
[arithmetic contract](v3-arithmetic.md) and
[assignment audit](v3-assignment.md) give the boundaries behind each row.

## How to read the classifications

These terms match `t/data/jq-differential.jsonl` and the
[differential harness](jq-differential-testing.md):

| Status | Meaning | Test policy |
| --- | --- | --- |
| **compatible** | This specifically tested input/filter behavior agrees with jq 1.7, including ordered results or the runtime-error category. | Differential CI gates the recorded fixture. |
| **known-difference** | Both understand the practical operation, but the current JQ::Lite meaning differs; it may deliberately preserve v2 behavior. | jq behavior is recorded; parity is **not** promised. |
| **unsupported** | The jq facility or target form is outside the supported JQ::Lite subset; do not rely on incidental fallback output. | Not a jq compatibility claim. |
| **planned** | A separately approved behavior change that has not been implemented and tested yet. | Not treated as compatible until fixed and tested. |

The rows below summarize *specific* audited forms. They are not a blanket
rating for an operator, builtin or parser family. No unresolved #625/#626
decision is silently promoted to `planned`; there are currently no
additional `planned` promises in this guide.

## Representative compatibility matrix

| Area | Input and filter | Status | Scope or observable behavior |
| --- | --- | --- | --- |
| Direct field read | `{};` `.missing` | **compatible** | One JSON `null` rather than an empty stream, for ordinary unquoted fields. |
| Missing nested field | `{};` `.missing.value` | **compatible** | One JSON `null` in the audited direct-path subset. |
| Object numeric index | `{};` `.[5]` | **compatible** | Structured runtime type error; not silent null. |
| Array iterator | `[2,3];` `.[]` | **compatible** | Emits 2 then 3; `[] \| .[]` produces no output. |
| Alternative | `false;` `. // []` | **compatible** | Returns `[]`; `null // []` is also covered. |
| Strict addition | `"1";` `. + 1` | **compatible** | Numeric-looking string plus number raises a runtime type error. |
| Typed comparison | `"10";` `. == 10` | **compatible** | Returns `false` (string is not number). |
| Array ordering | `[1,2];` `. < [1,3]` | **compatible** | Lexicographic comparison returns `true`. |
| Literal containment | `[1,2,3];` `contains([1,3])` | **compatible** | Recursive jq-style containment for the literal-argument subset. |
| UTF-8 string search | `"日本語";` `index("本")` | **compatible** | Byte offset 3 rather than a Perl character index. |
| Ordinary assignment | `{"a":1};` `.a = 2` | **compatible** | Emits the updated root object. |
| Update assignment | `{"a":1};` `.a \|= . + 1` | **compatible** | Evaluates RHS on old target and emits updated root. |
| Update deletion | `{"a":1};` `.a \|= empty` | **compatible** | Removes the key, not a JSON-null replacement. |
| Scalar-root assignment | `null;` `.a = 2` | **known-difference** | Ordinary assignment retains v2's unchanged null root; jq creates an object. |
| Compound assignment | `{"n":"2"};` `.n += 2` | **known-difference** | Retains v2 numeric-string coercion; strict v3 arithmetic does **not** extend to `+=`. |
| Jagged transpose | `[[1,2],[3]];` `transpose` | **known-difference** | Retained v2 truncation rather than jq's null padding. |
| Array path projection | `[{"x":1},{"x":2}];` `.x` | **known-difference** | Retained v2 projection through array members rather than jq's type error. |
| Scalar path leaves | `{"x":null};` `paths(scalars)` | **known-difference** | Retained v2 null-leaf inclusion; jq 1.7 excludes null leaves. |
| Plain slice assignment | `{"a":[1,2,3]};` `.a[0:1] = [9]` | **unsupported** | v3 rejects target before mutation; no truncated-prefix assignment. |
| Arbitrary jq definitions | `null;` `def inc: .+1; inc` | **unsupported** | No general jq user-defined function language. |
| jq import/modules | `import "x" as x; ...` | **unsupported** | Outside the lightweight query and CLI subset. |
| jq streaming CLI | `--stream` | **unsupported** | jq's streaming parser option is not implemented. |

A semicolon between input and filter in the table is explanatory punctuation,
**not part of the filter**. `compatible` describes these audited results,
not all type combinations or nested spellings. Empty output, one JSON null,
and a structured runtime error are three different outcomes.

## JQ::Lite-specific facilities

The following may be useful when migrating existing scripts, but their names
or meanings should not be mistaken for universal jq 1.7 compatibility:

- `contains_subset(value)` is a v2 extension with multiset accounting and
  string-coerced scalar comparison. It is **not** an alias of v3 `contains`.
- `to_number()`, `flatten_all()`, `flatten_depth(n)`, `avg`,
  `median`, `mode`, and other helpers remain JQ::Lite extensions.
- `slice(start,length)` is separate from jq-style `[start:end]`;
  `leaf_paths` and the `paths()` spelling also have distinct v2 contracts.
- Compound assignments keep their documented v2 behavior. Do not infer from
  the typed `+`, `-`, `*`, `/`, and `%` expression contract that their
  compound forms are all jq-compatible.

Unsupported expressions, unreviewed invalid-path cases and broader streaming
combinations must not be assumed to pass or fail like jq. Work is tracked by
[#625](https://github.com/kawamurashingo/JQ-Lite/issues/625)
(paths) and [#626](https://github.com/kawamurashingo/JQ-Lite/issues/626)
(assignments). The proposed `compile()` API in
[#627](https://github.com/kawamurashingo/JQ-Lite/issues/627) is **deferred**,
not an existing v3 public API or a 3.0 release condition.

## Practical assignment release boundary (#626)

The proposed 3.0 decision retains established v2 ordinary and compound
setters rather than extending jq assignment grammar. The 101-case
assignment audit records **40 compatible** results, **39 intentional
known differences** and **22 unsupported** forms; these categories
describe the *audited expressions*, not the operator names universally.
The existing `|=` subset evaluates RHS against the old target and returns
the updated root. Numeric-looking strings may still be coerced by
`+=`/`-=`/`*=`/`/=`, even though equivalent strict v3 arithmetic
expressions reject them. A rejected ordinary/compound bracket selector
reports an Evaluation/runtime error in JQ::Lite; it remains marked
`unsupported` for jq compatibility, not `compatible` merely because
the failure is structured.

Six additional unsupported multi-path/plain-RHS/update forms have no
promised incidental result. See the [assignment release audit](v3-assignment.md)
and [migration examples](v3-migration.md). The #626 sign-off still requires
final CI and review of this proposed decision.

## Stable integration boundary

The [CLI contract](cli-contract.md) remains in force: exit 0 success;
`-e` can return 1 for a false/null/empty result; compile, runtime, input
and usage errors are exits **2, 3, 4, 5** respectively. Errors keep
`[COMPILE]`, `[RUNTIME]`, `[INPUT]`, `[USAGE]` stderr prefixes and
empty stdout. Compile-before-input, UTF-8 handling and broken-pipe behavior
are protected by their contract tests. Exact jq diagnostic wording is **not**
promised.

The public [Library contract](library-contract.md) continues to use
`JQ::Lite->new` and `run_query`, returning ordered Perl-list results and
structured `JQ::Lite::Error::{Input,Parse,Evaluation}` categories.
Internal parser/builtin/util packages are not public API promises. Perl 5.14
support and the existing CPAN dependency footprint remain required.

## Verifying a candidate filter

Run the independent distribution tests without installing jq:

```sh
prove -lr t
```

With jq **1.7.x** available, run the recorded cross-engine comparisons:

```sh
JQ_DIFFERENTIAL=1 prove -l t/jq_differential.t
```

The differential suite checks ordered JSON results and success/runtime-error
categories for its fixtures. It does **not** prove that every jq expression,
every CLI option, every error message, or every possible input is compatible.
If your query is not in the supported practical subset, test that exact
filter/input pair before deployment.
