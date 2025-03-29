# JQ::Lite

**JQ::Lite** is a lightweight, pure-Perl JSON query engine inspired by the [`jq`](https://stedolan.github.io/jq/) command-line tool.  
It allows you to extract, traverse, and filter JSON data using a simplified jq-like query syntax — entirely within Perl.

## 🔧 Features

- Pure Perl (no XS, no external dependencies)
- Dot notation for key access (`.users[].name`)
- Optional keys (`.nickname?`)
- Array traversal and indexing (`.users[0]`, `.users[]`)
- Built-in functions: `length`, `keys`
- Filtering via `select(...)` with `==`, `!=`, `<`, `>`, `and`, `or`
- Usable as both a Perl module and a command-line tool

## 🤔 Why JQ::Lite (vs jq or JSON::PP)?

While [`jq`](https://stedolan.github.io/jq/) is a powerful CLI tool, **JQ::Lite** fills a different niche:

| Use Case | Tool |
|----------|------|
| Simple JSON parsing in Perl | ✅ `JSON::PP` |
| Powerful CLI processing | ✅ `jq` |
| Querying JSON inside Perl without shelling out | ✅ **JQ::Lite** |
| Lightweight, portable scripting with no non-core deps | ✅ **JQ::Lite** |
| jq-style syntax in Perl scripts (for filtering/traversal) | ✅ **JQ::Lite** |

JQ::Lite is particularly useful in environments where:
- You cannot install external binaries like `jq`
- You want to write reusable Perl code that dynamically handles JSON
- You want to keep dependencies minimal and avoid XS modules

## 🛠 Installation

```sh
perl Makefile.PL
make
make test
make install
```

Or just use it as a standalone script (see CLI usage below).

## 🚀 Usage

### As a Perl module

```perl
use JQ::Lite;

my $json = '{"users":[{"name":"Alice"},{"name":"Bob"}]}';
my $jq = JQ::Lite->new;
my @names = $jq->run_query($json, '.users[] | .name');

print join("\n", @names), "\n";
```

### As a CLI tool

```bash
cat users.json | ./script/jq '.users[] | .name'
```

Or install it globally:

```bash
ln -s script/jq ~/bin/jq
chmod +x ~/bin/jq
```

Then you can use it just like `jq`:

```bash
cat users.json | jq '.users[].name'
```

## 📘 Example Input

```json
{
  "users": [
    {
      "name": "Alice",
      "age": 30,
      "profile": {
        "active": true,
        "country": "US"
      }
    },
    {
      "name": "Bob",
      "age": 25,
      "profile": {
        "active": false,
        "country": "JP"
      }
    }
  ]
}
```

### Example Queries

```bash
jq '.users[] | .name'                 # => "Alice", "Bob"
jq '.users | length'                 # => 2
jq '.users[0] | keys'                # => ["age","name","profile"]
jq '.users[].nickname?'             # => No output, no error
jq '.users[] | select(.age > 25)'   # => {"name":"Alice",...}
jq '.users[] | select(.profile.active == true) | .name'
```

## 🧪 Testing

```sh
prove -l t/
```

## 📦 CPAN

This module is available on CPAN:  
👉 [JQ::Lite on MetaCPAN](https://metacpan.org/pod/JQ::Lite)

## 📝 License

This module is released under the same terms as Perl itself.

## 👤 Author

**Kawamura Shingo**  
📧 [pannakoota1@gmail.com](mailto:pannakoota1@gmail.com)  
🔗 GitHub: [https://github.com/kawamurashingo/JQ-Lite](https://github.com/kawamurashingo/JQ-Lite)
