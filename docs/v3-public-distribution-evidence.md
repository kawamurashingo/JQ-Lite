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
not necessarily a fresh or authoritative source. It saves **original downloaded
bytes**, HTTP response headers, source URLs, UTC collection times, the
checked-out SHA, SHA-256 checksums, both parsed TSVs and the observation
comparison under a `v3-public-history-observations-<run_id>` artifact
(retained for 14 days). Auditors must preserve the artifact independently
before expiry; it is neither a durable archive nor a validated PAUSE
publication ledger. A failed download, parse or comparison remains a
**review blocker**, but the upload step still retains any files collected
before failure. The artifact may therefore be partial; inspect its
manifest and workflow outcome before drawing conclusions.

Even a **green** workflow verifies only the supplied BackPAN/CPAN
observational sets. It does not validate original PAUSE chronology,
removed entries absent from both indexes, third-party channels or
readiness to call `--history-reviewed`. BackPAN timestamps are
observations rather than proof of upload time; note the index's
`Last-Modified` HTTP header and possible staleness in the human audit.

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
  approved** public beta/RC-to-stable sequence (or approved stable-only
  route) and run `ci/check-public-version-order.pl --history-reviewed`
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
