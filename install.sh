#!/usr/bin/env bash
set -euo pipefail

# Default install prefix (can be overridden by -p or PREFIX env)
PREFIX="${PREFIX:-$HOME/.local}"
RUN_TESTS=1

usage() {
  cat <<'USAGE'
Usage: install.sh [-p <prefix>] [--skip-tests] [<tarball>]

Installs JQ-Lite from a pre-downloaded tarball.
If no tarball is specified, the latest JQ-Lite-*.tar.gz file is used.

Options:
  -p <prefix>    Installation prefix (default: $HOME/.local)
  --skip-tests   Skip make test
  -h             Show this help message
USAGE
}

# --- Parse arguments ---
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p)
      PREFIX="$2"
      shift 2
      ;;
    --skip-tests)
      RUN_TESTS=0
      shift
      ;;
    -h)
      usage
      exit 0
      ;;
    -*)
      echo "[ERROR] Unknown option: $1" >&2
      exit 1
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [[ ${#POSITIONAL[@]} -gt 1 ]]; then
  echo "[ERROR] Too many positional arguments." >&2
  exit 1
fi

TARBALL="${POSITIONAL[0]:-}"

# --- Locate tarball ---
if [[ -z "$TARBALL" ]]; then
  TARBALL=$(ls -t JQ-Lite-*.tar.gz 2>/dev/null | head -n1 || true)
fi
if [[ -z "$TARBALL" ]]; then
  echo "[ERROR] No JQ-Lite tarball found." >&2
  exit 1
fi
if [[ ! -f "$TARBALL" ]]; then
  echo "[ERROR] Tarball '$TARBALL' not found." >&2
  exit 1
fi

# --- Tools check ---
for tool in tar perl make; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "[ERROR] '$tool' not found." >&2
    exit 1
  }
done

# --- Perl version check (require 5.14+) ---
perl -e 'use 5.014; 1' >/dev/null 2>&1 || {
  echo "[ERROR] Perl 5.14+ is required." >&2
  exit 1
}

if [[ $RUN_TESTS -eq 1 ]] && ! command -v prove >/dev/null 2>&1; then
  echo "[WARN] 'prove' not found; skipping tests."
  RUN_TESTS=0
fi

# --- Absolute path ---
if command -v realpath >/dev/null 2>&1; then
  TARBALL_ABS=$(realpath "$TARBALL")
else
  TARBALL_ABS=$(perl -MCwd=abs_path -e 'print abs_path(shift)' "$TARBALL")
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cd "$WORK_DIR"

# --- Detect tar support ---
TAR_FLAGS=()
if tar --help 2>/dev/null | grep -q -- '--warning'; then
  TAR_FLAGS+=(--warning=no-unknown-keyword)
fi

# --- Safely detect top-level distribution directory ---
LISTING=""

if [[ ${#TAR_FLAGS[@]} -gt 0 ]]; then
  LISTING=$(tar "${TAR_FLAGS[@]}" -tzf "$TARBALL_ABS" 2>/dev/null || true)
else
  LISTING=$(tar -tzf "$TARBALL_ABS" 2>/dev/null || true)
fi

# Fallback for busybox / non-gzip-aware tar
if [[ -z "$LISTING" ]]; then
  if command -v gzip >/dev/null 2>&1; then
    LISTING=$(gzip -dc "$TARBALL_ABS" 2>/dev/null | tar -tf - 2>/dev/null || true)
  fi
fi

DIST_DIR=$(printf '%s\n' "$LISTING" | head -n1 | cut -d'/' -f1 || true)

if [[ -z "$DIST_DIR" ]]; then
  echo "[ERROR] Unable to determine distribution directory from $TARBALL." >&2
  echo "[HINT] Try manually: tar tzf \"$TARBALL\" | head" >&2
  exit 1
fi

# --- Extract ---
echo "[INFO] Extracting $TARBALL..."
if [[ ${#TAR_FLAGS[@]} -gt 0 ]]; then
  tar "${TAR_FLAGS[@]}" -xzf "$TARBALL_ABS" || tar -xzf "$TARBALL_ABS"
else
  tar -xzf "$TARBALL_ABS"
fi

cd "$DIST_DIR"

echo "[INFO] Installing to $PREFIX..."

# Avoid inherited MakeMaker/Module::Build options (local::lib etc.)
MM_ENV=(env -u PERL_MM_OPT -u PERL_MB_OPT)

# Prefer INSTALL_BASE; fallback to PREFIX if unsupported
if "${MM_ENV[@]}" perl Makefile.PL INSTALL_BASE="$PREFIX" >/dev/null 2>&1; then
  :
else
  "${MM_ENV[@]}" perl Makefile.PL PREFIX="$PREFIX" >/dev/null
fi

make

if [[ $RUN_TESTS -eq 1 ]]; then
  make test
else
  echo "[INFO] Skipping tests."
fi

make install

# --- Post install message ---
PERL_MM_VER="$(perl -MConfig -e 'print $Config{version}' | awk -F. '{print $1"."$2}')"

cat <<EOM

[INFO] Installation complete.

To enable jq-lite, add the following to your ~/.bashrc:

  export PATH="$PREFIX/bin:\$PATH"

  # Recommended (works for most Perl setups)
  if perl -Mlocal::lib -e 1 >/dev/null 2>&1; then
    eval "\$(perl -I$PREFIX/lib/perl5 -Mlocal::lib=$PREFIX)"
  else
    # Fallback (when local::lib is not installed)
    export PERL5LIB="$PREFIX/lib/perl5:$PREFIX/share/perl5/$PERL_MM_VER:\$PERL5LIB"
  fi

Then reload:
  source ~/.bashrc

Verify installation:
  jq-lite -v
EOM
