# Practical v2-to-v3 path and iterator audit (checkpoint)

This is an initial **source-and-test inventory**, not a claim that every v2
filter or jq 1.7 expression works in v3. Issue #625 tracks the remaining
behavioral audit. The v2 practical subset remains the compatibility baseline;
new jq grammar and deep computed-selector combinations are not release goals.

## Reproducible source-size snapshot

Tracked `lib/**/*.pm` Git-tree blobs, **including** comments/whitespace and
**excluding** tests, CLI scripts and documentation. One blob per path; no
compressed-distribution or runtime-size claims.

| Snapshot | Commit | Modules | Bytes |
| --- | --- | ---: | ---: |
| stable main / v2 | `6880c30440b564480d9971d575179513e16ed51f` | 22 | 242,573 |
| pre-cleanup v3 | `40c05db` (roadmap baseline) | 22 | 326,242 |
| v3 after PR #750 | `6d3ad329038ed1383e582fcd57dc20ffeebd8a2e` | 22 | 318,514 |

The current v3 checkpoint is 75,941 bytes (+31.3%) over v2 and 7,728 bytes
smaller than the recorded pre-cleanup v3 baseline. This is not a line-count
claim. The five largest *per-module v3-versus-v2 byte increases* are:

| Module (`lib/JQ/Lite/` prefix unless noted) | v2 bytes | v3 bytes | Delta |
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
| Plain and quoted field access | `t/quoted_field_access.t` | Distinguish `.type` and other fields from bare builtins; preserve explicit null |
| Array/object `.[]` and nested paths | `t/object_iteration.t` | Output ordering; strict vs optional errors; no-output on empty iterators |
| Common function and constructor suffixes | `t/iterator_suffix.t` | `keys[]`, `to_entries[]`, `split(",")[]`, `[.a,.b][]` and comma-local application |
| Comma and pipeline streams | `t/comma.t` | Preserve left-to-right ordering and zero-output branches |
| Array slicing | `t/slice.t` | Distinguish jq bracket slice semantics from v2's `slice(start,length)` extension |
| Lookup/path functions | `t/getpath.t`, `t/setpath.t`, `t/delpaths.t`, `t/path.t` | Inventory supported arguments and errors, including existing v2 extensions |

A scoped grammar difference remains: jq 1.7 accepts `.obj .name` with a
space before a named dotted suffix, but the current JQ::Lite path normalizer
does not. This spacing was not established as a v2 practical baseline here;
do not change its recognition just to satisfy a broad jq-syntax test.

The tests above establish *v2 usage*, not blanket jq 1.7 conformance. v3 has
dedicated coverage under `t/v3_*.t` for quoted/numeric/computed selectors,
whitespace, strict/optional access, update and try/recurse; rare deep-selector
files are **review targets**, not grounds for extending the supported subset.

## Shared path-array index normalization (next checkpoint)

Read and write path-array traversals use identical scalar/index conversion:
negative indices add the current array length, numeric strings and JSON
booleans retain the v2 extension, and invalid/negative-out-of-range indices
return no usable index. The prior `_normalize_array_index_for_get` and
`_normalize_array_index_for_set` contained the same implementation. The
get helper now delegates to the set helper; read-side bounds checks still
produce JSON null beyond the array, while write-side `setpath` may grow the
array with null padding. No public parser or syntax changes are made.

Targeted v2-behavior regression tests cover both internal call sites and
public `getpath` / `setpath`. Additional jq 1.7 differential fixtures
compare ordinary positive/negative/out-of-range indices and ordered JSON
results; boolean path elements are marked **known differences**, because
jq 1.7 reports a runtime error but v2 JQ::Lite treats them as indices.
This checkpoint removes 154 implementation bytes from `Util/Paths.pm`;
measured tracked `lib/**/*.pm` source totals 316,383 bytes
(22 modules) from v3 base `faf56b7a` at 316,537 bytes.
This is a limited maintenance refactor; #625 remains open.

## Regex builtin dispatcher maintenance checkpoint

