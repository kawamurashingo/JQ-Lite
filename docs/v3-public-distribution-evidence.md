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
