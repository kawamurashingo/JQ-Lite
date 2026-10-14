# Practical v2-to-v3 path and iterator audit (checkpoint)

This is an initial **source-and-test inventory**, not a claim that every v2
filter or jq 1.7 expression works in v3. Issue #625 tracks the remaining
behavioral audit. The v2 practical subset remains the compatibility baseline;
new jq grammar and deep computed-selector combinations are not release goals.

## Reproducible source-size snapshot

Tracked \`lib/**/*.pm\` Git-tree blobs, **including** comments/whitespace and
**excluding** tests, CLI scripts and documentation. One blob per path; no
compressed-distribution or runtime-size claims.

| Snapshot | Commit | Modules | Bytes |
| --- | --- | ---: | ---: |
| stable main / v2 | \`6880c30440b564480d9971d575179513e16ed51f\` | 22 | 242,573 |
| pre-cleanup v3 | \`40c05db\` (roadmap baseline) | 22 | 326,242 |
| v3 after PR #750 | \`6d3ad329038ed1383e582fcd57dc20ffeebd8a2e\` | 22 | 318,514 |

The current v3 checkpoint is 75,941 bytes (+31.3%) over v2 and 7,728 bytes
smaller than the recorded pre-cleanup v3 baseline. This is not a line-count
claim. The five largest *per-module v3-versus-v2 byte increases* are:

| Module (\`lib/JQ/Lite/\` prefix unless noted) | v2 bytes | v3 bytes | Delta |
| --- | ---: | ---: | ---: |
| Filters.pm | 57,923 | 85,019 | +27,096 |
| Util/Transform.pm | 59,274 | 85,122 | +25,848 |
| Util/Paths.pm | 22,688 | 38,756 | +16,068 |
| Parser.pm | 9,062 | 12,741 | +3,679 |
| Runtime.pm | 1,052 | 2,566 | +1,514 |

These sizes identify review targets; a larger file alone does not mean code can
safely be deleted. The cleanup in this PR combines equivalent Parser.pm
rooted-path guards, preserving the full path validator and all existing
fallback paths. It does **not** remove supported syntax.

## Practical baseline anchored in stable v2 tests

| Behavior | Stable v2 test evidence | v3 audit/compatibility focus |
| --- | --- | --- |
| Plain and quoted field access | \`t/quoted_field_access.t\` | Distinguish \`.type\` and other fields from bare builtins; preserve explicit null |
| Array/object \`.[]\` and nested paths | \`t/object_iteration.t\` | Output ordering; strict vs optional errors; no-output on empty iterators |
| Common function and constructor suffixes | \`t/iterator_suffix.t\` | \`keys[]\`, \`to_entries[]\`, \`split(",")[]\`, \`[.a,.b][]\` and comma-local application |
| Comma and pipeline streams | \`t/comma.t\` | Preserve left-to-right ordering and zero-output branches |
| Array slicing | \`t/slice.t\` | Distinguish jq bracket slice semantics from v2's \`slice(start,length)\` extension |
| Lookup/path functions | \`t/getpath.t\`, \`t/setpath.t\`, \`t/delpaths.t\`, \`t/path.t\` | Inventory supported arguments and errors, including existing v2 extensions |

The tests above establish *v2 usage*, not blanket jq 1.7 conformance. v3 has
dedicated coverage under \`t/v3_*.t\` for quoted/numeric/computed selectors,
whitespace, strict/optional access, update and try/recurse; rare deep-selector
files are **review targets**, not grounds for extending the supported subset.

## Review order and compatibility boundaries

1. Keep common v2 field, index, slice, iterator, comma and constructor cases,
   checking ordered outputs plus null/empty/error distinctions against jq 1.7.
2. Compare the v2 and v3 implementations of those cases before removing
   special-case dispatch. Prefer shared, small guards with a single full
   validation step; do not loosen parser recognition.
3. Assess the additional v3-only numeric/computed-selector and try/recurse
   tests by frequency, maintenance cost and v2 compatibility. Do not delete
   behavior or add arbitrary depth support without separate evidence.
4. Track deliberate differences (notably \`slice(start,length)\`, array
   projection and first-result extension behavior) in the semantic-differences
   documentation rather than labelling them jq-compatible by assumption.
5. Keep the full Perl >= 5.14 matrix and jq 1.7 ordered-output/error-category
   differential CI green on the final HEAD before any merge.

This checkpoint does not close #625: individual behavioral comparison,
potential simplification of the three largest modules, and migration
documentation remain open.
