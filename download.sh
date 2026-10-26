#!/usr/bin/env bash
set -euo pipefail

DIST_NAME='JQ-Lite'
OUT_DIR='.'
SPECIFIED_VERSION=''

usage() {
  cat <<'USAGE'
Usage: download.sh [-v <stable-version>] [-o <output-dir>]

Download a stable JQ-Lite CPAN tarball via HTTPS from the SHINGO
CPAN author directory. No version means MetaCPAN's latest release.
Developer builds such as 3.00_03 are intentionally unsupported.

  -v <version>  Explicit stable numeric version (e.g. 2.59)
  -o <dir>      Output directory (default: current)
  -h            Show this help
USAGE
}

while getopts ':v:o:h' opt; do
  case "$opt" in
    v) SPECIFIED_VERSION="$OPTARG" ;;
    o) OUT_DIR="$OPTARG" ;;
    h) usage; exit 0 ;;
    :) echo "[ERROR] -$OPTARG requires a value" >&2; exit 1 ;;
    ?) echo "[ERROR] Unknown option: -$OPTARG" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))
if (( $# != 0 )); then
  echo '[ERROR] Unexpected positional arguments' >&2
  usage >&2
  exit 1
fi

for tool in curl perl mkdir mktemp rm; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "[ERROR] Missing required tool: $tool" >&2
    exit 1
  fi
done

# Reject developer builds and unsafe filenames *before* contacting the network.
is_stable_version() {
  [[ "$1" =~ ^[0-9]+(\.[0-9]+)+$ ]]
}

if [[ -n "$SPECIFIED_VERSION" ]]; then
  if ! is_stable_version "$SPECIFIED_VERSION"; then
    echo '[ERROR] Expected numeric stable version, not developer/path input' >&2
    exit 1
  fi
  VERSION="$SPECIFIED_VERSION"
else
  echo '[INFO] Finding latest stable JQ-Lite version from MetaCPAN...'
  VERSION="$(
    curl -fsSL --proto '=https' --proto-redir '=https' \
      'https://fastapi.metacpan.org/v1/release/JQ-Lite' |
    perl -MJSON::PP -0777 -ne '
      my $release = decode_json($_);
      die "Expected JSON object\n" unless ref($release) eq "HASH";
      my $version = $release->{version};
      die "Expected numeric stable version\n"
        unless defined($version) && !ref($version)
          && $version =~ /\A[0-9]+(?:\.[0-9]+)+\z/;
      die "Wrong distribution\n"
        if defined($release->{distribution})
          && (ref($release->{distribution}) || $release->{distribution} ne "JQ-Lite");
      die "Wrong author\n"
        if defined($release->{author})
          && (ref($release->{author}) || $release->{author} ne "SHINGO");
      die "Wrong release name\n"
        if defined($release->{name})
          && (ref($release->{name}) || $release->{name} ne "JQ-Lite-$version");
      print $version;
    '
  )"
fi

if ! is_stable_version "$VERSION"; then
  echo '[ERROR] Refusing non-stable release version' >&2
  exit 1
fi

TARBALL_NAME="${DIST_NAME}-${VERSION}.tar.gz"
TARGET_PATH="${OUT_DIR%/}/${TARBALL_NAME}"
DOWNLOAD_URL="https://cpan.metacpan.org/authors/id/S/SH/SHINGO/${TARBALL_NAME}"

mkdir -p -- "$OUT_DIR"
if [[ -e "$TARGET_PATH" || -L "$TARGET_PATH" ]]; then
  echo "[ERROR] Existing file will not be overwritten: $TARGET_PATH" >&2
  exit 1
fi

# Keep incomplete network responses out of the final tarball name.
# Publish by O_CREAT|O_EXCL instead of Bash noclobber, mv or ln: this
# rejects all competing destination types (including device/FIFO links)
# and works on filesystems without hard-link support.
TEMP_PATH="$(mktemp "${OUT_DIR%/}/.JQ-Lite-${VERSION}.XXXXXX")"
cleanup() {
  if [[ -n "${TEMP_PATH:-}" ]]; then
    rm -f -- "$TEMP_PATH"
  fi
}
trap cleanup EXIT

echo "[INFO] Downloading ${TARBALL_NAME} from HTTPS CPAN..."
curl -fsSL --proto '=https' --proto-redir '=https' \
  "$DOWNLOAD_URL" -o "$TEMP_PATH"
if [[ ! -s "$TEMP_PATH" ]]; then
  echo '[ERROR] Empty downloaded tarball' >&2
  exit 1
fi
if ! perl -MFcntl=O_WRONLY,O_CREAT,O_EXCL -e '
  use strict;
  use warnings;
  my ($from, $dest) = @ARGV;
  open my $source, "<", $from or die "Cannot read downloaded archive: $!\n";
  binmode $source;
  sysopen my $out, $dest, O_WRONLY|O_CREAT|O_EXCL, 0666
    or die "Output already exists or cannot be created: $!\n";
  binmode $out;
  my @created = stat $out;
  die "Cannot inspect new output identity\n" unless @created;
  my $closed = 0;
  my $ok = eval {
    while (1) {
      my $read = sysread($source, my $buffer, 65536);
      die "Read failed: $!\n" unless defined $read;
      last unless $read;
      my $offset = 0;
      while ($offset < $read) {
        my $written = syswrite($out, $buffer, $read-$offset, $offset);
        die "Write failed: $!\n" unless defined $written && $written > 0;
        $offset += $written;
      }
    }
    my $closed_ok = close $out;
    $closed = 1;
    die "Close failed: $!\n" unless $closed_ok;
    my @present = lstat $dest;
    die "Output replaced during copy\n"
      unless @present && $present[0] == $created[0]
        && $present[1] == $created[1];
    1;
  };
  if (!$ok) {
    my $reason = $@ || "Unknown copy failure\n";
    close $out unless $closed;
    # Never remove a competing path inserted after the exclusive open.
    my @present = lstat $dest;
    if (@present && $present[0] == $created[0]
        && $present[1] == $created[1]) {
      unlink $dest or warn "Cannot discard partial output: $!\n";
    }
    die $reason;
  }
' "$TEMP_PATH" "$TARGET_PATH"; then
  echo "[ERROR] Cannot publish new CPAN archive: $TARGET_PATH" >&2
  exit 1
fi

echo "[INFO] Downloaded: $TARGET_PATH"
echo '[INFO] For offline installation, separately verify the tarball and transfer it to the target host.'
