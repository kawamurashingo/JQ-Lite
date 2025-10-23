![JQ::Lite](./images/JQ_Lite_logo_small.png)
# 🧩 JQ::Lite — Lightweight jq in Pure Perl

[![GitHub](https://img.shields.io/github/stars/kawamurashingo/JQ-Lite?style=social)](https://github.com/kawamurashingo/JQ-Lite)

**JQ::Lite** is a pure-Perl JSON query engine inspired by [`jq`](https://stedolan.github.io/jq/).
It allows you to query and transform JSON using jq-like syntax — without external binaries.

---

## ✨ Highlights

* 🪶 **Pure Perl** — no XS or C dependencies
* 🔍 jq-style filters: `.users[].name`, `.nickname?`, `select(...)`, `map(...)`
* 🔢 Supports arithmetic & conditionals: `if ... then ... else ... end`
* 🔧 CLI tool: `jq-lite` with `--null-input`, `--slurp`, `--from-file`, `--yaml`
* 📊 Built-in 100+ jq functions (see [`FUNCTIONS.md`](FUNCTIONS.md))
* 💻 Interactive mode for exploring JSON
* 🧰 Works with JSON or YAML input
* 🌐 Compatible with almost any Linux (even legacy or air-gapped) (see [`VISION.md`](VISION.md))

---

## ⚙️ Installation

### 🛠 From CPAN

```bash
cpanm JQ::Lite
```

### 🍺 Homebrew (macOS)

```bash
brew tap kawamurashingo/jq-lite
brew install --HEAD jq-lite
```

### 🐧 Portable (Linux/macOS)

```bash
curl -fsSL https://raw.githubusercontent.com/kawamurashingo/JQ-Lite/main/install.sh | bash
```

> Installs to `$HOME/.local/bin`.
> Add to PATH if needed:
>
> ```bash
> export PATH="$HOME/.local/bin:$PATH"
> ```

---

## 🚀 Usage

### As a Perl module

```perl
use JQ::Lite;
my $jq = JQ::Lite->new;
my @names = $jq->run_query('{"users":[{"name":"Alice"}]}', '.users[].name');
print join("\n", @names);
```

### As a CLI tool

```bash
jq-lite '.users[].name' users.json
jq-lite '.users[] | select(.age > 25)' users.json
jq-lite --yaml '.users[].name' users.yaml
```

💡 Try interactive mode:

```bash
jq-lite users.json
```

---

## 🧱 Environment Support

| Environment          | jq | jq-lite |
| -------------------- | -- | ------- |
| Legacy CentOS / RHEL | ❌  | ✅       |
| Alpine Linux         | ⚠️ | ✅       |
| Air-gapped / Proxy   | ❌  | ✅       |
| No root privilege    | ⚠️ | ✅       |

✅ **Runs on Perl ≥ 5.14**, even on CentOS 6 or Debian 7 with `perlbrew` or local install.

---

## 🔍 Example Queries

```bash
jq-lite '.users[] | select(.profile.active) | .name' users.json
jq-lite '.users | sort_by(.age) | map(.name) | join(", ")' users.json
jq-lite '.users[].nickname? // .name' users.json
```

---

## 🧠 More Functions

See the complete list in
👉 [`FUNCTIONS.md`](FUNCTIONS.md) or on [MetaCPAN](https://metacpan.org/pod/JQ::Lite)

---

## 👤 Author

**Shingo Kawamura**
📧 [pannakoota1@gmail.com](mailto:pannakoota1@gmail.com)
🔗 [GitHub @kawamurashingo](https://github.com/kawamurashingo/JQ-Lite)

---

## 📜 License

Same terms as Perl itself.



