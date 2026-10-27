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

# --- Locate a stable source tarball only ---
if [[ -z "$TARBALL" ]]; then
  shopt -s nullglob
  archives=(JQ-Lite-*.tar.gz)
  shopt -u nullglob
  for candidate in "${archives[@]}"; do
    [[ "$candidate" =~ ^JQ-Lite-[0-9]+(\.[0-9]+)+\.tar\.gz$ ]] || continue
    if [[ -z "$TARBALL" || "$candidate" -nt "$TARBALL" ]]; then
      TARBALL="$candidate"
    fi
  done
fi
if [[ -z "$TARBALL" || ! -f "$TARBALL" ]]; then
  echo '[ERROR] No stable JQ-Lite tarball found.' >&2
  exit 1
fi
TARBALL_NAME="${TARBALL##*/}"
if [[ ! "$TARBALL_NAME" =~ ^JQ-Lite-[0-9]+(\.[0-9]+)+\.tar\.gz$ ]]; then
  echo '[ERROR] Expected stable JQ-Lite-<version>.tar.gz, not an internal developer build.' >&2
  exit 1
fi
DIST_DIR="${TARBALL_NAME%.tar.gz}"
for tool in perl make; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "[ERROR] '$tool' not found." >&2
    exit 1
  }
done
perl -e 'use 5.014; use Archive::Tar; 1' >/dev/null 2>&1 || {
  echo '[ERROR] Perl 5.14+ with core Archive::Tar is required.' >&2
  exit 1
}
if [[ "$RUN_TESTS" -eq 1 ]] && ! command -v prove >/dev/null 2>&1; then
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

# --- Validate and extract with the *same* Perl archive parser ---
# Refuse path traversal and links before creating any archive member.
perl -MArchive::Tar - "$TARBALL_ABS" "$DIST_DIR" <<'PERL'
use strict;
use warnings;
use Archive::Tar ();
use IO::Uncompress::Gunzip qw($GunzipError);
use File::Temp qw(tempfile);

my ($archive, $root) = @ARGV;
die "Unexpected distribution root\n"
  unless defined($root) && $root =~ /\AJQ-Lite-[0-9]+(?:\.[0-9]+)+\z/;

# A gzip trailer/CRC error is NOT reliably surfaced by Archive::Tar.
# Fully decompress using the core gzip reader first, with a fixed
# size limit, to an isolated temporary plain-tar file on disk.
my $gunzip = IO::Uncompress::Gunzip->new($archive, Strict => 1)
  or die "Invalid gzip: $GunzipError\n";
my ($plain_fh, $plain_path) = tempfile(DIR => ".", SUFFIX => ".tar", UNLINK => 1);
binmode $plain_fh;
my $plain_size = 0;
while (1) {
  my $got = $gunzip->read(my $buf, 65536);
  die "Corrupt gzip: $GunzipError\n" if $got < 0;
  last unless $got;
  $plain_size += $got;
  die "Uncompressed source tar exceeds 8 MB size budget\n"
    if $plain_size > 8_000_000;
  print {$plain_fh} $buf or die "Cannot write validated tar spool: $!\n";
}
$gunzip->close or die "Gzip trailer validation failed: $GunzipError\n";
close $plain_fh or die "Cannot close validated tar spool: $!\n";

# Tar files require integral 512-byte blocks and two zero-block end
# markers. A short final header can be silently ignored by some
# Archive::Tar versions, so verify framing before asking it to parse.
die "Invalid tar framing or missing end markers\n"
  unless $plain_size >= 1024 && $plain_size % 512 == 0;
