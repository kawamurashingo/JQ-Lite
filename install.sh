#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
RUN_TESTS=1

usage() {
  cat <<USAGE
Usage: $0 [-p <prefix>] [--skip-tests] [<tarball>]

Installs JQ-Lite from a pre-downloaded tarball. If no tarball is
specified, the latest JQ-Lite-*.tar.gz file in the current directory is
used.

Options:
  -p <prefix>    Installation prefix (default: \$PREFIX (env) or \$HOME/.local)
  --skip-tests   Skip make test
  -h             Show this help message
USAGE
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p)
      if [[ -z "${2:-}" ]]; then
        echo "[ERROR] -p requires a prefix argument." >&2
        usage >&2
        exit 1
      fi
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
    --)
      shift
      break
      ;;
    -*)
      echo "[ERROR] Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [[ $# -gt 0 ]]; then
  POSITIONAL+=("$@")
fi

if [[ ${#POSITIONAL[@]} -gt 1 ]]; then
  echo "[ERROR] Too many positional arguments." >&2
  usage >&2
  exit 1
fi

TARBALL="${POSITIONAL[0]:-}"

if [[ -z "$TARBALL" ]]; then
  TARBALL=$(ls -t JQ-Lite-*.tar.gz 2>/dev/null | head -n1 || true)
fi

if [[ -z "$TARBALL" ]]; then
  echo "[ERROR] No JQ-Lite tarball found. Pass the tarball path as an argument or place it in this directory." >&2
  exit 1
fi

if [[ ! -f "$TARBALL" ]]; then
  echo "[ERROR] Tarball '$TARBALL' not found." >&2
  exit 1
fi

# Check required tools
for tool in tar perl make; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "[ERROR] Required tool '$tool' is not available." >&2
    exit 1
  fi
done

# Skip tests if prove is not available
if [[ $RUN_TESTS -eq 1 ]] && ! command -v prove >/dev/null 2>&1; then
  echo "[WARN] 'prove' not found; tests will be skipped."
  RUN_TESTS=0
fi

# Get absolute path of the tarball
if command -v realpath >/dev/null 2>&1; then
  TARBALL_ABS=$(realpath "$TARBALL")
else
  TARBALL_ABS=$(perl -MCwd=abs_path -e 'print abs_path(shift)' "$TARBALL")
fi

# Create temporary working directory
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cd "$WORK_DIR"

# macOS compatible: handle TAR_WARN_FLAGS safely even if empty
TAR_WARN_FLAGS=()
if tar --version 2>/dev/null | grep -qi 'gnu tar'; then
  TAR_WARN_FLAGS=(--warning=no-unknown-keyword)
fi

# Safe expansion for older bash versions (e.g., macOS bash 3.2)
TAR_FLAGS=""
if [[ ${#TAR_WARN_FLAGS[@]} -gt 0 ]]; then
  TAR_FLAGS="${TAR_WARN_FLAGS[*]}"
fi

# Determine distribution directory name
DIST_DIR=$(eval tar $TAR_FLAGS tzf "$TARBALL_ABS" | head -n1 | cut -d'/' -f1)
if [[ -z "$DIST_DIR" ]]; then
  echo "[ERROR] Unable to determine distribution directory from $TARBALL." >&2
  exit 1
fi

# Clean up any existing directory
if [[ -d "$DIST_DIR" ]]; then
  rm -rf "$DIST_DIR"
fi

echo "[INFO] Extracting $TARBALL..."
eval tar $TAR_FLAGS xzf "$TARBALL_ABS"

cd "$DIST_DIR"

echo "[INFO] Installing to $PREFIX..."
perl Makefile.PL PREFIX="$PREFIX" >/dev/null
make

if [[ $RUN_TESTS -eq 1 ]]; then
  make test
else
  echo "[INFO] Skipping tests."
fi

make install

# --- Environment setup section ---
BASHRC="$HOME/.bashrc"
SITE_PATHS=(
  "$PREFIX/lib/perl5/site_perl"
  "$PREFIX/lib/perl5"
  "$PREFIX/lib/perl5/darwin-thread-multi-2level"
)

echo "[INFO] Updating ~/.bashrc with PATH and PERL5LIB if needed..."

# Ensure PERL5LIB includes all relevant module paths
for dir in "${SITE_PATHS[@]}"; do
  if [[ -d "$dir" ]] && ! grep -Fq "$dir" "$BASHRC" 2>/dev/null; then
    echo "export PERL5LIB=\"$dir:\$PERL5LIB\"" >> "$BASHRC"
  fi
done

# Ensure PATH includes $PREFIX/bin
if ! grep -Fq "$PREFIX/bin" "$BASHRC" 2>/dev/null; then
  echo "export PATH=\"$PREFIX/bin:\$PATH\"" >> "$BASHRC"
fi

echo
cat <<EOM
[INFO] Installation complete.

✅ Next steps:
  1. Reload your shell configuration:
       source ~/.bashrc
  2. Verify installation:
       jq-lite -v
EOM
