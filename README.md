![JQ::Lite](./images/JQ_Lite_logo_small.png)

# JQ::Lite

[![MetaCPAN](https://img.shields.io/cpan/v/JQ::Lite?color=blue)](https://metacpan.org/pod/JQ::Lite)
[![GitHub](https://img.shields.io/github/stars/kawamurashingo/JQ-Lite?style=social)](https://github.com/kawamurashingo/JQ-Lite)

**JQ::Lite** is a lightweight, pure-Perl JSON query engine inspired by the [`jq`](https://stedolan.github.io/jq/) command-line tool.  
It allows you to extract, traverse, and filter JSON data using a simplified jq-like syntax — entirely within Perl.

---

## 🔧 Features

- ✅ **Pure Perl** (no XS, no external binaries)
- ✅ Dot notation (`.users[].name`)
- ✅ Optional key access (`.nickname?`)
- ✅ Array indexing and expansion (`.users[0]`, `.users[]`)
- ✅ `select(...)` filters with `==`, `!=`, `<`, `>`, `and`, `or`
- ✅ Built-in functions: `length`, `keys`, `first`, `last`, `reverse`, `sort`, `sort_by`, `unique`, `has`, `map`, `group_by`, `count`, `join`, `empty` (v0.33+)
- ✅ Pipe-style queries with `.[]` (e.g. `.[] | select(...) | .name`)
- ✅ Command-line interface: `jq-lite`
- ✅ Reads from STDIN or file
- ✅ **Interactive mode** for exploring JSON line-by-line
- ✅ `--use` option to select decoder (JSON::PP, JSON::XS, etc.)
- ✅ `--debug` option to show active JSON module

---

## 🤔 Why JQ::Lite (vs `jq` or `JSON::PP`)?

| Use Case              | Tool            |
|-----------------------|-----------------|
| Simple JSON decode    | ✅ `JSON::PP`    |
| Shell processing      | ✅ `jq`          |
| jq-style queries in Perl | ✅ **JQ::Lite** |
| Lightweight & portable | ✅ **JQ::Lite** |

---

## 📆 Supported Functions

| Function       | Description                                           |
|----------------|-------------------------------------------------------|
| `length`       | Get number of elements in an array or keys in a hash |
| `keys`         | Extract sorted keys from a hash                      |
| `sort`         | Sort array items                                     |
| `sort_by(key)` | Sort array of objects by field (v0.32)               |
| `unique`       | Remove duplicate values                              |
| `first`        | Get the first element of an array                    |
| `last`         | Get the last element of an array                     |
| `reverse`      | Reverse an array                                     |
| `limit(n)`     | Limit array to first `n` elements                    |
| `map(expr)`    | Map/filter values using a subquery                   |
| `add`, `min`, `max`, `avg` | Numeric aggregation functions       |
| `group_by(key)`| Group array items by field                          |
| `count`        | Count total number of matching items                 |
| `join(sep)`    | Join array elements with custom separator (v0.31+)   |
| `empty()`      | Discard all results (compatible with jq) (v0.33+)    |

---

## 🚀 Usage

### Example Queries

```bash
jq-lite '.users[].name' users.json
jq-lite '.users | length' users.json
jq-lite '.users[0] | keys' users.json
jq-lite '.users[].nickname?' users.json
jq-lite '.users[] | select(.age > 25)' users.json
jq-lite '.users[] | select(.profile.active == true) | .name' users.json
jq-lite '.users | sort_by(.age)' users.json
jq-lite '.users | map(.name) | join(", ")' users.json
jq-lite '.users[] | select(.age > 25) | empty' users.json  # new in v0.33
```

---

## 🤮 Testing

```bash
prove -l t/
```

---

## 📦 CPAN

👉 [JQ::Lite on MetaCPAN](https://metacpan.org/pod/JQ::Lite)

---

## 📝 License

This module is released under the same terms as Perl itself.

---

## 👤 Author

**Kawamura Shingo**  
📧 pannakoota1@gmail.com  
🔗 [GitHub @kawamurashingo](https://github.com/kawamurashingo/JQ-Lite)
