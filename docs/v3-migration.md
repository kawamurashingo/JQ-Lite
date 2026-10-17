# Migrating JQ::Lite 2.x filters to v3-dev

This guide is for evaluating existing **stable 2.x** filters against the
current **unreleased v3 development branch**. It is not an upgrade instruction
for a published 3.0 distribution. Start with the
[jq 1.7 compatibility matrix](jq-compatibility.md) and the
[2.x behavior inventory](jq-semantics-differences.md). The practical v2
feature set is the baseline; do not rewrite working queries merely to use
extra jq syntax.

## Migration checklist

1. Keep `main` / 2.x deployed until the application-specific filters and
   error handling have been tested on the v3 candidate.
2. Record **all outputs in order**, including the difference between no
   output, one JSON `null` and a structured error.
3. Audit numeric-looking strings, booleans, comparisons and `//` fallbacks
   first; these are intentional semantic corrections in v3.
4. Review `contains`, string search positions and ordinary path access.
   Keep existing JQ::Lite extensions where their special meanings are needed.
5. Audit `=`, `|=` and compound assignments **separately**: they do not all
   follow the same numeric, path or result-stream rules.
6. Run `prove -lr t`, the optional jq 1.7 differential suite, and your own
   CLI/Library application fixtures before shipping.

## Query behavior that changes

The examples below refer to **representative, audited forms**, not every
arbitrary jq filter. A quoted JSON literal means a JSON string, not a number.

| Input and filter | Stable 2.x behavior | Current v3-dev behavior | Migration action |
| --- | --- | --- | --- |
| `true;` `. + 1` | Boolean coerces to 1, producing 2. | Runtime type error. | Make booleans explicit numeric values in upstream data if numeric arithmetic is intended. |
| `"1e3";` `. * 1` | Coerces to 1000. | Runtime type error for string-times-number in the scoped arithmetic evaluator. | Use `tonumber` before numeric arithmetic. |
| `"10";` `. == 10` | Numeric-looking string compares equal. | `false`. | Normalize inputs or compare a number with a number. |
| `[1,2];` `. < [1,3]` | `false`. | `true` by lexicographic ordering. | Review comparisons that previously depended on array ordering. |
| `false;` `. // 9` | Keeps `false`. | Returns `9`. | Test for `null` separately in application code if `false` is meaningful. |
| `{};` `.missing` | No results in the direct-path subset. | One JSON `null`. | Distinguish an absent value from an empty stream. |
| `{};` `.[5]` | May emit a JSON `null`. | Structured runtime error. | Guard the container type before indexing. |
| `[1,2,3];` `contains([1,3])` | `false` (single array element equality). | `true` (recursive subset containment). | Use `index([1,3]) != null` to retain exact whole-element lookup. |
| `"日本語";` `index("本")` | Character index 1. | UTF-8 byte offset 3. | Convert byte positions at the integration boundary if character offsets are required. |
| `{"a":1};` `.a \|= . + 1` | Emits only the updated target `2`. | Emits the updated root `{"a":2}`. | Remove any wrapper that reconstructed the root from the target. |
| `{"a":1};` `.a \|= empty` | No jq-equivalent deletion guarantee. | Deletes `a`, emits `{}`. | Use `|= null` when a null-valued key must be kept. |
| `{"a":[1,2,3]};` `.a[0:1] = [9]` | Could silently replace the whole `a` prefix. | Structured runtime error before mutation. | Use a supported literal index or a separate explicit transformation. |

In particular, do not apply the numeric-expression migration rules to the
compound setters. `{"n":"2"} | .n += 2` still coerces the field
and yields `{"n":4}` in v3-dev. That is a **known difference** from jq 1.7,
not a claim of type-safe compound assignment.

## Practical rewrites

### Convert deliberate numeric text before arithmetic

```sh
# For input {"n":"2"}, convert first, then use typed arithmetic.
jq-lite '(.n |= tonumber) | .n + 2'
```

The v3 arithmetic contract distinguishes `tonumber` and the JQ::Lite
extension `to_number()`. Boolean-as-number conversion should be explicit in
the caller; it is not an automatic 3.x coercion.

### Review fallback and missing-field streams

`false // 9` now returns 9, like jq. A plain `.missing` on `{}`
returns one JSON null, but `[] | .[]` still emits nothing. When consuming
`run_query` results, check **list length** before inspecting the value:
an empty list and a one-element list containing `undef` do not mean the
same thing.

### Migrate containment by *intent*

- For recursive jq-like inclusion, use v3 `contains(value)`.
- For v2's **exact array element** existence, use
  `index(value) != null`; for object key existence, use `has(key)`.
- For the v2 `contains_subset(value)` multiset extension, keep using that
  extension intentionally. It differs from both v3 `contains` and jq.

For example, searching for an entire array element `[1,3]` in
`[1,2,3]` is **not** the same as checking whether both 1 and 3 are
recursively contained.

### Audit assignment operators independently

- `.a = 2` updates the root for the supported ordinary field target.
  Ordinary assignment on a null root still differs from jq: it leaves null
  unchanged in the audited v3 subset.
- `.a |= filter` uses the **old target value** as RHS input and emits the
  updated root; an entirely empty RHS deletes a target, while an explicit
  JSON null retains a null-valued target. Supported multi-result RHS uses the
  first result.
- `.a += 2`, `-=`, `*=`, `/=` retain audited v2 coercion/no-op
  boundaries. Do not assume they inherit the stricter binary-expression
  rules or full jq path syntax.
- Slice, computed and iterator brackets are **not** supported as ordinary
  assignment targets. V3 rejects unsupported bracket spellings instead of
  discarding the bracket and writing a prefix.

See the [assignment audit](v3-assignment.md) before changing a setter.
The broader multi-path/plain-RHS and invalid-target choices remain open
under [#626](https://github.com/kawamurashingo/JQ-Lite/issues/626).

## Interfaces that stay stable

The CLI exit categories remain: success 0; `-e` false/null/empty 1;
compile 2; runtime 3; input 4; usage 5. On errors, stdout stays empty
and stderr starts with the corresponding bracketed category. Filter
compilation precedes input parsing and normal broken-pipe behavior remains
protected. See the [CLI contract](cli-contract.md); human-readable error
wording is not a jq compatibility guarantee.

For Perl callers, keep the documented public entry points:

```perl
use JQ::Lite;
my $jq = JQ::Lite->new;
my @values = $jq->run_query('{"a":1}', '.a');
```

`run_query` returns a Perl **list** of ordered results. The
`JQ::Lite::Error::{Input,Parse,Evaluation}` classes allow category-based
handling; do not parse the exact text of an exception. See the
[Library API contract](library-contract.md). A public `compile()` method
is **not** part of the current v3 requirement; proposal #627 is deferred.

V3 continues to target Perl **5.14+**, with no additional CPAN runtime
dependency. No semantic changes in this guide are backports to stable 2.x.

## Verification

```sh
# Always available from a checkout; no jq executable needed.
prove -lr t

# Optional: requires an installed jq 1.7.x executable.
JQ_DIFFERENTIAL=1 prove -l t/jq_differential.t
```

Add application fixtures for every filter you actually use, checking the
ordered output stream and error category. The differential harness checks
documented fixtures against jq 1.7; it is not an exhaustive jq parser test.
Remaining path/iterator audit belongs to
[#625](https://github.com/kawamurashingo/JQ-Lite/issues/625).
