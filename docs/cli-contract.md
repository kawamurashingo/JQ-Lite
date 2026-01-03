# CLI Contract (Stable)

This document defines the **stable, backward-compatible CLI contract** for `jq-lite`.
All behaviors documented here are guaranteed and enforced by automated tests. Breaking changes require a major version bump.

---

## Goals

* Shell scripts and CI must be stable (`if jq-lite …; then …; fi`)
* Follow `jq` conventions where practical
* Distinguish error categories via **exit codes** and **stderr prefixes**
* Keep **stdout clean on errors** (no unexpected stderr noise)

---

## Compatibility Guarantee

* This CLI contract is **stable**
* Any behavior described here is **backward-compatible**
* Breaking changes require:

  * a **major version bump**, or
  * an explicit compatibility flag (discouraged)

---

## Exit Codes

`jq-lite` returns one of the following exit codes:

| Code | Meaning                                                                 |
| ---- | ----------------------------------------------------------------------- |
| 0    | Success                                                                 |
| 1    | `-e/--exit-status` specified and result is false, null, or empty output |
| 2    | **Compile error** (filter parse error)                                  |
| 3    | **Runtime error** (evaluation failed)                                   |
| 4    | **Input error** (failed to read or decode input)                        |
| 5    | **Usage error** (invalid CLI arguments, invalid `--argjson`, etc.)      |

* Without `-e`, **empty output is considered success** (exit 0)
* `-e` affects only the **exit code**, not stdout formatting

---

## stdout / stderr Rules

### stdout

* On success (exit `0` or `1`): output may appear on **stdout**
* On errors (exit `2–5`): **stdout MUST remain empty**

### stderr

* On errors (exit `2–5`), a diagnostic message is written to **stderr**
* The **first line MUST start with a stable prefix**:

| Category | Prefix      |
| -------- | ----------- |
| Compile  | `[COMPILE]` |
| Runtime  | `[RUNTIME]` |
| Input    | `[INPUT]`   |
| Usage    | `[USAGE]`   |

Example:

```
[COMPILE] unexpected token at …
[RUNTIME] type mismatch at …
[INPUT] failed to parse JSON input: …
[USAGE] invalid JSON for --argjson x
```

---

## Truthiness (`-e/--exit-status`)

When `-e/--exit-status` is specified:

| Result               | Exit |
| -------------------- | ---- |
| truthy               | 0    |
| false / null / empty | 1    |

Truthiness rules (jq-style):

* `false` → falsey
* `null` → falsey
* empty (no output) → falsey
* everything else (`0`, `""`, `{}`, `[]`, etc.) → truthy

---

## Argument Semantics

### `--arg name value`

* Always binds `$name` as a **string**
* Missing value → **usage error** (`[USAGE]`, exit 5)

### `--argjson name json`

* Decodes `json` as JSON and binds to `$name`
* Scalar JSON values allowed: `1`, `"x"`, `true`, `null`
* Invalid JSON → **usage error** (`[USAGE]`, exit 5)

### `--argfile name file`

* Reads `file`, decodes as JSON, and binds to `$name`
* Missing/unreadable file → **usage error** (`[USAGE]`, exit 5)
* Invalid JSON → **usage error** (`[USAGE]`, exit 5)

---

## Broken Pipe (SIGPIPE / EPIPE)

When downstream closes the pipe early:

```sh
bin/jq-lite '.[]' | head
```

* `SIGPIPE` / `EPIPE` MUST NOT be treated as a fatal error
* `jq-lite` should exit `0` (or per `-e` rules)
* **No error output** should be printed to stderr

Rationale: This frequently occurs in pipelines and must not break scripts or CI.

---

## Examples

### Compile Error

```sh
jq-lite '.[ '  # stderr: [COMPILE] …, exit: 2
```

### Runtime Error

```sh
printf '{"x":"a"}\n' | jq-lite '.x + 1'
# stderr: [RUNTIME] …, exit: 3
```

### Input Error

```sh
printf '{broken}\n' | jq-lite '.'
# stderr: [INPUT] …, exit: 4
```

### `-e` falsey Result

```sh
printf 'false\n' | jq-lite -e '.'
# stdout: false, exit: 1
```

---

## Fully Supported Options

The following behaviors are fully supported and covered by tests:

* **Compile occurs before input parsing**
* `-e` truthiness fully matches jq (`0` is truthy)
* `-n / --null-input` is supported
* `-e` affects only exit code, not stdout format
* Pipeline (broken pipe) handling prints no stderr and exits normally

---

## Test-backed Guarantee

This contract is **enforced by automated tests**.
Any violation will fail CI:

```
prove -lv t/cli_contract.t
```

---

## Summary

* `jq-lite` provides a **stable, predictable CLI**
* Compatibility is **documented, intentional, and tested**
* Scripts, CI, and downstream tools can rely on this behavior

