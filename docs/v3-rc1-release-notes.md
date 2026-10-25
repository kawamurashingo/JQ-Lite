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
repository-wide fixture total. The previous beta checkpoint recorded
4,037 differential fixtures (3,940 compatible / 74 known differences /
23 unsupported / 0 planned); **recount actual final-head fixture
classifications before approving RC1**. Neither known differences nor
unsupported expressions promise jq compatibility.

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
