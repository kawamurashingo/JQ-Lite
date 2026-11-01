# v3 release evidence reconciliation — 2026-11-01

**Captured evidence, not human attestation or permission to publish.**
This updates the partial 2026-10-28 mailbox observation. The maintainer's
2026-11-01 instruction authorizes preparation through the pre-release stage
and merging reviewed, passing preparation PRs into `v3-dev`.

## Original records retained privately

Gmail API `format=raw` returned 532 original RFC822 messages: 265 upload
receipts and 267 indexer/reindex/deletion messages. Base64url-decoded bytes
are retained unchanged as individual `.eml` files, with per-file SHA-256,
API search pages, retrieval provenance and an evidence-linked manifest.
This is a **search-bounded API export**, not Google Takeout or a full-account
completeness certificate. No raw mail, identifiers or recipients are in Git.

The private evidence bundle `jq-lite-private-release-evidence-2026-11-01.zip`
was saved independently of GitHub Actions (SHA-256
`5ff44b1ecbc6b0e7618007622a8307108b3a26a9af2ac579764dea0887f7e2a1`).
It contains original messages, derived receipt chronology, fresh public
responses/headers, historical preserved snapshots and comparison results.
The raw-message preservation gap is closed **for these 532 records**;
human confirmation of the search scope and completeness remains open.

## Fresh HTTPS observations and reconciliation

| Source | Observed rows / versions | Result |
| --- | --- | --- |
| Original PAUSE upload bodies | 265 / 259 | Completion UTC, archive, bytes and SHA-256 extracted; six repeated versions have the same bytes |
| BackPAN SHINGO author directory | 259 / 259 | Version set equals original receipts and MetaCPAN |
| MetaCPAN distribution-wide search | 259 / 259 | Exact total checked; no non-SHINGO author in the returned set |
| Current CPAN author directory | 256 / 256 | Missing 0.05, 1.31, 1.32; matches the three tarball deletion-scheduling notices |
| CPAN Testers upload feed | 269 / 259 | Same version set; duplicate rows and one incomplete epoch-sentinel row retained |

The three missing CPAN archives were freshly fetched from BackPAN over
validated HTTPS. All three byte lengths and SHA-256 values equal their
original PAUSE upload receipts. The 0.11 deletion notice names only sidecars;
it is not evidence of deletion of the 0.11 tarball.

The offline comparator exits **1**, intentionally: it identifies five
historical non-increases, 0.100 through 0.104 below the preceding maximum
0.99. There are zero BackPAN-only or MetaCPAN-only versions. Do not change
the comparator or history to turn that result green. Original failed-indexer
reports confirm those five ordering errors. Other failures (0.09 missing
META files, later reindex attempts for 1.30/1.31) are separate events.

Same-byte repeated receipt versions: 0.36, 0.94, 1.26, 2.08, 2.10, 2.55.
The CPAN Testers feed is a different event source: its duplicate rows are
not equated to these repeated original receipts. Its 0.81 epoch-sentinel
row lacks author/filename; a separate normal 0.81 row and original receipt
exist. These feed anomalies do not introduce another version and are not
used as authoritative upload-completion times.

## GitHub exposure recheck

Current release/tag API observations show one release (`v2.59`, no assets)
and 24 tags. They do not prove the absence of removed tags or releases.
The previously noted inconsistent release `published_at`/`created_at`
timestamps are not used to order PAUSE uploads.

[Exposure workflow 41256990692](https://github.com/kawamurashingo/JQ-Lite/actions/runs/41256990692)
retained a metadata ZIP captured at 2026-11-01T00:29:53Z. Its SHA-256 is
`c3f4da296abfd063b72940d3c0c53c5ac3a750d81498879cb64c0b2f0a9c3c8b`.
The existing offline verifier passed ZIP/member hashes, two API pages,
172 unique artifact IDs and 92 matching, unexpired source-artifact names.
This is metadata, not archive contents or proof of downloads. The known
`3.00_03` exposure floor remains active; no artifact was deleted.

## Remaining human decision and proposed candidate

`3.01` is a **proposed, unreleased** candidate, staged for review in response
to the request to proceed to immediately before release. Perl core `version`
orders `2.59 < 3.00_03 < 3.01`. This numerical comparison neither certifies
all-time distribution history nor invokes `--history-reviewed`.

Before publication, the maintainer must review the private evidence and
confirm history scope, acknowledge the five historical inversions and
known Actions exposure, and approve the version, exact candidate commit and
distribution channels. No claim is made about inaccessible/deleted mail,
unknown external redistribution or a complete historical access log.
After that review, run the existing preflight on the retained chronology
with explicit historical acknowledgement. Keep repeated receipt events in
the evidence; the preflight may report historical repeats as well.

Preparing/testing 3.01 does not authorize `main`, tags, GitHub Releases,
PAUSE uploads or promoted download URLs. Candidate source archives stay on
the test runner. See [the proposed release notes](v3-3.01-release-notes.md).
