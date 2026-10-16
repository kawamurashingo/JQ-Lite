# Migrating practical filters from JQ::Lite 2.x to 3.x

This guide covers the current `3.00_01` development semantics. Use the
[compatibility matrix](jq-compatibility.md) to check the supported query/input
scope. The baseline is v2.59; this guide does not require adding new jq syntax
or changing the public `new` / `run_query` API.

## Review the result stream before upgrading

The number and order of results matter as much as their values. In Library
code, one `undef` is a JSON null result; an empty Perl list means no results.
Check callers that used only the first result or treated these cases alike.

| Input / filter | v2 result | Current v3 result |
| --- | --- | --- |
| `{}` / `.missing` or `.missing.value` | No results | One JSON null |
| `{"type":"vm"}` / `.type` | Builtin-style `"object"` | Field value `"vm"` |
| `{"empty":null}` / `.empty` | No results | One JSON null |
| `false` / `. // 9` | false | 9 |
| `null` / `[empty]` | `[null]` | `[]` |
| `null` / `{x:empty}` | `{"x":null}` | No object result |
| `null` / `empty \| type` | `"null"` | No results |
| `{}` / `.[0]` | One JSON null | Structured type error |
| `null` / `.[]` | No results | Structured iteration error |
| `[10,20]` / `.[-1]` | One JSON null | 20 |

Use bare `type` / `empty` to invoke a builtin and dotted names to read fields.
Use an explicit null or an audited fallback when a visible null is intended.
Zero and the empty string remain valid values for `//`.

```perl
my @values = $jq->run_query('{}', '.missing');
# v3: @values has one member, whose value is undef.
```

## Keep JSON types explicit

| Expression | v2 | Current v3 |
| --- | --- | --- |
| `"10" == 10` | true | false |
| `[1,2] < [1,3]` | false | true |
| `true + 1` | 2 | Structured type error |
| `"1e3" * 1` | 1000 | Structured type error |

Convert deliberately before numeric arithmetic:

```text
"1e3" | tonumber | . * 1
(.n |= tonumber) | select(.n + 1 > 2)
```

String addition still concatenates: `"1" + "2"` is `"12"`. JSON numeric
scientific notation such as `1e3` remains numeric. The
[arithmetic contract](v3-arithmetic.md) describes the supported type pairs,
nonnumeric jq overload differences and the existing predicate spelling.

Simple arithmetic predicates now share the strict evaluator. A numeric string
is not implicitly accepted, null/missing has the normal addition identity,
and divide/modulo-by-zero errors propagate instead of making the condition
false. To deliberately drop failing inputs:

```text
try select(.n / 0 > 0) catch empty
```

Supported piped addition also raises structured Evaluation errors.
`[select(...)]` and `{x:select(...)}` now use the selected input or an empty
stream rather than converting the inner comparison to a boolean. Remove any
workaround that depended on the former `[false]`/false-field result.

## Review containment, search and UTF-8 boundaries

`[1,2,3] | contains([1,3])` and nested partial-object containment now use
recursive jq-style containment and return true. To request the former exact
array-element membership meaning, use `index(value) != null`. For an object
key, use `has(key)`. `contains_subset`, `inside` and infix `contains` retain
their separate v2 meanings; they are not aliases for the new containment.

String `index`/`rindex` with an empty needle now return null, and
`indices("")` returns an empty array. jq 1.7 string positions are UTF-8 byte
offsets: for `"日本x"`, `index("本")` is 3 rather than the v2 character
offset 1. Null input remains one null in the adopted string-search scope;
an empty upstream stream remains empty. Array-search/coercion extensions
retain their documented differences.

UTF-8 raw input, `--arg` and `--rawfile` text are decoded consistently; raw
CLI output is UTF-8. Valid UTF-8 text from Base64/JSON conversion is Library
character text. Keep one deliberate encoding boundary when writing Library
strings to a byte-oriented destination.

## Distinguish ordinary assignment from update

For the supported update paths, `{"a":1,"b":7} | .a |= . + 1` now emits
`{"a":2,"b":7}` rather than the leaf 2. A missing target is evaluated as
null and may be created. The RHS receives the old target; bind or arrange
root data explicitly if the computation needs it.

- Empty RHS deletes the selected key/slot; `|= null` keeps a null value.
- Multiple RHS values use the first accepted result, preserving null/false.
- Audited comma/pipeline/range/recurse first-result paths stop before unused
  later work; general leaf filters still have eager-evaluation limits.

Code expecting only the old leaf result needs version-aware migration; an
appended projection is not a universal query that preserves both v2 and v3
update behavior. After requiring v3, `(.a |= . + 1) | .a` projects the new leaf.

Ordinary `=` and compound `+=`/`-=`/`*=`/`/=` retain separate v2 differences,
including null-root and coercion/error policies. Do not infer their behavior
from the strict expression or `|=` contract. See the
[assignment audit](v3-assignment.md) before porting those forms.

Unsupported plain/compound bracket targets now raise an Evaluation error
instead of allowing an update to a truncated prefix. Replace a query such
as `.a[0:1] = [9]` with an explicitly supported operation for the intended
target; compact literal indices and the existing `|=` iterator subset remain
available. Multi-target and general multi-result plain assignment are outside
the supported subset.

## Handle `try`, CLI status and Library errors explicitly

`try f` drops a failing result, like `try f catch empty`; use `catch null`
when a visible null is wanted. A catch handler receives the error message
string, not the original JSON input. A failing catch handler propagates its
error. Selected streamed iterator/range/recurse paths retain completed values
before a later caught error; the roadmap lists their limits.

The CLI keeps its existing exit categories, stderr prefixes, clean stdout on
errors, compile-before-input and broken-pipe behavior. Runtime failure is exit
3, not an upstream jq exit-code promise. For filters starting with a minus,
put `--` before the filter:

```sh
printf '3\n' | jq-lite -c -- '-.'
```

The Library still returns a Perl list from `run_query` and exposes documented
Input/Parse/Evaluation error classes. Parser/AST/evaluator helpers stay
private; the deferred compiled-query proposal adds no required public API.

Before switching a caller, record its current v2 results, compare the
supported cases against the intended v3 behavior, and keep regressions for
values, output count/order and error category. The
[CLI](cli-contract.md), [Library](library-contract.md) and
[differential-testing](jq-differential-testing.md) contracts provide the
remaining checks. Undecided/deferred differences remain explicit in the
compatibility matrix and roadmap.
