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

## Independently saved MetaCPAN release-search snapshot (additional observations)

[PR #882 MetaCPAN evidence run 40170962759](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40170962759)
collected the unmodified response to a `POST` request to
`https://fastapi.metacpan.org/v1/release/_search` on
**2026-10-25 06:57:31 UTC**, using `distribution=JQ-Lite`,
`track_total_hits=true`, `size=500`, sort by ascending `date`,
and **no latest-only restriction**. Checkout was the synthetic PR
merge `6f4264d48a406b617c845650349ff0b9316494ec`.
The original response is **115,770 bytes**, SHA-256
`22c374bdf19a69f2485bdcec4bc30b182b440a5658e289b0d4bc33189284432e`.
Request JSON: SHA-256
`5d8a267f0a48c649ac1d6658e08c7440f5ec30931186f98c82dc035630fe34a7`.
The extracted TSV is **19,764 bytes**, SHA-256
`755133adbed0a0fd69853f364b23d5a3e097da318e2a0acdf415bd84e878d693`.
Preserve [the original GitHub Actions artifact](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40170962759/artifacts/12590039931)
before its 14-day retention window expires, around **2026-11-08
06:57 UTC**.

The actual MetaCPAN response reports an **exact total of 259**
with **259 received hits**, all matching `JQ-Lite`. Its reported
`status` values were **255 `cpan`**, **3 `backpan`**, and
**1 `latest`**. No `3.00_0x` / `v3.00_0x` release was present
**in this one MetaCPAN result set**.

Comparing the version strings against the earlier, independently
downloaded **256-row** CPAN SHINGO HTML snapshot
(run 40168407663) yields **no CPAN-only versions and exactly
three MetaCPAN-only observations**:

| Version | MetaCPAN `date` (UTC) | MetaCPAN `status` |
| --- | --- | --- |
| `0.05` | `2025-03-29T03:37:09` | `backpan` |
| `1.31` | `2025-10-26T09:05:26` | `backpan` |
| `1.32` | `2025-10-26T11:09:48` | `backpan` |

These discrepancies **must be retained**, not silently filtered to
make the sets match. They demonstrate that the current CPAN directory
listing is **not a complete historical release inventory**. The
MetaCPAN `backpan` status indicates its indexed classification,
not independent proof of an original PAUSE upload time or continued
availability of the archived tarball. Neither this result nor the
observed match for the remaining 256 versions proves all-time
completeness. The direct BackPAN original index and authoritative
upload/redistribution history remain unverified, and the
`0.99 -> 0.100` chronological Perl ordering anomaly still requires
original-upload evidence.

**Release-history gate: BLOCKED. No public version selected or approved.**

## Original archived bytes recovered for all three MetaCPAN-only versions

The [first targeted BackPAN PR #883 capture](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40182465966),
retrieved **2026-10-25 09:52:50–09:52:53 UTC**, succeeded
**3/3** over verified HTTPS using the PAUSE-documented
`https://backpan.perl.org/authors/id/S/SH/SHINGO/` host.
Checkout was synthetic PR merge
`7ee842e53a5a0b3eee1662884dddac0485a4bc0f`.
Each response was **HTTP/2 200** and had
`Content-Type: application/x-gzip`. The independently saved
original-byte checksums below were checked against the downloaded
[Actions evidence ZIP](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40182465966/artifacts/12595026077).
The ZIP also contains response headers, each tar member listing,
provenance and `SHA256SUMS`; retain it independently before
GitHub's 14-day artifact expiry (approximately **2026-11-08
09:52 UTC**).

| Version | Archive bytes | SHA-256 of original `.tar.gz` | BackPAN HTTP Last-Modified (UTC) |
| --- | ---: | --- | --- |
| `0.05` | 4,757 | `9fa7c2d9fe0b31687a78efa13cc50a5edd52d3b51a0abac6034bcfcb59876909` | 2025-03-29 03:37:09 |
| `1.31` | 97,715 | `bd59e36506584f99a1efad919c4dc7022bbc5e4ff639571a6ae84752d92f5d13` | 2025-10-26 09:05:26 |
| `1.32` | 90,355 | `e55860aab98ae4148c4daf1bdb8d113f511159073ad9a93c6dbf641167617feb` | 2025-10-26 11:09:48 |

The gzip stream and tar member structure validated for all three.
Direct, read-only inspection of each included `META.json` confirmed
`name=JQ-Lite` and the exact advertised version. Their HTTP
`Last-Modified` timestamps match the previously collected MetaCPAN
`date` for each release; they remain **server file times**, not
independently certified PAUSE original-upload timestamps. These are
genuine accessible historical archive observations, not inferred
from the current CPAN author directory.

**Result:** the exact **three MetaCPAN-only / current-CPAN-absent
versions are confirmed to have corresponding BackPAN tarballs**.
This explains the observed 259-versus-256 set difference, but **does
not prove 259 is the full historical universe** or establish the
public release order. A full BackPAN releases index, original PAUSE
receipts/deletions, all external channels and `3.00_0x`
nonpublication review remain outstanding. Keep `--history-reviewed`
and all release publication actions **BLOCKED**.

## Remaining approval blockers

Independently secure the complete CPAN/PAUSE history with upload-order
evidence, reconcile BackPAN with a verifiably retrieved index, inspect
public GitHub assets/tags, downstream packages and external mirrors,
and investigate any historical gaps, developer artifacts and timestamp
conflicts. **Public-history and publication authorization: BLOCKED.**