The practical v2 baseline also includes literal `test(pattern; flags)` and
`match(pattern; flags)` filters (`t/test_function.t`, `t/match.t`).
Previously, the two branches in `Filters.pm` duplicated argument splitting
and decoding. A single explicitly whitelisted dispatcher now shares only
that parsing; `_apply_test` and `_apply_match` still run separately with
their original return types, source-order behavior, regular-expression
validation and function-specific error text. No general regex argument
expressions or new syntax are introduced. Targeted Perl regression cases
cover case-sensitive/insensitive behavior, ordered streams, the retained
v2 array-mapping extension, and invalid-pattern/flag errors. Six jq 1.7
differential cases check the supported scalar/stream subset and error
categories. This reduces the `Filters.pm` implementation by 298 bytes
compared with `5b30e5cc`; tracked `lib/**/*.pm` totals
316,085 bytes (22 modules), excluding tests/docs.

## Common path enumeration dispatcher (maintenance checkpoint)

The existing v2 `paths`, `paths()`, and `paths(scalars)` branches in
`Filters.pm` previously duplicated the output-stream collection loop. The
shared dispatcher only chooses the existing `_apply_paths` or
`_apply_scalar_paths` implementation once per filter; it does not change
accepted syntax, object key traversal, path order, empty output, or the
specific leaf predicate. Focused Perl regressions cover all three spellings,
whitespace, arrays, objects, empty/scalar roots, null, booleans, and pipelines.

Six jq 1.7 differential fixtures gate the ordinary supported subset, with one
**known-difference** fixture tracking the retained v2 behavior of including
null leaves in `paths(scalars)` (jq 1.7 excludes null). The extra `paths()`
spelling also remains a v2 extension: jq 1.7 rejects it at parse time; it is
covered by Perl regressions, not falsely marked jq-compatible.

This reduces `Filters.pm` by 40 tracked bytes relative to commit
`235f0e24` and changes the `lib/**/*.pm` aggregate from 316,085
to 316,045 bytes (22 modules). Tests and documentation are
not included in that measurement. Issue #625 remains open.

## Shared scalar/leaf path collector (maintenance checkpoint)

The pre-existing `_collect_scalar_paths` and `_collect_leaf_paths` each
recursed through sorted object keys and array indices, collecting the same
non-container leaf paths. The scalar check already delegates to the leaf
predicate. The scalar collector now delegates container traversal to the
existing leaf collector, retaining its historical no-output behavior when
called directly on a scalar. Public `paths(scalars)` still emits a stream of
paths while the v2 `leaf_paths` extension returns a single array of paths;
their root-scalar behavior therefore remains different by design.

Focused Perl regressions cover nested arrays and objects, empty containers,
null/boolean leaves, traversal order, both public output shapes, and direct
internal scalar-root behavior. Five jq 1.7 compatible fixtures cover the
ordinary `paths(scalars)` subset; one non-gating known-difference fixture
records v2 null-leaf inclusion (jq 1.7 excludes null). No new jq syntax or
CPAN dependencies are introduced.

This change removes 609 implementation bytes from `Util/Paths.pm`.
Tracked `lib/**/*.pm` total decreases from 316,045 to
315,436 bytes across 22 modules relative to
`2e6cd497`. Tests/documentation are excluded; #625 stays open.

## MANIFEST distribution coverage (maintenance checkpoint)

After PR #755 restored missing test/data/doc registrations, the Git tree and
`MANIFEST.SKIP` rules were compared against `MANIFEST`: the tracked source
files have no unlisted, non-excluded entries at this checkpoint.

The new `t/manifest_coverage.t` verifies that registered files exist, entries
are unique, and (when running from a Git checkout) every tracked file not
excluded by `MANIFEST.SKIP` is in `MANIFEST`. It uses only Perl core modules
and `git ls-files` in developer/CI checkouts. Release-source test runs without
Git metadata still check for duplicates and missing registered files; the
Git-specific assertion is skipped. The test is itself in `MANIFEST`.

This prevents silent omission of newly added regression tests from source
distributions, without changing the v2 practical feature set, jq grammar,
Perl 5.14 requirement or existing runtime code size. #625 remains open.

## Shared range argument scanner (maintenance checkpoint)

`Util/Transform.pm::_parse_range_arguments` formerly kept an independent
character-by-character semicolon/quote scanner. It now uses the existing
balanced `_split_semicolon_arguments` lexer, while preserving its previous
range-specific empty-slot omission, JSON literal decoding and first-value
selection for ordinary arguments. Array/iterator and range generator logic
remain unchanged, including zero-step empty streams and error categories.

