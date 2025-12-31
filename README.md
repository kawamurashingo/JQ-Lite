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

#### CPAN

```bash
cpanm JQ::Lite
```

---

### From Source (Manual Install)

jq-lite can be built and installed manually using the standard Perl toolchain.
This method is suitable for restricted or offline environments.

```bash
perl Makefile.PL
make
make test
make install
```

The installation prefix can be customized:

```bash
perl Makefile.PL PREFIX=$HOME/.local
make install
```

No compiler toolchain or external libraries are required.

---

### Offline / Restricted Installation

jq-lite can be installed without network access or system package managers.
This is useful for:

* air-gapped environments
* restricted corporate networks
* systems without root privileges
* legacy hosts

#### Portable Installer (Unix)

```bash
./download.sh [-v <version>] [-o <path>]
./install.sh [-p <prefix>] [--skip-tests] JQ-Lite-<version>.tar.gz
```

The default installation prefix is:

```text
$HOME/.local
```

---

#### Windows (PowerShell)

```powershell
.\install-jq-lite.ps1 [-Prefix <path>] [--SkipTests] JQ-Lite-<version>.tar.gz
```

This installs jq-lite into a user-writable directory
without requiring administrator privileges.

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

jq-lite can be used directly from Perl code:

```perl
use JQ::Lite;

my $jq = JQ::Lite->new;
say for $jq->run_query($json, '.users[].name');
```

---

## Documentation

* [`FUNCTIONS.md`](FUNCTIONS.md) — supported jq functions
* [`DESIGN.md`](DESIGN.md) — design principles and scope
* [CPAN documentation](https://metacpan.org/pod/JQ::Lite)

---

## Project Status

jq-lite is in a **maintenance-focused phase**.

* Backward compatibility is prioritized
* Breaking changes are avoided
* New features are accepted only when required for correctness

Downstream patches for distribution integration are welcome.

---

## License

Same terms as Perl itself.
