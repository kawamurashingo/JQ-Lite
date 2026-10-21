# JQ::Lite 3.0 beta1 candidate — draft notes

**Status: INTERNAL CANDIDATE; NOT PUBLISHED.** These notes describe the
proposed first beta checkpoint for the **practical v2.59 feature subset**.
They do **not** announce a release, authorize a CPAN upload or tag, or claim
complete jq conformance. See the [release readiness gate](v3-release-readiness.md)
and [roadmap #619](https://github.com/kawamurashingo/JQ-Lite/issues/619).

## Candidate identity and version policy

| Item | Proposed identity |
| --- | --- |
| Human-facing milestone | JQ::Lite 3.0 **beta1 candidate** (not released) |
| Perl / CPAN developer version | `$JQ::Lite::VERSION = '3.00_02'` |
| Expected source archive | `JQ-Lite-3.00_02.tar.gz` (CI artifact only) |
| Preceding development version | `3.00_01` (retained in `Changes`) |
| Future stable Perl version | **Not yet chosen.** `3.00` is allowed only if the `3.00_0x` developer archives remain **permanently unpublished**; otherwise choose a strictly newer public stable version after verifying Perl ordering |
| Stable deployed branch | `main`, JQ::Lite **2.59** (untouched) |

Perl distribution versions and the human-facing milestone have different
formats: `3.00_02` is an **underscore developer release**, not a public
SemVer `3.0.0-beta1` Git tag. **All `3.00_0x` developer artifacts in
this release train must remain permanently unpublished**: no CPAN upload,
GitHub Release, publicly advertised install link, or public beta/RC tag.
The GitHub Actions tarballs are short-lived **internal test artifacts**;
their existence is not a public beta publication. Previous alpha milestones
were development checkpoints; these notes do not claim separate published
alpha artifacts. The final candidate SHA is established **after** review.

### Perl developer-to-stable ordering: release blocker

**Perl's version ordering is not SemVer pre-release ordering.** Using
`version->parse`, `3.00_02` sorts **after** `3.00`. If an underscore
developer archive is publicly distributed, then later publishing stable
`3.00` would make that stable appear older to CPAN clients and dependency
resolvers. Simply removing `_02` for stable does **not** resolve this.

The project currently chooses the **internal-only** branch of the policy:
keep `3.00_01`, `3.00_02`, and any further `3.00_0x` artifacts
**permanently unpublished** and verify this before any public stable
release. Under that strict condition `3.00` can remain an *option*,
not a finalized stable version. Anyone who manually installed one of
these internal builds may need to uninstall/reinstall the stable release;
ordinary version-based upgrades should **not** be assumed to work.

If a *public* beta/RC is desired or any `3.00_0x` build has already
been officially distributed, stop and approve a new version sequence
before publication. The chosen stable Perl version must compare **strictly
greater** than every publicly distributed predecessor; a stable `3.00`
would then be prohibited. Also review how a higher Perl version number
maps to the announced 3.0 release name. Do not invent a public version,
renumber a shipped archive, or silently declare a lower version stable.

Reproduce the ordering using Perl's core `version` module:

```sh
perl -Mversion -e 'print version->parse("3.00_02") > version->parse("3.00") ? "developer > stable candidate\n" : "unexpected order\n"'
```

**Before any RC/stable publication**, the maintainer must document which
artifacts were publicly distributed and approve either the internal-only
`3.00_0x` policy or a strictly increasing public version sequence.

## What changes in the supported practical subset

- **Typed JSON arithmetic and comparison.** Numeric-looking strings and
  booleans no longer silently become numbers in ordinary arithmetic;
  `+` retains its documented null identity, string concatenation, array
  concatenation and shallow object merge. `/` and `%` with zero
  divisors raise structured runtime errors. Type-aware comparisons stay
  in the audited JSON operand scope.
- **Field, iterator and empty-stream behavior.** A missing ordinary object
  field emits one JSON null, not no outputs. Supported strict iterators on
  invalid inputs raise runtime errors; optional iterators skip them.
  Empty constructors preserve the distinction between null and no output.
  `false // fallback` now returns the fallback.
- **Practical update semantics.** Supported `path |= filter` evaluates the
  RHS on the old target, returns the updated **root**, and deletes the
  selected path if the RHS emits nothing. A missing target may be created.
  Ordinary `=` and compound assignment retain separately audited v2
  differences; they are **not** blanket jq-compatible operations.
- **Selected compatibility fixes and maintenance.** Previously approved
  containment, search-position, path and iterator corrections remain
  covered by the same jq 1.7 differential harness. Source-size and
  maintainability work did not add new public APIs or dependencies.

### Migration examples (illustrative audited forms)

| Input / filter | Stable 2.59 | Proposed beta1 candidate |
| --- | --- | --- |
| `{"n":"2"}` / `.n * 2` | Numeric-string coercion | Structured runtime type error; normalize explicitly |
| `false` / `. // 9` | `false` | `9` |
| `{}` / `.missing` | No outputs | One JSON `null` |
| `null` / `.[]` | No outputs | Runtime iterator type error; use `.[]?` to skip |
| `{"a":1}` / `.a |= . + 1` | Selected value `2` | Updated root `{"a":2}` |
| `{"n":"2"}` / `.n += 2` | `{"n":4}` | **Still `{"n":4}`**, retained v2 compound coercion |

These are concrete migration cases, not a promise for every jq filter.
Review the [compatibility matrix](jq-compatibility.md),
[arithmetic contract](v3-arithmetic.md),
[assignment contract](v3-assignment.md),
[path/iterator audit](v3-practical-path-audit.md) and
[migration guide](v3-migration.md) before changing application queries.

## jq 1.7 compatibility and retained differences

At the frozen pre-beta checkpoint, `t/data/jq-differential.jsonl` has
**4,037 fixtures**: **3,940 compatible**, **74 known differences**,
**23 unsupported** and **zero planned**. The 408 arithmetic contract
cases include 12 documented jq nonnumeric-overload differences; the
101 assignment cases include 39 retained ordinary/compound differences
and 22 unsupported forms; the bounded 54 jq-recognized path/iterator
samples include four retained v2 differences.

These scopes **overlap** the 4,037 fixtures; their subcounts must not be
added to derive a repository-wide total. Fixtures marked
`known-difference` and `unsupported` are **not parity promises**.
The **compatible** cases are the jq 1.7 differential gate. Recount
fixtures and review status changes on the final candidate HEAD.

Retained compatibility boundaries include array-field projection,
scalar-field no-output behavior, string bracket-slice passthrough, the
v2-only `slice(start,length)` helper and v2 compound numeric coercion.
No arbitrary jq `def` / modules, full streaming grammar, rare deep
computed selectors or new `compile()` API (#627) is added for beta1.

## Public CLI / Library contract and platform policy

`JQ::Lite->new` and `run_query` remain the public Library entry
points. Preserve list results in order, including the distinction
between zero results and one null, and structured
`JQ::Lite::Error::Evaluation` runtime errors. The CLI's exit 0/1/2/3/4/5
categories, stderr prefixes, empty stdout on errors, compile-before-input
and SIGPIPE/EPIPE behavior remain contract-checked.

Target **Perl 5.14+**, pure Perl, and the existing prerequisite set
without new CPAN modules or native dependencies. This is a development
release candidate; keep stable `main` / 2.x unchanged.

## Beta1 promotion gate (all evidence must match the final SHA)

- [ ] Maintainer explicitly accepts bounded #623, #625 and #626
  dispositions (and records their issue closure or a specific blocker).
  #629 migration/matrix documentation is already closed; #627 is deferred.
- [ ] Final candidate **Push HEAD** and its associated **PR
  head/base/synthetic-merge** identities are recorded with workflow URLs.
  All Perl **5.14, 5.26, 5.38, latest** Push and PR jobs pass.
- [ ] Both jq **1.7.x** Push/PR differential workflows pass on those refs,
  with no silent fixture downgrade to `known-difference`.
- [ ] `v3 source distribution candidate` CI passes **both Perl 5.14
  and latest**, including source-tree tests, `make disttest`, a full
  test run against the **actual extracted tarball**, separate-prefix
  installation and installed CLI/Library smoke checks.
- [ ] `t/v3_release_metadata.t` passes for the new version and matching
  `Changes` / POD. Confirm the exact tarball includes this document,
  compatibility docs, tests and jq comparison fixtures.
- [ ] Codex reviews **final HEAD**, all findings are resolved, and the
  candidate's release notes and known limitations receive maintainer
  approval. Record whether `3.00_0x` archives have been distributed;
  enforce the version ordering gate before public release. No tag, CPAN
  upload or GitHub Release in this PR.

## RC1 and stable promotion

After an approved beta1 candidate, accept **only release blockers**:
regressions within the frozen v2 practical scope, unexpected supported
jq-parity changes, CLI/Library API breaks, portability/packaging failures,
or missing migration/release evidence. Re-run every beta gate on an
**independent RC candidate commit and distribution archive**; do not
reuse beta CI URLs for RC approval. Choose the next developer version
and RC announcement only when creating that RC candidate.

For stable 3.0, **first close the Perl-version ordering gate** above:
verify the `3.00_0x` developer train was never publicly released if
selecting `3.00`, or select and verify a stable Perl version strictly
above every publicly distributed predecessor. Then remove any underscore
from the chosen stable version, align module/POD/`Changes`/packaging,
run the entire release matrix and tarball tests on the final stable
candidate, get explicit maintainer approval, and **then** decide
tag/publication.
No performance micro-optimizations, speculative feature coverage or
silent `main` branch switch are release blockers.