Perl regression tests cover ordinary one-, two-, three-bound ranges, ordered
pipeline/comma streams, blank slots, quoted or escaped semicolons, string-bound
errors and the original argument fallback. Nine jq 1.7 differential cases
check the supported public range subset and runtime-error categories; they do
not establish support for arbitrary nested/computed argument expressions.
The latter were not part of the v2 practical subset being preserved.

The independent range scanner cleanup removes 785 implementation bytes
from `Util/Transform.pm`. Tracked `lib/**/*.pm` size is
315,436 → 314,651 bytes (22 modules) relative to
`e98058a7`, excluding tests and docs. The new test is registered in
`MANIFEST`, maintaining distribution coverage. #625 remains open.

## Shared slice bound validation (maintenance checkpoint)

Both the existing v2 `slice(start,length)` extension and jq-style
`[start:end]` selectors rejected text and other nonnumeric bounds via
duplicated validation in `Util/Transform.pm`. A single
`_slice_numeric_bound` helper now preserves these checks without changing
length-versus-exclusive-end semantics. In particular, a beyond-end v2
`slice()` start still yields an empty array before examining its length,
while bracket slicing validates its end first; invalid bracket ends retain
the legacy `slice(): length must be numeric` diagnostic. Scalar and null
inputs still short-circuit before validating bounds.

Focused Perl regression tests cover negative and omitted bounds, empty
results, scalar passthrough, invalid numeric-string bounds, and validation
precedence. Eight jq 1.7 differential cases check the supported bracket
slice subset and runtime error categories. They do not relabel v2's
`slice(start,length)` extension as jq-compatible. The test is registered in
`MANIFEST`. Implementation source shrinks by 70 bytes (tracked
`lib/**/*.pm`: 314,651 → 314,581 across 22 modules) versus
`7fb6483b`, excluding tests/docs. #625 remains open.

## Shared literal path validation (maintenance checkpoint)

The JSON-literal path operand branches of `getpath` and `setpath` both
recognized a single validated array path or an array of validated array paths.
`_validate_literal_paths` now centralizes only that identical recognition and
reuses the existing segment validator with the original function-specific error
labels. Empty `[]` still denotes **one root path**, not an empty output stream.
The separate evaluation and filtering of dynamically produced path values is
unchanged: these have different v2 behaviors and are not folded together.

New Perl regressions cover nested/single/multiple/root paths, negative array
indices, missing null values, and invalid scalar/null/container path elements.
Nine jq 1.7 differential cases cover the standard literal single-path subset
and error classes. The v2 array-of-paths extension is tested as JQ::Lite
behavior only and is not labelled jq-compatible. The added regression file is
registered in `MANIFEST`; Perl >= 5.14 and zero non-core dependencies remain.

This reduces `Util/Paths.pm` by 253 implementation bytes, with tracked
`lib/**/*.pm` decreasing 314,581 → 314,328 bytes across 22 modules
relative to `1e1ec3b0`. Tests/docs excluded; #625 remains open.

## Shared top-level delimiter scanner (maintenance checkpoint)

`Util/Parsing.pm` previously had literally identical quoted-string and
nested-bracket scanners for top-level semicolons and commas, except for the
separator character. One `_split_top_level_delimiter` now implements both;
`_split_top_level_semicolons` and `_split_top_level_commas` retain their
names, list return behavior, and error/empty-input behavior. The scanner
preserves the existing behavior for empty fields, escaped quotes, mismatched
closing delimiters, and unmatched opening delimiters. Other operator and
pipe scanners are deliberately unchanged.

The Perl regressions cover direct splitting and common v2 comma, iterator,
reduce and foreach filters, including null values versus a genuinely empty
stream and per-input output ordering. Seven jq 1.7 differential cases cover
supported comma/array/iterator/reduce/foreach output order. The v2-only
foreach behavior for an empty extraction is protected in Perl tests and
not labelled jq-compatible. No grammar expansion or new CPAN dependency.

Implementation bytes in `Util/Parsing.pm` decrease by 1118; tracked
`lib/**/*.pm` totals fall from 314,328 to 313,210 bytes
across 22 modules relative to `d5ccf6c9`, excluding tests/docs.
The new test is registered in `MANIFEST`; Issue #625 remains open.

## Shared scoped numeric array access (maintenance checkpoint)

The scoped literal-path visitor previously duplicated negative-index
normalization and array bounds checks for ordinary `[N]` and computed numeric
selectors such as `[.idx]`. The small `_v3_array_index_or_null` helper now
owns only the confirmed-array read: negative indexes count from the end, and
out-of-bounds indexes or explicit null slots yield a single null. Existing
computed-selector `int()` conversion remains at its call site. Field, optional,
wrong-type error and null-target decisions are unchanged. Identical null-target
cases for computed string and numeric keys are consolidated.

