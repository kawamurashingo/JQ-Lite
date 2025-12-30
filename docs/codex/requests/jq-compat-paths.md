# Codex Request: jq-compat `paths` / `paths(scalars)`

## Summary
Add jq-compatible `paths` and `paths(scalars)` to `jq-lite`.

These filters must stream JSON paths as arrays, matching jq semantics.

## Specification

### `paths`
- When the input is an **object** or **array**, stream **all reachable paths** (each path is an array).
- **Include the path to object/array values themselves** (not only leaf scalars).

Example:
Input:
```json
{"a":[1,2]}
````

Filter:

```jq
paths
```

Expected streamed paths (order not important):

```json
["a"]
["a",0]
["a",1]
```

Notes:

* The root path `[]` is **not** required by this spec (keep consistent with examples above).
* Keys are strings, array indices are numbers.

### `paths(scalars)`

* Stream only the paths that reach **scalar values**:

  * `null`, `boolean`, `number`, `string`
* Do **not** emit paths to intermediate objects/arrays unless they are scalars (they are not).

Example:
Input:

```json
{"a":[1,{"b":true}], "c":null}
```

Filter:

```jq
paths(scalars)
```

Expected (order not important):

```json
["a",0]
["a",1,"b"]
["c"]
```

### Scalar input behavior (important)

For both `paths` and `paths(scalars)`:

* If the input itself is a **scalar** (`null/bool/number/string`),

  * Do **not** error
  * Produce an **empty stream** (stdout empty)
  * Exit code **0**

Example:
Input:

```json
1
```

Filter:

```jq
paths
```

Expected: no output, exit=0

## Tests to add

Add regression tests for the following 3 cases (verify as a **set**, order-independent):

### Case 1: `paths` includes container-value paths

Input:

```json
{"a":[1,2]}
```

Filter:

```jq
paths
```

Expected set:

* `["a"]`
* `["a",0]`
* `["a",1]`

### Case 2: `paths(scalars)` emits only scalar-leaf paths

Input:

```json
{"a":[1,{"b":true}], "c":null}
```

Filter:

```jq
paths(scalars)
```

Expected set:

* `["a",0]`
* `["a",1,"b"]`
* `["c"]`

### Case 3: scalar input yields empty stream (no error)

Input:

```json
1
```

Filters:

```jq
paths
paths(scalars)
```

Expected:

* stdout empty
* exit=0

## Error contract (must preserve)

If implementation fails at runtime:

* stderr must start with `[RUNTIME]`
* exit code must be `3`
* stdout must be empty

## Implementation notes (guidance)

* Paths are arrays of components where:

  * object keys are strings
  * array indices are numbers
* Output should be streamed (one JSON array per path), consistent with jq-lite’s streaming model.
* Test order must not rely on hash ordering; compare as an unordered set.

