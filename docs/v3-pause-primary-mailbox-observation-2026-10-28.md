# Primary PAUSE mailbox observation — 2026-10-28 (PARTIAL; no release authorization)

**Status: PRIMARY RECEIPTS LOCATED / PUBLIC RELEASE STILL BLOCKED.**
This observation supplements [the v3 public-distribution evidence](v3-public-distribution-evidence.md)
and the [public cutover gates](v3-public-release-cutover-plan.md).
It is **not** the complete, independently preserved and human-attested
PAUSE upload ledger required by `--history-reviewed`. No public
version number, 3.x beta/RC/stable artifact, or distribution action is approved.

## Provenance and privacy boundary

- On 2026-10-28, the maintainer identified the Gmail account holding
  the original PAUSE notices and enabled read access to it for the audit.
  The account and individual private message IDs/links are **not recorded
  here**, and no raw email body, addresses, auth token or private export
  is committed to this public repository.
- Several read-only Gmail subject searches and paginated result sets were
  combined by **message ID**, because individual search result sets were
  incomplete/inconsistent. One union observed **265 distinct `CPAN
  Upload: .../JQ-Lite-<version>.tar.gz` messages for 259 distinct
  stable numeric filename versions**, covering 2025-03-28 through
  2026-09-20. Six version names occur twice in that subject inventory:
  `0.36`, `0.94`, `1.26`, `2.08`, `2.10`, `2.55`.
  These are **message/filename counts, not proven distinct uploads or
  distinct bytes**; the same version can be retried and indexed again.
- The observed **259-version count** happens to agree with the
  separately captured BackPAN-author and MetaCPAN 259-version counts.
  This is only a **count comparison**: no complete byte-level export,
  chronology-preserving email inventory, per-version set equality
  or guarantee against missing/deleted messages has yet been certified.
- Searches of the accessible PAUSE mailbox found no matching
  `JQ-Lite-3.00_0x.tar.gz` upload receipt in the inspected results.
  This is **not** proof that those archives were never uploaded or
  publicly accessible via GitHub Actions or other channels; the
  [confirmed Actions exposure](v3-actions-artifact-exposure-decision.md)
  and strict version floor remain in force.

## Selected original upload-receipt facts verified from message bodies

