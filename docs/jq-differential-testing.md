# jq 1.7 differential testing (JQ::Lite 3.x)

This suite checks jq-compatible behavior against upstream **jq 1.7.x** without
introducing a required runtime dependency on jq or any native library.

## Run locally

The standard distribution tests run without jq:

    prove -lr t

To enable differential tests, install jq 1.7.x and run:

    JQ_DIFFERENTIAL=1 prove -lv t/jq_differential.t

Set `JQ_BIN=/path/to/jq` to choose another jq executable or
`JQ_LITE_BIN=/path/to/jq-lite` to test an alternate jq-lite entry point.
The suite rejects jq versions outside the 1.7 series, rather than silently
testing against a different baseline. The CI job pins Ubuntu 24.04 and checks
the jq version before running this suite.

## Fixture format

Each non-comment line of `t/data/jq-differential.jsonl` is a JSON object with
these fields:

- `name`: unique case identifier.
- `input`: a JSON input value, including `null` when applicable.
- `filter`: a jq expression executed as one command-line argument.
- `status`: `compatible`, `planned`, `known-difference`, or `unsupported`.
- `expected`: upstream jq outcome, `ok` or `runtime-error`.

The runner sends the same single JSON input to both CLIs in compact-output
mode, decodes each emitted JSON value, canonicalizes object-key ordering, and
compares the **ordered** result stream. It compares success versus runtime
error for cases where exact diagnostic messages and exit-code numbers differ.

## Compatibility statuses

| Status | CI behavior | Meaning |
| --- | --- | --- |
| `compatible` | Gating | Both tools must have the expected outcome and identical successful JSON result streams. |
| `planned` | jq reference outcome gates; jq-lite difference is diagnostic only | Approved v3 semantic change not necessarily implemented on the branch yet. |
| `known-difference` | jq reference outcome gates; jq-lite difference is diagnostic only | Intentional documented deviation that is not a jq compatibility promise. |
| `unsupported` | Reported, not run | jq construct outside JQ::Lite's documented subset. |

Never label a failing compatibility case as `planned` solely to make CI pass.
Review the semantic inventory and the v3 roadmap before changing a status.
As implementation proceeds, convert approved `planned` cases to
`compatible` in the same PR that fixes the behavior and adds direct,
**dependency-free** regression tests.

## Scope and limitations

- This is a focused *single-input CLI* differential suite, not full jq
  language conformance testing. Add cases incrementally for paths, iterators,
  constructors, arithmetic, comparisons, aggregates, assignment, and errors.
- Compact JSON streams are compared structurally, preserving array order and
  the number/order of results. Exact whitespace, object-key order, and jq's
  human-readable error text are not compared.
- `runtime-error` comparison checks jq 1.7's runtime exit code (5) and
  JQ::Lite's documented runtime exit code (3); compile errors and other
  categories should get dedicated fixtures and explicit classification before
  being claimed compatible.
- The CLI invocations use argument lists, never shell interpolation. Fixtures
  are trusted repository test inputs; large or adversarial stress fixtures
  need a separate resource-limited runner.
- Keep the existing `t/jq_semantic_differences.t` as a dependency-free
  regression snapshot for the current branch. This suite complements it; it
  does not replace the CLI and Library API contract tests.

See [the v3 roadmap](v3-roadmap.md) and
[the 2.x semantic differences inventory](jq-semantics-differences.md) for
the approved changes and preserved differences.