Perl regressions cover both access paths, negative/out-of-bounds/null slots,
invalid scalar index types, optional access and the null-versus-empty-stream
distinction. Nine jq 1.7 differential cases cover the supported practical
subset and error class. The new regression test is registered in `MANIFEST`.

This saves 106 source bytes in `Util/Transform.pm` (tracked `lib/**/*.pm`:
313,210 → 313,104 bytes across 22 modules relative to `5507198c`),
excluding tests/docs. No grammar or dependency expansion. #625 remains open.

## Shared standalone/path iterator expansion (maintenance checkpoint)

Standalone ` .[] ` / ` .[]? ` handling in `Filters.pm` and the final
iterator step in `_traverse_v3_field_iterator` both expanded array elements,
object values and raised the same structured scalar error. The small
`_v3_iterate_values` helper consolidates only that shared expansion. Both
callers retain their own input-stream iteration and pipeline ordering, and
path-local optional markers still suppress only their own invalid iteration.
The object's existing `values %hash` iteration order is unchanged.

Focused Perl regressions check emitted null and boolean members versus empty
streams, standalone and nested paths, arrays/objects, strict scalar errors,
optional suppression, optional field suffixes and comma branches. Eleven jq
1.7 differential cases cover the same supported scope and error categories.
No new syntax or dependency is introduced and the added test is in `MANIFEST`.

Tracked `lib/**/*.pm` implementation size decreases by 820 bytes,
313,104 → 312,284 across 22 modules versus `d061cf7b`,
excluding tests/docs. Issue #625 remains open.

## Shared top-level colon scan (maintenance checkpoint)

The top-level colon splitter had another standalone quote/bracket scanner. For
a literal `:` delimiter, its behavior matched the existing one-character
`_split_top_level_operator` scanner: it returns only the first top-level
pair, protects quoted and nested colons, and stops with no result on an invalid
closing bracket before a split. The colon helper now forwards to the existing
scanner with `':'`; arithmetic `+`/`-` exponent/update exclusions in the
operator helper do not apply to `:`. The helper keeps its existing name and
returns the same empty/list-shaped output without changing parsing grammar.

Perl tests protect direct splitting (quoted/escaped punctuation, nesting,
empty sides, malformed brackets) and v2 object constructors with nested,
quoted, missing-null and streaming fields. Six jq 1.7 compatible fixtures
cover the object-constructor subset and field/output ordering. Added regression
tests are in `MANIFEST` and no dependency or feature coverage is added.

The `Util/Parsing.pm` source decreases by 1044 bytes; tracked `lib/**/*.pm`
decreases 312,284 → 311,240 bytes across 22 modules, relative
to `12d5ca24`. Tests/docs are excluded. Issue #625 remains open.

## Shared test/match regex validation (maintenance checkpoint)

The existing `test()` and `match()` filter implementations compiled the same
literal pattern and flags using `_build_regex`, trimmed identical trailing
newlines from compile errors, and raised their function-specific messages.
A small private `_apply_regex_filter` now shares only compilation, validation
and dispatch. `_test_against_regex` and `_match_against_regex` keep their
separate boolean and match-object/offset/capture semantics, including v2 array
mapping and null behavior. Supported i/m/s/x flags, rejection of unsafe
embedded Perl code, and all existing regular-expression error text are
preserved; the regex compiler is unchanged.

Perl regressions exercise both result shapes, flags, array/null cases,
invalid patterns and flags. Four jq 1.7 differential cases cover case-insensitive tests,
no-capture match results and invalid flag error categories. This maintenance
refactor does not claim full jq parity for `m` regex flag semantics or
capture-group metadata; those remain separate compatibility audit items. No new syntax,
CPAN dependency or public API is introduced, and the new test is in MANIFEST.

Implementation source in `Util/Transform.pm` decreases by 63 bytes;
tracked `lib/**/*.pm` totals 311177 bytes (22 modules), versus
`c593f71b`, excluding tests/docs. Issue #625 stays open.

## Shared CSV/TSV row and field formatting (maintenance checkpoint)

