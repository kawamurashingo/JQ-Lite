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
