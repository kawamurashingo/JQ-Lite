# v3 Actions exposure metadata: independently inspected snapshot

**Evidence observation, NOT public-release approval or a complete history.**
Original snapshot capture: **2026-10-25 15:36:15 UTC**.
Independently downloaded and inspected on **2026-10-26 (JST)**,
after merged [#889](https://github.com/kawamurashingo/JQ-Lite/pull/889).
This document records a repeatable integrity and membership check of
**metadata only**; it does not claim the original ZIP will remain available.

## Source and observed artifact

- Repository: `kawamurashingo/JQ-Lite`; source workflow run:
  [40207717858](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40207717858).
- Artifact: [`v3-ci-exposure-metadata-40207717858`](https://github.com/kawamurashingo/JQ-Lite/actions/runs/40207717858/artifacts/12604331230),
  artifact ID **12604331230**, size **18,825 bytes** as reported by
  GitHub Actions.
- Reported expiry: **2026-11-08 15:36:15 UTC**. Preserve the original
  downloaded ZIP in a separate controlled archive before this deadline.
- Saved `provenance.txt`: `event=pull_request`,
  `checkout_sha=fc21de3feafd34c13be6138cf1da6893ba28c8a4`,
  `captured_utc=2026-10-25T15:36:15Z`. The checkout SHA is the
  **PR synthetic merge checkout**, not an assertion that it equals the
  feature-branch commit SHA. Source was the read-only GitHub Actions
  artifact metadata API, not an original PAUSE publication ledger.
- Retrieved ZIP SHA-256:
  `9c18e179c242efe20c21edf705e92310ad5f3742e749ad786ff1e2f65e4c229e`.

## Exact archived members and their recorded SHA-256

The ZIP member-name whitelist is exactly:

| Member | SHA-256 (checked against original `manifest-sha256.txt`) |
| --- | --- |
| `artifact-page-1.json` | `3d7fa102ed7c9e27535115ddbb2f6beff61bee983b84780298c88fdbe696f8d0` |
| `artifact-page-2.json` | `64ebba96efbf0c414bd4335ba2a06a18f0de04591fdb4f39023791358f16aef0` |
| `developer-artifacts.tsv` | `5fa4ad0f197bbca16a86a53caab9d2e4a7bd43a7f44307176690da489bc4e8b5` |
| `provenance.txt` | `115723a1c13203a63212b8692be77ff8c02ec84c9a1eafb64e5aeb3df6e9d4a6` |
| `manifest-sha256.txt` | Original checksum listing; its own digest is **not** in that listing |

All **four** digests present in the manifest matched the exact member
bytes from the downloaded ZIP. A verifier must also compare the ZIP
SHA-256 above; the unlisted manifest is **not** self-authenticating.

## Read-only structural reconciliation performed

- `artifact-page-1.json`: `total_count=126`, **100** artifact rows.
- `artifact-page-2.json`: `total_count=126`, **26** artifact rows.
- Exactly **126** returned rows and **126 distinct artifact IDs**
  across the two saved pages; the returned totals agree.
- Exactly **92** rows have names beginning `v3-unreleased-source-`,
  and all 92 have `expired=false` **in this capture**. The remaining
  34 rows are other artifact names, not additional confirmed developer
  archives.
- Exactly **92** lines in `developer-artifacts.tsv`. Its rows
  match the GitHub API rows **in order**, field by field:
  artifact ID, name, expired flag, UTC creation timestamp, and
  `workflow_run.id`. No count or metadata discrepancy was observed.
- Matching artifact creation timestamps in the saved API range from
  **2026-10-20T22:26:54Z** to **2026-10-25T13:55:39Z**.

These assertions were checked from the **actual downloaded ZIP bytes**,
not inferred solely from a green workflow or the previous 92-count
summary. They describe one finite point-in-time API response; no claim
is made that paging captures every artifact that ever existed.

## Mandatory qualifications / still blocked

1. The ZIP is a **GitHub Actions metadata snapshot**. It contains no
   developer `JQ-Lite-*.tar.gz` source archive member; this check
   does **not** inspect the contents of the 92 older ZIP artifacts.
2. Accessibility and `expired=false` do **not** prove any downloads,
   third-party copies, public installation, PAUSE upload, or release.
   Artifacts already deleted, expired or otherwise omitted before
   capture cannot be recovered from these pages.
3. Artifact expiry and loss of the only copy would prevent re-verifying
   the original bytes. This checked checksum record is not a substitute
   for preserving the ZIP **off GitHub Actions**. No deletion of old
   developer artifacts is approved by this observation.
4. Original PAUSE receipts/order, historic numeric inversion
   `0.99 -> 0.100`, external distribution and final maintainer
   sign-off remain unresolved. `--history-reviewed`, a public
   version, `main` merge, tag, GitHub Release and CPAN upload
   remain **BLOCKED**. The conservative public-version floor above
   `3.00_03` remains in force under #887.

**Verification procedure:** independently download the exact artifact
ZIP before expiry, compare the ZIP SHA-256 above, inspect the member
list for unexpected extra files, verify the four manifest-listed member
hashes, and re-derive the two-page/126-unique-ID/92-filtered-row result
from the original saved JSON and TSV. Never treat the two-page count as
a complete historical GitHub or PAUSE access/publication ledger.
