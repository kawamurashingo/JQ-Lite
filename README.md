# JQ::Lite

**JQ::Lite** is a lightweight, pure-Perl JSON query engine inspired by the `jq` command-line tool.  
It allows simplified jq-like querying of JSON data using dot notation and minimal syntax.

## 🔧 Features

- Pure Perl implementation (no XS, no external dependencies)
- Simple jq-like query syntax (e.g. `.users[] | .name`)
- Supports dot access, array traversal, optional keys, indexing
- Built-in functions: `length`, `keys`
- Filter support: `select(...)` with logical ops (`and`, `or`) and comparisons
- Can be used as a CLI tool (`script/jq` or symlink as `jq`)
- Useful for scripting, data extraction, teaching

## 🛠 Installation

```sh
perl Makefile.PL
make
make test
make install
```

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
cat users.json | script/jq '.users[] | .name'
```

Or create a symlink or copy to use as `jq`:

```bash
ln -s script/jq ~/bin/jq
chmod +x ~/bin/jq
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
cat users.json | script/jq '.users[] | .name'
cat users.json | script/jq '.users | length'    # => 2
cat users.json | script/jq '.users[0] | keys'   # => ["age","name"]
cat users.json | script/jq '.users[].nickname?' # => （何も出力されない、でもエラーもなし）
cat users.json | script/jq '.users[] | select(.age > 25)' # => Aliceのデータ
cat users.json | script/jq -r '.users[].name'
```

## 🧪 Testing

```sh
prove -l t/
```

## 📦 CPAN

This module is available on CPAN: [JQ::Lite](https://metacpan.org/pod/JQ::Lite)

## 📝 License

This module is released under the same terms as Perl itself.

## 👤 Author

Kawamura Shingo  
[pannakoota1@gmail.com](mailto:pannakoota1@gmail.com)

GitHub: [https://github.com/kawamurashingo/JQ-Lite](https://github.com/kawamurashingo/JQ-Lite)
