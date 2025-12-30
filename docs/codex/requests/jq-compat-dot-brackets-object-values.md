# Codex Request: jq-compat for `.[]` on objects

## Summary
`jq-lite` currently supports `[]` iteration for arrays but outputs nothing when `.[]` is applied to an object.
This diverges from `jq`, where `.[]` iterates over **object values**.

## Expected jq behavior (reference)
Input (`users.json`):

```json
{
  "users": [
    { "name": "Alice", "age": 30 },
    { "name": "Bob", "age": 25 }
  ]
}
````

Command:

```sh
jq .[] users.json
```

Output (value of `"users"` emitted once):

```json
[
  { "name": "Alice", "age": 30 },
  { "name": "Bob", "age": 25 }
]
```

## Current jq-lite behavior

```sh
jq-lite '.[]' users.json
```

Produces **no output**.

The following do work:

```sh
jq-lite '.users' users.json
jq-lite '.users[]' users.json
jq-lite 'keys' users.json
```

## Requested change

Update the implementation of the `[]` operator:

* If input is an **array** → iterate over elements (current behavior)
* If input is an **object** → iterate over its **values** (jq-compatible)
* Otherwise → keep existing policy (runtime error or empty stream; do not change)

This should apply to both:

* `.[]`
* `.foo[]` where `.foo` resolves to an object

## Notes

* Output order for object values does not need to be stable.
* Add regression tests.

## Suggested minimal tests

### Object with a single key

Input:

```json
{"users":[1,2]}
```

Filter:

```jq
.[] 
```

Expected:

```json
[1,2]
```

### Object with multiple keys (order not important)

Input:

```json
{"a":1,"b":2}
```

Filter:

```jq
.[] 
```

Expected (any order):

```text
1
2
```

```
