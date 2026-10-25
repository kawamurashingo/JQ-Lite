# JQ::Lite 3.0 release readiness gate

**Status: NOT RELEASE READY.** This is a working sign-off checklist for
the practical-v2-baseline release, **not** a release announcement, a claim
of complete jq conformance, or an authorization to merge or publish.
Tracked by [#619](https://github.com/kawamurashingo/JQ-Lite/issues/619).

## Scope freeze

The target is v2.59's practical features with specifically audited jq 1.7
semantic corrections. Keep `main` / stable 2.x unchanged while validating
`v3-dev`. Maintain Perl 5.14+, pure Perl and the existing dependency set.
Do not add new public API, jq grammar or rare deep computed-selector/try
variants to satisfy 3.0. The proposed `compile()` API (#627) is deferred.

From this checkpoint, prefer release blockers (behavior/error regressions,
supported-scope decisions, tests, distribution or migration gaps) over
additional micro-optimizations. Existing acknowledged jq differences are
not automatically blockers: explicitly decide whether they are retained v2
behavior with tests and migration notes, or selected v3 corrections.

## Proposed INTERNAL RC1 checkpoint (2026-10-25)

[Draft internal RC1 notes](v3-rc1-release-notes.md) stage **Perl
developer version `3.00_03`** in a distinct candidate commit and
source archive `JQ-Lite-3.00_03.tar.gz` (GitHub Actions artifact,
**not published**). Previous beta1 `3.00_02` notes remain as a
historical, unpublished development checkpoint. This is **not a
public release**, public SemVer RC tag, CPAN upload, or authorization
to merge `v3-dev` into `main`.

**All practical scope issues are now closed:** #623, #625 and #626.
#625's #861 bounded 54-case path audit and retained v2 differences
were reconciled by [merged #865](https://github.com/kawamurashingo/JQ-Lite/pull/865)
(final head `c2b40b7c`, merged `b107d17c`). Its final HEAD
passed Perl and jq 1.7 Push/PR suites and source-package CI; the
Codex final-head review was clean. The already closed #867 warning
gate also passed on the merged #868 baseline. **These are scoped
decisions only**; the independent RC1 HEAD/PR synthetic merge, archive,
CLI/Library, warning-clean and final Codex checks remain pending.

**Public version numbering remains blocked:** `3.00_03` compares
newer than hypothetical stable `3.00` in Perl. Do not distribute
any `3.00_0x` developer archive as a public beta/RC. A **public**
beta or RC requires separately approved monotonically increasing
versions through stable. If no developer/prerelease was ever publicly
distributed, stable-only `3.00` may be considered, with internal
tester reinstall caveats, but is **not yet approved**.

## Historical beta1 candidate (2026-10-21)

[Draft beta1 release notes](v3-beta1-release-notes.md) map the internal
milestone **beta1 candidate** to Perl developer version **`3.00_02`**
(`JQ-Lite-3.00_02.tar.gz`). This is **not** a published beta, CPAN
release, stable 3.0 tag, or permission to switch `main`. The
`3.00_01` development history remains preserved under its own
`Changes` heading. For stable 3.0 the final approved version must
remove the underscore **and resolve public version ordering**.
Perl considers `3.00_02` newer than `3.00`: `3.00` is an option only
if the `3.00_0x` developer train is permanently unpublished.
The final stable number is **not yet selected**; see the
[beta1 version policy](v3-beta1-release-notes.md#perl-developer-to-stable-ordering-release-blocker).

The preceding [PR #862](https://github.com/kawamurashingo/JQ-Lite/pull/862)
merged to `v3-dev` at `33e6f83d71f0fc75303c87804b8c7016957f71e7`.
Its **final head** passed both Push/PR Perl and jq 1.7 workflows, and
the PR packaging workflow passed the extracted-tarball full suite,
`make disttest` and separate-prefix installation on Perl 5.14 and
latest. That is a **previous development-version packaging baseline**,
not CI evidence for `3.00_02`; do not reuse it to sign off this beta.

Scoped freeze PRs #859 (arithmetic), #860 (assignment/update) and
#861 (path/iterator) are merged. **#623 and #626 were closed** on
2026-10-21 after verifying their final-head Push/PR Perl and jq 1.7 CI
and the documented bounded scope. Documentation issue #629 is closed.
**#625 remains open** until the original
`docs/jq-semantics-differences.md` inventory is reconciled with #861's
four intentionally retained jq differences (a P2 review finding) and
accepted on its own final reviewed PR. Closing scoped issues does **not**
constitute approval of the complete beta/RC candidate or full jq parity.

The internal `3.00_02` beta1 candidate PR #863 and public-version policy
PR #864 are also merged, each with successful final-head Push/PR Perl
and jq 1.7 tests and PR distribution packaging checks; **both had
additional review findings discovered before merge**. The last
remaining #864 P1 called out the need for **public beta** version-order
approval in the `Changes` summary as well as the existing public RC
and stable gates. Do not treat their successful CI as resolution of that
review finding. The candidate must rerun its matrix on the **new final
reviewed head and synthetic merge**. Earlier alpha milestones are not
retroactively claimed as published releases.

## Baseline snapshot (2026-10-20)

This table records an auditable **pre-candidate** checkpoint, not the later
release candidate's result.

| Evidence | Snapshot | Interpretation |
| --- | --- | --- |
| Stable baseline | `main` v2.59, `6880c30440b564480d9971d575179513e16ed51f` | Existing practical behavior to inventory and preserve or explicitly migrate |
| v3 working branch | `v3-dev` merge `f07a406a42450a98b86e8eaaff168b28955be611` (#857) | Not a release tag |
| jq 1.7 fixtures | 4,037: 3,940 compatible, 74 known differences, 23 unsupported, 0 planned | Exact classifications in `t/data/jq-differential.jsonl`; only compatible outcomes are parity gates |
| Implementation size | Stable: 22 `lib/**/*.pm` blobs / 242,573 bytes; initial v3 `40c05db`: 22 / 326,242; current v3: 23 / 307,417 | Git tree blob-size sum; includes comments/whitespace, excludes docs/tests/CLI; current extra module is `Util/Stream.pm` |
| Most recent merged CI | PR #857: Push tests on final branch HEAD and PR tests on its associated synthetic merge ref all succeeded (Perl 5.14, 5.26, 5.38, latest; jq 1.7 differential) | PR CI checks the merge result, not the branch HEAD directly. Evidence of the merged change, **not** fresh beta/RC/package validation |

The 74 known-difference fixtures are **non-gating for jq parity**, not
automatically approved release semantics. Cases marked unsupported do not
become supported merely by passing the test suite. Rerun and recount on the
actual candidate commit; do not treat this snapshot as a frozen denominator.

## Scoped decisions and remaining sign-off

| Issue | Evidence already in-tree | Scoped acceptance / remaining gate |
| --- | --- | --- |
| [#623](https://github.com/kawamurashingo/JQ-Lite/issues/623) arithmetic | `docs/v3-arithmetic.md`, `t/v3_arithmetic_contract.t`; 408 cases: 396 compatible / 12 known differences | **SCOPED COMPLETE / CLOSED.** PR #859 final Push/PR Perl and jq 1.7 CI succeeded; numeric operand, null/error/divisor and CLI runtime policy accepted. Does not promise jq nonnumeric overloads. |
| [#625](https://github.com/kawamurashingo/JQ-Lite/issues/625) null/path/iterator | `docs/v3-practical-path-audit.md`, `t/v3_practical_path_audit.t`; 54 jq-recognized examples: 50 compatible / 4 preserved differences, plus the v2-only `slice()` extension | **SCOPED COMPLETE / CLOSED.** PR #861 audited practical paths; merged PR #865 aligned the original semantic-difference inventory, migration and compatibility documents. Final-head Perl/jq Push/PR and package CI succeeded; no full jq path-grammar claim. |
| [#626](https://github.com/kawamurashingo/JQ-Lite/issues/626) assignment/update | `docs/v3-assignment.md`, `t/v3_assignment_audit.t`; 101 cases: 40 compatible / 39 known differences / 22 unsupported | **SCOPED COMPLETE / CLOSED.** PR #860 final Push/PR Perl and jq 1.7 CI succeeded; retain separate ordinary `=`, corrected `|=` and v2 compound setter boundaries, with unsupported multi-result forms explicitly out of scope. |

**#623, #625 and #626 are all CLOSED for their documented
practical-v2 scopes**, not all jq syntax or future assignment/path
behavior. Issue #629's compatibility matrix and migration guide are
delivered and aligned with these bounded decisions by merged #865.
Separate #600/#601 and cross-platform proposal #633 are not silently
added to the #619 release scope. Independent RC1/publishing gates
remain open.

## Warning-clean CI acceptance (#867)

Successful `prove`/`make test` status does **not** guarantee the absence
of Perl warnings: on merged #866, Perl 5.14 and 5.26 produced 1,175
`sort`-comparator warning lines each while test jobs still passed,
and Perl 5.14's package job emitted 3,525 warning lines across three
test phases. See the [recorded warning audit](v3-ci-warning-audit.md)
for the associated SHAs, run URLs, and distinct already-fixed
`Aggregate.pm` warning.

The **scoped warning-audit task #867 is COMPLETE/CLOSED** after
maintainer-merged #868 (head `6daa508a`, merge `b7f303c3`). Its
final-head and post-merge Push/PR Perl, jq 1.7 and packaging tests all
passed, Codex found no remaining issues, and seven post-merge job logs
contained no unexpected Perl test warnings. See the
[scoped CI warning audit](v3-ci-warning-audit.md#final-verified-evidence-2026-10-23)
for run URLs and the separate GitHub Action Node.js deprecation note.

**Every later beta/RC candidate still must independently run** the shared
`ci/fail-on-test-stderr.sh` gate on all Push/PR Perl jobs, jq
differential tests and all three package test phases (source `make
test`, `make disttest`, extracted-archive `make test`). The gate
rejects unexpected stderr even when tests otherwise pass; there is no
global warning suppression or catch-all allowlist. Reconfirm the
intentional warning sentinel and inspect raw CI logs on the candidate
head and synthetic PR merge. Historical #868 success cannot substitute
for this final release-candidate gate.

## Candidate verification (record for **each** beta and RC head)

- [x] **Scoped decisions complete:** #623, #625 and #626 are
  closed for their audited practical-v2 subsets. The four retained
  #625 differences and #626 unsupported forms are explicitly
  documented in `docs/jq-semantics-differences.md`,
  `docs/jq-compatibility.md` and `docs/v3-migration.md`.
  Merged #865 resolved the documentation mismatch with final-head
  Push/PR Perl/jq and packaging checks. **RC1 scope revalidation
  and final publication review are still separate unchecked gates.**
- [ ] **Public contracts:** `t/cli_contract.t`,
  `t/v3_library_api_contract.t` and `t/library_errors.t` pass. Preserve
  `new` / `run_query` list-return semantics, output order, null vs no
  output, CLI exit 0/1/2/3/4/5, stderr categories and empty stdout on
  errors; compile-before-input and SIGPIPE/EPIPE remain covered.
- [ ] **Semantic regression:** `t/v3_arithmetic_contract.t`,
  `t/v3_assignment_audit.t`, `t/v3_practical_path_audit.t`
  and all other distribution tests pass. Do not claim complete jq parity.
- [ ] **jq comparison:** all `compatible` fixtures pass against jq 1.7.x,
  including ordered outputs and success/runtime-error categories.
  Review changed fixture classifications and known differences rather than
  downgrading failing compatible fixtures to bypass the gate.
- [ ] **Perl/CI:** identify the final candidate branch HEAD SHA and its
  intended base SHA. Verify Push CI checks that exact head SHA, with all
  Perl jobs (5.14, 5.26, 5.38, latest) and jq 1.7 differential passing.
  Separately verify passing PR CI for that head/base pairing: current
  `pull_request` workflows use `actions/checkout` without an explicit
  `ref`, so PR jobs test GitHub's synthetic merge commit, **not** the
  head commit directly. Record PR number, associated head/base/merge
  SHAs, run URLs and tested checkout ref/SHA; reject stale results if
  head or base changes. Resolve final-head review findings, not only
  findings from an earlier commit.
- [ ] **Warnings:** #867 audit confirms all tested supported Perl
  versions and the actual packaged-source test phases are free of
  unexpected test-process stderr; verify warning-gate self-test and
  do not treat `##[error]` annotations as proof of a failed process.
- [ ] **Packaging/portability:** `t/manifest_coverage.t` and
  `t/v3_release_metadata.t` pass in the source checkout **and** an
  extracted source tarball. Verify `Makefile.PL` minimum Perl 5.014,
  unchanged dependencies and that the archive includes CLI, modules,
  regression tests, fixture JSONL and migration/compatibility docs.
  Run `make disttest`, then independently install from a fresh tarball
  extraction and exercise the **installed** `JQ::Lite` and `jq-lite` CLI
  with no checkout modules on the Perl include path.
- [ ] **RC1 release artifacts:** verify internal developer
  version `3.00_03` consistently in Library/POD/`Changes`,
  `JQ-Lite-3.00_03.tar.gz`, the generated source distribution,
  `MANIFEST`, and included `docs/v3-rc1-release-notes.md`.
  Retain beta1 `3.00_02` history. Review the draft notes and
  known differences independently. **Never publish `3.00_0x`**
  developer artifacts under the internal-only policy.
- [ ] **Public version-order gate:** `version->parse('3.00_02')`
  compares greater than `version->parse('3.00')`. **Internal**
  `3.00_0x` betas/RCs may only be validated as permanently
  unpublished test archives; they are not public prereleases.
  **Before ANY publicly distributed beta or RC**, approve a
  strictly increasing public sequence from its first public version
  through eventual stable, using Perl's core `version` comparisons;
  the internal-only policy **cannot substitute** for this requirement.
  **Stable-only publication, without any public beta/RC:** `3.00`
  may be considered only if the maintainer verifies every
  `3.00_0x` archive remained permanently unpublished, with
  manual reinstall guidance for internal testers. If any prior
  developer/prerelease was publicly distributed, the approved
  stable version must compare strictly greater than every such
  predecessor. Final stable Perl number remains **undecided**.
  Record publication history, check ordering, remove any underscore
  on the stable version, re-freeze changelog/README/migration docs
  and require explicit approval before any public tag, CPAN upload,
  GitHub Release or promoted install URL. Keep stable 2.x unchanged.

### Source-distribution CI (pre-release package gate)

The opt-in and PR/merge-check workflow
[`v3-source-dist.yml`](../.github/workflows/v3-source-dist.yml)
runs on PRs targeting `v3-dev`, merges to `v3-dev`, and manual dispatch.
It tests Perl **5.14 and latest** separately and uses the ordinary Perl
matrix/ jq 1.7 differential workflows for the full baseline.

For each tested ref, it executes `perl Makefile.PL`, `make`,
`make test`, `make dist` and `make disttest`; checks that the
source tarball contains the public module, CLI, docs, contract tests
and differential fixtures. **MakeMaker's `disttest` recreates a
distribution directory from `MANIFEST`; it does not test the
previously generated tarball itself.** The workflow therefore extracts
that exact tarball into a clean directory and runs a separate
`perl Makefile.PL`, `make` and full `make test` against its contents
before `make install` to a temporary `INSTALL_BASE`. It then changes
out of the extracted source tree and checks the installed Library
and CLI without relying on source-tree modules. A short-lived
**unreleased candidate source tarball** is retained as a CI artifact
on the latest-Perl job; this is **not** a GitHub release or CPAN upload.

The workflow prints the checked-out ref SHA for every event;
PR runs also print the explicit PR head SHA, base SHA and synthetic
merge SHA. Record these identities and the run URL together for each
source candidate. Check the workflow results before
claiming packaging success. The workflow does not by itself validate
every downstream OS, all Perl releases, installation into system
paths, or a public stable version. No tag or release is automated.

### Local reproduction from the candidate checkout

```sh
prove -lr t
prove -l t/v3_release_metadata.t t/manifest_coverage.t
prove -l t/cli_contract.t t/v3_library_api_contract.t t/library_errors.t
prove -l t/v3_arithmetic_contract.t t/v3_assignment_audit.t t/v3_practical_path_audit.t
JQ_DIFFERENTIAL=1 prove -l t/jq_differential.t  # needs jq 1.7.x
perl Makefile.PL
make
make test
make dist
make disttest
# Also extract the resulting JQ-Lite-*.tar.gz in a fresh directory,
# install from there with INSTALL_BASE to a temporary prefix, and smoke-test
# that prefix's Perl Library and bin/jq-lite; see the workflow above.
```

Run CI in the repository for the entire Perl matrix, not just the local
interpreter. For each PR run, verify its tested merge ref/SHA separately
from the Push head SHA; do not infer what `actions/checkout` tested from
the run's reported `head_sha` alone. The previous #862 development
version passed `make disttest` and actual extracted-tarball tests,
but **`3.00_03` RC1 requires independent candidate checks**.
Never publish an underscore developer version as a stable release.

## Sign-off record (fill only after independent verification)

| Gate | Candidate SHA / evidence URL | Result |
| --- | --- | --- |
| Practical-scope decisions (#623/#625/#626) | All three scoped issues closed; #625 [merged PR #865](https://github.com/kawamurashingo/JQ-Lite/pull/865), head `c2b40b7c`, merge `b107d17c` | SCOPED COMPLETE; RC1 STILL NEEDS NEW CI |
| Full Perl matrix, Push HEAD SHA + PR merge SHA and run URLs | Previous #864 head `2410606a`: [Push](https://github.com/kawamurashingo/JQ-Lite/actions/runs/39538124269), [PR](https://github.com/kawamurashingo/JQ-Lite/actions/runs/39538128367) | PASSED HISTORICALLY; NEW FINAL CANDIDATE REQUIRED |
| jq 1.7 differential, Push HEAD SHA + PR merge SHA and run URLs | Previous #864: [Push](https://github.com/kawamurashingo/JQ-Lite/actions/runs/39538124258), [PR](https://github.com/kawamurashingo/JQ-Lite/actions/runs/39538128322) | PASSED HISTORICALLY; NEW FINAL CANDIDATE REQUIRED |
| CLI/Library + extracted-source disttest + clean install | Previous #864: [source-dist PR run](https://github.com/kawamurashingo/JQ-Lite/actions/runs/39538128301), Perl 5.14 + latest | PASSED HISTORICALLY; NEW FINAL CANDIDATE REQUIRED |
| Clean warning gate (#867) | #867 closed after [merged #868](https://github.com/kawamurashingo/JQ-Lite/pull/868); [post-merge Perl](https://github.com/kawamurashingo/JQ-Lite/actions/runs/39867435287), [jq](https://github.com/kawamurashingo/JQ-Lite/actions/runs/39867435269), [package](https://github.com/kawamurashingo/JQ-Lite/actions/runs/39867435373) | SCOPED GATE COMPLETE; RECHECK ON FINAL CANDIDATE |
| Migration/README/Changes and Perl version-order decision | _pending_ | **BLOCKED: public version not selected** |
| Final review and release approval | _pending_ | NOT APPROVED |

Only after the above gates are satisfied should the beta/RC candidate be
promoted. Do not merge `v3-dev` into `main` or publish a stable 3.0 artifact
just because the latest ordinary development PR has green CI.
