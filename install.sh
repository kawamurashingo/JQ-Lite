#!/usr/bin/env bash
set -euo pipefail

# Default install prefix (can be overridden by -p or PREFIX env)
PREFIX="${PREFIX:-$HOME/.local}"
RUN_TESTS=1

usage() {
  cat <<USAGE
Usage: $0 [-p <prefix>] [--skip-tests] [<tarball>]

Installs JQ-Lite from a pre-downloaded tarball.
If no tarball is specified, the latest JQ-Lite-*.tar.gz file is used.

Options:
  -p <prefix>    Installation prefix (default: \$HOME/.local)
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
  command -v "$tool" >/dev/null 2>&1 || { echo "[ERROR] '$tool' not found." >&2; exit 1; }
done

if [[ $RUN_TESTS -eq 1 ]] && ! command -v prove >/dev/null 2>&1; then
  echo "[WARN] 'prove' not found; skipping tests."
  RUN_TESTS=0
fi

# --- Abs path ---
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

# --- Safely extract top directory ---
if [[ ${#TAR_FLAGS[@]} -gt 0 ]]; then
  DIST_DIR=$(tar "${TAR_FLAGS[@]}" tzf "$TARBALL_ABS" 2>/dev/null | head -n1 | cut -d'/' -f1 || true)
else
  DIST_DIR=$(tar tzf "$TARBALL_ABS" 2>/dev/null | head -n1 | cut -d'/' -f1 || true)
fi

if [[ -z "$DIST_DIR" ]]; then
  echo "[WARN] Failed to detect distribution directory — retrying without options..."
  DIST_DIR=$(tar tzf "$TARBALL_ABS" | head -n1 | cut -d'/' -f1)
fi

if [[ -z "$DIST_DIR" ]]; then
  echo "[ERROR] Unable to determine distribution directory from $TARBALL." >&2
  exit 1
fi

# --- Extract safely ---
echo "[INFO] Extracting $TARBALL..."
if [[ ${#TAR_FLAGS[@]} -gt 0 ]]; then
  tar "${TAR_FLAGS[@]}" xzf "$TARBALL_ABS" || tar xzf "$TARBALL_ABS"
else
  tar xzf "$TARBALL_ABS"
fi

cd "$DIST_DIR"

echo "[INFO] Installing to $PREFIX..."

# Avoid inherited MakeMaker options conflicting with our explicit install args.
# Many environments (e.g., local::lib) set PERL_MM_OPT/PERL_MB_OPT with INSTALL_BASE.
MM_ENV=(env -u PERL_MM_OPT -u PERL_MB_OPT)

# If the user's environment is already configured for INSTALL_BASE, do not pass PREFIX too.
if [[ "${PERL_MM_OPT:-}" == *"INSTALL_BASE"* ]] || [[ "${PERL_MB_OPT:-}" == *"INSTALL_BASE"* ]]; then
  "${MM_ENV[@]}" perl Makefile.PL INSTALL_BASE="$PREFIX" >/dev/null
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

# --- Setup env ---
cat <<EOM

[INFO] Installation complete.

To enable jq-lite, add the following to your ~/.bashrc:
  export PATH="$PREFIX/bin:\$PATH"
  export PERL5LIB="$PREFIX/lib/perl5:\$PERL5LIB"

Then reload:
  source ~/.bashrc

Verify installation:
  jq-lite -v
EOM
