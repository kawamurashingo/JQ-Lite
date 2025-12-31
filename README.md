# jq-lite

jq-lite is a **jq-compatible JSON processor written in pure Perl**.

It is designed for **long-term CLI stability** and **minimal dependencies**,
making it suitable for use as an OS-level utility in constrained environments.

- No external binaries
- No native libraries
- No compilation step

---

## Overview

jq-lite allows querying and transforming JSON using jq-like syntax,
while remaining fully portable across systems where Perl is available.

It is particularly suited for:

- minimal Linux distributions
- containers and CI environments
- legacy or restricted systems
- offline / air-gapped deployments

jq-lite is available as an **official Alpine Linux package**:

```bash
apk add jq-lite
````

---

## Design Goals

* **CLI contract stability**
  Behavior, exit codes, and error handling are treated as compatibility promises.

* **Minimal dependency footprint**
  Implemented in pure Perl without XS, C extensions, or external libraries.

* **Predictable behavior**
  Intended for use in shell scripts and infrastructure automation.

jq-lite prioritizes **reliability over feature growth**.

---

## CLI Contract (Stable)

jq-lite defines a **stable CLI contract** that is treated as a
backward-compatibility guarantee.

The contract covers:

* Exit codes
* Error categories and stderr prefixes
* stdout behavior on success and failure
* jq-compatible truthiness rules

These guarantees are formally documented here:

👉 **[`docs/cli-contract.md`](docs/cli-contract.md)**

Changes that would violate this contract are intentionally avoided.

---

## Quick Start

```bash
jq-lite '.users[].name' users.json
jq-lite '.users[] | select(.age > 25)' users.json
jq-lite --yaml '.users[].name' users.yaml
```

Interactive mode:

```bash
jq-lite users.json
```

---

## Environment Support

| Environment          | jq | jq-lite |
| -------------------- | -- | ------- |
| Alpine Linux         | △  | ✓       |
| Legacy CentOS / RHEL | ✗  | ✓       |
| Air-gapped systems   | ✗  | ✓       |
| No root privileges   | △  | ✓       |

Runs on **Perl ≥ 5.14**.

---

## Installation

### Package Manager

#### Alpine Linux

```bash
apk add jq-lite
```

---

### CPAN

```bash
cpanm JQ::Lite
```

---

## From Source (Latest, Simple)

This method installs the **latest released version** directly from CPAN
without requiring `jq`.

### Download (latest)

```bash
ver=$(curl -s https://fastapi.metacpan.org/v1/release/JQ-Lite | perl -MJSON::PP -ne 'print decode_json($_)->{version}')
curl -sSfL https://cpan.metacpan.org/authors/id/K/KA/KAWAMURASHINGO/JQ-Lite-$ver.tar.gz -o JQ-Lite-$ver.tar.gz
```

### Install (user-local, no root)

```bash
tar xzf JQ-Lite-$ver.tar.gz
cd JQ-Lite-$ver

perl Makefile.PL INSTALL_BASE=$HOME/.local
make
make test
make install
```

Enable jq-lite:

```bash
export PATH="$HOME/.local/bin:$PATH"
export PERL5LIB="$HOME/.local/lib/perl5:$PERL5LIB"
```

Verify:

```bash
jq-lite -v
```

---

### Install (system-wide / root)

```bash
tar xzf JQ-Lite-$ver.tar.gz
cd JQ-Lite-$ver

perl Makefile.PL
make
make test
sudo make install
```

---

## Installing into a user directory (details)

When installing outside system directories:

* `PATH` must include the installation `bin` directory
* `PERL5LIB` must include the directory containing `JQ/Lite.pm`

### Recommended: INSTALL_BASE

```bash
perl Makefile.PL INSTALL_BASE=$HOME/.local
make install
```

This keeps binaries and modules under a consistent layout and is preferred.

---

### Using PREFIX (advanced / legacy)

```bash
perl Makefile.PL PREFIX=$HOME/.local
make install
```

In this case, you must configure `PERL5LIB` manually:

```bash
export PATH="$HOME/.local/bin:$PATH"
export PERL5LIB="$HOME/.local/share/perl/$(perl -e 'print $]'):$PERL5LIB"
```

---

## Offline / Restricted Installation

jq-lite can be installed without network access or system package managers.

Typical use cases:

* air-gapped environments
* restricted corporate networks
* systems without root privileges
* legacy hosts

### Portable Installer (Unix)

```bash
./download.sh
./install.sh JQ-Lite-<version>.tar.gz
```

The default installation prefix is:

```text
$HOME/.local
```

---

### Windows (PowerShell)

```powershell
.\install-jq-lite.ps1 JQ-Lite-<version>.tar.gz
```

Administrator privileges are not required.

---

## Containers

```dockerfile
FROM alpine
RUN apk add --no-cache jq-lite
```

jq-lite can be used as a **container-standard JSON processing tool**
without adding native dependencies.

---

## Perl Integration

jq-lite can also be used directly from Perl code:

```perl
use JQ::Lite;

my $jq = JQ::Lite->new;
say for $jq->run_query($json, '.users[].name');
```

---

## Documentation

* [`docs/cli-contract.md`](docs/cli-contract.md) — **stable CLI contract**
* [`docs/FUNCTIONS.md`](docs/FUNCTIONS.md) — supported jq functions
* [`docs/DESIGN.md`](docs/DESIGN.md) — design principles and scope
* [CPAN documentation](https://metacpan.org/pod/JQ::Lite)

---

## License

Same terms as Perl itself.
