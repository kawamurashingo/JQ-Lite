# Practical assignment audit for JQ::Lite 3.x

This checkpoint distinguishes ordinary `=`, the audited v3 `|=` update,
and retained v2 compound assignment. They do not yet share every path,
type or stream rule. Issue #626 remains open for the remaining semantic
decisions; recording a difference does not silently approve a new break or
promise full jq assignment grammar.

## Supported practical forms

| Form | Input used by the RHS | Output / scope |
| --- | --- | --- |
| `.a = value` | Original root for an existing path/variable RHS | One root with a literal, copied path value or variable; existing named fields and compact literal numeric indices |
| `.a \|= filter` | Old selected target, null for a missing target | Updated root; empty RHS deletes; first accepted RHS value replaces |
| `.a += n`, `-=`, `*=`, `/=` | Existing target plus RHS resolved from the root | Existing v2 numeric-coercion behavior; not aliases for strict v3 expression operators |

For ordinary assignment, compact `[N]` / `[-N]` indices retain existing
behavior, including negative indexing and array growth with null-filled
gaps. Missing/null intermediate object fields grow into containers. The
existing string/JSON-number variable bindings work in literal-field targets.
Single-quoted literal assignment remains a v2 extension covered by
`t/assignment.t`, not a jq syntax claim.

The v3 `|=` subset supports literal named fields/nonnegative numeric indices
and the existing array/object iterator paths. It keeps the updated root,
evaluates the RHS on the old target, creates missing targets, distinguishes
null/false from no output, deletes on empty output, and reports invalid
target types as structured errors. Its existing first-result visitor,
iterator ordering and generator limitations remain documented in the
[v3 roadmap](v3-roadmap.md); this audit adds no new update grammar.

## Reject unsupported bracket targets before mutation

The legacy ordinary/compound setter only understands compact literal numeric
brackets. Previously, an unsupported bracket could be discarded and the
remaining prefix assigned successfully. For example:

```text
input:  {"a":[1,2,3]}
filter: .a[0:1] = [9]
v2:     {"a":[9]}
```

That replaces the whole `a` array instead of assigning the slice. V3 now
raises `JQ::Lite::Error::Evaluation` for these targets before resolving the
RHS or mutating the root. The same restriction applies to plain/compound
iterator, computed, quoted, internally spaced and nested unsupported bracket
selectors, as well as an optional suffix after a numeric index (`.a[0]?`),
including on a null input. These forms are classified as unsupported
and are not jq-compatible assignment claims.

Use existing compact literal indices for known slots, such as `.a[0] = 9`.
For a per-member replacement, the existing `.a[] |= 9` update form is
available. Slice/computed plain targets require a separate design rather
than a partial-prefix fallback. Read-side slicing and valid literal-index
assignment keep their existing behavior.

## Retained differences requiring separate decisions

| Example | Current JQ::Lite | jq 1.7 |
| --- | --- | --- |
| `null` with `.a = 2` | null root is unchanged | Creates `{"a":2}` |
| `{"a":1}` with `.a.x = 2` | Root is unchanged | Runtime type error |
| `{"a":{}}` with `.a[0] = 2` | Root is unchanged | Runtime type error |
| `{"a":[1]}` with `.a[-2] = 2` | Root is unchanged | Runtime out-of-range error |
| `{"n":"2"}` with `.n += 2` | Coerces to numeric 4 | Runtime type error |
| `{"n":null}` with `.n -= 2` | Coerces null to zero, producing -2 | Runtime type error |
| `{"n":10}` with `.n /= 0` | Root is unchanged | Runtime zero-divisor error |
| `{"n":"a"}` with `.n += "b"` | Root is unchanged | Concatenates to `"ab"` |

Compound assignment also retains boolean 0/1 coercion and numeric-looking
string conversion. Nonnumeric values leave the root unchanged. These are
existing v2 behaviors, **not** the strict expression contract from
[the arithmetic guide](v3-arithmetic.md). This checkpoint deliberately
records their boundary without silently changing those assignment semantics.

Multi-target `(.a,.b) = ...` / `|= ...`, multi-result plain RHS, root-only
plain assignment, negative `|=` indices and arbitrary arithmetic/filter
plain RHS are outside this audited subset. They are tracked as unsupported
fixtures without freezing their incidental fallback values as a Library
contract. In particular, an expression such as `.a = .b + 1` is not
advertised as general filter-valued plain assignment.

## Reproducible behavior matrix

The audit compares 101 cases with jq 1.7:

| Scope | Cases | Classification |
| --- | ---: | --- |
| Ordinary assignment | 23 | 19 compatible, four known differences |
| Existing compound assignment | 42 | Seven compatible, 35 known differences |
| Audited `\|=` update | 14 | All compatible |
| Unsupported bracket targets rejected by this change | 16 | Unsupported; structured-error regression |
| Other unsupported stream/target forms | 6 | Unsupported; no incidental-result promise |

Thus 40 cases are compatible, 39 are known differences and 22 are unsupported.
The shared differential file gains 100 cases and annotates one existing case.
`assignment_v3` outcomes protect 95 current results/errors through the public
Library API; the six unpromised forms are deliberately excluded. The sixteen
new selector rejections check the structured Evaluation error even though
their unsupported differential fixtures are not presented as jq parity.

```sh
prove -l t/assignment.t t/v3_update_assignment.t t/v3_assignment_audit.t
JQ_DIFFERENTIAL=1 prove -l t/jq_differential.t
```

All 65 recorded ordinary/compound results were also checked against stable
v2.59 (`6880c304`) without changing that branch. To reproduce that subset:

```sh
v2_assignment_dir=$(mktemp -d)
git archive 6880c30440b564480d9971d575179513e16ed51f lib |
    tar -x -C "$v2_assignment_dir"
JQ_AUDIT_V2=1 prove -I"$v2_assignment_dir/lib" t/v3_assignment_audit.t
```

The new rejection is a v3 migration change: callers relying on a truncated
prefix must replace that query with an explicitly supported target. It uses
the existing CLI runtime error category (exit 3) and structured Library error.
No public API, dependencies or syntax support are added. Main/stable 2.x is
unchanged. The known ordinary/compound differences and unsupported forms
remain part of #626's scope/migration review.
