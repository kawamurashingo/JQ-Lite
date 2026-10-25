# JQ::Lite v3 public release cutover: feature freeze and decision gates

**Status (2026-10-25): FEATURE FROZEN / PUBLICATION BLOCKED.**
This is a working plan for [#619](https://github.com/kawamurashingo/JQ-Lite/issues/619),
**not** a release authorization or a choice of the final public version.
Target review window: **2026-11-01–2026-11-08**, conditional on
closing the evidence gates below; missing evidence moves the window.
Only the maintainer can authorize an actual public release.

## Newly established source-distribution exposure blocker

Merged #886 stopped publishing internal `3.00_03` tarballs as downloadable
GitHub Actions artifacts; the read-only inventory found 92 non-expired
source artifacts and inspected one `3.00_03` tarball. This is an
**exposure**, not proof of a third-party download or a PAUSE/CPAN upload.
The [Actions exposure decision record](v3-actions-artifact-exposure-decision.md)
defines evidence retention, human deletion approval and why stable `3.00`
cannot be assumed compatible with every publicly accessible predecessor.
Version policy, original PAUSE chronology and all distribution channels
remain blocked pending explicit review.

## Scope freeze

- **Do not add features** or broaden jq grammar/syntax. Keep v2.59's
  practical features, selected jq 1.7 semantic corrections, minimal
  maintenance complexity and Perl >=5.14 as the accepted v3 scope.
- Changes on `v3-dev` are limited to demonstrated release blockers:
  compatibility regressions, release documentation/metadata errors,
  reproducible packaging/CI defects, security defects, and genuine
  public-distribution evidence gaps. Defer all other improvements.
- The internal `3.00_0x` train remains **INTERNAL ONLY / NEVER PUBLISH**,
  including `JQ-Lite-3.00_03.tar.gz`. Never merge v3 into stable `main`
  or mutate stable 2.x as part of collecting evidence.
- The compiled-query API (#627), full jq parity, rare deep computed
  selectors, and cross-platform expansion (#633) are **not new gates**
  unless a concrete supported-scope release blocker is demonstrated.

## Where we are

The [internal RC1 technical checkpoint](v3-release-readiness.md#internal-rc1-technical-evidence--merged-869)
has separately tested Perl 5.14/5.26/5.38/latest, jq 1.7
`compatible` fixtures, the actual source tarball, isolated
installation, CLI/Library contracts, and warning-clean test runs.
Merged [#880](https://github.com/kawamurashingo/JQ-Lite/pull/880)
finished at `40d15e0f041c34fcf6fdf1aab120c48b57cb29ca`;
its **final-head** Perl, jq differential and source-dist CI passed.
The observation workflow completed as designed, but **BackPAN remained
unavailable via TLS verification and the release audit is BLOCKED**.
Green *collection* CI must never be interpreted as history sign-off.

Observed external facts (not a complete public publication ledger):

| Source | 2026-10-25 observation | Limitation |
| --- | --- | --- |
| [CPAN SHINGO author index snapshot](v3-public-history-observation-2026-10-25.md) | 256 distinct JQ-Lite tarball version strings, all observed below 3.x; original HTML and checksums retained as an expiring Actions artifact | Current author-directory index can omit deleted, renamed or redistributed uploads; displayed mtime does not certify PAUSE upload time |
| [MetaCPAN](https://metacpan.org/release/SHINGO/JQ-Lite-2.59) | JQ-Lite 2.59 dated 2026-09-20 10:59:07 UTC | One release page is not an exhaustive deleted-release search |
| [Secondary CPAN mirror](https://mirror.cogentco.com/pub/cpan/authors/id/S/SH/SHINGO/) | Mirrors JQ-Lite historical tarballs including 2.x | Mirrors replicate CPAN and are **not independent proof** of original chronology or deleted releases |
| [GitHub Releases](https://github.com/kawamurashingo/JQ-Lite/releases) | One public release `v2.59`, with zero attached assets in inspected API result | Tags and links/CI artifacts may still have been exposed; published_at anomaly needs investigation |
| [GitHub tags](https://github.com/kawamurashingo/JQ-Lite/tags) | 24 tag refs, none 3.x in the inspected response | A tag is not proof of a public dist, and refs need periodic rechecking |
| [PAUSE operating model](https://pause.perl.org/pause/query?ACTION=pause_operating_model) | Deleted CPAN author files may remain on BackPAN | Explains why current CPAN listings **cannot** prove all-time history |

The already-observed `0.99 -> 0.100` order is a historical Perl
`version` **non-increase**, based on directory/index timestamps;
it must be resolved against original upload order rather than
pretended absent. The odd GitHub `v2.59` `published_at` vs
`created_at` timestamps must **not** be used to order releases.

## Critical path: evidence before selecting a public number

- [ ] **Original PAUSE upload chronology:** obtain the uploader's
  historical PAUSE upload records/receipt emails and the underlying
  author-upload history with timestamps and original archive names,
  including deletions, retries, developer versions and any renames.
  Preserve source/export date, original records, digest and a reviewable
  filename/date table. If PAUSE has no complete export, record that
  limitation and corroborate using separately preserved original records;
  do **not** fabricate completeness from a current index.
- [ ] **Independent historical archive:** obtain a *TLS-validated*
  BackPAN archive/index or another trustworthy independent archive
  (e.g. `backpan.perl.org`), record retrieval UTC time, URL, response
  headers and SHA-256, and compare its version/path set with the saved
  CPAN author inventory using existing **offline** comparison scripts.
  Never use `curl -k` or `--insecure`. A failed lookup is a
  documented **BLOCKED** evidence gap, not a reason to sign off.
- [ ] **Cross-check third-party metadata:** research *all* JQ-Lite
  releases, not just the latest, in MetaCPAN release metadata
  (date/path/author/status). Save the query, pagination, response bodies,
  request time and checksums; compare mismatches and flag removed
  uploads. MetaCPAN and CPAN mirrors may share inputs and do **not**
  provide independent proof by themselves.
- [ ] **Other public channels:** reconcile GitHub tags/releases/assets,
  GitHub Actions artifact access and promoted download links, docs/site
  installers, CPAN mirrors and downstream Alpine packages. Especially
  investigate whether *any* `3.00_0x` / `v3.00_0x` internal build
  was ever offered to the public, even temporarily, or shared outside
  the organization.
- [ ] **Resolve contradictions and attest:** review any archive-set
  differences, disputed timestamps, missing entries, duplicates and the
  `0.99/0.100` inversion. Produce a *human-vetted* chronological
  public-versions ledger with links to retained raw provenance and
  explicit maintainer confirmation of completeness. The source file's
  name/order is not a substitute for PAUSE upload sequence.

Until **all** the above are completed, **do not invoke**
`ci/check-public-version-order.pl --history-reviewed`; never
convert CPAN-index mtime order or BackPAN epoch order directly into
a certified `--published-file` ledger. A successful set comparison
alone is not a publication history audit.

## After history review: choose and verify the final candidate

1. **Version proposal / human approval:** If *no* `3.00_0x`
   developer candidate or other higher version was ever publicly
   distributed, a **stable-only `3.00`** could be proposed; otherwise
   choose a public number strictly above *every* predecessor according
   to core Perl `version` ordering. No version number is approved yet.
   Any public beta/RC route needs its full monotonic sequence through
   stable, and must not use internal `3.00_0x`.
2. **Reproducible preflight:** With the complete independently reviewed
   chronological `--published-file`, run the existing strict
   `ci/check-public-version-order.pl --history-reviewed` preflight.
   If verified older inversions exist, explicitly acknowledge *only
   those historical regressions* with the tool's documented flag.
   Save the exact command, exit code, candidate version and evidence.
3. **Final public-candidate freeze:** update module/POD, `Changes`,
   README, migration notes, `MANIFEST`, distribution metadata and
   release notes coherently for the **approved public candidate**.
   Keep existing known jq differences/unsupported features explicit;
   do not silently expand the compatibility promise.
4. **Candidate-specific fresh verification:** identify final head,
   base and synthetic PR merge SHAs; rerun all Perl versions, jq 1.7
   compatible fixtures, warning gates, release metadata, actual
   extracted-tarball `make test`, `make disttest`, clean installed
   Library/CLI smoke, and final-head Codex review. A prior internal
   RC1 or audit PR passing CI **does not** certify the final candidate.
5. **Explicit publication decision:** require maintainer approval
   naming the chosen stable version, reviewed history/evidence,
   final commit SHA and approved distribution channels.
   Only **after** that approval should any `main` merge, tag,
   GitHub Release, PAUSE/CPAN upload or promoted URL occur.

## Sign-off record (intentionally blank)

| Gate | Human reviewer / immutable evidence | Decision |
| --- | --- | --- |
| Complete public PAUSE chronology incl. deletions and `3.00_0x` | _not supplied_ | **BLOCKED** |
| Independent historical archive + other channels | _not supplied_ | **BLOCKED** |
| Chronological public-version ledger and highest predecessor | _not supplied_ | **BLOCKED** |
| Approved strictly monotonic public version | _not selected_ | **BLOCKED** |
| Final exact-candidate CI / archive / install / review | _not run for approved public number_ | **PENDING** |
| Maintainer permission to publish | _not granted_ | **NOT AUTHORIZED** |

**No early-November date is guaranteed**. The target is useful only
if these approval gates close with verifiable records; never override
a blocker to meet the calendar.
