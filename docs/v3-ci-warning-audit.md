# v3 CI warning audit — scoped #867

**Status: scoped #867 COMPLETE/CLOSED after merged #868 and independently checked Push/PR CI.** This is not approval of any public beta/RC or the final 3.0 candidate.
A successful TAP/Perl exit code does not mean the test emitted no warnings.
GitHub Actions can annotate warning lines as `##[error]` without failing
the job. Run the check against each **final** Push SHA and associated PR
synthetic merge SHA before accepting a beta/RC.

## Reproducible baseline: merged #866 / current v3-dev

Checked merged `v3-dev` commit
`b7d9e3e4e812c34553a070db1ae1a3d58e00618c` (#866).
All existing CI workflows completed successfully:

| GitHub Actions run | Perl environment | Uninitialized Perl warning lines | Provenance |
| --- | --- | ---: | --- |
| [Perl Push #39780062182](https://github.com/kawamurashingo/JQ-Lite/actions/runs/39780062182) | 5.14 | 1,175 | path deletion-sort test and `Transform.pm` |
| same run | 5.26 | 1,175 | same sort; modern Perl adds "in sort" |
| same run | 5.38 | 0 | none observed in this run |
| same run | latest | 0 | none observed in this run |
| [Source dist Push #39780062348](https://github.com/kawamurashingo/JQ-Lite/actions/runs/39780062348) | 5.14 | 3,525 | source `make test`, `make disttest`, actual extracted-tarball `make test` (1,175 each) |
| same run | latest | 0 | no uninitialized Perl warning (separate Node.js deprecation notice from a GitHub Action) |

All numbers are counts of matching **log lines** for these specific
completed runs, not a blanket warning-free statement about every version.
The old Perl failures originate from **three sort comparator sites**:
two test reference comparators in `t/v3_paths_dispatch.t` and the cached
runtime sort in `lib/JQ/Lite/Util/Transform.pm`. They used `return` within a Perl
`sort { ... }` comparator; on older Perls a comparator result can be
uninitialized. The new implementation uses a final-expression comparison
chain with the same depth / parent-prefix / last-segment priority.
The test retains the reference comparison and asserts **no warnings**.

The distinct `Aggregate.pm` null numeric-conversion warning from
earlier [PR #865 source-dist CI](https://github.com/kawamurashingo/JQ-Lite/actions/runs/39777213077)
was fixed by merged [#866](https://github.com/kawamurashingo/JQ-Lite/pull/866).
The merged-run dist test no longer emits this aggregate warning and
its regression test also protects JSON numeric-string input flags.
The GitHub Actions Node.js runtime deprecation notice in the latest
Perl package job is **not a Perl test warning** and must be addressed
through the upstream action/toolchain separately if it remains relevant.

## Proposed non-silent warning gate

The portable POSIX shell helper `ci/fail-on-test-stderr.sh` runs a
test command, captures its stderr, prints any diagnostics and **fails
if nonempty** even if the command itself exited 0. This deliberately
avoids a broad warning allowlist or global `no warnings`. Tests
intentionally checking warnings should capture them locally, using
`local $SIG{__WARN__}`, and make assertions about their content.

This helper is wired to:

- the normal Perl 5.14 / 5.26 / 5.38 / latest Push and PR matrix;
- jq 1.7 differential Push/PR tests;
- the distribution workflow's source `make test`, `make disttest`,
  and `make test` against the **actual extracted archive**, on
  Perl 5.14 and latest.

The ordinary Perl workflow self-tests the checker with an intentionally
generated warning whose stderr is captured and *not* printed as an
actual warning annotation. CI must verify that this sentinel is rejected,
while a clean command succeeds. The jq 1.7 differential runner used
`diag` on its intentionally documented **known-difference** fixtures;
that informational output is now emitted via Test::More `note` on TAP
stdout instead. **Failure diagnostics** continue using `diag`/stderr
so unexpected failures are not hidden.

**Child-process capture also needs an assertion:** the differential
runner's `run_command()` captures each `jq-lite` subprocess's stderr.
That captured stream does not reach the outer shell's stderr gate.
The differential test now explicitly fails when **any successful**
`jq-lite` execution has nonempty captured stderr, **including**
intentionally known-difference fixtures. A separate subprocess probe
uses a successful Perl child that intentionally writes a warning to
stderr, proving this captured-stderr check detects it. Expected
`[RUNTIME]` stderr from **nonzero** runtime-error outcomes remains
available for diagnostic assertions, not treated as a success warning.
This closes Codex's P1 observation on PR #868; final-head CI is
required before acceptance.

The helper is part of `MANIFEST` and must ship in the candidate
archive. The shell gate concerns **test-process stderr** and the child
assertion covers successful jq-lite subprocess stderr; unrelated
warnings from third-party GitHub Actions themselves are not
incorrectly counted as Perl runtime warnings.

## Scoped #867 sign-off (completed after #868 merge)

- [x] New PR's **final HEAD and PR synthetic merge SHA** are recorded and
  green for all Perl matrix and jq 1.7 runs.
- [x] Both source-dist package jobs pass source/tree and extracted-archive
  stderr gates; inspect their raw logs, not only run conclusions.
- [x] Test confirms warning sentinel causes a failed gate, and the
  regular path-sorting regression remains warning-free on older Perl.
- [x] Confirm no new test process warnings have been introduced elsewhere;
  any warning must be investigated rather than globally suppressed.
- [x] Final Codex findings resolved, maintainer merges, #619 reflects
  completed release warning gate. No publication is implied by CI success.

## Final verified evidence (2026-10-23)

- #868 final head: `6daa508aaa4b8cc99e587c192b9205bd1095b956`;
  merged onto `v3-dev` as `b7f303c3111f2c744bd555aa51a058a9e368eabe`.
  Final-head [Perl Push](https://github.com/kawamurashingo/JQ-Lite/actions/runs/39863749091),
  [Perl PR](https://github.com/kawamurashingo/JQ-Lite/actions/runs/39863754019),
  [jq 1.7 Push](https://github.com/kawamurashingo/JQ-Lite/actions/runs/39863748882),
  [jq 1.7 PR](https://github.com/kawamurashingo/JQ-Lite/actions/runs/39863754071),
  and [package PR](https://github.com/kawamurashingo/JQ-Lite/actions/runs/39863754003)
  all passed; Codex final-head review had **no findings**, and the
  captured-child-stderr P1 thread was resolved.
- **Post-merge** [Perl Push](https://github.com/kawamurashingo/JQ-Lite/actions/runs/39867435287)
  (all four Perls), [jq 1.7 Push](https://github.com/kawamurashingo/JQ-Lite/actions/runs/39867435269),
  and [package Push](https://github.com/kawamurashingo/JQ-Lite/actions/runs/39867435373)
  (Perl 5.14 and latest, each running source, `disttest` and extracted-archive
  tests) also passed. All **seven successful job logs** were inspected:
  **zero** `Use of uninitialized value`, unexpected test error markers,
  or warning-gate failures. Perl 5.14/5.26 regression tests and jq
  differential subprocess warning probe are part of the suites.
- **Unrelated toolchain warning:** the latest-Perl package job had one
  `actions/upload-artifact@v4` Node.js 20 deprecation annotation. It
  originates in the GitHub Action, **not** the Perl tests or jq-lite;
  package tests and the warning-clean gate passed. Review action versions
  separately when updating CI; do not misreport this as a Perl warning.

The scope-specific warning gate is accepted and #867 is closed, but
**every later beta/RC candidate commit and synthetic PR merge must rerun
this gate independently**. The evidence above is a development checkpoint,
not permission to publish a release or close #619/#625.
