# v3 public-distribution observation, 2026-10-25 (PARTIAL; release BLOCKED)

This is a **source snapshot observation, not a PAUSE upload-history
attestation**. Never pass its version list directly to
`ci/check-public-version-order.pl --history-reviewed`, choose a stable
version, publish an internal `3.00_0x`, or infer history completeness.
The full multichannel audit in #619 remains blocked.

## Provenance of the first live-index attempt

- GitHub Actions [PR #880 observation run 40168407663](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40168407663);
  checked-out synthetic PR merge SHA
  `a65205844be219b3bd05fb830485026fab25564d`.
- Collection time: **2026-10-25 06:14:47 UTC**; CPAN source
  `https://www.cpan.org/authors/id/S/SH/SHINGO/`.
- Raw HTTPS response: **HTTP/2 200**, `Content-Length: 171252`;
  response `Date: Sun, 25 Oct 2026 06:14:47 GMT`.
- Original CPAN HTML: **171,252 bytes**, SHA-256
  `a1a9d9ac9ba6ab09f27c773166cabbf2ae04293bfc07ab1278fe5a9fa1abd110`.
- Derived `cpan-observed.tsv`: **15,165 bytes**, SHA-256
  `9b669de492d63320b57d2db152c68748b5991a75a9f739071e06c0048719cd98`.
- Original HTML, parsed TSV, HTTP headers and run provenance are retained
  in the [GitHub Actions evidence artifact](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40168407663/artifacts/12589571118);
  expiry **2026-11-08 06:14 UTC (approximately)**. Save and checksum
  the complete ZIP independently before GitHub's 14-day retention lapses.
  The reported time is the collection time; it is **not** a PAUSE release time.

## What the CPAN index actually shows

The existing `ci/inventory-cpan-jq-lite-index.pl` parsed **256
`JQ-Lite-*.tar.gz` archive rows with 256 distinct version strings**:
100 `0.x`, 97 `1.x`, and 59 `2.x` versions. The oldest directory
mtime in the observed ordering is `JQ-Lite-0.01.tar.gz` at
`2025-03-28 21:14`. The latest is `JQ-Lite-2.59.tar.gz` at
`2026-09-20 10:59`.

The observed `0.99 → 0.100` directory timestamps are respectively
`2025-10-13 01:26` and `2025-10-13 03:50`, matching the historical
Perl `version` ordering risk discussed in #873. **Directory mtime is
not independently verified original upload chronology.** No archive
named `3.00_0x` or `v3.00_0x` appeared in these 256 CPAN entries.
That narrow negative observation **does not prove no internal candidate
was ever distributed elsewhere or removed from the listing**.

## BackPAN source blocked (not reconciled)

The corresponding BackPAN source was
`https://backpan.cpantesters.org/backpan-releases-by-dist-index.txt.gz`.
Its fetch failed with **curl (60): self-signed TLS certificate** on the
runner. No BackPAN index, checksum, version count or comparison result
was obtained from this attempt. Do not use `curl -k` / `--insecure`,
construct a fictitious BackPAN ledger, or report a set match.

A subsequent change to #880 ensures even on such a download failure the
CPAN raw file and SHA-256 checksum are preserved separately. This
observation record documents the earlier, actual run and must not be
silently replaced by a later attempt.

## Remaining approval blockers

Independently secure the complete CPAN/PAUSE history with upload-order
evidence, reconcile BackPAN with a verifiably retrieved index, inspect
public GitHub assets/tags, downstream packages and external mirrors,
and investigate any historical gaps, developer artifacts and timestamp
conflicts. **Public-history and publication authorization: BLOCKED.**
