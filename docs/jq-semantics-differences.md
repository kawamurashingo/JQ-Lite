# jq semantic differences in JQ::Lite 2.x

JQ::Lite implements a useful jq-like language, but it is not a drop-in
implementation of every jq runtime semantic. This document records the
currently known **semantic** differences: cases where a filter is accepted by
both tools but its result or failure behaviour differs. It is a snapshot of
the 2.x behaviour, not a claim that unsupported jq syntax is supported.

The examples in the `jq` column describe jq 1.7 behaviour. The JQ::Lite
results are protected by `t/jq_semantic_differences.t`; the regression suite
does not require a jq executable.

## Classification

### A. Preserved 2.x compatibility behaviour

These differences are observable existing behaviour on which 2.x callers may
rely. Changing them requires an explicit compatibility decision rather than
an incidental parser or filter refactor.

| Area | Example | jq | JQ::Lite 2.x |
| --- | --- | --- | --- |
| Array `contains` | `[1,2,3] \| contains([1,3])` | `true` (recursive subset containment) | `false` (looks for one element equal to the complete argument) |
| Nested object `contains` | `{"a":{"b":1,"c":2}} \| contains({"a":{"b":1}})` | `true` | `false` (nested values must be equal) |
| Alternative operator | `false // 9` | `9` | `false` (only null, missing, or empty output selects the fallback) |
| Jagged `transpose` | `[[1,2],[3]] \| transpose` | `[[1,3],[2,null]]` | `[[1,3]]` (truncates to the shortest row) |

For jq-style recursive array containment, JQ::Lite provides the explicit
`contains_subset(value)` alternative. It avoids changing the established
meaning of `contains(value)` in the 2.x series.

### B. Permissive and vectorised JQ::Lite behaviour

JQ::Lite commonly favours lossless pipeline processing and Perl scalar
coercion where jq reports a type error or applies a different overloaded
operation.

| Area | Example | jq | JQ::Lite 2.x |
| --- | --- | --- | --- |
| Numeric coercion | `"1e3" * 1` | `"1e3"` (string repetition) | `1000` |
| Boolean arithmetic | `true + 1` | type error | `2` |
| Vectorised rounding | `[1.2,"2.8","x"] \| floor` | type error | `[1,2,"x"]` |
| Lossless JSON parsing | `["1","true","bad"] \| fromjson` | type error (input is not a string) | `[1,true,"bad"]` (element-wise, invalid text passes through) |
| Regex scalar coercion | `42 \| match("2")` | type error | a match object for the string form `"42"` |

This category is especially important when moving filters between the tools:
successful JQ::Lite output does not imply that jq will accept the same input
types. Conversely, jq operator overloading must not be assumed to use Perl's
numeric coercion in JQ::Lite.

### C. Explicit JQ::Lite extensions and migration aids

These names do not represent a conflicting jq meaning; they make JQ::Lite's
intent explicit or provide behaviours useful to existing pipelines.

| Extension | Purpose |
| --- | --- |
| `contains_subset(value)` | Opt in to recursive, order-insensitive subset containment without changing 2.x `contains(value)` |
| `to_number()` | Lossless/vectorised numeric conversion, distinct from strict `tonumber()` |
| `flatten_all()`, `flatten_depth(n)` | Explicit flattening variants |
| Statistical and convenience helpers | `avg`, `median`, `mode`, `percentile`, `variance`, `stddev`, `clamp`, and the other extensions listed in the function reference |

## What this inventory does not cover

- Syntax or built-ins which JQ::Lite does not implement are feature-coverage
  differences, not same-filter semantic differences.
- CLI diagnostics are governed by the stable CLI contract; exact jq error text
  is not a JQ::Lite compatibility promise.
- Object key order is not compared because JSON object ordering is not a
  portable semantic guarantee.
- jq may evolve after 1.7. When this inventory is updated, jq-version changes
  and JQ::Lite behaviour changes should be reviewed separately.

When a new difference is found, add it to the appropriate category and add a
dependency-free regression assertion for the current JQ::Lite behaviour. A
future behaviour change should be proposed separately, with the relevant 2.x
compatibility impact called out explicitly.
