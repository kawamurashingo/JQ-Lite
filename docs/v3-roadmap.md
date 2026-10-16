# JQ::Lite 3.0 roadmap

## Purpose

JQ::Lite 3.0 is the compatibility boundary for correcting selected runtime
semantics that cannot change safely in the stable 2.x series. Its goal is not
to implement every jq feature. It is to make the supported language more
predictable, move deliberately toward jq 1.7 where that benefits portable
filters, and preserve the lightweight, pure-Perl deployment model.

The current behaviour and the decision status of every known difference are
recorded in the [2.x semantic differences inventory](jq-semantics-differences.md).
That inventory is the source of truth for scope: this roadmap does not silently
turn an `undecided` item into a commitment.

## Practical v2 baseline and size policy (2026-10-13)

Use v2's practical feature set as the baseline. Prioritize compatibility
within that subset, smaller implementation size, and simple maintenance.
New syntax coverage is not a release goal. Rare deeply nested computed
selectors and try/recurse combinations are not required release criteria;
review existing support before removing it rather than expanding it further.
Keep Perl 5.14 support, existing dependencies, and stable 2.x unchanged.

The public API remains `new` and `run_query`. A compiled-query API (#627)
is deferred beyond the current 3.0 scope and is not a release requirement.
Semantic changes are developed on `v3-dev`; `main` remains the stable 2.x
baseline. Freeze the practical subset, fix its selected semantic differences,
verify the existing contracts, and document migration before releasing 3.0.

An initial size measurement of tracked `lib/**/*.pm` files at stable/main
`6880c30` and v3-dev `40c05db` gives:

| Source | Modules | Lines | Bytes |
| --- | ---: | ---: | ---: |
| Stable/main (v2 baseline) | 22 | 8,839 | 242,573 |
| v3-dev before dispatch cleanup | 22 | 10,560 | 326,242 |
| v3-dev after dispatch cleanup | 22 | 10,451 | 321,629 |

The pre-cleanup implementation is 34.5% larger in bytes than stable/main.
These counts include comments and whitespace; they do not measure installed
archive size, execution speed, or feature usage. Tests and documentation are
excluded. A complete practical-feature inventory remains pending in #625.

The first cleanup combines repeated path-dispatch guards in `Filters.pm`.
It preserves their syntax triggers and full-parser validation, removes three
redundant subset guards, and attempts that parser at most once per dispatch.
It removes 109 lines / 4,613 bytes without removing supported expressions.
Existing regression and jq 1.7 differential fixtures remain the behavioral
checks. Further cleanup should focus on shared handling for ordinary lookup,
indexing, iteration and optional access before specialized syntax support.

A maintenance-only iterator pass shares the non-path suffix eligibility
check between standalone filters and comma branches. Dotted paths,
comparisons, alternatives and `try` retain their existing guards;
`keys[]`, `split(",")[]`, comma-local suffixes and `null // []` remain
regression-checked. The practical path/iterator inventory and release
audit remain open under #625.

## Compatibility policy

- The 2.x CLI and Library API contracts remain unchanged. Semantic corrections
  listed here are 3.0 changes and must not be backported to 2.x.
- The documented public Library API (`new` and `run_query`) remains supported.
  Version 3 changes query-language semantics, not the shape of those entry
  points.
- jq 1.7 is the comparison baseline for changes marked **change in v3**.
  Exact jq diagnostic text and unsupported jq facilities are not compatibility
  promises.
- Existing JQ::Lite extensions remain available unless a separate proposal
  documents their replacement and migration path.
- Every intentional incompatibility requires focused tests for both the new
  result and the migration guidance described below.

## Committed semantic changes

The following inventory items are approved for the 3.0 compatibility break.
They should be implemented as independently reviewable changes rather than as
one parser rewrite.

### Containment

- Make `contains(value)` use jq-style recursive containment for arrays and
  objects.
- Keep 2.x `contains_subset(value)` unchanged until its **undecided** status is
  resolved. It must not be presented as an exact alias for the new `contains`.

The 3.x literal-argument `contains` correction is implemented. Arrays and
objects use recursive containment; repeated array needles may reuse one input
match. Strings use substring containment, while numbers, booleans and null use
JSON-type-sensitive equality. Root type mismatches, including true versus
false, raise structured evaluation errors; mismatched nested values simply do not match. This includes the normal
`select(contains(...))` and `map(contains(...))` forms. Arbitrary filter-valued
arguments are outside this scoped correction.

Migration examples: `[1,2,3] | contains([1,3])` now returns true; nested object
needles may match a larger nested object. For the v2 array-element membership
meaning, use `index(value) != null`; for object key existence, use `has(key)`.
Callers needing exact nested object equality should compare the projected
value explicitly in their application. `contains_subset`, `inside`, and the
infix `contains` extension retain their v2 meanings. In particular,
`contains_subset` still counts duplicate needles and coerces scalar strings;
`inside` is not advertised as the inverse of 3.x `contains`.

### Search positions

`index(value)` and `rindex(value)` share first/last search while retaining
the practical v2 array-element and scalar-coercion policies. For string
haystacks, an empty string needle now emits one JSON null in both functions,
matching jq 1.7; it no longer yields zero or the string length. Unicode
substring positions now count UTF-8 bytes, also matching jq 1.7; for example,
`"\u65e5\u672c\u8a9e\u65e5\u672c" | index("\u672c")` returns 3 rather than 1.
ASCII offsets, overlapping matches, array null/false values and empty
upstream streams retain their existing order and cardinality.

Migration: explicitly return `0` or `length` when an empty needle is intended
to mean the first or final string boundary; convert byte offsets in the
application if a character position is required.

`indices(value)` applies the same jq 1.7 string rules: an empty string needle
emits one empty array, and substring positions count UTF-8 bytes in ascending
order, including overlapping matches. With a string needle, a null input emits
one JSON null rather than an empty array; missing fields keep that null, while
an empty upstream stream still emits nothing. Array null/false matches retain
their positions.
Migration: generate a character-boundary list explicitly in the application
when the v2 `indices("")` extension was intended; use `indices(...) | . // []`
when a null input should produce an empty result array.

Array needles still mean exact-element lookup, scalar array equality still
permits numeric-string coercion, and invalid/null-needle fallbacks retain their
v2 meanings. Those
are documented differences, not full jq search/error compatibility claims;
this correction adds no argument grammar, function, public API or dependency.

The CLI decodes UTF-8 raw text before JSON wrapping, for both per-line `-R`
and slurped `-Rs` input. Search offsets therefore match decoded JSON inputs
instead of double-counting UTF-8 bytes. Raw string output (`-r`) writes UTF-8
bytes as well. Migration: supply UTF-8 text to these raw modes; line splitting
and the existing CLI exit/error categories are retained. `--arg` and
`--rawfile` use the same text decoder before binding string variables, keeping
their Unicode raw output and search offsets consistent. Unicode line order,
multibyte needles and Latin-1 characters are covered by CLI regression and
raw-mode jq 1.7 differential fixtures. This uses the existing core Encode
dependency.

Valid UTF-8 text returned by `@base64d`, `tojson` and structured `tostring`
is a Perl character string, matching ordinary decoded JSON strings.
`fromjson` encodes character text before feeding the existing UTF-8 JSON
decoder. This keeps Unicode search, raw output and format/parse round trips
consistent; existing base64 validity checks and malformed-fromjson fallbacks
are retained. Migration: explicitly UTF-8-encode Library string results at a
byte-oriented output boundary; use `MIME::Base64::decode_base64` directly when
binary bytes, rather than UTF-8 text, are required.

The retained structured-member CSV/TSV extensions share this character-text
conversion; their v2 acceptance policy is unchanged.

### Null, fallback, and paths

Ordinary unquoted field paths retain their leading dot and are evaluated as
paths before builtin dispatch. `.type`, `.length`, `.empty`, `.null` and other
legal names therefore read fields rather than invoking functions/literals.
Nested named paths use the same existing traversal. Missing/null object reads
still emit null, while truly empty upstream input remains empty. Existing
array-projection and invalid-target policies are preserved; this change does
not promise full jq path error semantics.

Migration: use bare `type`, `length` or `empty` to invoke the builtin; use
`.type`, `.length` or `.empty` to read a field. For example,
`{"type":"vm","length":99,"empty":null}` yields `"vm"`, `99` and JSON null
for those field paths; `.empty | type` emits `"null"`, while `empty | type`
emits nothing. To deliberately construct that former empty-stream fallback,
use `null | type`. No additional function or public API is introduced.

Within supported array/object constructors, a filter that emits nothing does
not become JSON null: `[empty | type]` yields `[]`, and
`{x: (empty | type)}` emits no object. Explicit `null | type` still yields
`"null"`. Object fields continue to use the first value when a filter emits
multiple values; this is not a claim of full jq constructor stream parity.

For practical literal/current-value/named-field alternatives, a trailing empty
array remains the right operand: `null // []` and `false // []` emit one empty
array, while zero and empty strings remain valid left values. Comma branches
retain their order. To iterate that result, use `(null // [])[]`, which emits
nothing; a strict iterator on a boolean still raises a runtime error.
For a function result, apply the fallback in a pipeline, for example
`indices("an") | . // []`. Existing first-result alternative evaluation is
retained; this correction does not promise arbitrary filter-operand or full
streaming parity and introduces no argument grammar or dependency.

- Treat both `false` and `null` as absent for the `//` alternative operator.
- Emit `null` for a missing object field and for continued traversal through a
  missing field.
- Reject a numeric index applied to an object instead of returning `null`.

The direct-path missing-field correction is implemented by the scoped v3
path change: `.missing` and `.missing.value` yield one JSON null instead
of an empty output stream. This applies to straightforward dot-separated,
unquoted field paths only; quoted/optional paths and internal traversal
consumers keep their earlier behavior pending separate audits. A genuine
empty iterator (`.[]` on `[]`) still produces no output.
Numeric indices applied to objects now produce a structured evaluation
error instead of silently yielding null, including the direct `.[5]` form and
nested `.a[5]` where `a` holds an object. Numeric indexing into arrays
continues to work. This change is limited to numeric object indices; the
broader invalid-path policy remains a separate work item.

Numeric indexing on JSON null, null-valued array elements, and array
out-of-bounds slots now produces one JSON null rather than an empty result
stream in 3.x. This includes direct `null | .[5]`, nested
`{"a":null} | .a[5]`, and `[10] | .[5]` queries. A true empty iterator
(`[] | .[]`) continues to produce no output. The change is limited to
numeric-index query paths; it does not imply a decision on other invalid
path types or internal helper traversal.

The error policy for other invalid paths remains undecided and is not implied
by these changes.

### Arithmetic and comparison

- Reject boolean operands in arithmetic expressions.
- Keep JSON scalar types distinct for equality, so a numeric-looking string is
  not equal to a number.
- Compare arrays lexicographically using jq-compatible value ordering.

The practical v3 comparison correction is implemented for JSON values, literal
operands, and simple named-field `select` predicates. Equality requires matching
JSON types and recursively equal contents. Ordering follows
`null < false < true < numbers < strings < arrays < objects`; arrays compare
lexicographically, and objects compare sorted key sets before their values.
All six comparison operators share the existing internal `JQ::Lite::Value`
implementation. `type` uses that same JSON classifier. JSON array/object
literals are decoded before expression/path handling, preserving empty arrays
and operator characters inside literal strings.

Migration examples: `"10" == 10` now returns false, `[1,2] < [1,3]` returns
true, and `select(.age == "30")` no longer selects a numeric age of 30.
Use a numeric literal when comparing numeric data, or normalize explicitly
before comparison, e.g. `"10" | tonumber | . == 10` and
`10 | tostring | . == "10"`. Existing convenience-function comparisons are
not silently changed by this operator correction.

`type` now preserves empty input streams: `empty | type` emits no output,
while `null | type` emits one `"null"` string. All six comparison operators
also preserve zero-output operands: `empty == null` and `null == empty` emit
nothing, while `null == null` and `{} | .missing == null` emit true.
Operands retain the existing value shortcut for literals and plain named
fields. Optional/quoted/index/iterator paths use the existing query evaluator,
so a missing object field remains JSON null rather than an empty stream.
Empty iterators and filtered-out values remain empty. Comparisons inside
supported constructors use the same comparison evaluator.
An unparenthesized right iterator keeps its operand meaning:
`{"arr":[1,2]} | 1 == .arr[]` yields true, false. Its trailing `[]` is
not applied to the comparison's booleans; `(1 == 1)[]` still raises the
existing iterator type error.

Comparisons evaluate the right operand first; an empty right operand skips
the left operand (`(1 / 0) == empty` emits nothing), while a right-operand
error still propagates (`empty == (1 / 0)` fails). For supported finite
operand outputs, result order follows the right operand before the left,
e.g. `(1,3) < (2,4)` yields true, false, true, true. This uses the existing
eager query evaluation and does not promise lazy delivery of partial results
before an operand error or full jq expression grammar.

Migration: use an explicit null or an alternative such as
`(empty // null) == null` when a null fallback is intended. Comparisons no
longer insert null for empty operands. Existing array-projection and
invalid-target path policies remain in place. No variable arithmetic, new
syntax, function, public API, or dependency is introduced.

Numeric-looking strings are now rejected by numeric arithmetic in the 3.x
developer-release series; callers that intend conversion should use
`tonumber()` or `to_number()` explicitly. Regex scalar coercion remains
undecided and is not changed by the arithmetic work.

The existing simple named-field arithmetic predicates now use that same
typed evaluator and JSON comparator. They no longer coerce numeric strings
or turn division/modulo errors into false. Supported constructors dispatch
`select(...)` as a filter, preserving its selected input, zero-output and
error behavior. See the [practical arithmetic contract](v3-arithmetic.md)
for the type table, 404-case audit, retained nonnumeric jq overload
differences and executable v2 migration examples. Predicate spelling and
the separate plain/compound-assignment scope are unchanged.

### Assignment and update

- Make update assignment (`|=`) emit the updated root value.
- Allow update assignment to create a missing target using the same input
  semantics as jq.

The supported `path |= filter` form now evaluates the right-hand filter against
the **old target value** (JSON null for missing targets), writes that value to
the target, and emits the entire updated root. The first implementation is
intentionally restricted to simple dotted object keys and nonnegative literal
array indices, including nested combinations. A null root can grow into the
required object or array. Invalid intermediate container types raise structured
runtime errors rather than silently dropping the update.

The update operator now also supports jq 1.7's zero-result deletion: when
the RHS produces no values (such as `empty` or `select(false)`), it deletes
the selected object key or splices out the selected array element, then emits
the updated root. Missing targets and out-of-range indices are no-ops; no
intermediate objects or arrays are created solely to delete a path, and
`null | .a |= empty` continues to produce `null`. This differs from
`path |= null`, which **retains** the field or array slot with JSON null.

When the RHS produces multiple values, update assignment now takes the **first
emitted result** and returns one updated root, matching jq 1.7 for the supported
simple-path expressions. JSON `null` and `false` are valid first results and
are not confused with an empty result stream. For example, `.a |= (10,20)`
updates `a` to `10`; `.a |= (empty,5)` uses `5`; only an entirely empty
RHS deletes the path.

Update assignment now short-circuits **top-level comma alternatives**
in its RHS, including nested parenthesized groups: once an alternative
produces a value, subsequent alternatives are not evaluated. For example,
`.a |= (7, 1 / 0)` now updates `a` to `7` without evaluating the unused
division-by-zero expression; `.a |= (empty, 7, 1 / 0)` also selects `7`,
and `.a |= (empty, 1 / 0)` still evaluates and raises the error. JSON
`null`, `false`, and numeric `0` are values, not empty result streams.
This short-circuit applies to updates using literal fields and all supported
array/object iterator paths.

The update RHS now also walks **pipeline stages** in first-result order.
For example, `.a |= ((1,2) | . + 1)` updates `a` to `2`,
and `.a |= ((1,0) | (1 / .))` uses the result of the first upstream value
without evaluating the division by zero from the later input. If the first
upstream input produces no downstream output, evaluation continues with the
next input (`.a |= ((1,2) | select(. > 1))` updates `a` to `2`).
If *all* pipeline paths produce no value, the selected assignment path is
deleted as before. These semantics also apply to nested array and object
update paths, and do not change the public `run_query` stream results.

The update RHS visitor now also evaluates the leaf generator `recurse`
(or `recurse(filter)`) **on demand**. jq emits each current value before
attempting to traverse its descendants, and `|=` needs only the first
value that survives the rest of the RHS pipeline. For example,
`.a |= recurse(. + 1)` returns the old value immediately rather than
evaluating unbounded recursion, and
`.a |= (recurse(. + 1) | select(. > 3))` starts at `1` and stops at
the first selected descendant, `4`. Errors in unused child expansions
are not triggered, while errors from children required to find a matching
result still propagate. This behavior is shared by array/object update
iterators, including nested `[][]` paths. Normal `run_query` still
emits its complete finite recurse stream.

The update RHS now also generates `range(...)` values **on demand**,
using the same numeric argument parsing, endpoint exclusion, and step
semantics as the regular range filter. For example,
`.a |= range(1000000000)` immediately uses `0` instead of materializing
a billion values, while `.a |= (range(1000000000) | select(. > 3))`
visits only the first five integers before selecting `4`. Positive and
negative steps, zero-step and empty ranges, comma alternatives, and pipeline
filtering all retain their established behavior. In particular, a range
that emits no values causes an update assignment to delete the selected
path; a later comma alternative can still supply a replacement instead.
The ordinary `range` query continues to emit its complete finite stream.

Custom `recurse(filter)` **child-filter streams** are now also consumed
incrementally for `|=`, rather than evaluating every child before traversing
any descendant. The first child is visited depth-first, and an accepted
downstream result stops later child branches. For example,
`.a |= (recurse((. + 1, 1 / 0)) | select(. > 1))` uses `2`
without evaluating the unused division-by-zero branch, and a later
match such as `select(. > 3)` visits the chain `1, 2, 3, 4`.
An error from a branch that **must** be evaluated still propagates
(`recurse((empty, 1 / 0)) | select(. > 1)`).
The default `recurse` traversal remains iterative; custom child filters
now use recursive visitor calls to maintain depth-first streaming, so very
deeply nested custom recursion may need further stack-depth work.
Ordinary `run_query` and its finite `recurse(filter)` streams are unchanged.

The ordinary `recurse(.[])` filter now also respects jq 1.7's **strict
iterator type errors**: a scalar or JSON null root/descendant causes a
structured evaluation error rather than silently terminating the recursion.
In contrast, plain `recurse` still terminates safely at all scalar/null
leaves, and optional child navigation such as `recurse(.children[]?)`
remains non-throwing. For example, `[1,[2]] | recurse(.[])` fails
when visiting `1`, whereas `[[],{}] | recurse(.[])` succeeds.
The same scoped validation applies to `recurse(.[] | ...)` when the
explicit iterator is the first child-filter stage.

The ordinary, **standalone `.[]` filter** now enforces jq 1.7's
container-only iteration as well: arrays and objects yield their members,
while `null`, booleans, numbers, and strings raise a structured
evaluation error instead of producing an empty stream or iterating over
the characters of a string. For example, `"abc" | .[]` and
`1 | .[]` are runtime errors; `[1,2] | .[]` emits `1` and `2`.
The check also applies when `.[]` receives scalar values from a preceding
pipeline stage, but does not run if an earlier stage emitted no inputs.
Existing object traversal order is intentionally unchanged; JSON object
insertion-order parity remains a separate concern.

The **optional standalone iterator `.[]?`** now matches jq 1.7 for the
audited container/scalar cases. Like `.[]`, it emits all members of arrays
and objects (including any null or false members), but it **silently drops
only non-container inputs** (null, booleans, numbers, strings) instead of
raising the strict iteration error. For example, `1 | .[]?` emits no
results whereas `1 | .[]` raises an error. `[1,null,[2]] | .[]? | .[]?`
emits `2`. Errors in other filters are not suppressed: `1 / 0 | .[]?`
still fails, and `[1] | .[]? | .[]` still errors.

Simple **literal named-field paths with `[]` and `[]?` at any
position** now evaluate each field lookup and iteration stage in jq 1.7
order. Field access on JSON null or a missing object key yields null, but
indexing a number, string, boolean or array with a field name raises a
structured evaluation error. Each strict `[]` raises a type-specific error
if that stage receives null or a scalar; each optional `[]?` drops only
that stage's non-container inputs. For example, `{} | .a[]` raises
`Cannot iterate over null`, whereas `{} | .a[]?` has no output.
However, `1 | .a[]?` fails with an **invalid field indexing** error,
because the optional iterator does not forgive a bad earlier lookup.

This now also covers intermediate iterators:
`{"items":[{"name":"A"}]} | .items[].name` yields `"A"`; `{"items":null} | .items[]?.name`
produces no results; and `{"items":[2]} | .items[]?.name` raises a
field-indexing error at `.name`. Multi-step iteration treats each suffix
independently. `{"items":[[1,2],null]} | .items[][]?` yields `1` and
`2`, while `.items[][]` fails at the strict second iterator.
`.items[]?.children[]?` likewise preserves the independent optional
choice at each stage. Empty intermediate streams never evaluate later
fields or iterators, and array/object members retain their original value
types, including JSON null and false.

**Literal signed numeric indices** (`[0]`, `[1]`, `[-1]`, etc.) are
now also supported as ordered steps **in these named-field paths when at
least one `[]` or `[]?` iterator occurs**. `{"items":[[{"name":"A"}]]}
| .items[0][].name` emits `"A"`, and
`{"items":[{"names":["A","B"]}]} | .items[].names[-1]` emits `"B"`.
Each numeric index reads an array element, including negative indexing
relative to its length; a missing/out-of-bounds slot or an index on JSON
null emits one null. An object, number, string, or boolean indexed by
a number raises a structured evaluation error. A later `[]?` can drop
an index's null result, but **cannot suppress an earlier invalid numeric
index**. Thus `{"items":null} | .items[0][]?` has no result, but
`{"items":3} | .items[0][]?` raises an error.

**Literal JSON-quoted field keys** are now supported within these ordered
iterator paths. Bracket notation `.["items"][].name`, a key containing a
literal period `.["a.b"][0][]`, and a quoted key after an iterator
`.items[].["full name"]` each evaluate in jq 1.7's field/index/iterator
order. A dot-quoted field such as `.items[]."full name"` is accepted as
well. Quoted keys are decoded as JSON strings: empty keys, periods, spaces,
brackets, arithmetic and assignment characters (including `|=`),
escaped quotes/backslashes, and Unicode escapes remain **literal key text**,
not path operators or separators. This also preserves error boundaries:
`.["items"][]?` can drop a null field, but it does not suppress a bad
field lookup, numeric index, or later field access. A **complete, recognized
quoted literal iterator path** bypasses the legacy expression/assignment
shortcut; arbitrary quoted expressions and standalone quoted key access
keep their previous processing.

The v3 evaluator now also supports **a simple computed root key**
`.[.key]` (including a literal dotted selector such as
`.[.config.selected]`). The selector field path is evaluated against
the **same current input** that is indexed. A resulting JSON string is
used as the exact object key, including unusual characters and numeric-
looking strings. A missing selected object field produces one null, but
a selector returning null, number, boolean, array, or object raises
a structured indexing error. For example,
`{"key":"a","a":7} | .[.key]` yields `7` while
`{"key":null} | .[.key]` fails. The computed output can feed audited
literal suffix stages such as `.[.key][]?`, `.[.key][0]`, or
`.[.key].child`. After a pipeline stage, e.g.
`.items[] | .[.field]`, each emitted object computes its own key.

A **simple computed selector `[.key]` may now appear after a literal
named or quoted field, numeric index, or iterator**, for example
`.obj[.key]`, `.items[0][.key]`, `.["obj"][.key]`, or
`.items[][.key]`. jq 1.7 evaluates the selector's field path against
the **original input to this filter**, not the intermediate object
being indexed. Thus `{"key":"a","obj":{"key":"b","a":7,"b":8}}
| .obj[.key]` selects `7`, even though the nested object's `key`
would have selected `8`. With `.items[][.key]`, every emitted item
is indexed by the same selector value from the original filter input.
A **new pipeline filter** establishes a new context, so
`.items[] | .obj[.key]` computes each item-specific key.
Multiple simple selectors within one path, such as
`.obj[.first][.second]`, independently refer to that original input.

A selector is restricted to a **simple dotted field path** such as
`.key`, `.cfg.selected`, `."key"`, or `.cfg."full name"`. Individual
JSON-quoted field names may include literal periods, empty names,
escaped quotes/backslashes or Unicode escapes. A field inside a simple
computed selector may use either dot-quoted `."a.b"` or bracket-quoted
`["a.b"]` syntax. For example, `.obj[.cfg["a.b"]]` reads the exact
`a.b` field from the outer `cfg` object before using its value to index
`obj`. Bracket syntax can start the selector: `.[.["key"]]`, and can
follow quoted stages: `.obj[.["cfg"]["selected"]]`. All selector fields read
from the original filter input, not from an intermediate target.
Its field lookups are evaluated
before traversing the path stages, including when an earlier iterator
would yield no elements. That preserves jq errors such as
`{"items":[],"cfg":7} | .items[][.cfg.key]`, which fails because
the selector tries to read `.key` from the number `7`. The resulting
computed key indexes the intermediate value, with the existing type
and optional-iteration rules: missing target fields yield null,
invalid key/index types raise structured errors, and a later
`[]?` omits only non-container values at that final iterator stage.

Simple computed selectors also support **optional indexing** with a trailing
`?`: `.[.key]?`, `.obj[.key]?`, and `.items[][.key]?`. A mismatch between
the selected key and target types suppresses that indexed output. Valid
lookups, including a missing object field or indexing null with a valid key,
still emit a value (possibly JSON null). Selector *evaluation* errors are
not suppressed: `.items[][.cfg.key]?` still raises an error if `cfg` is
a number, including when `items` is empty. Later stages remain strict;
`.obj[.key]?[]` may still fail if the selected value cannot be iterated.
Each optional computed step applies independently within a path.

Dot-quoted `."field name"` and bracket-quoted `["field name"]` field
stages share the restricted computed-selector parser. **Signed literal
numeric indices** are now also available inside selector paths, for
example `.obj[.keys[0]]`, `.obj[.keys[-1]]`, and
`.obj[.cfg["names"][0]]`. These indices read arrays in the original
filter input (not the eventual object being indexed), so a numeric
selector value may then index an array target. Negative indices count
from the end, out-of-bounds and null array values yield JSON null,
and numeric indexing on objects or scalars raises a structured runtime
error.

**Optional named-field selector stages** such as `.obj[.cfg.name?]`,
`.obj[.cfg."name"?]`, and `.obj[.cfg["name"]?]` now skip an invalid
field lookup into a number, boolean, string, or array, producing **no
result**, rather than JSON null. A missing field in an object or a field
read from JSON null still yields JSON null, which can fail a strict outer
computed index. Optionality is scoped to a single named-field stage:
`.obj[.cfg?.name]` still fails if `cfg` is a number, whereas
`.obj[.cfg?.name?]` skips. An independent `?` after the closing
computed bracket (e.g. `.obj[.cfg.name?]?`) is required to suppress
an outer invalid/null-key index. The selector still reads from the
original input; errors or empty results are resolved before an earlier
path iterator. Multiple computed selectors continue evaluating from
right to left, so a rightmost empty optional selector can short-circuit
errors from a selector to its left.

**Optional numeric selector indices** such as `.obj[.keys[0]?]` and
`.obj[.cfg["names"][-1]?]` now suppress a numeric index's own invalid
target type (scalar or object), yielding **zero filter results**. They do
not turn that error into null. Out-of-range and null array values still
produce a JSON null selector value; a strict *outer* computed lookup can
therefore fail (e.g. `{"keys":[],"obj":{}} | .obj[.keys[0]?]`).
Use an additional trailing `?` after the outer `]` when a null key
should be skipped: `.obj[.keys[0]?]?`. Selector field lookup errors
before the numeric index remain strict. Multiple computed selector
expressions are resolved right-to-left, matching jq's nested index
evaluation order; an empty optional selector can short-circuit an
earlier selector's error. A numeric selector expression is still
evaluated even if an *earlier path iterator* would be empty. Optional
computed indexing is still available as `.obj[.cfg["full name"]]?`,
without suppressing errors *inside* the selector. A balanced bracket
scanner prevents `]` inside quoted key text from prematurely ending the
computed selector. Iterator stages (`[]`/`[]?`) *inside* selectors,
computed/generator-backed index expressions, slices, arithmetic and
arbitrary computed expressions remain outside this scoped implementation. They need separately audited evaluation/streaming
semantics rather than treating every expression as a field path.

**Optional literal numeric indices** now accept `[N]?` in complete
literal paths, including standalone lookups `.[0]?`, `.items[0]?`,
and `.items[0]?.name`, as well as paths with an audited iterator or
computed-key stage such as `.items[][0]?`, `.items[0]?[]`, and
`.obj[.key][0]?`. The trailing `?` suppresses only an invalid
numeric lookup on an object or scalar, producing zero results for that
intermediate value. Indexing an array out of bounds or indexing JSON
null still produces **one JSON null**, even for `[N]?`. Earlier
strict field lookups and iterators, computed-selector evaluation, and
later strict suffixes retain their own error boundaries. This is
different from optional numeric **selector** indices inside
`[.keys[0]?]`, which are evaluated against the original input.
The strict parser shape `['index', N]` is preserved; optional literal
numeric index steps are `['index', N, 1]`.

**Optional literal named fields** support `field?`,
`."quoted field"?`, and `["quoted field"]?`, including standalone
`.name?`, `."a.b"?`, `.["a.b"]?`, and `.cfg?.name`, as well as
ordered paths such as `.items[].name?`, `.items[]["a.b"]?`,
and `.obj[.key].child?`.
The `?` suppresses only a named lookup on an incompatible non-object
value, yielding **no result for that stream member**. Looking up a
missing object field or a field on JSON null still emits one JSON null.
Optionality does not extend to a subsequent strict stage:
`.items[].name?.child` can still fail if a valid `name` is numeric.
Field stages are handled by the scoped visitor when the entire literal
path has an optional named field, optional numeric index, recognized
iterator, or computed selector. A strict-only named-field path retains
the previous runtime behavior. For example, `.cfg?.name` still fails
on an invalid strict `.name` lookup after a successful `.cfg?`,
and `.cfg.name?` still fails on an invalid strict `.cfg` lookup.
Strict field steps keep `['field', name]`; optional steps use
`['field', name, 1]`.

**Standalone strict negative numeric indices** now share the ordered
v3 path visitor even without an iterator, computed selector, or optional
stage. For example, `.[-1]`, `.items[-1]`,
`.items[-1].name`, and `.items[0][-1]` read signed positions
from an array; a negative index counts from the end. Out-of-range
arrays and JSON null yield **one null**; numeric lookup on an object
(including an object with key `"-1"`), number, string or boolean
raises the same structured runtime error as other strict numeric
stages. An error in a later strict field/iterator is not suppressed,
and optional `[-1]?` keeps the previously audited zero-output
behavior for invalid target types. Positive strict-only paths
without these scoped stages remain on the existing implementation,
as do arbitrary expressions.

**Standalone strict bracket-quoted field paths** such as
`.["a.b"]`, `.obj["a.b"]`, and `.obj["a.b"].name` now use the
ordered v3 literal visitor without needing an iterator, computed
selector, optional step, or negative index. JSON quoted names are
decoded as exact field keys, including spaces, literal dots, escaped
quotes, Unicode escapes and characters that resemble operators.
A missing key or field lookup on JSON null produces **one JSON null**;
a strict field lookup on a number, boolean, string, or array raises
a structured evaluation error. Bracket quoting does not change
the error boundaries of prior or later strict stages. The parser
distinguishes `.["name"]` from the **array constructor**
`["name"]`: the latter is not interpreted as a field path.
**Standalone strict dot-quoted fields** now also enter that visitor,
for example `."a.b"`, `."full name"`, and `.obj."a.b".name`.
This uses the same JSON field-name decoding and strict type errors as
bracket-quoted access. The leading dot is semantically important:
`."a.b"` reads the object key `a.b`, whereas `"a.b"` is a JSON
**string literal** and must continue to return that string unchanged.
Paths with a strict dot-quoted stage are recognized only after the
whole filter is validated as a literal path. Their strict earlier and
later stages remain strict. Standalone strict unquoted (`.name`) paths retain existing handling
unless another audited stage is present.

**Standalone strict nonnegative numeric literal indices** such as
`.[0]`, `.items[0]`, `.items[0].name`, and `.[0][1]` now
use the same ordered v3 path visitor as strict negative indices,
without needing an iterator, computed key, optional step, or quoted
field. Valid positions select one array element; out-of-bounds
indices or indexing JSON null yield **one JSON null**. Indexing
numbers, booleans, strings or objects (even objects with a matching
string key `"0"`) remains a structured runtime error. Earlier and
later strict stages retain their errors; optional `[0]?` still
omits only that stage's wrong-type lookup. The strict
`['index', N]` shape stays unchanged. Existing unquoted strict
field-only paths and compatibility-sensitive helper traversal remain
outside this scope.

**Whitespace-padded literal numeric indices** are accepted inside
the audited v3 literal path visitor, for example `.[ 0 ]`,
`.[ -1 ]`, `.items[ 0 ].name`, and `.items[ -1 ]?`.
Optional `?` is outside the closing bracket and remains local to
that numeric lookup. Whitespace does not change numeric indexing
behavior: array bounds and JSON null produce one JSON null, while
strict wrong-type lookups still error and optional wrong-type lookups
emit no value. Spaces are permitted inside numeric brackets only
in fully recognized literal paths. Arithmetic selectors, slices,
and bare `[ 0 ]` array constructors are not reclassified as paths.

**Whitespace before a literal numeric index bracket** is now accepted
in ordered v3 paths, for example `. [0]`, `. [ -1 ]`,
`.items [ 0 ].name`, and `.items[0] [1]`. This is jq 1.7 syntax
whitespace: numeric indexing and stage-local `[N]?` optionality
retain their existing strict/null/empty-output rules. The scanner
consumes whitespace **only** when the next stage is a complete
literal signed-integer bracket, including whitespace *inside* the
bracket from the preceding change. It does not broaden arbitrary
computed selectors or slice expressions; whitespace before
brackets containing literal JSON strings is audited separately below. Bare `[0]` and `[ 0 ]` remain array constructors, not
rooted numeric lookups; a leading dot is required for root indexing.

**Whitespace before JSON-quoted field brackets** now works in
complete literal v3 paths: `. ["a.b"]`, `.obj [ "a.b" ]`,
`.obj [ "a.b" ]?`, and `.obj ["a.b"] [0]`.
JSON-quoted names are decoded as single literal keys; punctuation
such as `.`, `|`, `,`, and `|=` inside a key is not an operator.
Strict lookups keep their own wrong-type errors; stage-local
optional `? ` (written immediately after `]`, as `["a.b"]?`)
omits only invalid lookups while missing/null fields yield one
JSON null. Only whitespace before a **complete literal
JSON-quoted bracket** is consumed. Dynamic selectors and slices
remain separate, and bare `["a.b"]` or `[ "a.b" ]` are
array constructors, not object lookups.

**Whitespace-padded literal iterators** are now supported in the
ordered v3 path visitor. For example, `.items [ ]`,
`.items[ ]?`, `. [ ]`, and `.groups [ ] [ ]` all use the same
strict or optional iteration stages as `[]` and `[]?`.
An array or object yields its members in the established library
order; strict iteration of a scalar or JSON null raises a structured
evaluation error. The optional form drops only invalid iterator
targets and never masks earlier/later strict field or numeric errors.
The scanner recognizes brackets containing whitespace only in a
**rooted literal path**; a space before `[]` is treated likewise.
Bare `[ ]` remains an empty array constructor, and expressions such
as `try [ ]` are not misidentified as path traversals. This support
does not widen arbitrary computed selectors, slices, or non-path
constructor iteration.

**Whitespace before a dotted literal suffix** is accepted by the
ordered v3 path visitor, for example `.items[0] .name`,
`.items[] .name`, `.obj["a.b"] .name`, and
`.items[0] .["a.b"]`. This applies only when the *entire rooted
path* already has an audited stage (numeric index, iterator,
JSON-quoted field, computed selector or optional named field).
A whitespace-separated dot is a stage separator, not a pipeline
or a request for implicit array projection; the visitor keeps
source-ordered strict/optional errors, missing/null behavior and
per-member iterator results. Quoted names remain literal keys,
including punctuation that resembles operators. A bare `.name`
and an unquoted field-only chain keep their existing dispatch.
jq 1.7 does **not** allow whitespace immediately *after* the dot
before an unquoted name (for example `.items[0]. name`), so that
invalid syntax is not newly accepted by the scoped visitor.
The parser now also preserves the rooted form when the dotted
suffix is followed by spaces before a **literal bracket**:
`.items[0] . [0]`, `.items[0]. [1]`,
`.items[0] . ["a.b"]`, and `.items[0] . [ ]?`.
This ensures the already audited v3 numeric-index, quoted-field and
iterator stages receive the original complete path instead of a
dotless fragment. Stage-local strict and optional error handling
is unchanged; bare `[0]` or `["a.b"]` remain constructors.
Arbitrary computed selectors, slices, and whitespace before an
unquoted name *after* a dot are not widened by this change.
Non-path expressions and constructor/try syntax remain unchanged.

**Whitespace before a simple computed selector bracket** is now
supported by the same audited visitor as adjacent `[.key]`.
For instance `. [.key]`, `.obj [.key]`,
`.obj [ .key ]?`, `.arr [ .idx ]`, and
`.obj [ .cfg.chosen ].name` resolve the selector against the
original filter input, then index the current intermediate value.
The selector itself must still be the already supported simple dotted
field expression; arbitrary selector expressions and slices are not
newly accepted. A missing object field yields one null; invalid key or
container types raise a structured error at the relevant strict stage,
while `[.key]?` only suppresses errors from its own lookup.
Whitespace changes no result ordering or optional behavior.
A bare `[.key]` or `try [.key]` remains an array-construction
expression; the new gap recognition requires a rooted literal path.

For literal paths, unquoted names, JSON-quoted keys, and adjacent
`[]`/`[]?`/`[integer]`/`[integer]?` steps are supported
when there is an iterator, computed selector, **optional literal
numeric index, optional named field, strict numeric index of either
sign, or strict JSON-quoted field (bracket or dot form)**.
Strict-only unquoted field paths without any audited stage
continue using their prior query-path handling. A bare JSON string
filter stays a literal, not a field lookup.
The compatibility-sensitive internal traversal helper, implicit array
projection, slices, and arbitrary optional expressions remain unchanged.
Existing object iteration order remains unchanged.

**A `try` expression without an explicit `catch` now
drops errors as an empty result stream**, following jq 1.7's
`try f catch empty` equivalence. For example,
`null | try .[]` and `null | try (1 / 0)` emit no
results, rather than one JSON null; in `0, try (1 / 0), 9`
only `0` and `9` are emitted. A successful `try null`
still emits exactly one JSON null, and valid `false` values
are retained. `catch null` remains the explicit way to return
null on an error; `catch 42`, `catch $error` and
`catch empty` keep their existing handling.
The parser also keeps `try .[]` and `try .items[]` intact
instead of lowering their suffix iterators *outside* the `try`
handler; otherwise the caught error could escape the handler.
Top-level comma alternatives follow the same boundary.
Other nested try/catch parsing and unrelated filters are unchanged.

**Errors raised by an explicit `catch` handler now propagate** rather
than being replaced with a synthetic JSON null. For example, in
`try (1 / 0) catch recurse(.[])`, the division error is handled,
but a strict iterator failure inside the handler is a new runtime
error. An enclosing `try` can handle that subsequent failure.
Successful `try` results still bypass the handler, and `catch null`
and `catch empty` continue to emit null and no values respectively.
This handler-error change is limited to propagation. The catch input
context is audited separately below; broader streaming semantics remain
unchanged.

**Explicit `catch` handlers preserve empty output streams** rather
than generating JSON null when an expression shortcut yields no values.
The handler is now evaluated once as a full filter, so for example
`try (1 / 0) catch .[]?` on a null input and
`try (1 / 0) catch (empty | 9)` emit no results.
Comma alternatives retain their successful surrounding outputs.
An explicit `catch null` still emits one null; a successful `try`
still bypasses its handler.

**A `catch` handler now runs on its error message as a JSON string,**
matching jq 1.7, rather than reusing the original input value.
Thus `try (1 / 0) catch type` produces `"string"` and
`try (1 / 0) catch .` returns a diagnostic string. The precise
wording of error messages may differ from jq, but the handler
receives a string and may inspect it or emit its own outputs.
If a handler must access the original document, bind it before
the `try`, for example
`. as $original | try (.num / .den) catch $original.den`.
The preexisting `$error` variable is retained as a JQ::Lite
extension for existing callers, though jq 1.7 itself does not
predefine `$error`. A `catch` handler that raises a new error
still propagates it, and `catch empty` still returns no values.

**Successful top-level comma branches inside a `try` are retained
even when a later branch fails.** For example,
`try (0, (1 / 0), 9)` emits `0`, and
`try (0, (1 / 0), 9) catch 42` emits `0` then `42`.
A failing branch stops later alternatives and runs the explicit
handler only once; `catch null` emits one null after prior outputs,
while no `catch` and `catch empty` leave prior outputs alone.
This audit preserves only outputs from **completed comma branches**.
A leading standalone `.[]` or `.[]?` iterator in a `try` pipeline
now also preserves results from **completed earlier members** when a
later member fails. For example, given `[{"name":"Ada"},3]`,
`try (.[] | .["name"]) catch 42` emits `"Ada"` then `42`,
not just `42`. The strict bracket-quoted `.["name"]` lookup raises on a numeric
member; plain unquoted `.name` retains its separately documented
legacy dispatch. Processing stops at the failing member; subsequent
members are not evaluated. The optional head `.[]?` follows the same
per-member rule, while a scalar input produces no values.

The same completed-member preservation now applies to a `try`
pipeline starting with a **simple named field iterator** such as
`.items[]` or `.items[]?`, not just root `.[]`. For example,
`{"items":[{"name":"Ada"},3]}` with
`try (.items[] | .["name"]) catch 42` emits `"Ada"` then `42`.
A valid empty array produces no results. A null/scalar `.items`
is an error for strict `.items[]`, but is skipped by `.items[]?`.
The strict or optional boundary is evaluated by the existing path
visitor; only the completed member outputs of the tail are retained.

**Two-level iterator heads** such as `.[][]` and `.items[][]`
inside a `try` pipeline now visit outer and inner members in
depth-first output order. If a later inner iterator or the tail filter
fails, output from completed earlier members remains visible before
the `catch` handler runs. For example,
`[[{"name":"Ada"}],[3]] | try (.[][] | .["name"]) catch 42`
emits `"Ada"` followed by `42`. A non-array inner member
still raises on strict `[]`, whereas an optional second iterator
`[][]?` drops that member. The scope also includes the two-level
named-head `.items[][]`, without changing ordinary paths.

**Bare two-level iterators in `try` now emit their member streams**
without requiring a trailing pipe filter. For example,
`[[1],[2]] | try .[][]` emits `1` and `2`, while
`[[1],3,[2]] | try .[][] catch 42` emits `1` then `42`.
This also applies to bare `try .items[][]`, and to optional
outer or inner iterator stages. The handler still runs only once,
after previously completed output, and retains the jq 1.7
error-string input contract. Single-stage `try .[]` and
`try .items[]`, plus array constructors `try []` and
`try [ ]`, keep their existing behavior.

**Three or more simple nested iterator stages** in a `try` head
now follow the same member-by-member traversal as two-level paths.
Both bare `try .[][][]` and pipeline forms such as
`try (.[][][] | . + 10)` preserve outputs from finished members
when a later inner iterator or tail expression fails. The same
behavior applies to a named first field, for example
`try .items[][][]`, and to longer simple literal chains.
Optional `[]?` applies only at the stage where it appears:
`.[][]?[]` skips a scalar at the middle stage, whereas
`.[][][]?` skips a scalar at the deepest stage.
The first error terminates the remaining traversal and invokes
the explicit `catch` (if any) once, after earlier results.
Arrays with no members emit nothing; valid JSON `null` and
`false` remain values. Single-stage iterators and `try []`
array constructors retain their prior behavior.

**A parenthesized comma-expression head in a `try` pipeline now
retains earlier completed outputs**, even if a later alternative
or downstream tail fails. For example,
`try ((0, (1 / 0), 9) | . + 1) catch 42` emits `1`
followed by `42`. The first completed `0` passes through
`. + 1`, then the second alternative fails; `9` is never
evaluated. `try ((0,1,2) | if . == 1 then (1 / 0) else . end)
catch 42` similarly emits `0` and `42`, since the tail
fails before another head value is requested. Empty alternatives
remain empty, while JSON `null` and `false` are preserved.
With `catch empty` or no handler, only the preceding successful
values remain, and outer comma expressions continue normally.

This is deliberately limited to a *parenthesized, top-level comma
head followed by a pipeline*. Partially emitted results within a
single failing alternative or tail leaf are still eager and subject
to separate audits; ordinary comma expressions and prior generator
visitors are unchanged.

**A parenthesized comma-expression at the *end* of a `try`
pipeline now preserves its completed alternatives**, even when
a later alternative throws. `try (range(0;3) | (., 1/0)) catch 42`
emits `0` then `42`, rather than losing the first generated
value. The same rule works after a simple `.[]` or named-field
iterator, nested iterators, comma-expression heads, `recurse`,
and non-generator heads like `.`. More than one prefix stage
is allowed, e.g. `try (range(0;3) | . + 1 | (., 1/0)) catch 42`
emits `1`, `42`. Completed JSON null and false outputs
remain real values, while `catch empty`, `catch null` and
multi-output handlers retain their separate semantics.
A later generator item is never requested after a failing
final comma alternative.

**The same parenthesized comma stage may now be followed by a
downstream pipeline suffix**. For example,
`try (range(0;3) | (., 1/0) | tostring) catch 42`
emits `"0"` then `42`, whereas the preceding end-only
implementation discarded `"0"`. Each completed comma
alternative is passed through the trailing suffix before the
next alternative is evaluated. Other previously audited heads
such as `.[]`, `.items[]`, `recurse`, and a parenthesized
comma head follow the same ordering. A non-generator `.`
head is also supported. For a successful middle comma stage,
`try (range(0;2) | (., . + 10) | . + 1)`
emits `1`, `11`, `2`, `12`.
Output filtering, empty alternatives, JSON null and false,
multi-value handlers and no-catch semantics remain distinct.

**Multiple fully parenthesized comma stages** in a `try` pipeline
are now evaluated in source-order depth-first stream order.
For example, `try (range(0;2) | (., . + 10) |
(., . + 100))` produces `0, 100, 10, 110, 1, 101, 11, 111`.
When a later alternative fails,
`try (range(0;2) | (., . + 10) | (., 1/0)) catch 42`
emits `0, 42` and does not visit any remaining alternatives,
sibling values or later range items. Comma stages followed by
`tostring` or other simple suffix filters are handled in the
same order. The implementation uses an explicit continuation
stack rather than recursive closures, and reuses the existing
range, recurse and iterator source visitors. Valid JSON null
and false outputs remain visible before a later error, and
explicit catch values are appended only once.

**Nested, fully parenthesized comma alternatives** in a `try`
pipeline now preserve completed inner outputs too. For example,
`try (. | ((0, 1/0), 9)) catch 42` emits `0, 42`;
the earlier inner `0` is no longer lost when the next inner
alternative errors. Success paths such as
`try (. | (((0,1),2),3))` emit `0,1,2,3` in order.
The continuation stack expands the nested parenthesized
alternatives in source order while retaining the remaining
pipeline suffix for each emitted value. The same behavior is
available after `range`, `.[]`, named iterators, recurse,
and with a downstream `tostring` suffix. JSON null and false,
`empty`, and handler output semantics are preserved.

**A nested comma alternative that itself starts with a `range(...)`
pipeline** now also retains outputs completed before a later error
within that alternative. For example,
`try (. | ((range(0;4) | if . == 2 then (1/0)
else . end), 99)) catch 42` produces `0, 1, 42`.
The later sibling `99` is not evaluated after the error.
This also applies with a downstream `tostring` stage and
further fully parenthesized comma stages. A very large inner
range is stopped at the failing element rather than eagerly
materialized.

The scoped implementation reuses the demand-driven update-RHS
stream visitor for a `try` branch containing a fully
parenthesized comma stage and an inner **literal `range(...)`
pipeline**. The visitor preserves the jq depth-first sequence
of finished outputs and passes any later error to the existing
catch machinery. Other filters that emit partially before
failing, arbitrary generator arguments, and nonliteral
subexpressions still require a separate audit.

**Nested, parenthesized `range(...)` pipelines do not need a
comma alternative** to preserve completed outputs. For example,
`try (. | (range(0;4) | if . == 2 then 1/0 else . end))
catch 42` emits `0, 1, 42`. A nested pipeline following
`.items[]` or `.[0]` behaves the same, and any later input
to an outer `range` or array iterator is not visited once
the first error has been caught. Downstream `tostring` or
parenthesized comma suffixes continue to receive completed
generator results in source order. On an empty nested `range`,
there is no synthetic `null`; on a completed `false`
or `null`, the output remains a real JSON value.
The same generator can be extremely large and still stop after
the first failing member.

The implementation now routes **a complete `try` pipeline
containing a literal, parenthesized `range(...)` subpipeline**
through the demand-driven update-RHS stream visitor, whether
or not it contains a comma stage. It does not affect unwrapped
`range` heads, which retain their existing dedicated visitor.
Other arbitrary generators, dynamic `range` arguments,
eagerly failing single leaf filters, and unrelated path
semantics remain separate audits.

**Parenthesized nested default `recurse` and
`recurse(.[]?)` pipelines** now retain completed outputs
before a later tail error as well. For example,
`[1,[2],3] | try (. | (recurse | if . == 2 then
1/0 else . end)) catch 42` emits the original array,
`1`, `[2]`, then `42`. The same ordering holds
with optional-child recursion, nested comma alternatives,
and trailing `type` or parenthesized comma stages.
Successful recursion visits the root before its descendants.
JSON null and false roots and empty containers remain
ordinary outputs; handlers still receive the error string.

**Strict `recurse(.[])` nested inside a parenthesized `try`
pipeline** now obeys the same yield-before-expand rule as
its already-supported unwrapped counterpart. For
`[1,[2],3] | try (. | (recurse(.[]) | type)) catch 42`,
the output is `"array", "number", 42`: the number's type
is emitted before its strict child iteration raises an error.
With a null or false root, `type` emits `"null"` or
`"boolean"` before the caught error. Empty arrays have no
children to fail on. Downstream suffixes, comma alternatives,
outer iterators, `catch empty`, and multi-output handlers
retain the same ordering.

The nested literal generator dispatch now recognizes default,
optional-child `recurse(.[]?)`, **and strict `recurse(.[])`**
via the existing demand-driven update-RHS visitor. The shared
visitor now attempts strict `.[]` expansion of a null node
if downstream filters have not already accepted an output.
This is also consistent with `|=` first-result short-circuiting:
an accepted root value suppresses unused child errors, whereas
an empty RHS after `recurse(.[])` propagates the required
null-iteration error. The update RHS regression uses a simple
`.a |=` path on a null-valued field directly, without a
surrounding `try` (update expressions inside `try` require
a separate parser audit). Optional `.[]?` still skips null. Other
arbitrary custom child filters, unusual argument nesting,
and partially emitting individual eager leaf filters remain
separate audits. Previously supported unwrapped recurse
heads keep their existing behavior.

**Nested custom-child `recurse(.[]? | f)` inside `try`**
now streams completed nodes before a later child-filter or
downstream error. On `[1,[2],3,4]`,
`try (. | (recurse(.[]? | if . == 3 then
1/0 else . end) | type)) catch 42`
emits `"array", "number", "array", "number", 42`.
A complete node and its downstream transformation are
delivered before the next child is requested, so neither the
failed child nor later siblings are emitted. The same
ordering is preserved with nested comma alternatives,
outer iterators, multi-stage suffixes and custom filters
that emit zero or multiple child results. JSON null, false
and empty-container roots remain regular outputs.

This narrowly expands the nested-generator routing to
a parenthesized `recurse(.[]? | f)` head. It reuses the
existing update-RHS demand-driven visitor without changing
the semantics of standalone `recurse(f)`.
**Named-field custom child pipelines**, such as
`recurse(.items[]? | if .id == 2 then 1/0 else . end)`,
now also preserve completed recursive outputs when nested
inside a `try` pipeline. For an object with three children
under `items`, the root object and the first child are
emitted before the second child raises an error; later
siblings are not visited. Nested `items` arrays are visited
depth-first. Child filters that emit zero or multiple values
retain source order, and their successfully transformed
outputs remain visible before `catch`.
Literal **bracket-quoted child iterators** such as
`recurse(.["items"][]? | f)` have the same nested
`try` streaming behavior. The exploratory
`t/v3_recurse_dynamic_child_audit.t` test is now a
jq 1.7-backed regression suite. This accepts a literal
JSON-quoted field followed by `[]?` and a child pipeline;
it does not imply support for arbitrary computed selectors.

Literal **dot-quoted child iterators**, such as
`recurse(."items"[]? | f)`, now use that same scoped
demand-driven dispatch when nested in `try`.
Field names containing periods or spaces remain literal
keys. Earlier completed outputs remain visible before a
later child error and its `catch` handler. This change
does not generalize streaming to computed selectors,
arbitrary custom children, or partially failing eager leaves.
Direct regressions and 23 jq 1.7 differential fixtures
cover the additional dot-quoted forms. Unwrapped recurse
and the stable 2.x API are unchanged.
**Strict named-field child iterators** such as
`recurse(.items[] | f)`, `recurse(.["items"][] | f)` and
`recurse(."items"[] | f)` now also preserve prior recursive
nodes when a later child or downstream filter raises an error
inside a parenthesized `try` pipeline. Unlike the optional
forms, strict `[]` raises when the selected child field is
missing or null; the node was already emitted, so a `catch`
handler follows the completed output. Null roots therefore
produce the root null *and then* the caught strict-iterator
error. This uses the existing update-RHS demand-driven
visitor, with a narrow null-node expansion correction for
simple named/quoted strict child iterators. It does not add
general streaming for arbitrary computed keys, and it does
not change stable 2.x behavior. The scoped suite contains
27 jq 1.7 differential fixtures and direct Perl regressions.

This is a named-field **optional iterator followed by a
custom child pipeline**, not general dynamic path support.
Errors in non-iterator portions of the field access and
other custom child expressions still follow their existing
semantics.

**Dotted computed-key selectors** beginning with a
simple field path, such as `recurse(.[.cfg.key][]? | f)`
or its strict `[]` variant, now retain completed ancestor
and sibling outputs when used as the head of a nested
parenthesized `try` pipeline. Each recursion node resolves
the dotted selector against that node's input, so later
children may use different computed field names.
The selector is evaluated even on null or invalid inputs;
a missing, null, or invalid intermediate selector value
raises before the optional iterator can suppress anything.
However, `[]?` skips a missing or null **selected array**,
while strict `[]` raises after the current node has been
emitted. Emission remains depth-first across downstream
pipelines, comma alternatives and outer iterators.
This is deliberately limited to **simple dot-separated
identifier field paths** within one computed selector
followed by literal `[]` or `[]?` and a child pipeline.
Arbitrary computations, nested computed selectors and
individual eager-leaf partial streams remain outside
this change. The scoped Perl tests and 36 jq 1.7
differential fixtures cover its compatibility boundary.

**Bracket-quoted literal stages inside a computed selector**
such as `recurse(.[.cfg["selected"]][]? | f)`, and the
strict `[]` counterpart, now preserve finished recursive
nodes within a parenthesized `try` pipeline before a
later child or tail error. This uses the same demand-driven
visitor as simple `.[.cfg.key][]?` selectors; only the
literal bracket-quoted selector field and existing optional
or strict iterator are added to the routing and null-node
error guard. JSON-quoted selector names containing spaces,
periods or bracket characters remain literal keys.
The selector is still evaluated on null nodes and can
raise before optional iteration, while a missing or null
*selected container* is skipped by `[]?` and rejected
by strict `[]`. This is a single bracket-quoted literal
field following a simple dotted-identifier selector prefix,
not arbitrary dynamic expressions or general lazy leaf
streaming. The direct regressions and 39 jq 1.7 differential
fixtures cover this scoped change.
**Dot-quoted computed selector stages** within the same
nested `try` shape now also preserve completed outputs:
`recurse(.[.cfg."selected"][]? | f)` and the corresponding
strict `[]` form are dispatched through the existing
demand-driven recurse visitor. The selector still reads
from each current node; a selector lookup error happens
after that node is emitted and is not hidden by `[]?`.
Selected null/missing arrays remain optional or strict
according to the explicit iterator suffix. Quoted names
containing spaces, dots, and closing brackets are treated
literally. This is limited to one final dot-quoted literal
field after a simple dotted identifier selector prefix,
not arbitrary expression evaluation or eager-leaf partial
streaming. The regression suite adds 39 jq 1.7 differential
fixtures and a separate Perl test file for this form.
**Signed literal numeric indices in computed selectors**
now retain already completed outputs for nested
`recurse(.[.keys[0]][]? | f)` and `recurse(.[.keys[-1]][] | f)`
pipelines within `try`. A simple dotted prefix such as
`.[.cfg.names[0]][]?` is also supported. These forms use
the existing update-RHS demand-driven visitor, not a
general computed-expression evaluator. Numeric indexing
takes place against each recursion node's selector array.
An invalid computed key or numeric selector path still
raises after emitting its node; optional `[]?` skips
a missing or null *selected container*, while strict
`[]` rejects it. Earlier siblings remain emitted in
depth-first order, and `catch` outputs follow the error.
Literal signed indices (including negative indices),
missing selector keys, null/scalar values, comma tails
and outer iterators are covered by direct Perl assertions
and 40 jq 1.7 differential fixtures. Arbitrary arithmetic
inside selectors, multiple computed brackets, and
partially failing eager leaves remain separate #625 audits.

**Two consecutive signed numeric selector indices**,
such as `recurse(.[.cfg.names[0][0]][]? | f)` and
`recurse(.[.cfg.names[-1][-1]][] | f)`, also preserve
prior completed nodes under parenthesized `try`.
The extension is deliberately limited to one or two
literal signed numeric indices after a simple dotted
identifier selector prefix; earlier path parsing and
jq 1.7 error semantics remain unchanged. Selector
errors are not suppressed by optional child iteration,
while strict iteration on a null or missing selected
container raises after the node has been emitted.
37 jq 1.7 differential fixtures and a standalone Perl
regression suite cover recursion order, multiple
outputs, catches, nested descendants and bad selectors.
**A quoted literal field followed by one signed numeric
index in a computed child selector** now retains prior
recursive nodes when nested within parenthesized `try`:
`recurse(.[.cfg["names"][0]][]? | f)` and
`recurse(.[.cfg."names"[-1]][] | f)`. The extension
matches one bracket-quoted or dot-quoted field after
a simple dotted identifier prefix, followed by exactly
one signed literal index and strict/optional child
iteration. Both spellings reuse the existing demand-
driven recurse visitor and do not change path parsing.
Computed selector failures (including null nodes and
out-of-range numeric indices that yield invalid keys)
occur after the current node has been emitted. Optional
`[]?` skips a missing/null *selected container*, whereas
strict `[]` raises. Direct Perl regressions and 72 jq
1.7 differential fixtures cover catch order, ancestor
preservation, nested recursion, numeric signs, special
quoted names, and earlier selector controls. This does
not support arbitrary computed expressions or partially
failing eager leaf streams.
**One or two signed numeric indices after a quoted
literal selector field** are now handled by the scoped
nested `try` recurse stream visitor. This covers
`recurse(.[.cfg["names"][0][0]][]? | f)` and
`recurse(.[.cfg."names"[-1][-1]][] | f)` in addition
to the existing single-index forms. Both bracket-quoted
and dot-quoted literal selector fields work after a
simple dotted-identifier prefix; arbitrarily nested
computed expressions are not part of this extension.
The ancestor node and any finished siblings remain
visible if a selector or later child fails. Optional
`[]?` still skips a null/missing selected container,
while strict `[]` raises after the current node is
emitted. Direct Perl regressions and 72 additional
jq 1.7 differential fixtures cover depth-first order,
catch variants, signed indices, invalid selectors,
and unusual quoted names.
**Two successive simple computed selector stages**,
such as `recurse(.[.first][.second][]? | f)` or
`recurse(.[.cfg.first][.cfg.second][] | f)`, are now
recognized by the narrowly scoped nested `try`
stream visitor. Both selector expressions read from
the same current recursion node before descending
into the selected child stream. This preserves
completed ancestors and earlier siblings before
a later selector, child filter, or downstream tail
raises an error. An invalid computed key on a null
node is still evaluated after that node is emitted;
optional `[]?` only skips null/missing *selected*
containers, whereas strict `[]` raises. The change
is limited to two simple dot-separated identifier
selector stages, not arbitrary expressions or three
or more computed selectors. Direct Perl regression
tests and 37 jq 1.7 differential fixtures cover
these boundaries, catches and depth-first order.
**Paired computed selectors with quoted literal suffixes**
are now recognized in nested `try` recurse streams:
`recurse(.[.cfg["first"]][.cfg.second][]? | f)` and
`recurse(.[.cfg.first][.cfg."second"][] | f)`.
Either or both simple selector stages may end in a
JSON-quoted bracket or dot field. Both selectors are
resolved from the current recursion node, preserving
earlier depth-first outputs if a later child or selector
fails. On null recursion nodes, selector errors follow
the completed node rather than being swallowed by
optional `[]?`; strict `[]` continues to reject a
missing/null selected array. This limited extension
keeps the previously audited two-identifier form,
without enabling arbitrary computed expressions or
three or more computed selector stages. New direct
Perl regressions and 100 jq 1.7 differential fixtures
cover the bracket/dot combinations and controls.
**Paired computed selectors with one numeric stage each**
now retain jq 1.7 demand-driven recursion order under
`try`, including `recurse(.[.first[0]][.second[-1]][]? | f)`
and `recurse(.[.cfg["first"][0]][.cfg."second"[0]][] | f)`.
Each selector may finish with one signed literal
numeric index, optionally following one quoted field,
while the preceding dotted-identifier path stays
literal and simple. No new parser or arbitrary
computed-expression behavior is introduced.
The previous node is emitted before selector or child
errors; `[]?` skips null/missing selected children,
whereas strict `[]` raises. 97 jq 1.7 differential
fixtures and direct Perl assertions check depth-first
output, catches, negative indices, missing keys, and
the prior unindexed selector forms.
**Three successive simple computed selector stages**
may also be used inside a nested `try` recurse stream:
`recurse(.[.first][.second][.third][]? | f)` and
`recurse(.[.cfg["first"][0]][.cfg."second"[0]][.cfg.third[-1]][] | f)`.
This adds only a third selector stage to the existing
narrow literal-path dispatch. Each stage is a simple
dotted identifier path with an optional literal quoted
field and/or one signed numeric index, all evaluated
on the current recursion node by the existing parser.
Ancestors and earlier siblings remain visible when
a later selector, child filter, or tail raises. Null
selector errors are not suppressed by `[]?`; a missing
selected container is skipped only with optional
iteration. The change adds 52 jq 1.7 differential
fixtures and a dedicated Perl regression file.
General jq expressions and arbitrary selector depth
remain outside the audited v3 compatibility scope.
**Shared scoped-selector recognition.** The nested
`try` recurse generator dispatcher and the visitor's
null-node expansion guard now use the same audited
computed-child grammar. Single computed selectors may
include up to two signed literal numeric indices;
two or three computed selector stages may each contain
one, with optional final quoted literal fields.
The supported runtime semantics are unchanged; this
refactoring removes duplicated, diverging regex
alternatives so a new selector form cannot accidentally
be enabled for the dispatcher but omitted from the
null-node guard. `t/v3_computed_recurse_matcher.t`
tests both accepted cases and deliberately excluded
arbitrary expressions, deeper paths and iterators.
**Four successive scoped computed selector stages**
are supported for streaming nested `try`/`recurse`
child pipelines. For example, the filter
`recurse(.[.a][.b][.c][.d][]? | f)` preserves
previously completed outputs before later errors.
Each stage still consists of a simple dotted-identifier
selector with, at most, a single quoted literal field
and/or a signed numeric index. The fourth selector
uses the existing path parser and shared matcher;
five stages and arbitrary computed expressions remain
unaudited. Optional/strict iteration, depth-first
ordering and error handling are covered by direct
Perl assertions and 42 jq 1.7 differential fixtures.
**A third signed literal numeric stage** is now
recognized within a single computed selector in
nested `try` recurse streams. The scoped visitor
covers `recurse(.[.cfg.names[0][0][0]][]? | f)`
and `recurse(.[.cfg["names"][-1][-1][-1]][] | f)`.
The existing v3 path parser already evaluates
those stages; only the common dispatch and null
expansion grammar changes. The earlier node and
completed siblings remain visible before a later
child or selector error; optional iteration skips
missing/null selected arrays, strict iteration raises.
Four numeric stages or arbitrary arithmetic selectors
remain outside the audited grammar. Direct Perl
regressions and 41 jq 1.7 differential fixtures
verify this bounded extension.
**Optional numeric stages within computed child selectors**
are supported in the existing scoped nested `try`
recurse visitor. For example,
`recurse(.[.keys[0]?][]? | f)` preserves prior
completed nodes before a later child failure.
An inner `[0]?` suppresses *invalid numeric-index
target type* errors by yielding no selector output;
it does not make a valid array's out-of-range null
result into `empty`. The resulting computed null key
still raises, even with an outer `[]?` child iterator.
Strict `[]` on a null/missing selected container still
raises after its recursion node has been emitted.
Quoted selector fields and mixed strict/optional
numeric stages retain their existing v3 semantics.
The change adds 40 jq 1.7 differential fixtures and
direct Perl tests, without enabling arithmetic
selectors or arbitrary filter evaluation.
**Optional field stages inside computed selectors**
are now also routed through the shared nested
`try`/`recurse` visitor. Examples include
`recurse(.[.key?][]? | f)`,
`recurse(.[.cfg["name"]?][] | f)`, and
`recurse(.[.cfg?.name?][]? | f)`.
An optional `.field?` or quoted-field `?`
suppresses an invalid *field lookup target type*
by yielding no selector results. A missing field
or JSON null still yields an actual null value,
which is an invalid computed key and can raise
after emitting the recursion node. Outer `[]?`
only skips null/missing *selected* values;
strict `[]` still errors on those values.
Only simple parser-supported optional field
stages are added, without arbitrary expressions.
Direct Perl tests and 40 jq 1.7 differential
fixtures cover the independent error boundaries.
**Optional computed lookup steps themselves**,
such as `recurse(.[.key]?[]? | f)` or
`recurse(.[.cfg.name]?[] | f)`, now participate
in the same nested `try` stream handling. The
`?` attached to `[.selector]` suppresses an invalid
computed index operation and yields no children,
unlike a strict computed lookup where a null key
raises. A separate invalid operation *within* the
selector expression, such as `.cfg.name` on a
numeric `.cfg`, continues to raise before the
optional outer lookup is reached. Optional child
`[]?` and strict `[]` retain their own distinct
null/missing-container behavior. The scoped
parser and null-node visitor are reused, with
40 jq 1.7 differential fixtures and a direct
Perl regression file. Arbitrary computed arithmetic
still requires separate auditing.

**Four literal signed numeric stages in one computed selector**,
for example `recurse(.[.cfg.names[0][0][0][0]][]? | f)` or
`recurse(.[.cfg["names"][-1][-1][-1][-1]][] | f)`, now share the
same demand-driven nested `try` visitor. Previously this valid v3
selector shape fell outside the narrow recurse matcher, allowing a
later child error to discard already completed nodes. Inner numeric
`?`, outer computed-lookup `?`, and final `[]?` remain independent;
invalid selector operations are not hidden by optional child iteration.
This change extends only the single-selector depth bound from three
to four, retains the existing four-computed-selector breadth limit,
and adds direct Perl and jq 1.7 differential coverage. Arithmetic,
slices, and general computed expressions remain outside this audit.
















**Simple computed-key strict child iterators**,
such as `recurse(.[.field][] | f)`, are now handled
by the same narrowly scoped nested `try` stream visitor.
The current node and any fully evaluated earlier siblings
remain visible before a later strict child iterator or
child-filter raises an error. Unlike `[]?`, strict `[]`
raises when a computed field is missing or null, after
its containing node has been emitted; an empty array
ends normally. The computed `.[.field]` selector is
still evaluated on a null root, where a null selector
key raises before iteration. Multiple catch outputs,
nested recursion, comma stages, outer iterators and
literal unusual field names retain their jq 1.7 order.
This is only one simple computed field selector plus
strict `[]` and a child pipeline; general dynamic
selectors and partially failing eager leaf filters
remain separate audits. The scoped regression suite
includes 34 jq 1.7 differential fixtures.
**Simple computed-key optional child iterators**,
such as `recurse(.[.field][]? | f)` inside a parenthesized
`try` pipeline, now preserve ancestor and prior sibling
outputs when later children fail. Each recursion node
evaluates `.field` against its own input, selects that
object field, and optionally iterates the selected value.
The selector itself is not optional: missing or null
selector keys still raise after the current node has
been emitted, including when the current node is null.
Likewise, a non-object field lookup failure occurs before
the `[]?` suffix can suppress iteration. Zero/multiple
child outputs retain depth-first order and catch handlers
follow completed outputs. This is limited to a **single
simple `.field` computed selector** plus `[]?` and a
custom child pipeline, not arbitrary computed expressions
or eager-leaf partial streaming. A dependency-free Perl
regression suite and 29 jq 1.7 differential fixtures
cover the scoped behavior.

Remaining arbitrary dynamic selector expressions,
computed-key forms without this exact optional iterator,
and individual failing eager leaves remain subject to
separate #625 audits.

This remains a scoped correction for **fully parenthesized
comma alternatives inside a pipeline stage**. An individual
failing eager leaf filter may still lose its earlier output,
and bare nested `try` expressions remain separately audited.

This is an intentionally scoped streaming correction. Partial values
produced *within one failing member* or inside other generator/path
forms remain subject to the eager-evaluation limitation; this does
not introduce a general-purpose streaming evaluator.

The parser now preserves **`try []` and `try [ ]` as
empty-array constructor expressions** instead of lowering the
brackets into a standalone iterator. Both forms emit one empty
array, including in comma branches (`0, try [ ]` emits `0`
then `[]`). `try [ ] | length` emits `0`, and piping that
empty array into `.[]` emits no values without a scalar
iteration error. This is deliberately restricted to the literal
`try` keyword directly followed by an empty array bracket;
ordinary value-producing suffixes such as `keys[]?` and rooted
literal `.items [ ]` are unchanged. Other `try` expression
semantics remain separately scoped.

Standalone `.[]?` is also available in a pipeline (including
`recurse(.[]?)`). Non-path array-result suffixes `keys[]?`,
`split(",")[]?`, and `[4,5][]?` lower to an optional iteration stage,
with the same rule independently applied inside comma alternatives.
Errors from upstream functions are not converted to empty results.
Computed (non-literal) path segments beyond simple dotted-field
selector expressions `[.field]`, composite literal paths with no iterator,
arbitrary optional expressions, and more general iterator compositions
still require separate audits beyond the scoped support described above.

**Simple `range(...)` heads inside `try` pipelines are now consumed
one value at a time.** The existing update-RHS range visitor also
supplies `try (range(0;5) | f)`, so a failing `f` cannot discard
earlier completed outputs or force the rest of the range. For example,
`try (range(0;5) | if . == 3 then (1 / 0) else . end) catch 42`
emits `0`, `1`, `2`, `42`. Negative steps, empty ranges,
multiple tail stages, `catch null` and `catch empty` follow the
same ordering. Large ranges are not eagerly allocated if a downstream
error stops generation. This is restricted to a complete, simple
`range(...)` pipeline head with ordinary literal arguments.
Nested generator arguments, non-literal argument expressions,
general-purpose lazy filters, and errors within a single tail filter's
partially produced stream remain outside scope.

**Default `recurse` and `recurse(.[]?)` inside a `try` pipeline**
now use the existing depth-first, demand-driven update-RHS recurse
visitor. Each successfully produced recursion value is evaluated
through the downstream pipeline before any further descendants are
visited. For `[1,[2],3]`,
`try (recurse | if . == 2 then (1 / 0) else . end) catch 42`
emits the original array, `1`, `[2]`, and then `42`.
Earlier completed outputs survive the error; later siblings
are not visited. `catch empty` leaves the earlier outputs intact,
while `catch null` appends one actual JSON null. The optional-child
form `recurse(.[]?)` follows the same ordering.
A successful recursion still emits every visited value; no-catch
errors suppress only the failing remainder.

This is a scoped change for complete, literal `recurse` and
`recurse(.[]?)` *heads with a downstream pipeline*; bare recurse
queries are unchanged. Strict `recurse(.[])` is handled by the
separate scoped visitor below; arbitrary custom child generators,
object key visitation order and general streaming of partially
failing leaf filters remain separate audits.

**Strict `recurse(.[])` inside `try` now yields before expanding
each node's children**, matching jq 1.7. Unlike `recurse(.[]?)`,
a scalar, boolean or null leaf causes an error *after* its own
value has been emitted. Given `[1,[2],3]`,
`try recurse(.[]) catch 42` emits the original array, `1`,
then `42`; the later `[2]` and `3` are never visited.
`try (recurse(.[]) | type) catch 42` emits `"array"`,
`"number"`, `42`. On input `null`, a bare strict recurse
emits one real JSON null followed by the catch fallback.
With `catch empty` or no catch, only completed earlier results
remain. The same yield-before-expand semantics apply to bare and
pipelined strict recurse, including comma alternatives.
The implementation is limited to the literal `recurse(.[])`
form; arbitrary child filters and object visitation order are
audited separately below.

**Custom `recurse(f)` child filters now preserve completed recursive
outputs inside `try`**, whether used bare or followed by a pipeline.
For example, `[1,[2],3,4] | try recurse(.[]? | if . == 3 then
(1 / 0) else . end) catch 42` emits the original array, `1`,
`[2]`, `2`, then `42`. The child expansion fails when it
reaches `3`; previously emitted nodes survive, and `4` is not
visited. A custom child filter can emit zero, one or multiple child
values. Children are evaluated depth-first before their next
sibling, and completed earlier nodes remain when a downstream
`try (recurse(f) | g)` tail fails. The change reuses the
demand-driven update-RHS child visitor, including its special
support for comma expressions and pipelines in the child filter.

This is intentionally scoped to a complete `recurse(f)` head
inside `try`. Errors after partial output *within an individual
unsupported child-filter leaf* may still lose those leaf outputs.
Arbitrary computed selectors, object member ordering, and broader
generator stream semantics require independent audits.

Only `recurse` and `range` have demand-driven leaf output handling
so far. **Other leaf filters remain eager** under the existing engine;
short-circuiting within arbitrary built-ins, generator argument expressions,
and complex filter bodies is not yet guaranteed. Stateful filter effects
and iterator update ordering require separate audits. This is not a
general-purpose streaming evaluator.
**Array and object iterators** are supported in simple update paths:
`.items[] |= . + 1` updates every array or object member value, and
`.[] |= empty` removes every member of the root container. Each RHS runs
against the old selected leaf and the query emits one updated root.
A literal field or numeric index can precede or follow the iterator (for
example `.groups[0][]` or `.items[].count`). Empty arrays and objects
produce one unchanged root; missing/null/scalar iterator targets raise
structured evaluation errors instead of manufacturing a container.

For object iteration, the engine operates on the original **keys directly**:
empty keys and names containing dots, spaces, or brackets are supported
without constructing invalid dotted paths. No-output RHS deletes the member
key, whereas `null` is stored as a value. A suffix path updates a member's
nested field or indexed element without deleting the member itself.
Object keys are processed in sorted order for determinism. Array indices
are processed in reverse to keep deletion stable. **Stateful RHS effects
and evaluation order are therefore not guaranteed to match jq.**

Multiple `[]` iterators are now supported for simple literal paths.
For example, `.groups[][] |= . + 1` updates the scalar leaves of arrays of
arrays; `.groups[][].n |= . + 1` updates object fields nested under both
iterators. Each iterator can traverse an array or an object, so an object of
arrays, an array of objects, and deeper mixtures are supported. Iteration
recurses into the original members, preserving arbitrary object keys instead
of constructing dotted paths from them. Empty inner containers are no-ops.

An RHS that emits no results deletes only the selected **innermost target**:
`[[1,2],[3,4]] | .[][] |= empty` becomes `[[],[]]`; the outer
arrays remain. Nested conditional updates also retain original container
boundaries, and nested updates still emit one updated root.

This extension retains the ordering limitations above: array members are
visited in reverse to avoid deletion-induced index shifts and object keys
are processed in sorted order, rather than promising jq's evaluation order.
Computed/quoted iterator paths and jq's fully streamed update evaluation
remain outside this scoped implementation. The relationship with compound
`+=` and other operators requires a separate audit under #626. Do not
assume complete jq assignment compatibility.

Multi-result **plain** assignment remains undecided and requires a separate design.

## Explicitly preserved scope

The following choices continue in 3.0 unless separately reconsidered:

- vectorised `floor`, `ceil`, `round`, `fromjson`, and related lossless helpers;
- array path projection;
- JQ::Lite convenience and statistical functions;
- truncating jagged `transpose` behaviour;
- the absence of modules/imports and jq's streaming parser mode; and
- the pure-Perl implementation and Perl 5.14 minimum.

Iterator suffixes, plain assignment, cross-type ordering, and missing-value
comparison already match the audited jq cases and are regression guards, not
3.0 work items.

## Undecided items and decision gates

An undecided behaviour may enter 3.0 only after a focused proposal includes:

1. examples of jq 1.7 and JQ::Lite 2.x behaviour;
2. known compatibility impact on existing filters;
3. the proposed result and error policy;
4. migration guidance; and
5. dependency-free regression tests.

This gate applies to numeric-string arithmetic, regex scalar coercion, invalid
path errors, mixed iterator pipelines, multi-result assignment, unsupported
parser syntax, control flow, and the future role of `contains_subset`.
Unresolved items retain their 2.x behaviour in 3.0.

## Delivery sequence

1. **Freeze the baseline.** Keep the 2.x inventory and regression tests intact.
2. **Build shared semantics.** Use the internal `JQ::Lite::Value` type and
   comparison primitives, then introduce path-result primitives, without
   changing public behaviour.
3. **Land isolated changes.** Implement containment, fallback/path,
   arithmetic/comparison, and update-assignment changes in separate reviews.
4. **Publish migration notes.** Provide before/after examples and replacements
   for filters whose output or failure mode changes.
   Differential fixture format, compatibility statuses, and opt-in execution
   are documented in [jq differential testing](jq-differential-testing.md).
5. **Validate the release candidate.** Run the full Perl test suite on all
   supported Perl versions and differential tests against jq 1.7 for every
   committed compatibility case.

## Migration guidance

Applications that need one code path across 2.x and 3.x should avoid relying
on the changed edge cases until they can require 3.0. Some changed semantics,
including the result of update assignment, cannot be normalized by appending a
filter that works in both major versions; those cases require version-aware
application logic. In particular:

| 2.x-dependent filter | 3.0-safe migration approach |
| --- | --- |
| `contains(...)` expecting exact array elements or nested object equality | express exact equality explicitly before upgrading |
| `false // fallback` expecting `false` | use an explicit null test when `false` is data; in v3 `false // 9` returns `9` |
| a missing path as an empty output stream | use `empty`/selection explicitly rather than relying on implicit dropping |
| arithmetic with booleans | convert the boolean to the intended number explicitly |
| arithmetic with numeric-looking strings | convert explicitly with `tonumber()` or `to_number()` before using `- * / %` or numeric `+` |
| equality between numeric strings and numbers | normalize both sides explicitly with `tonumber` or `tostring` |
| bare `.[]` on null, booleans, numbers, or strings expecting empty results or character splitting | validate or normalize values to arrays/objects before iterating; v3 raises a runtime error for scalar inputs, matching jq 1.7 |
| `.field[]` on a missing, null, or scalar-valued field expecting no results | use `.field[]?` when dropping non-iterable final values is intended; ensure every preceding named-field lookup is valid, because `[]?` does not suppress an invalid prefix lookup |
| intermediate `.items[].name` or nested `.items[][]` silently skipping malformed values | use `[]?` at precisely the iteration stage where skipping non-containers is intended; later named-field lookups can still fail, so validate those inputs separately |
| `.items[0][].name` or `.items[].names[0]` assuming invalid array indexing quietly disappears | use explicit validation or null/array checks for numeric-index input; `[]?` can skip only a later iteration failure, not indexing a wrong JSON type |
| keys containing periods, spaces, quotes, or brackets used inside iterator paths | use literal bracket-quoted fields (e.g. `.["a.b"][].["full name"]`) instead of manually splitting dotted path text; the quoted keys retain their JSON meaning and each `[]?` applies only at its own stage |
| a field's name is stored in another field (e.g. `{"key":"a","a":7}`) | use `.[.key]` to select dynamically, or `.items[] | .[.field]` per item; the selected key must be a JSON string, and `[]?` does not suppress a bad computed selector |
| a computed selector after an intermediate path (e.g. `.obj[.key]`) was assumed to read `key` from `obj` | the selector `.key` reads from the **original filter input**, not `.obj`; use a pipeline `.obj | .[.key]` only when the key should come from the nested object itself |
| selector field names containing periods/spaces previously being interpreted as dots or unsupported syntax | use `."quoted.name"` or `["quoted.name"]` *inside the computed expression*, e.g. `.obj[.cfg["selected field"]]`, to read one exact original-input field name; this is different from putting a quoted literal key *outside* the selector |
| selecting a key from an array in the input | use a literal numeric selector index, e.g. `.obj[.keys[0]]` or `.obj[.cfg["names"][-1]]`; out-of-range indices produce null, but invalid array target types raise an error even with `?` on the outer computed lookup |
| a numeric *selector stage* must silently skip an object/scalar instead of raising | use `.obj[.keys[0]?]`; this skips invalid numeric index targets but does **not** suppress null selector keys or errors earlier in the selector; add another `?` as `.obj[.keys[0]?]?` to suppress an invalid *outer* lookup |
| a named *selector field stage* must skip invalid non-object values | use `.obj[.cfg.name?]` or `.obj[.cfg["name"]?]`; placing `?` on an earlier field (`.cfg?.name`) does not suppress the later named lookup, and missing/null fields still yield null, not an empty stream |
| an object key with a literal dot, space, or operator-like punctuation must be read strictly | use bracket-quoted syntax `.["a.b"]` / `.obj["a.b"].name` or dot-quoted syntax `."a.b"` / `.obj."a.b".name`; an absent key/null yields JSON null but wrong-type inputs still raise structured errors; bare `["a.b"]` is an array constructor and bare `"a.b"` is a string literal |
| whitespace is present after an audited dotted separator before a literal bracket | `.items[0] . [1]` and `.items[0] . ["a.b"]` now keep their explicit rooted path; numeric/quoted/iterator suffix semantics and strict/optional error boundaries are unchanged |
| whitespace separates a rooted path stage from a computed selector | `. [.key]`, `.obj [ .key ]` and `.arr [ .idx ]?` use the original input for the simple dotted selector, preserve strict/optional lookup boundaries, and never reclassify bare `[.key]` or `try [.key]` constructors |
| whitespace appears before a dot separating audited path stages | `.items[0] .name` and `.obj["a.b"] .name` follow the same strict/optional stages as unspaced paths; `.items[0]. name` is not jq syntax and pure unquoted field-only paths retain existing handling |
| custom `try recurse(f)` discarded completed nodes when a later child filter or pipeline tail raised an error | custom child filters now use the demand-driven recurse visitor; earlier depth-first outputs remain visible, and the handler runs once at the first error |
| strict `try recurse(.[])` lost completed nodes or failed to catch a later leaf iteration error | each node is emitted first, then its strict `.[]` children are requested; an invalid leaf triggers catch after prior outputs, while `recurse(.[]?)` continues to skip invalid leaves |
| `try (recurse | f)` or `try (recurse(.[]?) | f)` lost completed ancestor/sibling outputs on a later error | default and optional-child recurse heads now visit recursion values on demand, preserving completed output and stopping before unused descendants after an error |
| `try (range(...) | f)` lost earlier generated numbers when a later tail value raised an error | a simple range head is now generated on demand; completed earlier tail outputs remain visible before catch, while later range values are not requested |
| three or more simple `[]` / `[]?` stages in a `try` head lost earlier completed member results or returned null | literal root and named-field iterator chains now visit each nested stage in order, retain completed outputs, and let strict/optional semantics apply at each level; arbitrary computed paths/generators remain separately scoped |
| bare `try .[][]` or `try .items[][]` yielded null or missed earlier completed nested members | bare two-level iterators now visit each member and emit it directly, preserving strict/optional errors and completed prior outputs before catch; arbitrary deeper paths still require audit |
| a `try (.[][] | f)` or `try (.items[][] | f)` pipeline lost completed inner members on a later error | two-level iterator heads are visited member by member; a failing inner iterator or tail stops further members, preserving already completed outputs, with optional `[][]?` still skipping non-iterable members |
| a `try (.items[] | f)` pipeline lost completed named-field iterator results after a later error | simple named-field `[]` / `[]?` heads now retain completed element outputs and preserve strict versus optional head errors; nested iterators and generators remain separately scoped |
| `try (source | (recurse(.items[]? | child_filter) | tail))` lost completed named-field child outputs before a later error | nested named-field optional child pipelines now use the existing demand-driven recurse visitor, retaining earlier nodes in depth-first order |
| `try (source | (recurse(.[]? | child_filter) | tail))` discarded previously completed recursive nodes on a later child-filter error | parenthesized optional-iterator custom child pipelines now reuse the existing streamed recurse visitor; completed nodes survive errors before catch |
| `try (source | (recurse(.[]) | f))` lost an already yielded scalar/null node before a strict child-expansion error | nested literal strict recurse now emits each value and completes its tail before strict child expansion, preserving completed outputs before catch |
| `try (source | (recurse | f))` and optional-child forms dropped earlier nodes after a later tail error | parenthesized default and optional-child recurse pipelines now use the demand-driven visitor, preserving ancestor and sibling outputs before catch |
| `try (source | (range(...) | f))` discarded earlier completed nested generator values when a later `f` input failed | the existing demand-driven visitor now covers fully parenthesized nested literal range pipelines with or without comma alternatives; earlier values remain before catch |
| `try (source | ((range(...) | f), fallback))` lost completed generator outputs when a later element of `f` failed | nested literal range pipelines in parenthesized comma alternatives now stream their completed results before the catch handler and do not evaluate later siblings after error |
| `try (source | ((a, b), c))` lost output from completed nested comma alternatives when a later inner alternative errored | the continuation stack now expands fully parenthesized nested alternatives, preserving completed inner output and downstream suffixes before catch |
| `try (source | (a, b) | (c, d))` lost completed results when the second comma stage failed | multiple parenthesized comma stages now execute in depth-first order with completed suffix output preserved before the first error |
| a `try (source | (a, b) | f)` pipeline lost completed middle-stage results if a later comma alternative failed | fully parenthesized middle comma alternatives now feed the downstream suffix in source order, before proceeding to the next alternative or generator input |
| a `try (source | (a, b, c))` pipeline lost outputs from earlier completed final-stage comma alternatives after a later error | parenthesized final comma alternatives now run in order for each preceding input; the first error stops later alternatives and generator inputs, preserving completed output before catch |
| a `try ((a, b, c) | f)` pipeline lost output from completed head alternatives when a later alternative or tail raised an error | parenthesized comma-head alternatives now feed the pipeline one at a time; earlier completed outputs remain visible before catch |
| a `try (.[] | f)` pipeline lost completed earlier element results when a later element failed | completed elements now retain their output before the error fallback; later elements are skipped, while partially failing individual members and other iterator forms remain outside the scoped change |
| earlier results inside a `try` comma expression disappeared after a later error | completed earlier comma branches now retain their output, and a `catch` fallback follows them; partial results inside an individual failing branch still need a separate streaming audit |
| a `catch` handler assumed the original JSON input | `catch` now evaluates on the error message string, like jq 1.7; bind the original value first with `. as $original | try ... catch $original.field` when needed; the legacy `$error` alias is retained as an extension |
| a `catch` handler deliberately emits no results | the handler now preserves an empty stream instead of synthesizing JSON null; use `catch null` to emit a visible null |
| an explicit `catch` handler error was replaced with JSON null | a failing handler now raises a runtime error; use an outer `try` when intentional suppression or a fallback is needed |
| an unhandled `try` error used to appear as JSON null | `try f` now emits nothing when `f` fails, equivalent to `try f catch empty`; use `try f catch null` when a visible JSON null is intended, while successful `try null` still emits one null |
| a `try` expression directly constructs an empty array | `try []` and `try [ ]` now emit one `[]` instead of triggering a synthetic `.[]` iterator; this includes comma branches, without changing `.[]` or `keys[]` suffixes |
| spaces appear inside or before an iterator bracket | `.items [ ]`, `.items [ ]?`, and `. [ ]` use the same strict/optional iteration as `[]`/`[]?`; bare `[ ]` still constructs an empty array and `try [ ]` is not a path |
| whitespace separates a path stage from a quoted field bracket | `. ["a.b"]`, `.obj [ "a.b" ]` and `.obj [ "a.b" ]?` now match unspaced bracket-quoted lookups; missing/null stay one null and strict wrong types remain errors, while bare `[ "a.b" ]` is still an array constructor |
| whitespace separates a path stage from a numeric index | `. [0]`, `.items [ -1 ]` and `.items[0] [1]` now match their no-space equivalents; `[N]?` keeps stage-local optionality, while slices, computed brackets and bare array constructors remain separate |
| spaces are present inside a literal numeric index | `.[ 0 ]`, `.items[ -1 ]`, and `.items[ 0 ]?` have the same v3 semantics as their unspaced forms; optional `?` stays outside `]`, and slices/computed expressions keep their separate handling |
| a strict standalone nonnegative array index is required | use `.[0]` or `.items[0].name`; arrays and JSON null preserve one value (possibly null), but wrong-type numeric targets still raise errors; use `[0]?` only to omit wrong-type outputs |
| a strict standalone negative array index is required | use `.[-1]` or `.items[-1].name`; negative positions count from the end, out-of-range/null produce JSON null, and wrong-type targets still raise errors; use `[-1]?` only to omit wrong-type index outputs |
| a literal numeric index should skip invalid object/scalar targets | put `?` immediately after that index, e.g. `.[0]?`, `.items[0]?`, `.items[][0]?` or `.obj[.key][0]?`; null and out-of-range array indices still produce JSON null, and later strict operations may still fail |
| a named field lookup should omit wrong-type values | append `?` immediately to that field, e.g. `.name?`, `.cfg?.name`, `.items[].name?` or `.items[]["a.b"]?`; this skips invalid types but keeps missing keys and JSON null as one null output, and does not suppress earlier/later strict lookup errors |
| `path |= filter` expecting only the updated leaf | no single appended filter preserves this result in both versions; keep the original filter on 2.x, and only after requiring 3.0 append the path projection or select the leaf in version-aware application code |

Release notes must include concrete, executable examples for each committed
change. Library consumers should also review code that assumes `run_query`
returns no value for a missing field; in 3.0 that query returns one JSON null.

## 3.0 release criteria

JQ::Lite 3.0 is ready only when:

- every **change in v3** inventory row is implemented or explicitly deferred
  with a documented reason;
- every changed behaviour has jq 1.7 differential coverage and a direct
  JQ::Lite regression test;
- all preserved and still-undecided inventory rows remain covered;
- CLI and Library API contract suites pass unchanged;
- migration notes cover every intentional output or error change; and
- the complete distribution test suite passes on the supported Perl range.
