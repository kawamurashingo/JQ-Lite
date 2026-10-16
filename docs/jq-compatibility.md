# jq compatibility in JQ::Lite 3.x

This guide describes the current `3.00_01` development series against **jq
1.7.x**. The practical v2.59 feature set is the baseline. Version 3 improves
selected semantics and maintenance while retaining pure Perl, Perl 5.14,
the existing dependencies, and the `new` / `run_query` public API.

For changes from v2, start with the [migration guide](v3-migration.md).
The [function reference](FUNCTIONS.md) lists available functions; the scope
and input types below determine the jq compatibility claim.

## Status meanings

| Status | Meaning |
| --- | --- |
| Compatible | The listed form/input scope has live jq 1.7 output and success/runtime-error coverage. |
| Documented difference | JQ::Lite retains the stated result, error or v2 extension; jq interchangeability is not promised. |
| Unsupported | The form is outside the supported contract. Some forms are explicitly rejected; legacy fallbacks are not proof of support. |
| Planned | A separately approved change awaiting implementation. No additional feature or public API is required by this checkpoint. |

Undecided semantic-inventory rows retain their current behavior until a
separate decision. They are not automatically planned fixes. The compiled
query proposal is deferred beyond this release: use `new` and `run_query`;
there is no public `compile()` API in the current scope.

## Practical compatibility matrix

| Area | Compatible forms / input scope | Boundaries and references |
| --- | --- | --- |
| Identity and fields | `.`, ordinary object fields, builtin-name fields such as `.type`, missing/null object fields | Array projection and ordinary scalar-field errors differ; see below. |
| Literal indices and optional access | Audited positive/negative array indices, null/out-of-range results, stage-local optional field/index/iterator access | An optional stage does not suppress errors from earlier/later strict stages. |
| Array iteration and slicing | Array `.[]` / `.[]?`, ordinary array bracket slices, audited named-field iterator paths | Object traversal can sort keys; JSON object insertion order is not a stream-order promise. String bracket slicing differs. |
| Function/constructor suffixes | Audited `keys[]`, `split(",")[]`, `[1,2][]`, comma-local suffixes | This does not establish arbitrary filter/suffix composition. |
| Streams and constructors | Audited comma order, empty versus null, `[empty]`, `{x:empty}`, selected `select(...)` constructor forms | Object fields retain first-value selection; full jq Cartesian object construction is outside this claim. |
| Arithmetic | JSON-type-sensitive `+`; numeric `-`, `*`, `/`, `%` and unary minus; existing simple arithmetic predicates | Numeric-looking strings require conversion; several nonnumeric jq overloads are absent. See [arithmetic contract](v3-arithmetic.md). |
| Comparison and type | Six comparisons over audited JSON values/operands; `type`; named-field predicates | Eager operands and retained path extensions limit general streaming parity. |
| Fallback | Audited literal/current-value/named-field `//` forms, including false/null and empty-array fallback | Existing first-result/filter-operand limits remain. |
| Containment | Literal-argument `contains` for strings, arrays, objects and JSON scalar identity | `inside`, `contains_subset` and infix `contains` retain distinct v2 meanings. |
| String search and text | Audited string `index`, `rindex`, `indices`, UTF-8 text boundaries | Positions follow jq 1.7 UTF-8 byte offsets; array/coercion search policies remain v2 extensions. |
| Regex | Audited string/literal-argument forms such as `test("^a"; "i")`, `match("lph"; "i")` | Scalar coercion, flags and regex behavior have scoped tests; full jq regex facilities are not implied. |
| Path-array functions | Audited `getpath`, `setpath` and `delpaths` literal path arrays | v2 numeric-string/boolean index extensions remain; see the [path audit](v3-practical-path-audit.md). |
| Update assignment | Audited simple `.a \|= filter` and existing array/object iterator targets | Old-target RHS, root result, empty deletion and first-result behavior are covered. General multi-target forms are unsupported. |
| Ordinary/compound assignment | Listed matching cases only | Existing null/type/coercion differences and rejected targets are explicit in the [assignment audit](v3-assignment.md). |
| `try` and recursion | Audited catch input, empty/no-catch behavior and selected iterator/range/recurse pipelines | General leaf filters remain eager; arbitrary partial-output streaming and deep combinations are not promised. |

The matrix describes a subset, not a general jq grammar. A fixture for one
composition does not establish all combinations of its parts. Rare deep
computed-selector/try/recurse combinations and new syntax coverage are not
release requirements.

## Retained differences and extensions

| Behavior | Current JQ::Lite result / policy |
| --- | --- |
| `[{"x":1},{"x":2}] \| .x` | Projects `1`, `2`; jq reports a type error. |
| `7 \| .name` | Emits nothing; jq reports a type error. |
| `"abcd" \| .[1:3]` | Passes the string through; jq returns `"bc"`. |
| `slice(start,length)` | v2 length-based extension; not jq bracket slicing. |
| `unique_by`, grouping and smart sorting | Retain their recorded v2 key/signature/order policies; do not assume jq ordering for mixed values. |
| Statistical/convenience helpers | `avg`, `median`, `mode`, `percentile`, `variance`, `stddev`, `sum_by`, `drop`, `tail`, `chunks` and related helpers retain documented v2 behavior. |
| Jagged `transpose` | Truncates to the shortest row. |
| Vectorized/lossless helpers | `floor`, `fromjson`, `to_number` and related extensions retain their scoped v2 conversion/passthrough policies. |
| Ordinary/compound assignment | Includes unchanged null-root behavior, compound coercion and ignored zero-divisor cases; see its dedicated audit. |

User-defined `def`, labels/`break`, imports/modules, jq `--stream`, general
multi-target assignment and unadvertised filter-valued plain RHS are outside
the supported subset. Unsupported plain/compound bracket targets now raise a
structured runtime error before a legacy setter can assign a truncated prefix.

## CLI, Library and verification

The [CLI contract](cli-contract.md) retains its own exit categories:
0 success, 1 false/null/empty with `-e`, 2 compile, 3 runtime, 4 input and
5 usage. Error output stays on stderr with its stable prefix and stdout stays
empty. Compile-before-input and SIGPIPE/EPIPE behavior are unchanged.
These numeric exit codes are not an upstream jq exit-code compatibility claim.

The [Library contract](library-contract.md) keeps `new`, `run_query`, list
results, documented options and structured error categories. Query-language
semantic changes are described in the migration guide. Internal parser,
evaluator and builtin packages remain private.

This checkpoint has 4,031 differential fixtures: 3,940 compatible, 74 known
differences and 17 unsupported. Compatible fixtures compare live ordered JSON
results or runtime-error categories. Known differences are diagnostic rather
than jq-lite parity gates; dedicated Library regressions protect selected
current outcomes. Unsupported fixtures do not claim live jq-lite parity.
Exact jq diagnostic wording is not compared.

```sh
prove -lr t
JQ_DIFFERENTIAL=1 prove -l t/jq_differential.t
```

The ordinary distribution suite requires no jq installation. The optional
differential suite requires jq 1.7.x and documents its format and limitations
in [differential testing](jq-differential-testing.md). For a new query,
check the matching form and input types, run a focused regression with the
intended data, and retain its output/error/cardinality expectations.

The [roadmap](v3-roadmap.md) and [semantic inventory](jq-semantics-differences.md)
track the remaining decisions. This guide is a development compatibility
checkpoint; it does not announce a stable 3.0 release or change main/2.x.
