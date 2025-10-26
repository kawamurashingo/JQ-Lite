#!/usr/bin/env bash

set -euo pipefail

DIST_NAME="JQ-Lite"
OUT_DIR="."

usage() {
  cat <<USAGE
Usage: $0 [-o <output-dir>]

Downloads the latest ${DIST_NAME} release tarball from MetaCPAN into the
specified directory (defaults to the current directory).

Options:
  -o <dir>   Directory where the tarball should be saved (default: current)
  -h         Show this help message
USAGE
}

while getopts ":o:h" opt; do
  case "$opt" in
    o)
      OUT_DIR="$OPTARG"
      ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo "[ERROR] Option -$OPTARG requires an argument." >&2
      usage >&2
      exit 1
      ;;
    ?)
      echo "[ERROR] Unknown option -$OPTARG" >&2
      usage >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))

if [[ $# -gt 0 ]]; then
  echo "[ERROR] Unexpected positional arguments: $*" >&2
  usage >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "[ERROR] curl is required to download the tarball." >&2
  exit 1
fi

if [[ ! -d "$OUT_DIR" ]]; then
  echo "[INFO] Creating output directory $OUT_DIR"
  mkdir -p "$OUT_DIR"
fi

META_URL="https://fastapi.metacpan.org/v1/release/${DIST_NAME}?fields=download_url,version"

echo "[INFO] Fetching latest version of $DIST_NAME from MetaCPAN..."
RELEASE_JSON=$(curl -sSfL "$META_URL")
DOWNLOAD_URL=$(printf '%s' "$RELEASE_JSON" | grep '"download_url"' | cut -d'"' -f4)
VERSION=$(printf '%s' "$RELEASE_JSON" | grep '"version"' | head -n1 | cut -d'"' -f4)

if [[ -z "$DOWNLOAD_URL" ]]; then
  echo "[ERROR] Failed to resolve the download URL from MetaCPAN." >&2
  exit 1
fi

TARBALL_NAME="${DIST_NAME}-${VERSION}.tar.gz"
TARGET_PATH="${OUT_DIR%/}/$TARBALL_NAME"

if [[ -f "$TARGET_PATH" ]]; then
  echo "[WARN] $TARGET_PATH already exists. Overwriting..."
  rm -f "$TARGET_PATH"
fi

echo "[INFO] Downloading $TARBALL_NAME..."
curl -sSfL "$DOWNLOAD_URL" -o "$TARGET_PATH"

echo
cat <<EOM
[INFO] Download complete.
Copy $TARGET_PATH to your offline environment (e.g. via USB), then run:
  ./install.sh $TARBALL_NAME
from within the target machine.
EOM