The original PAUSE `CPAN Upload` emails state the filename, byte length,
SHA-256, `Request entered on` and `Request completed` timestamps.
The following selected bodies were directly read; timestamps are UTC.
The hashes/lengths are reproduced here **only because the same archive
hashes and byte lengths were already published** in the
[BackPAN 3-archive comparison](v3-public-history-observation-2026-10-25.md#original-archived-bytes-recovered-for-all-three-metacpan-only-versions).

| Version | PAUSE request completed (UTC) | Bytes | PAUSE receipt SHA-256 vs preserved BackPAN archive |
| --- | --- | ---: | --- |
| `0.05` | 2025-03-29 03:37:10 | 4,757 | **MATCH** `9fa7c2d9fe0b31687a78efa13cc50a5edd52d3b51a0abac6034bcfcb59876909` |
| `1.31` | 2025-10-26 09:05:27 | 97,715 | **MATCH** `bd59e36506584f99a1efad919c4dc7022bbc5e4ff639571a6ae84752d92f5d13` |
| `1.32` | 2025-10-26 11:09:49 | 90,355 | **MATCH** `e55860aab98ae4148c4daf1bdb8d113f511159073ad9a93c6dbf641167617feb` |

The three corresponding tarballs were missing from the current CPAN
author index but already obtained and checksum-verified over HTTPS from
BackPAN. The original PAUSE receipts now add directly observed
completion times, **not** a permanent exported mailbox ledger.

## Original timing confirms the historic Perl version-order regression

The actual PAUSE completion times (not mirror mtimes) were:

| Release name | PAUSE request completed (UTC) |
| --- | --- |
| `JQ-Lite-0.99.tar.gz` | 2025-10-13 01:26:30 |
| `JQ-Lite-0.100.tar.gz` | 2025-10-13 03:50:59 |

The original `0.100` `Failed: PAUSE indexer report` body confirms
status **Decreasing version number** and specifically records that
`JQ::Lite` in `0.99` had the higher Perl version number. Failed
indexer-report *subjects* were also located for `0.101`, `0.102`,
`0.103` and `0.104` (their individual bodies need separate
validation before asserting each precise failure reason). This is
stronger evidence for the known historic inversion than the former
mirror-date inference; it **does not relax the future monotonic-version
requirement**. A past non-increase must be explicitly acknowledged
only after full chronological history attestation.

## Original PAUSE deletion notices

Four `Files of SHINGO scheduled for deletion` bodies were inspected:

| Notice (UTC) | Listed JQ-Lite files | Evidence limitation |
| --- | --- | --- |
| 2025-03-29 07:46:29 | `0.05` `.meta`, `.readme`, `.tar.gz` | Scheduled removal, not independent proof of final deletion time |
| 2025-04-05 02:04:40 | `0.11` `.meta`, `.readme` only | **No `.tar.gz` listed**; do not infer tarball deletion |
| 2025-10-27 09:04:51 | `1.32` `.meta`, `.readme`, `.tar.gz` | Scheduled removal, not independent proof of final deletion time |
| 2025-10-31 09:14:34 | `1.31` `.meta`, `.readme`, `.tar.gz` | Scheduled removal, not independent proof of final deletion time |

These messages explain why current mirrors alone cannot serve as a
complete past-publication ledger, while the 3 direct BackPAN archive
observations verify that archive bytes are still independently available.

## Follow-up: full observed version-set comparison (2026-10-28)

A subsequent **read-only** audit compared the version-name set transcribed from one
265-message paginated PAUSE mailbox search to the **original extracted TSV
files** in the previously saved [BackPAN-author/MetaCPAN evidence
artifact](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40184472171/artifacts/12595646464).
That original ZIP contains `backpan-author-observed.tsv` (259 records)
and `metacpan-observed.tsv` (259 records), collected on 2026-10-25;
the published observation already confirmed BackPAN/MetaCPAN equality.
The present read-only recheck independently inspected both TSV files.

| Compared observed version sets | Unique stable versions | Set difference |
| --- | ---: | ---: |
| PAUSE `CPAN Upload` mailbox subject inventory (one 265-message retrieval) | 259 | 0 vs BackPAN; 0 vs MetaCPAN |
| Saved BackPAN-author archive TSV | 259 | 0 vs PAUSE and MetaCPAN |
| Saved MetaCPAN release TSV | 259 | 0 vs PAUSE and BackPAN |

To verify the **contents**, not just their cardinalities, all three
version sets were deduplicated and sorted lexically, joined with a
single `\n` between version strings (without a final newline) and
hashed as UTF-8 text. All three yielded the same SHA-256:
`3d2a03f601a97eab03e9e956db37c8c3b0a1de58d8fe3bd589c16595610bb354`.
The PAUSE names were **manually transcribed from the successful search
result** into the local comparison; an independent raw mailbox export
was **not** created. This establishes exact equality of the three
compared name sets, not a reproducible complete PAUSE ledger or
all-time completeness.

**Search-reproducibility caveat:** Repeating the same paginated Gmail
search also produced an incomplete 264-message / 258-version result.
Therefore the successful 265/259 retrieval is **not an immutable,
reproducible mailbox export**. The source may omit results inconsistently
across searches. Absence of an email in one result set is not evidence
that its upload never occurred. Original RFC822 source preservation,
independently checked pagination, and private complete-ledger attestation
remain mandatory.

### Six original repeat-upload pairs

The original bodies of both PAUSE receipts for **each** of `0.36`,
`0.94`, `1.26`, `2.08`, `2.10` and `2.55` were directly read.
Each pair has two different request-completion timestamps and
**identical archive SHA-256 and byte size within that pair**.
These are six observed *same-byte repeat uploads*, **not six additional
unique version strings or different binary builds**. The complete
chronology must retain both events rather than silently discard them.

### Five verified indexing failures

Original `Failed: PAUSE indexer report` bodies for `0.100`,
`0.101`, `0.102`, `0.103` and `0.104` were read; each explicitly
reports `Status of this distro: Decreasing version number` and an
older indexed `0.99` as having the higher module version. Perl core
`version->parse` confirms each of these five versions compares lower
than `0.99`. This is a **historical** regression, not permission to
accept a non-increasing *future* publication sequence. An independently
read failed report for `0.09` identifies missing distribution metadata,
a different kind of indexing failure. Later failed reports for `1.30`
and `1.31` were reruns and must not be mistaken for the original upload
time or for a new upload.

**Gate status: PARTIAL PROVENANCE CROSS-CHECK PASSED;
PUBLICATION STILL BLOCKED.** The 259-name set match does not settle
missing/deleted correspondence, historical archive/channel completeness,
independent private email preservation, the public Actions developer
tarball exposure, the agreed version floor, or the required
human-attested chronological ledger. Do **not** use `--history-reviewed`,
choose a public version, merge `v3-dev` to `main` or publish.

## Remaining release gates — explicitly NOT signed off

1. Independently retain a **private**, access-controlled export of all
   relevant original PAUSE `CPAN Upload`, indexer and deletion notices,
   with RFC822 provenance, hashes and dates; never push email bodies or
   recipients to public GitHub.
2. Reconcile the **full per-version set** with the 259 BackPAN/MetaCPAN
   observations, the current CPAN 256-row index, public GitHub channels,
   and the 269 CPAN Testers upload observations. Review missing and
   repeated entries, statuses and ambiguous/deleted/renamed uploads.
3. Construct the full chronological ledger from the **original request
   completion times**, independently verify all historical ordering
   anomalies (not only `0.99`/`0.100`), and have the maintainer confirm
   completeness and exceptional history handling.
4. Keep the [public `3.00_03` Actions exposure floor](v3-actions-artifact-exposure-decision.md)
   active. Choose a new strictly increasing public version train **only
   after** the complete review and explicit maintainer policy approval.
5. Run `ci/check-public-version-order.pl --history-reviewed` **only
   after** that human attestation. Re-freeze the chosen candidate,
   rerun its full Perl/jq/package/install checks and obtain separate
   maintainer permission before any `main` merge, release tag or upload.

**Result: substantial new primary evidence; not yet release-ready.**
