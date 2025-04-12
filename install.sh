#!/bin/bash

set -e

DIST_NAME="JQ-Lite"

echo "[INFO] Fetching latest version of $DIST_NAME from MetaCPAN..."

TARBALL_URL=$(curl -s "https://fastapi.metacpan.org/v1/release/$DIST_NAME" | grep '"download_url"' | cut -d'"' -f4)
if [[ -z "$TARBALL_URL" ]]; then
  echo "[ERROR] Failed to fetch tarball URL from MetaCPAN."
  exit 1
fi

TAR=$(basename "$TARBALL_URL")
DIST="${TAR%.tar.gz}"

echo "[INFO] Downloading $TAR..."
curl -sLO "$TARBALL_URL"

echo "[INFO] Extracting..."
tar xzf "$TAR" 2>/dev/null

echo "[INFO] Resetting timestamps to avoid future file errors..."
find "$DIST" -exec touch {} + >/dev/null 2>&1

cd "$DIST"

echo "[INFO] Installing..."
perl Makefile.PL PREFIX=$HOME/.local >/dev/null
make -s
make -s test
make -s install

echo ""
echo "[INFO] Installation complete."
echo "Make sure to add the following to your shell config:"
echo '  export PATH="$HOME/.local/bin:$PATH"'