open my $raw, "<", $plain_path or die "Cannot read tar spool: $!\n";
binmode $raw;
my ($entry_count, $position, $end_seen) = (0, 0, 0);
while ($position < $plain_size) {
  my $got = read($raw, my $header, 512);
  die "Truncated tar header\n" unless defined($got) && $got == 512;
  $position += 512;
  if ($header eq "\0" x 512) {
    die "Missing second tar end marker\n" if $plain_size - $position < 512;
    my $remaining = $plain_size - $position;
    while ($remaining) {
      my $chunk = $remaining > 65536 ? 65536 : $remaining;
      my $n = read($raw, my $tail, $chunk);
      die "Truncated tar trailer\n" unless defined($n) && $n == $chunk;
      die "Nonzero data beyond tar end marker\n" unless $tail eq "\0" x $n;
      $remaining -= $n;
    }
    $end_seen = 1;
    last;
  }
  die "Too many tar entries\n" if ++$entry_count > 2000;
  my $raw_name = substr($header, 0, 100);
  $raw_name =~ s/\x00.*\z//s;
  die "Empty raw tar member name\n" unless length($raw_name);
  my $size_field = substr($header, 124, 12);
  die "Invalid tar size field\n"
    unless $size_field =~ /\A[\x00 ]*([0-7]+)[\x00 ]*\z/;
  my $size = oct($1);
  die "Tar member exceeds 4 MB size budget\n" if $size > 4_000_000;
  my $check_field = substr($header, 148, 8);
  die "Invalid tar checksum field\n"
    unless $check_field =~ /\A[\x00 ]*([0-7]+)[\x00 ]*\z/;
  my $expected = oct($1);
  substr($header, 148, 8) = " " x 8;
  die "Tar header checksum mismatch\n"
    unless $expected == unpack("%32C*", $header);
  my $type = substr($header, 156, 1);
  die "Unsafe tar link/special/extended-header type\n"
    unless $type eq "0" || $type eq "5" || $type eq "\0";
  my $padded = int(($size + 511) / 512) * 512;
  die "Truncated tar file content\n" if $position + $padded > $plain_size;
  seek($raw, $padded, 1) or die "Cannot skip tar member: $!\n";
  $position += $padded;
}
close $raw or die "Cannot close tar header scan: $!\n";
die "Missing tar end markers\n" unless $end_seen;
die "No tar entries\n" unless $entry_count;

# The complete bounded tar has now passed gzip CRC/trailer, raw tar
# framing and header checks. Archive::Tar is reused for named-member
# validation and final extraction, so parser differences cannot turn
# an uninspected symlink into a write.
my $tar = Archive::Tar->new;
my $parsed = $tar->read($plain_path, 0);
die "Incomplete or corrupt source tar: " . ($tar->error || "no entries") . "\n"
  unless $parsed && !$tar->error;
my @parsed_files = $tar->get_files;
die "Tar parser skipped or added archive members\n"
  unless @parsed_files == $entry_count;
my (%seen, $makefile, $count);
for my $entry (@parsed_files) {
  die "Too many archive members\n" if ++$count > 2000;
  my $full = $entry->full_path;
  die "Missing entry path\n" unless defined($full) && length($full);
  die "Unsafe archive path: $full\n" if $full =~ /[\\\x00\r\n]/;
  my $path = $full;
  $path =~ s{/\z}{} if $entry->is_dir;
  die "Entry outside distribution root: $full\n"
    unless ($path eq $root && $entry->is_dir)
      || $path =~ m{\A\Q$root\E/(?:[^/]+/)*[^/]+\z};
  die "Unsafe dot/empty path segment: $full\n"
    if grep { $_ eq "." || $_ eq ".." || !length($_) } split m{/}, $path, -1;
  die "Unsafe link or special member: $full\n"
    unless $entry->is_file || $entry->is_dir;
  die "Duplicate archive path: $full\n" if $seen{$path}++;
  die "Unsafe setuid/setgid mode: $full\n" if $entry->mode & 06000;
  $makefile = 1 if $path eq "$root/Makefile.PL" && $entry->is_file;
}
die "Archive lacks root Makefile.PL\n" unless $makefile;
$tar->extract or die "Extraction failed after validation\n";
PERL
if [[ ! -d "$DIST_DIR" || -L "$DIST_DIR" ]]; then
  echo '[ERROR] Archive did not create expected distribution directory.' >&2
  exit 1
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
