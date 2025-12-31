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

## From Source (Manual Install)

jq-lite can be built and installed manually using the standard Perl toolchain.
This method is suitable for restricted or offline environments.

```bash
perl Makefile.PL
make
make test
make install
```

---

## Installing into a user directory (no root)

When installing into a user-writable directory (for example `$HOME/.local`),
**both PATH and Perl module search paths must be configured**.

### Recommended: INSTALL_BASE

This is the **recommended method**, as it keeps binaries and Perl modules
under a consistent directory layout.

```bash
perl Makefile.PL INSTALL_BASE=$HOME/.local
make
make test
make install
```

Then enable jq-lite:

```bash
export PATH="$HOME/.local/bin:$PATH"
export PERL5LIB="$HOME/.local/lib/perl5:$PERL5LIB"
```

Verify:

```bash
jq-lite -v
```

---

### Using PREFIX (advanced / legacy)

Using `PREFIX` installs Perl modules under:

```
$PREFIX/share/perl/<perl-version>/
```

This directory is **not automatically included** in Perl’s `@INC`.

```bash
perl Makefile.PL PREFIX=$HOME/.local
make install
```

In this case, you must also set `PERL5LIB` manually:

```bash
export PATH="$HOME/.local/bin:$PATH"
export PERL5LIB="$HOME/.local/share/perl/$(perl -e 'print $]'):$PERL5LIB"
```

This method is supported, but **INSTALL_BASE is preferred**.

---

## Offline / Restricted Installation

jq-lite can be installed without network access or system package managers.
This is useful for:

* air-gapped environments
* restricted corporate networks
* systems without root privileges
* legacy hosts

### Portable Installer (Unix)

```bash
./download.sh [-v <version>] [-o <path>]
./install.sh [-p <prefix>] [--skip-tests] JQ-Lite-<version>.tar.gz
```

The default installation prefix is:

```text
$HOME/.local
```

The installer prints any required environment variables
if manual configuration is needed.

---

### Windows (PowerShell)

```powershell
.\install-jq-lite.ps1 [-Prefix <path>] [--SkipTests] JQ-Lite-<version>.tar.gz
```

This installs jq-lite into a user-writable directory
without requiring administrator privileges.

---

## Notes on Environment Variables

jq-lite itself has **no external runtime dependencies**, but when installed
outside system directories:

* `PATH` must include the installation `bin` directory
* `PERL5LIB` must include the directory containing `JQ/Lite.pm`

This is standard Perl behavior and applies to all non-system Perl modules.

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

* [`docs/cli-contract.md`](docs/cli-contract.md) — **stable CLI contract**
* [`docs/FUNCTIONS.md`](docs/FUNCTIONS.md) — supported jq functions
* [`docs/DESIGN.md`](docs/DESIGN.md) — design principles and scope
* [CPAN documentation](https://metacpan.org/pod/JQ::Lite)

---

## License

Same terms as Perl itself.