The existing `@csv` and `@tsv` row serializers duplicated array mapping,
joining and scalar dispatch. Their field formatters also duplicated null,
boolean, structured JSON and reference stringification. Two small shared
helpers now perform that common work, while retaining separate quoted CSV
versus escaped TSV output, the pre-stringification numeric SV flag check for
CSV, scalar fields, and the v2 extension for nested containers. Array row
ordering and empty rows are unchanged; structured values still use the
existing UTF-8 JSON text conversion.

Focused Perl regressions check numeric values versus numeric-looking strings,
quoted and escaped punctuation, null/boolean values, structured fields, scalar
fields, empty arrays and multi-row output ordering. Six jq 1.7 differential
fixtures cover compatible ordinary row cases and output order; nested
container/scalar-root extensions are tested as v2 behavior only, not mislabeled
as jq-compatible. No new syntax, dependencies or public API changes; the
test is in `MANIFEST`.

Tracked `lib/**/*.pm` implementation decreases by 462 bytes,
311,177 → 310715 bytes (22 modules), versus `42e45cc2`,
excluding tests/docs. Issue #625 remains open.

## Shared Base64 input conversion (maintenance checkpoint)

The existing v2 `@base64` and `@base64d` implementations duplicated
null/boolean/string/structured-value conversion into text. A small private
`_base64_input_text` helper now shares that conversion while preserving
encoding's literal `null` text versus decoding's empty-null input. The
decoder's numeric-scalar validation remains **at the original call site
before coercion**, so Perl scalar flags and their error messages are not
silently changed. MIME::Base64 encode/decode, strict alphabet/padding and
round-trip validation, and final UTF-8 decoding are unchanged.

Perl regressions cover scalar and structured inputs, null, booleans,
numeric-looking strings, nested JSON, whitespace, decoding errors and ordered
array streams. Nine jq 1.7 compatible differential fixtures cover ordinary
encoding/decoding values and stream order. Non-jq decoding of null or
non-string structured inputs remains protected only as historical JQ::Lite
behavior, not incorrectly labelled jq-compatible. No grammar change,
dependency, public API expansion or stable/main edits.

Tracked `lib/**/*.pm` source decreases by 215 bytes,
310,715 → 310500 bytes across 22 modules (versus `7915321c`).
Tests/docs excluded. Issue #625 remains open.

## Shared min_by/max_by dispatch (maintenance checkpoint)

The existing `max_by(path)` and `min_by(path)` branches in `Filters.pm`
performed identical argument normalization, array-only mapping, non-array
passthrough and stream assignment. A single narrowly matched dispatcher
now selects only the comparison mode (`max` or `min`) and calls the
unchanged `_extreme_by` implementation. Its first-item tie behavior,
null result on empty arrays or missing keys, value comparison and field
projection are unchanged. The accepted grammar remains exactly
`max_by(<nonempty argument>)` or `min_by(<nonempty argument>)`.

Focused Perl regressions protect projected numeric and string keys,
whole-value comparisons, empty arrays, absent paths, ties, scalars,
nulls and multiple array streams. Eight jq 1.7 compatible differential
fixtures cover supported ordinary extrema and ordered results.
Non-array passthrough and first-item tie behavior are explicitly protected
as existing JQ::Lite behavior rather than advertised as jq guarantees.
No new dependencies, public API or syntax.

Tracked `lib/**/*.pm` implementation source decreases by 355 bytes,
310,500 → 310145 bytes (22 modules), against `12b281f1`.
Tests/docs excluded. Issue #625 remains open.

## Review order and compatibility boundaries

1. Keep common v2 field, index, slice, iterator, comma and constructor cases,
   checking ordered outputs plus null/empty/error distinctions against jq 1.7.
2. Compare the v2 and v3 implementations of those cases before removing
   special-case dispatch. Prefer shared, small guards with a single full
   validation step; do not loosen parser recognition.
3. Assess the additional v3-only numeric/computed-selector and try/recurse
   tests by frequency, maintenance cost and v2 compatibility. Do not delete
   behavior or add arbitrary depth support without separate evidence.
4. Track deliberate differences (notably `slice(start,length)`, array
   projection and first-result extension behavior) in the semantic-differences
   documentation rather than labelling them jq-compatible by assumption.
5. Keep the full Perl >= 5.14 matrix and jq 1.7 ordered-output/error-category
   differential CI green on the final HEAD before any merge.

This checkpoint does not close #625: individual behavioral comparison,
potential simplification of the three largest modules, and migration
documentation remain open.
