#!/bin/sh
# Fail even when a test command exits 0 but emits unexpected stderr.
# Test code that intentionally exercises warnings must capture those warnings
# locally; blanket warning suppression or CI allowlists hide regressions.
set -u

if [ "$#" -eq 0 ]; then
    echo "usage: sh ci/fail-on-test-stderr.sh command [args ...]" >&2
    exit 2
fi

log=$(mktemp "${TMPDIR:-/tmp}/jq-lite-test-stderr.XXXXXX") || exit 2
trap 'rm -f "$log"' 0
trap 'exit 130' 1 2 3 15

"$@" 2>"$log"
status=$?

if [ -s "$log" ]; then
    cat "$log" >&2
    echo "JQ-Lite CI: unexpected test stderr (including Perl warnings); failing even if tests passed." >&2
    exit 1
fi

exit "$status"
