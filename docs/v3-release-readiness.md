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

## Baseline snapshot (2026-10-20)

This table records an auditable **pre-candidate** checkpoint, not the later
release candidate's result.

| Evidence | Snapshot | Interpretation |
| --- | --- | --- |
| Stable baseline | `main` v2.59, `6880c30440b564480d9971d575179513e16ed51f` | Existing practical behavior to inventory and preserve or explicitly migrate |
| v3 working branch | `v3-dev` merge `f07a406a42450a98b86e8eaaff168b28955be611` (#857) | Not a release tag |
| jq 1.7 fixtures | 4,037: 3,940 compatible, 74 known differences, 23 unsupported, 0 planned | Exact classifications in `t/data/jq-differential.jsonl`; only compatible outcomes are parity gates |
| Implementation size | Stable: 22 `lib/**/*.pm` blobs / 242,573 bytes; initial v3 `40c05db`: 22 / 326,242; current v3: 23 / 307,417 | Git tree blob-size sum; includes comments/whitespace, excludes docs/tests/CLI; current extra module is `Util/Stream.pm` |
| Most recent merged CI | PR #857 final HEAD: Push and PR Perl (5.14, 5.26, 5.38, latest), and Push and PR jq 1.7 differential jobs all succeeded | Evidence of the merged change, **not** fresh beta/RC/package validation |

The 74 known-difference fixtures are **non-gating for jq parity**, not
automatically approved release semantics. Cases marked unsupported do not
become supported merely by passing the test suite. Rerun and recount on the
actual candidate commit; do not treat this snapshot as a frozen denominator.

## Scope decisions still requiring sign-off

| Issue | Evidence already in-tree | Required release decision |
| --- | --- | --- |
| [#623](https://github.com/kawamurashingo/JQ-Lite/issues/623) arithmetic | `docs/v3-arithmetic.md`, `t/v3_arithmetic_contract.t`; 408 scoped cases (396 compatible / 12 known differences) | Confirm typed numeric expressions, null/error/divisor behavior, documented nonnumeric jq overload exclusions and CLI exit 3. Reconcile issue checklist with implemented scope. |
| [#625](https://github.com/kawamurashingo/JQ-Lite/issues/625) null/path/iterator | `docs/v3-practical-path-audit.md`, `t/v3_practical_path_audit.t`, many targeted path/iterator tests | Finish bounded practical v2 inventory and confirm missing/null/no-output, ordinary paths, optional/strict iterator and comma/pipeline boundaries; preserve or explicitly document v2 extensions. Review complexity/size, without pursuing rare syntax. |
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
- [ ] **Perl/CI:** verify *final candidate SHA* has successful **both Push
  and PR** Perl jobs for 5.14, 5.26, 5.38 and latest; verify **both** jq
  differential jobs. Resolve final-HEAD review findings, not only the
  findings from an earlier commit.
- [ ] **Packaging/portability:** `t/manifest_coverage.t` passes;
  built distribution includes tests and docs. Verify `Makefile.PL` minimum
  Perl 5.014 and the existing dependency set. Verify an actual generated
  distribution test, not just tests in the Git checkout.
- [ ] **Release artifacts:** choose stable Perl module version (no
  underscore developer-release suffix), freeze changelog, audit README and
  migration docs, prepare beta/RC/release notes and tag only after approval.
  Keep stable 2.x branch untouched.

### Local reproduction from the candidate checkout

```sh
prove -lr t
prove -l t/cli_contract.t t/v3_library_api_contract.t t/library_errors.t
prove -l t/v3_arithmetic_contract.t t/v3_assignment_audit.t t/v3_practical_path_audit.t
JQ_DIFFERENTIAL=1 prove -l t/jq_differential.t  # needs jq 1.7.x
perl Makefile.PL
make
make test
make dist
make disttest
```

Run CI in the repository for the entire Perl matrix, not just the local
interpreter. `make disttest` is still a pending **candidate** check; no
distribution test is asserted successful by this snapshot. Do not ship a
developer version `3.00_01` as the final stable version.

## Sign-off record (fill only after independent verification)

| Gate | Candidate SHA / evidence URL | Result |
| --- | --- | --- |
| Practical-scope decisions (#623/#625/#626) | _pending_ | BLOCKED |
| Full Perl matrix, Push + PR | _pending_ | NOT RUN ON CANDIDATE |
| jq 1.7 differential, Push + PR | _pending_ | NOT RUN ON CANDIDATE |
| CLI/Library/distribution test + packaging | _pending_ | NOT RUN ON CANDIDATE |
| Migration/README/Changes and version audit | _pending_ | NOT FINAL |
| Final review and release approval | _pending_ | NOT APPROVED |

Only after the above gates are satisfied should the beta/RC candidate be
promoted. Do not merge `v3-dev` into `main` or publish a stable 3.0 artifact
just because the latest ordinary development PR has green CI.
