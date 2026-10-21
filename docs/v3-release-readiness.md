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

## Proposed beta1 candidate (2026-10-21)

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

Scoped freeze PRs #859 (arithmetic), #860 (assignment/update) and #861
(path/iterator) are merged, and documentation issue #629 is already
closed. Parent roadmap issue checkboxes and child issues #623/#625/#626
still require explicit reconciliation/acceptance. Their scoped decisions
do not imply exhaustive jq feature parity or automatic issue closure.
The beta1 candidate must rerun the complete matrix and get approval
on **its own final HEAD and PR synthetic merge**. Earlier alpha milestones
are not retroactively claimed as published releases.

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

## Scope decisions still requiring sign-off

| Issue | Evidence already in-tree | Required release decision |
| --- | --- | --- |
| [#623](https://github.com/kawamurashingo/JQ-Lite/issues/623) arithmetic | `docs/v3-arithmetic.md`, `t/v3_arithmetic_contract.t`; 408 scoped cases (396 compatible / 12 known differences) | Confirm typed numeric expressions, null/error/divisor behavior, documented nonnumeric jq overload exclusions and CLI exit 3. Reconcile issue checklist with implemented scope. |
| [#625](https://github.com/kawamurashingo/JQ-Lite/issues/625) null/path/iterator | `docs/v3-practical-path-audit.md`, `t/v3_practical_path_audit.t`, targeted path/iterator tests; proposed 54 audited jq-recognized examples (50 compatible, four retained v2 differences) plus the v2-only `slice()` extension | Review the bounded practical-v2 inventory and confirm missing/null/no-output, ordinary paths, optional/strict iterator and comma/pipeline boundaries; retain/document the four v2 differences. The source-size audit is recorded, not a mandate for broad parser rewrites. Sign off only after final PR CI/review. |
| [#626](https://github.com/kawamurashingo/JQ-Lite/issues/626) assignment/update | `docs/v3-assignment.md`, `t/v3_assignment_audit.t`; 101 scoped cases (40 compatible / 39 known differences / 22 unsupported) | Decide whether ordinary/compound v2 differences remain intentional in 3.0, and freeze the supported `=`, `|=`, compound and invalid-target matrix. Do not assume compound setters inherit strict expression arithmetic. |

None of these three open issues is treated as complete by this document.
Issue #629's compatibility matrix and migration guide are already delivered,
but their text must be checked against the **final** semantic decisions.
Separate #600/#601 and cross-platform proposal #633 are not silently added
to the #619 release scope.

## Candidate verification (record for **each** beta and RC head)

- [ ] **Scope and migration:** #623/#625/#626 have explicit disposition of
  selected corrections, retained known differences and unsupported forms.
  Update `docs/jq-compatibility.md`, `docs/v3-migration.md`, `Changes`
  and README for any newly decided breaking behavior. No undocumented
  accidental behavior changes.
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
- [ ] **Packaging/portability:** `t/manifest_coverage.t` and
  `t/v3_release_metadata.t` pass in the source checkout **and** an
  extracted source tarball. Verify `Makefile.PL` minimum Perl 5.014,
  unchanged dependencies and that the archive includes CLI, modules,
  regression tests, fixture JSONL and migration/compatibility docs.
  Run `make disttest`, then independently install from a fresh tarball
  extraction and exercise the **installed** `JQ::Lite` and `jq-lite` CLI
  with no checkout modules on the Perl include path.
- [ ] **Release artifacts:** for beta1, verify developer version
  `3.00_02` consistently in Library/POD/`Changes`, the generated
  archive name, `MANIFEST` and the included
  `docs/v3-beta1-release-notes.md`; review the draft notes before
  approval. **Never publish `3.00_0x` developer artifacts** under
  the currently selected internal-only policy.
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
but **`3.00_02` still requires independent candidate checks**.
Never publish an underscore developer version as a stable release.

## Sign-off record (fill only after independent verification)

| Gate | Candidate SHA / evidence URL | Result |
| --- | --- | --- |
| Practical-scope decisions (#623/#625/#626) | _pending_ | BLOCKED |
| Full Perl matrix, Push HEAD SHA + PR merge SHA and run URLs | _pending_ | NOT RUN ON CANDIDATE |
| jq 1.7 differential, Push HEAD SHA + PR merge SHA and run URLs | _pending_ | NOT RUN ON CANDIDATE |
| CLI/Library + extracted-source disttest + clean install | _pending_ | NOT RUN ON CANDIDATE |
| Migration/README/Changes and Perl version-order decision | _pending_ | **BLOCKED: public version not selected** |
| Final review and release approval | _pending_ | NOT APPROVED |

Only after the above gates are satisfied should the beta/RC candidate be
promoted. Do not merge `v3-dev` into `main` or publish a stable 3.0 artifact
just because the latest ordinary development PR has green CI.
