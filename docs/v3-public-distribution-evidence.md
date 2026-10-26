# JQ::Lite v3 public-distribution history: partial evidence snapshot

**Observed 2026-10-25 UTC; NOT a completed publication-history audit.**
This is evidence collected after merged PR #871 on `v3-dev` at
`d19e6f7b583896f3fbe2d5b096441350914439a3`, not a
`--history-reviewed` attestation, not public-version approval, and
not a release. The current `3.00_0x` developer train remains
**INTERNAL ONLY / NEVER PUBLISH**. Stable `main`/2.x is unchanged.

## Publicly observable evidence (a subset, not exhaustive)

| Channel / query | Observation on 2026-10-25 | Limit |
| --- | --- | --- |
| [MetaCPAN JQ-Lite 2.59](https://metacpan.org/release/SHINGO/JQ-Lite-2.59) | JQ-Lite 2.59, timestamp 2026-09-20 10:59:07 UTC, is listed as a distribution release | One release page is not a complete, chronological history |
| [CPAN mirror index](https://mirrors.edge.kernel.org/CPAN/modules/by-category/05_Networking_Devices_IPC/Net/SHINGO/) | The mirror index shows prior JQ-Lite 2.x tarballs through 2.59 | Mirrors may be stale/incomplete; no assertion about all older uploads |
| [GitHub Releases API](https://api.github.com/repos/kawamurashingo/JQ-Lite/releases?per_page=100) | One result: public non-draft, non-prerelease release `v2.59`, with no attached release assets | GitHub Releases are not the only public distribution channel |
| [GitHub tag refs](https://api.github.com/repos/kawamurashingo/JQ-Lite/git/refs/tags) | 24 refs, from historical v1/v2 tags through `v2.59`; none with a 3.x tag in this returned set | A tag is not evidence of a published tarball; other upload URLs may exist |
| [Project installation page](https://kawamurashingo.github.io/JQ-Lite/index-en.html) | Documents CPAN tarball, CPAN installation, and Alpine Linux package channels | Downstream package versions and third-party mirrors not audited |

**Do not use GitHub Release `published_at` as a chronological proof here.**
The `v2.59` API response reports `created_at=2026-09-20T10:55:44Z`
but `published_at=2026-01-03T03:53:26Z`. These values are inconsistent
with a straightforward release-creation chronology and require
independent verification before being used to order public versions.
The MetaCPAN timestamp and GitHub timestamps refer to different
systems and should not be conflated.

No 3.x release appears in the inspected GitHub Releases/tag responses
or the specifically inspected MetaCPAN latest release page. This
**does not prove** that any `3.00_0x` artifact was never publicly
distributed, nor that all public predecessors have been identified.

## 2026-10-26 GitHub release/tag channel and public install-link observation

A read-only GitHub API recheck on 2026-10-26 enumerated
`/releases?per_page=100&page=1` and `page=2`: page 1 returned
the sole public, non-draft, non-prerelease `v2.59` GitHub Release,
with **zero attached assets**; page 2 returned zero results. The
`/git/refs/tags` response listed **24 tag refs**; none were 3.x.
This bounds currently visible GitHub Releases and tag refs only,
**not** removed releases/tags, offsite copies or prior Actions access.
The earlier confirmed exposure of `3.00_03` is unchanged.

The `v2.59` GitHub Release continues to report
`created_at=2026-09-20T10:55:44Z` but
`published_at=2026-01-03T03:53:26Z`. This inconsistent ordering
cannot establish original PAUSE publication chronology.

The live [English installation page](https://kawamurashingo.github.io/JQ-Lite/index-en.html)
currently documents HTTP requests for release metadata and CPAN
tarballs. The prior v3 README also used HTTP and a bogus
`JSON-PP-4.xx.tar.gz` placeholder. The corrected **v3-dev README**
now requires HTTPS even on redirects, parses the response using
Perl 5.14+'s core `JSON::PP`, and accepts only stable numeric
versions. This does **not** change the deployed website. Identify
and review the website publishing source separately, with explicit
maintainer authorization before altering stable `main` or deployed
content. Prefer `cpanm JQ::Lite` or independently verified HTTPS
downloads until its public example is corrected.

These bounded observations provide no original PAUSE receipts,
historical access log or permission for public version selection.
**Public release remains BLOCKED.**

## Confirmed historical Perl ordering anomaly (not a complete audit)

The [CPAN SHINGO author tarball index](https://www.cpan.org/authors/id/S/SH/SHINGO/)
lists `JQ-Lite-0.99.tar.gz` at **2025-10-13 01:26** and
`JQ-Lite-0.100.tar.gz` at **2025-10-13 03:50** (directory times).
[MetaCPAN 0.99](https://metacpan.org/release/SHINGO/JQ-Lite-0.99)
independently records the earlier 0.99 release. Under Perl's core
`version` module, `version->parse('0.99') >
version->parse('0.100')`: **the later public filename sorts lower**.
This is a *historical* inversion, not a suggested v3 version or a
claim to have reconstructed the whole CPAN/PAUSE upload history.

`ci/check-public-version-order.pl` now reports any historical
non-increase relative to the highest older public version; only after
separate `--history-reviewed` and explicit
`--acknowledge-historical-regressions` attestations can such
historical observations be tolerated. **The first planned public
version must still be strictly above the historical maximum**, and
every later planned version must be strictly increasing. No historical
inversion can be repaired by pretending an old tarball was never public.

The [Alpine edge community package](https://pkgs.alpinelinux.org/package/edge/community/x86_64/jq-lite)
is currently listed as `jq-lite 2.49-r0` for x86_64. That confirms
a separate downstream publication route but does not audit every
architecture/branch, old artifact or external mirror.

## Audit input ergonomics (not an audit sign-off)

The offline public-version preflight accepts a line-oriented
`--published-file PATH` as an alternative to hundreds of repeated
`--published VERSION` arguments. The reviewed file must list
**every independently confirmed public version in chronology order**;
a separate evidence log should retain archive name, published time,
source URL and any corrections to the archive index's displayed
timestamps. The tool rejects missing, empty, mixed-source or malformed
files but **cannot prove completeness or verify provenance**. Do not
create a fictitious full ledger from this partial CPAN index snapshot,
and do not pass `--history-reviewed` until the maintainer's complete
multichannel publication audit is finished.

## Offline CPAN author-index inventory (not a publication ledger)

The [SHINGO CPAN author directory](https://www.cpan.org/authors/id/S/SH/SHINGO/)
shows individual `JQ-Lite-*.tar.gz` archives, with **directory
last-modified times**, not certified PAUSE upload dates. A saved copy
of that HTML listing can be reduced to a reviewable TSV:

```sh
curl -fsSL https://www.cpan.org/authors/id/S/SH/SHINGO/ \
  -o /tmp/cpan-shingo-index.html
perl ci/inventory-cpan-jq-lite-index.pl \
  --input /tmp/cpan-shingo-index.html > /tmp/jq-lite-observed-archives.tsv
```

This helper **never fetches the network itself**, includes only exact
`JQ-Lite-<version>.tar.gz` links, and sorts the output by the
observed listing modification time. It rejects duplicate/malformed
archive entries or an empty result; a visible `3.00_0x` candidate
triggers an alert and nonzero exit rather than being silently ignored.

**Do not pipe this TSV directly into `--published-file`**: it has
four provenance/observation columns rather than a reviewed,
chronological, versions-only publication ledger. Directory mtime is
not reliable evidence of original publication order, and the index
may omit deleted/renamed or externally distributed archives. An
independent CPAN/PAUSE and multichannel audit must reconcile these
observations, archive links, timestamps and distribution history
before any human `--history-reviewed` attestation. Saving or
extracting the listing is **not a release sign-off**.

## Compare an observed CPAN index with a proposed history (offline only)

After generating the four-column TSV above, reviewers can compare the
**sets of versions** against a separate, manually researched,
chronological versions-only history:

```sh
perl ci/reconcile-cpan-public-history.pl \
  --inventory /tmp/jq-lite-observed-archives.tsv \
  --published-file /path/to/researched-public-versions.txt
```

An observed archive missing from the supplied history is reported as
`UNRECONCILED`; a history version absent from this particular index
requires separate external evidence. Duplicate/malformed records
are rejected, and any observed internal `3.00_0x` archive forces
a failure even if both input sets contain it.

**An exact match only checks set membership.** This tool does not
establish upload chronology, include removed archives, audit
distribution mirrors or certify that history is complete. It never
calls the version-order preflight, never supplies
`--history-reviewed`, and never authorizes a release.

## Independent BackPAN observation cross-check (offline, no release approval)

The [BackPAN archive index](https://backpan.cpantesters.org/) is a
**different observation source** from the current CPAN author directory.
[CPAN::ReleaseHistory 0.10+](https://metacpan.org/pod/CPAN::ReleaseHistory)
provides an iterator over its archived release history, including releases
that may no longer appear on current CPAN mirrors. This is useful evidence,
**not proof of a complete or current PAUSE upload ledger**. In particular,
the BackPAN index may lag behind newer uploads, and its stored timestamps
must be independently checked against original PAUSE upload records.

Download the **releases-only BackPAN index** in a separate, manually
operated audit environment. [BackPAN::Index::Create](https://metacpan.org/pod/BackPAN::Index::Create)
defines its `#FORMAT 1` lines as archive path, epoch timestamp,
and byte size. A releases-only index omits the `authors/id/` prefix;
the extractor also accepts that prefix from full indexes. Neither
the index's modification time nor its per-file epochs independently
certifies original PAUSE publication chronology.

```sh
curl -fL https://backpan.cpantesters.org/backpan-releases-by-dist-index.txt.gz \
  -o /tmp/backpan-releases-by-dist-index.txt.gz
sha256sum /tmp/backpan-releases-by-dist-index.txt.gz
perl ci/inventory-backpan-jq-lite-index.pl \
  --input /tmp/backpan-releases-by-dist-index.txt.gz \
  > /tmp/jq-lite-observed-backpan.tsv

perl ci/compare-backpan-cpan-inventory.pl \
  --backpan-file /tmp/jq-lite-observed-backpan.tsv \
  --inventory /tmp/jq-lite-observed-archives.tsv
```

The new inventory extractor accepts locally saved plain-text or gzip
`#FORMAT 1` inputs; it uses **only core Perl**, including
`IO::Uncompress::Gunzip`, and **does not fetch the network**.
Malformed/duplicate JQ-Lite archive records, an unexpected
JQ-Lite release suffix, missing/invalid sources or a `3.00_0x`
developer candidate (with or without `v`) cause nonzero exit.
The TSV preserves the observed timestamps; it is review-only.
`CPAN::ReleaseHistory` remains an optional alternative for analysts
but is no longer needed for this extraction workflow.

Retain the downloaded `.gz`, its SHA-256 checksum, source URL,
UTC retrieval date and the resulting TSV outside the repository
for independent provenance review. A matching BackPAN/CPAN
comparison is **not** evidence of complete PAUSE release history.

The second input is the saved CPAN index TSV from
`ci/inventory-cpan-jq-lite-index.pl`. The comparator needs **only core
Perl** and performs **no network access**. It rejects malformed or
duplicate records, flags versions seen only on either side, detects
author/path mismatches and identical BackPAN epochs, and reports
historical non-increases under Perl `version` comparisons.
Any `3.00_0x` (including `v3.00_0x`) observation causes failure.
A zero exit status means only that the **two supplied sets agree**, not
that either source is complete, fresh, authoritative, or that chronological
publication has been verified.

Keep the original downloaded index, the three-column TSV, exact source
URLs, retrieval time, content checksums and all discrepancies in a
separate human-review evidence record. Do **not** copy the comparator's
epoch-sorted output into `--published-file` and do **not** use
`--history-reviewed` until CPAN/PAUSE upload records, BackPAN, MetaCPAN,
GitHub and downstream publication channels are independently reconciled.
Any missing or contradictory observation remains an unresolved release
blocker.

## Repeatable live-index snapshot on GitHub Actions (opt-in, observation only)

The **v3 public history observation snapshot (NOT release approval)**
workflow in `.github/workflows/v3-public-history-observations.yml`
offers a separate, read-only way to collect current public evidence when
the two remote indexes cannot be fetched from a local audit environment.
It runs only when its own workflow file changes in a PR targeting
`v3-dev` or is merged/pushed to `v3-dev`. Reviewers can refresh an
existing run with GitHub Actions **Re-run jobs**. It is **not** scheduled,
does not run on ordinary development PRs, and does not publish a package.
It deliberately does **not** promise manual `workflow_dispatch` on
`v3-dev`: that GitHub event needs the workflow to exist on the default
branch, and this project must not modify stable `main` for the v3 audit.

The workflow retrieves the CPAN SHINGO directory via **verified TLS**
(primary CPAN host, with named CPAN mirror fallbacks recorded verbatim)
and the BackPAN releases-by-dist gzip index. TLS certificate checking
must **not** be bypassed. A mirror listing is observational evidence,
not necessarily a fresh or authoritative source. When all verified CPAN
sources or the BackPAN source are unreachable, the workflow issues an
explicit **audit BLOCKED / source unavailable** warning and stores a
partial artifact, while allowing the evidence-collection check to
complete (an external TLS outage is not a test defect). **This green
check does NOT mean the audit passed.** A successfully downloaded source
with malformed records, internal developer artifacts, or an unresolved
version-set discrepancy remains a **failing validation check**. It saves **original downloaded
bytes**, HTTP response headers, source URLs, UTC collection times, the
checked-out SHA, SHA-256 checksums, both parsed TSVs and the observation
comparison under a `v3-public-history-observations-<run_id>` artifact
(retained for 14 days). Auditors must preserve the artifact independently
before expiry; it is neither a durable archive nor a validated PAUSE
publication ledger. A failed download, parse or comparison remains a
**review blocker**, but the upload step still retains any files collected
before failure. The artifact may therefore be partial; inspect its
provenance `AUDIT_STATUS`, captured files, and workflow log before drawing
conclusions. A completed job with `BLOCKED_*_SOURCE_UNAVAILABLE`
means **no reconciliation happened**, and never authorizes publication.

Even a **green** workflow verifies only the supplied BackPAN/CPAN
observational sets. It does not validate original PAUSE chronology,
removed entries absent from both indexes, third-party channels or
readiness to call `--history-reviewed`. BackPAN timestamps are
observations rather than proof of upload time; note the index's
`Last-Modified` HTTP header and possible staleness in the human audit.

## Full MetaCPAN release-search observations (source preserved, not a PAUSE ledger)

The separate `.github/workflows/v3-metacpan-release-observations.yml`
workflow collects the **unmodified JSON** response for a
`/v1/release/_search` query restricted to `distribution=JQ-Lite`,
without a `status=latest` filter. It asks for **exact hit totals**,
limits the request to 500 hits, and preserves the request JSON, HTTP
headers, original response bytes, UTC retrieval time, checkout SHA,
SHA-256 checksums and a reviewable TSV for 14 days. Runs are scoped to
this workflow/parser/test in PRs targeting `v3-dev`, or to an update
of the workflow file merged into `v3-dev`—not every development PR.

`ci/inventory-metacpan-jq-lite-releases.pl --input SAVED_RESPONSE.json`
uses core `JSON::PP` and works **offline**. It fails on an API error,
missing or approximate hit totals, a result count less than the total,
malformed releases/dates, duplicates, foreign distributions, failed
search shards, or an internal `3.00_0x` observation. It keeps the
internal sighting in TSV stdout before exiting nonzero. Retrieval
unavailability is **warned and explicitly BLOCKED**, not transformed
into a fabricated empty history or a code-test failure; successful
network retrieval with an invalid response remains a failed check.

A green *collection workflow* means at most that the observed search
response was saved or source unavailability was safely classified. The
MetaCPAN search may omit removed/hidden uploads, use dates that differ
from original PAUSE upload times, or share underlying data with CPAN.
It is an **additional observation channel, not independent proof of
complete historical publication**. Its `metacpan_date` column must
never be copied into `--published-file` or treated as
`--history-reviewed` chronology. Independently compare the observed
release versions with the saved CPAN author inventory; investigate
any discrepancies, download URLs, status values, original PAUSE
receipts and public distribution of developer candidates.

## Targeted BackPAN retrieval of the three missing CPAN-index versions

The [official PAUSE operating model](https://pause.perl.org/pause/query?ACTION=pause_operating_model)
distinguishes current CPAN mirror content from historical BackPAN:
deleting an author's uploaded distribution removes it from ordinary
mirrors eventually, while BackPAN is intended to preserve historical
uploads. PAUSE's [privacy policy](https://pause.perl.org/pause/query?ACTION=pause_privacy_policy)
also states that PAUSE records original upload timestamps and checksums.
Neither statement makes MetaCPAN index `date` a certified upload time.

Merged #882 observed three MetaCPAN `backpan` records missing from
the earlier 256-row CPAN author index: **0.05, 1.31 and 1.32**. The
read-only `.github/workflows/v3-backpan-gap-archives.yml` workflow
makes **targeted** validated-HTTPS requests for precisely those
`JQ-Lite-*.tar.gz` files from the two BackPAN hostname endpoints
named by PAUSE (`backpan.perl.org` and
`backpan.cpantesters.org`). It saves the exact attempted and
selected URLs, responses/headers, UTC run provenance, original
tarball bytes and SHA-256 checksums for any recovered archives.
Downloaded bytes must pass gzip/tar integrity checks and show the
expected distribution directory. A successfully downloaded invalid
archive is a **hard failure**, never a reason to silently substitute
a different host. An inaccessible host is recorded as **BLOCKED**
rather than mistaken for proof that a historical version never existed.
The short-lived artifact is an evidence snapshot, not a published
install link or release.

**This three-version check does not replace** a complete historical
BackPAN index, PAUSE source upload receipts, original upload chronology,
the human review of `0.99 -> 0.100` ordering, other distribution
channels, or the `3.00_0x` nonpublication investigation. Even three
validated tarballs would verify their **archived contents**, not that
all past releases are known or that a public version can be selected.
No `--history-reviewed`, new tag or publication is permitted.

## All observed SHINGO BackPAN author tarballs versus full MetaCPAN search

The [BackPAN historical author directory](https://backpan.perl.org/authors/id/S/SH/SHINGO/)
is available under verified HTTPS and contains the three archive files
recovered by #883. It is a **different list** from the unavailable
CPAN Testers *global* `backpan-releases-by-dist-index.txt.gz`.
It is useful for testing whether the author-history archive set
covers the already observed 259 MetaCPAN versions, but it is **not**
a whole-BackPAN index or a complete PAUSE publication ledger.

The read-only, scoped
`.github/workflows/v3-backpan-author-metacpan-compare.yml` saves
the original BackPAN author-directory HTML, the unmodified full
MetaCPAN release-search JSON, the exact MetaCPAN request, HTTP
response headers, SHA-256 hashes, UTC collection time, checkout SHA,
both derived TSVs and a review-only version-set comparison. The
existing offline CPAN HTML extractor can parse an Apache author
directory; here its `index_last_modified` column means **BackPAN
directory** modification time, not CPAN upload time. The separately
queried MetaCPAN search demands an exact hit total, no timed-out
results, no failed shards and no truncated return. The offline
`ci/compare-backpan-author-metacpan-inventory.pl` script requires
valid TSV schemas, checks for duplicate or developer versions and
non-SHINGO release authors, and fails on any version-set mismatch.

Download failures over authenticated HTTPS are recorded as
**AUDIT BLOCKED / SOURCE UNAVAILABLE** rather than successful audits.
After a source has downloaded, malformed listings, invalid MetaCPAN
results, developer archives and mismatched version sets are **hard
failures** with original evidence retained. All redirects are also
restricted to HTTPS. The short-lived GitHub Actions artifact must
be archived outside the repository before its 14-day expiry.

Even if the author directory and MetaCPAN sets agree, they can both
miss removed/backfilled archives, different-author releases, versions
shared through external channels, or public copies of the internal
`3.00_0x` builds. Archive directory `Last-Modified` and MetaCPAN
`date` are not independently certified original upload timestamps.
Do not use any of these timestamps to assert chronological PAUSE
publication order. Do not pass `--history-reviewed`, select the
public version, tag, merge v3 to `main`, upload CPAN or publish.

## CPAN Testers uploads timeline (third observation source; not PAUSE receipts)

The [CPAN Testers Uploads API](https://api.cpantesters.org/)
provides a **distribution-scoped** public endpoint
[`GET /v1/upload/dist/JQ-Lite`](https://api.cpantesters.org/v1/upload/dist/JQ-Lite),
as [documented by its upstream controller](https://metacpan.org/pod/CPAN::Testers::API::Controller::Upload).
The API returns upload observations including distribution, release
filename, version, author and a `released` timestamp. The published
[CPAN Testers upload-table schema](https://metacpan.org/pod/CPAN::Testers::Schema::Result::Upload)
explicitly says that its release time comes from **the local CPAN
mirror file mtime or NNTP upload-notification time**. It is a
separate public observation worth checking against BackPAN and
MetaCPAN, but **not a signed original PAUSE upload ledger**, and
not an independent completeness attestation.

The read-only, paths-scoped
`.github/workflows/v3-cpantesters-upload-observations.yml`
preserves the raw JSON response, HTTP response headers, retrieval UTC,
checked-out SHA, content SHA-256 and a derived review-only TSV as a
short-lived 14-day Actions artifact. Original and redirected transport
is restricted to verified HTTPS. The offline core-Perl
`ci/inventory-cpantesters-jq-lite-uploads.pl` parser requires an
actual, nonempty JSON array of JQ-Lite upload records, checks filenames
and dates, preserves **every** upload row without silently
de-duplicating, and explicitly alerts on any `3.00_0x` or
`v3.00_0x` internal version, off-SHINGO author, or duplicate
filename/version. It does not fetch network data.

If the endpoint is unavailable, the workflow warns and marks
**AUDIT BLOCKED**, retaining partial provenance rather than failing
ordinary Perl feature tests. A **valid but historically ambiguous**
response with duplicate versions, empty uploader/filename fields or
an epoch-sentinel date preserves every row and marks
**BLOCKED_UPLOAD_RECORD_ANOMALIES** (collection job can finish without
pretending the audit passed). A malformed JSON/schema, foreign
uploader or detected internal developer candidate is a **hard
validation failure**. The API does not provide an independently
auditable historical total in its example array schema; receiving
valid JSON must **never** be interpreted as proof that all uploads
have been returned. Even a perfect 259-version match would not
resolve PAUSE upload chronology, deletion/reupload history,
external distribution of internal `3.00_0x` builds, or public
version approval. Do not use this feed directly as
`--published-file`, do not call `--history-reviewed`, and do
not publish a release based solely on these observations.

## Critical: GitHub Actions source artifacts were an accessible distribution channel

**Discovery (2026-10-25 UTC): release history still BLOCKED.**
The `v3 source distribution candidate` workflow previously uploaded
`JQ-Lite-*.tar.gz` using `actions/upload-artifact@v4` on each
PR/push with the name `v3-unreleased-source-<run_id>`.
The current `v3-dev` module identifies as **internal `3.00_03`**.
The actual [run 40188275036 artifact 12597242129](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40188275036/artifacts/12597242129)
is an unexpired, 569,572-byte GitHub Actions artifact, and independent
read-only inspection of its downloaded ZIP showed
**`JQ-Lite-3.00_03.tar.gz`** inside. Other known unexpired examples,
without claiming a complete repository-wide inventory:
[run 40184611220 / 12595905899](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40184611220/artifacts/12595905899),
[run 40182945614 / 12595032233](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40182945614/artifacts/12595032233),
[run 40171340850 / 12590531371](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40171340850/artifacts/12590531371),
and [run 40169376705 / 12589947578](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40169376705/artifacts/12589947578).
Their names, creation times and retained ZIP bytes establish
**observable CI artifact exposure**, not PAUSE or GitHub Release uploads.
The other ZIPs' contents must not be inferred from filenames alone.
A [read-only repository-wide artifact inventory run 40200136630](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40200136630)
on **2026-10-25 around 13:59 UTC** scanned the currently returned
GitHub Actions artifact metadata over all available pages. It
reported **92 not-expired artifacts** with the
`v3-unreleased-source-*` naming pattern. This is a **point-in-time
count of accessible metadata**, **not 92 confirmed downloads or
independently verified ZIP contents**, and does not include artifacts
already purged/expired. The run summary retains matching artifact IDs,
creation times, expiry flags and workflow run IDs without republishing
any developer archive bytes.


[GitHub's documented artifact access policy](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)
states that signed-in GitHub users with repository read permission can
download workflow artifacts. For a public repository, this can expose
an internal developer archive beyond the maintainer. **Calling a CI
artifact "unreleased" does not make it private.**

The source-distribution test workflow is changed in this PR to
**stop uploading actual internal developer tarballs**, while retaining
the complete on-runner archive tests, extracted-tarball install
checks, and SHA-256 in CI logs. The independent
`.github/workflows/v3-internal-artifact-exposure-audit.yml`
performs a **read-only, paginated** inventory of *present* repository
artifact metadata under `actions: read`. It emits IDs, names,
creation dates and expiry for the `v3-unreleased-source-*` train but
does not download, delete, or re-upload package archives. A separate
**metadata-only, 14-day** Actions artifact retains the original paged
API JSON, matching TSV, workflow-run/check-out-SHA/UTC provenance and
SHA-256 list even when enumeration fails after a partial fetch. The
snapshot is publicly readable metadata, **not** tarball bytes,
verified download logs, complete historical access records or an
original PAUSE ledger. The separately inspected
[2026-10-25 metadata snapshot](v3-actions-exposure-snapshot-2026-10-25.md)
records the retrieved ZIP hash, four matching member SHA-256 checks,
and exact original-JSON-to-TSV reconciliation (126 metadata rows,
92 matching live names). Independent off-CI preservation of the
original archive is still required before its recorded expiry. A maintainer must preserve copies and checksums
independently before their 14-day expiry. A failing inventory stays
**BLOCKED**, regardless of whether partial evidence was retained.

**Human decision still required:** review every historical Actions
archive exposure, any promoted links and external redistribution,
decide whether any development artifact counts as a previously
publicly distributed version, and choose a public version strictly
consistent with Perl `version` ordering. In particular,
`version->parse("3.00_03") > version->parse("3.00")`; **do not
automatically approve stable `3.00`** on the assumption that
`3.00_0x` never left internal access. Absence from CPAN, BackPAN
author index and MetaCPAN does **not** overcome this separate evidence.
Deleting old artifacts would not prove no prior downloads or third-party
copies. Existing artifacts were **not deleted** in this change; agree
on evidence retention and any deletion separately. The inventory
cannot enumerate previously expired/deleted artifacts, nor prove that
the remaining population never was copied externally.

**Gate remains BLOCKED: no `--history-reviewed`, public version,
`main` merge, tag, CPAN upload, or GitHub Release approved.**

## Still required before `--history-reviewed`

- [ ] Independently obtain **the complete public CPAN/PAUSE upload history**,
  including older and developer releases, with actual publication order,
  not just a newest-version lookup.
- [ ] Audit GitHub release assets, historical tags, promoted direct
  tarball URLs, external mirrors, archived installers and downstream
  distribution/package channels (including Alpine) for any public
  `3.00_0x` distribution.
- [ ] Confirm whether CI-produced/internal candidate archives have ever
  been redistributed or advertised as public install targets; do not
  infer from the label "CI artifact" alone.
- [ ] Reconcile all public versions **chronologically**, resolve timestamp
  inconsistencies, identify any duplicates/downgrades and record source
  links and the maintainer's sign-off.
- [ ] Only after actual history verification, choose a **separately
  approved** public beta/RC-to-stable sequence above the conservative
  `3.00_03` exposure floor; stable-only `3.00` remains blocked under
  the current policy. Then run `ci/check-public-version-order.pl --history-reviewed`
  with **every** actual public predecessor in publication order.
- [ ] Re-run all candidate-specific release gates and obtain explicit
  maintainer publication approval. No `main` merge, tag, CPAN upload,
  GitHub Release, or public version is authorized here.

**Current gate result: BLOCKED / INCOMPLETE.**
In particular, **do not invoke the preflight tool with
`--history-reviewed` using only `2.59` as historical input**. That
would make an unverified completeness claim and could falsely suggest
the release-order gate passed. See
[release readiness](v3-release-readiness.md#offline-public-version-preflight-no-release-action)
and [#619](https://github.com/kawamurashingo/JQ-Lite/issues/619).
