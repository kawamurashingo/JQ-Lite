# v3 CI artifact exposure: maintainer decision and evidence retention

**Status: PUBLIC RELEASE BLOCKED / NO ARTIFACT DELETION APPROVED.**
Updated 2026-10-26. This records a distribution-channel risk
discovered after #885 and mitigated by merged
[#886](https://github.com/kawamurashingo/JQ-Lite/pull/886).
It is not an assessment that 92 archives were actually downloaded.

## What is established

- The internal v3 branch still identifies as Perl `3.00_03`.
- The previously enabled source-distribution workflow exported the built
  `JQ-Lite-*.tar.gz` via GitHub Actions downloadable artifacts named
  `v3-unreleased-source-<run_id>`.
- [One directly inspected Actions artifact](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40188275036/artifacts/12597242129)
  contained `JQ-Lite-3.00_03.tar.gz`. It was an Actions artifact,
  **not** a GitHub Release asset, tag or CPAN upload.
- The [read-only paginated inventory](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40200136630)
  found **92 unexpired artifacts** with that naming pattern at
  2026-10-25 ~13:59 UTC. That is a point-in-time count of entries,
  **not** proof that all 92 contained the same version or were downloaded.
- #886 stopped future candidate-tarball artifact uploads and preserved
  local distribution build, extracted archive tests and independent
  installation checks. Its final-head Perl, jq 1.7, source distribution
  and exposure inventory CI all passed. No existing archive was deleted.
- GitHub's documented artifact access permits signed-in people with
  read access to retrieve artifacts; that includes a wider audience
  on a public repository than strictly internal maintainers.

## What is NOT established

- Who, if anyone outside the project, downloaded any old artifact,
  when downloads occurred, or whether a local copy was redistributed.
  An artifact having been accessible is not proof of a download.
- The content of every historic ZIP, including expired or deleted
  artifacts. The current GitHub API listing is not a historical access log.
- Whether an internally named `3.00_01` or `3.00_02` tarball was also
  downloadable. Absence in CPAN, BackPAN, MetaCPAN and current GitHub
  Releases is insufficient to exclude Actions or external links.
- A complete, authoritative PAUSE receipt/order ledger: the 259-version
  BackPAN/MetaCPAN match and 269 CPAN Testers observations still
  leave duplicates, one incomplete `0.81` record, and original chronology
  unverified. The observed `0.99 -> 0.100` Perl-order inversion
  remains an explicit historical issue.

## Preservation and mitigation decision

1. **Maintain #886's upload prohibition**: the source distribution
   workflow may build/test local candidate tarballs but must not export
   internal `3.00_0x` bytes through Actions artifacts. The new
   `t/v3_public_ci_archive_nonpublication.t` regression guards against
   accidentally reintroducing upload-artifact there.
2. **Preserve minimal evidence first**: record workflow run IDs,
   artifact IDs, UTC creation times, names, expiry and the inspected
   original tarball's SHA-256 plus access scope. Avoid committing
   unpublished tarball bytes or access tokens to this repository.
   The Actions run summary is short-lived and cannot on its own
   constitute permanent records.
3. **No automatic deletion**: removing existing artifacts needs explicit
   maintainer approval and a separate reviewed operation after
   provenance has been retained. Deletion reduces future exposure, but
   cannot reverse past access or demonstrate absence of external copies.
4. **Review downstream public channels**: any links in Issues/PRs/README,
   releases, direct Actions artifact URLs, installer scripts and
   mirrors. Treat source contents and artifact access as independent
   from actual PAUSE/CPAN publication history.
5. **Human version decision**: specify a policy for whether an openly
   downloadable Actions internal dev tarball must be treated as a
   prior public version for Perl monotonic numbering. Document the
   policy, evidence reviewed, any disputed cases, and explicit
   maintainer sign-off before running
   `ci/check-public-version-order.pl --history-reviewed`.

## Numeric version decision boundaries (illustrative, not approval)

Perl's `version->parse("3.00_03")` sorts **higher** than
`version->parse("3.00")`; publishing stable `3.00`
**after** a prior publicly distributed `3.00_03` would violate
the project's strict monotonicity rule.

| Scenario after human evidence review | Consequence |
| --- | --- |
| A complete history confirms no internal `3.00_0x` was ever treated as public distribution | Stable-only `3.00` may be assessed, but is **not approved** |
| `3.00_03` or another 3.x candidate must be counted as previously publicly distributed | Do **not** select stable `3.00`; propose a stable version above the maximum Perl-parsed predecessor, subject to a complete chronological ledger and explicit approval |
| Existing history cannot distinguish exposure from actual distribution or lacks PAUSE upload chronology | **BLOCKED**; do not invent a published-version ledger or grant `--history-reviewed` approval |

**Required approvals before publication:** documented upload history
including historical regressions, Actions exposure/retention review,
all other channels, selected monotonic stable number, fresh
candidate-specific Perl/jq/package/installer CI, Codex final HEAD,
and maintainer approval covering `main`, tag, GitHub Release and
PAUSE/CPAN publication separately.

None of these approvals are supplied by this document.
