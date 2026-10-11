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

### Null, fallback, and paths

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

Numeric-looking strings are now rejected by numeric arithmetic in the 3.x
developer-release series; callers that intend conversion should use
`tonumber()` or `to_number()` explicitly. Regex scalar coercion remains
undecided and is not changed by the arithmetic work.

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

For literal paths, unquoted names, JSON-quoted keys, and adjacent
`[]`/`[]?`/`[integer]`/`[integer]?` steps are supported
when there is an iterator, computed selector, **or optional literal
numeric index**. Standalone strict-only numeric and field paths
(with no iterator, computed selector or optional numeric index)
continue using the existing query-path implementation.
The compatibility-sensitive internal traversal helper, implicit array
projection, slices, and arbitrary optional expressions remain unchanged.
Existing object iteration order remains unchanged.

Standalone `.[]?` is also available in a pipeline (including
`recurse(.[]?)`). Non-path array-result suffixes `keys[]?`,
`split(",")[]?`, and `[4,5][]?` lower to an optional iteration stage,
with the same rule independently applied inside comma alternatives.
Errors from upstream functions are not converted to empty results.
Computed (non-literal) path segments beyond simple dotted-field
selector expressions `[.field]`, composite literal paths with no iterator,
arbitrary optional expressions, and more general iterator compositions
still require separate audits beyond the scoped support described above.

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
| a literal numeric index should skip invalid object/scalar targets | put `?` immediately after that index, e.g. `.[0]?`, `.items[0]?`, `.items[][0]?` or `.obj[.key][0]?`; null and out-of-range array indices still produce JSON null, and later strict operations may still fail |
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
