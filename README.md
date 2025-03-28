### 📄 `README.md`

# JQ::Lite

**JQ::Lite** is a lightweight, pure-Perl JSON query engine inspired by the `jq` command-line tool.  
It provides a simplified jq-like syntax for querying JSON structures from Perl or the command line.

## 🔧 Features

- Pure Perl implementation (no XS, no external dependencies)
- Simple jq-like query syntax (e.g. `.users[] | .name`)
- Can be used as a CLI tool (`script/jq.pl`)
- Suitable for scripting, automation, and teaching purposes

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

print join(\"\\n\", @names), \"\\n\";
```

### As a CLI tool

```bash
cat users.json | script/jq.pl '.users[] | .name'
```

## 📦 Example Input

```json
{
  "users": [
    { "name": "Alice", "age": 30 },
    { "name": "Bob", "age": 25 }
  ]
}
```

### Example Query

```bash
cat users.json | script/jq.pl '.users[] | .name'
```

### Output

```
Alice
Bob
```

## 🧪 Testing

```sh
prove -l t/basic.t
```

## 📝 License

This module is released under the same terms as Perl itself.

## 🧑‍💻 Author

Kawamura Shingo  
[pannakoota1@gmail.com](mailto:pannakoota1@gmail.com)

GitHub: [https://github.com/kawamurashingo/JQ-Lite](https://github.com/kawamurashingo/JQ-Lite)
