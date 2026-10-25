# JQ::Lite 3.0 RC1 — internal candidate notes

**Status: DRAFT / INTERNAL ONLY / NOT PUBLISHED.** This file proposes the
next **release-candidate validation checkpoint**, not a public RC
announcement, CPAN upload, GitHub Release, or Git tag.
`v3-dev` is the candidate source branch; stable `main` / JQ::Lite 2.59
must not be changed by this PR.

## Candidate identity

| Item | Internal RC1 candidate |
| --- | --- |
| Practical feature baseline | Stable JQ::Lite 2.59, with explicitly audited v3 changes |
| Perl developer version | `3.00_03` (underscore developer build) |
| Source archive | `JQ-Lite-3.00_03.tar.gz` (**CI artifact only**) |
| Previous internal checkpoint | beta1 candidate `3.00_02` (historical, unpublished) |
| Public RC / stable version | **UNDECIDED; requires a separate monotonic version plan and approval** |
| Release authority | Maintainer's explicit decision **after** final-head gates; no automatic publication |

The `3.00_0x` development versions are **permanently unpublished**.
Perl `version->parse("3.00_03") > version->parse("3.00")`; an
internal developer build can sort **newer** than a hypothetical public
stable `3.00`. Never distribute `3.00_03` as a public RC and then
publish `3.00` as the upgrade target. For **any public beta or RC**,
approve a strictly increasing Perl version sequence through the future
stable release **before publication**. Stable-only `3.00` may be
considered only if **every** `3.00_0x` archive stayed unpublished,
and internal testers understand manual reinstall may be necessary.
A stable Perl version is not selected here. See the
[beta1 ordering policy](v3-beta1-release-notes.md#perl-developer-to-stable-ordering-release-blocker).

## Frozen practical feature scope

The following **bounded** scope reviews are complete/closed; their
acceptance is not a claim of jq 1.7 grammar-wide parity.

| Issue / merged evidence | Audit | Scope decision |
| --- | --- | --- |
| [#623](https://github.com/kawamurashingo/JQ-Lite/issues/623), PR #859 | 408 arithmetic cases: 396 compatible / 12 known differences | Typed numeric expressions, null/error/divisor policy; nonnumeric jq operator overloads not promised |
| [#625](https://github.com/kawamurashingo/JQ-Lite/issues/625), PRs #861/#865 | 54 jq-recognized path/iterator cases: 50 compatible / 4 known differences; separate v2-only `slice(start,length)` | Explicit missing/null/no-output and iterator behavior; retain scoped v2 array projection, scalar field, string slice and mixed projection differences |
| [#626](https://github.com/kawamurashingo/JQ-Lite/issues/626), PR #860 | 101 assignment cases: 40 compatible / 39 known differences / 22 unsupported | Distinguish ordinary `=`, supported `|=` and legacy compound coercion; unsupported multi-stream/multi-path selectors remain outside the contract |
| [#629](https://github.com/kawamurashingo/JQ-Lite/issues/629), migration/matrix | Completed | The compatibility matrix and concrete v2-to-v3 migration examples document the retained differences |
| [#867](https://github.com/kawamurashingo/JQ-Lite/issues/867), PRs #866/#868 | Warning audit completed | Full Perl/jq/package CI gates test-process stderr, including captured successful jq-lite child stderr, to prevent green builds with hidden Perl warnings |

Counts above are **overlapping scoped audits**, not an additive
repository-wide fixture total. The `#869` RC1 staging head's
`t/data/jq-differential.jsonl` fixture statuses were **recounted
from all 4,037 JSONL records**, not inferred by adding the overlapping
sub-audits:

| Classification | RC1 staging head count |
| --- | ---: |
| `compatible` | 3,940 |
| `known-difference` | 74 |
| `unsupported` | 23 |
| `planned` | 0 |
| **Total** | **4,037** |

These counts match the previous beta checkpoint. The fixture file
is the same recorded revision in merged `#869`; any later
candidate **must recount on its own final SHA**. Only compatible
fixtures are jq parity gates; known-difference and unsupported
fixtures are not parity promises.

Do not add speculative deep computed selectors, complete jq modules,
new builtins or `compile()` (#627), dependencies, or a new public API
solely to rename this checkpoint RC1.

## Public contract and compatibility

The Library entry points remain `JQ::Lite->new` and `run_query`.
Preserve ordered list results, the distinction between a zero-result
stream and a single JSON null, and structured evaluation errors.
The CLI must retain exit codes 0/1/2/3/4/5, empty stdout on errors,
documented stderr prefixes, compile-before-input and SIGPIPE/EPIPE
behavior. The supported target remains **pure Perl 5.14+** with no
additional runtime dependencies or native extension.

Read the [compatibility matrix](jq-compatibility.md),
[migration guide](v3-migration.md),
[arithmetic audit](v3-arithmetic.md),
[path audit](v3-practical-path-audit.md),
[assignment audit](v3-assignment.md) and
[beta1 notes](v3-beta1-release-notes.md) for concrete examples.

## Technical checkpoint — merged PR #869 (2026-10-25)

**Development-candidate verification evidence, not public release approval.**
The version-staging [PR #869](https://github.com/kawamurashingo/JQ-Lite/pull/869)
merged its final HEAD `34e7a7e8aef27f153a933f6bc2c27d2373b21c2c`
on top of base `b107d17ce926592a107bab6a279ccbbbf23429bf`
as commit `a597fd6c32368ee471709ed115ad7bc6fe16c3c6`.
The associated PR workflow actually tested synthetic merge
`a47aba4599330eb19023db41cc0d92c5ff138f15`,
as verified from packaging job logs.

| Check at #869 final HEAD | Observed result |
| --- | --- |
| [Perl Push](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40148335027) and [Perl PR](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40148416217) | **PASS**, all 5.14, 5.26, 5.38, latest jobs |
| [jq 1.7 Push](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40148335018) and [jq 1.7 PR](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40148416225) | **PASS**, complete differential harness with successful-child stderr gate |
| [Source distribution PR](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40148416214) | **PASS** on Perl 5.14 and latest, checkout `make test`, `make disttest`, real extracted `3.00_03` archive tests, independent install and CLI/Library smoke tests |
| Codex final-head review | **COMPLETED, no findings or unresolved threads**, on `34e7a7e8` |
| Full final-head job-log warning scan | **No test-process `##[error]`, uninitialized-value warning or warning-gate failure detected.** Latest-Perl package job has an **unrelated GitHub Action Node.js 20 deprecation notification**, not a Perl warning |
| Source version / archive | Library/POD/`Changes` stage `3.00_03`; package logs confirm `JQ-Lite-3.00_03.tar.gz` built and tested |

A later `v3-dev` Push run checks the merged candidate tree,
but **does not substitute for PR synthetic merge evidence**.
Publication history, publicly monotonic Perl-version selection,
maintainer approval for any public beta/RC and subsequent stable
build/test/tag decisions remain **BLOCKED / NOT APPROVED**.

## RC1 acceptance — record results on the exact final commit

- [ ] Final branch **Push HEAD SHA** and associated PR
  **head/base/synthetic-merge SHA** are recorded with their CI URLs.
  Do not use a past beta job to sign off this RC.
- [ ] Push **and** PR Perl tests succeed on **5.14, 5.26, 5.38
  and latest** with warning-clean gates; CLI/Library API regression
  suites, failure contracts and minimum-version metadata pass.
- [ ] Push **and** PR jq **1.7.x differential** tests pass; check that
  all successful jq-lite subprocesses emit **no captured stderr**.
  Recount fixture classifications without silently changing the
  status of a known difference or unsupported case.
- [ ] Package workflow passes on **Perl 5.14 and latest**: checkout
  tests, `make disttest`, full tests from **the actual extracted
  `JQ-Lite-3.00_03.tar.gz` archive**, separate-prefix installation
  and installed CLI/Library smoke tests. Both source and archive
  must include this document, CI warning checker, migration docs
  and differential fixtures, with no native runtime dependencies.
- [ ] The current `$JQ::Lite::VERSION`, POD, top `Changes`
  entry and generated archive name all agree on `3.00_03`.
- [ ] Final-head Codex review is clean, all review threads resolved,
  documentation/known differences accepted, and maintainer explicitly
  signs off **internal RC1 validation only**. No tag, CPAN upload,
  public RC announcement or GitHub Release follows automatically.

## Promotion beyond the internal candidate

After accepted **internal** RC1 validation, handle only bona fide release
blockers (practical-scope regressions, incorrect supported jq results,
API/CLI breaks, Perl portability, source distribution failures,
unclear migration, or actual warning leaks). New functionality and rare
jq expression variants are **not** release blockers.

Any **public RC** needs a newly approved strictly increasing Perl
pre-release-to-stable version plan, followed by a separately validated
public-release candidate. For **stable**, verify all public version
history, pick the approved **non-underscore** Perl version, update all
release metadata and notes, rerun complete CI on that exact stable
candidate, and get explicit approval for tag, CPAN upload and
stable-branch changes. No stable/public promotion is authorized here.
