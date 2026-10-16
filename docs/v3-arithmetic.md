# JQ::Lite 3.x practical arithmetic contract

This contract covers the binary and unary arithmetic already accepted by
the practical v2 expression evaluator. It specifies the selected v3 type
correction, not full jq operator overloading or new expression grammar.
The public entry points remain `new` and `run_query`; Perl 5.14 and the
existing dependency set are retained.

## Binary and unary operators

`+` keeps JSON types distinct:

| Operands | Result |
| --- | --- |
| Either operand is JSON null | The other operand, including false or a container |
| Two numbers | Numeric addition |
| Two strings | Concatenation, including numeric-looking strings |
| Two arrays | Concatenation in left-to-right order |
| Two objects | Shallow merge; the right value wins for a duplicate key |
| All other pairs, including two booleans | Structured runtime type error |

`-`, `*`, `/` and `%` accept two JSON numbers. Unary `-` accepts one JSON
number. Null, booleans, strings and containers are not implicitly converted
to numbers. Scientific notation in a JSON numeric literal remains numeric;
the JSON string `"1e3"` remains a string. Use `tonumber` or `to_number`
explicitly when conversion is intended. `/` and `%` with a zero divisor
raise structured runtime errors. Addition with supported piped operands uses
the same private primitive, including its structured type errors.

Existing expression precedence and parentheses remain in place: `1+2*3`
is 7, and `(1+2)*3` is 9. Ordinary named-field operands use the established
scalar path resolver and its first-result behavior. This does not promise
full jq streaming arithmetic, arbitrary variable expressions or exact jq
diagnostic text.

## Arithmetic predicates and constructors

The existing simple predicate spelling, for example
`select(.n + 1 > 2)`, now evaluates its arithmetic operand through the same
typed expression evaluator. Numeric-looking strings and booleans raise
errors instead of being coerced; division/modulo by zero raises an error
instead of silently making the condition false. Missing/null fields have
the same arithmetic meaning as an explicit null: `.n + 1` is 1, while
`.n - 1` is a type error. All six existing comparison operators use the
shared JSON comparator after arithmetic evaluation.

The existing predicate matcher is unchanged: a single named field, one
arithmetic operator, a decimal numeric literal, a comparison and a decimal
numeric literal. This correction does not add nested-field, variable or
scientific-notation *predicate spelling*. A field's scientific-notation
numeric value is supported as before.

`and` / `or` retain short-circuit behavior. A skipped predicate does not
raise its unused error; a required failing predicate does. An empty upstream
stream does not evaluate a downstream predicate.

`select(...)` remains a filter when used in a supported array/object
constructor. It emits the original input or nothing, rather than a boolean
for its inner comparison. Thus `{"n":3} | [select(.n + 1 > 0)]` emits
`[{"n":3}]`, while `{"n":-3} | [select(.n + 1 > 0)]` emits `[]`.
An object field with an empty `select` result suppresses the object, and
arithmetic errors inside either constructor propagate normally.

## jq boundary and reproducible coverage

The arithmetic snapshot in `t/data/jq-differential.jsonl` has 408 cases:

| Scope | Cases |
| --- | ---: |
| Five binary operators over eight representative values on both sides | 320 |
| The existing arithmetic predicate over those eight values | 40 |
| Unary minus over those eight values | 8 |
| Error, conversion, numeric, comparison, map, try and constructor boundaries | 40 |

The eight representatives are null, false, true, a number, a numeric-looking
string, another string, an array and an object. The 408 cases have **396 jq
1.7-compatible outcomes** and **12 documented differences**. These are
representative values and accepted forms, not an exhaustive numeric-precision
or expression-grammar conformance claim.

The twelve differences are ten binary cases and two predicate cases where
jq provides nonnumeric overloads outside this practical numeric scope:

| jq operation | JQ::Lite 3.x behavior |
| --- | --- |
| Array subtraction | Runtime type error |
| String/number multiplication in either order | Runtime type error |
| Recursive object multiplication/merge | Runtime type error |
| String/string division into substrings | Runtime type error |
| String repetition inside an arithmetic predicate | Runtime type error |

They remain `known-difference` fixtures, not compatibility claims or new
release requirements. `arithmetic_v3` metadata records the current result or
structured error for the dependency-free Library regression. The normal
differential runner still executes the real jq and jq-lite CLIs for each
fixture and gates compatible output/error categories.

```sh
prove -l t/arithmetic.t t/v3_arithmetic_contract.t
JQ_DIFFERENTIAL=1 prove -l t/jq_differential.t
```

## Migration from v2

- `"1e3" * 1` no longer coerces the string. Use
  `"1e3" | tonumber | . * 1` to request numeric conversion. To concatenate
  strings, `"1" + "2"` still returns `"12"`.
- `true + 1` is now a type error. Choose an explicit numeric value in the
  application when a boolean was intended to represent 0 or 1.
- For a numeric-string field, normalize it before filtering, for example
  `(.n |= tonumber) | select(.n + 1 > 2)`.
- `select(.n / 0 > 0)` now raises a runtime error. If deliberately dropping
  failing inputs is intended, write `try select(.n / 0 > 0) catch empty`.
- A missing/null field is not an empty arithmetic operand: its addition
  identity may now select an input that v2 dropped. Validate the field before
  arithmetic when null/missing values must be excluded.
- Constructor callers that worked around the former `[false]` result for
  `[select(...)]` should remove that workaround and handle the selected
  original value or the empty result directly.

Runtime errors keep the public CLI runtime category (exit 3) and structured
`JQ::Lite::Error::Evaluation` Library error. Existing CLI stdout/stderr,
compile-before-input and pipe behavior remain covered by the contract suite.
Plain and compound assignment are separate scopes under #626; this contract
does not silently give `+=`, `-=`, `*=` or `/=` new semantics.
