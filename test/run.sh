#!/usr/bin/env bash
# Linux / macOS shortcut for the offline logic tests. The runner itself is test/run.py (one runner for every OS,
# so there's only one place to change); this keeps the old command working.
#   sudo apt install python3 lua5.3     (Debian/Ubuntu/Mint; Fedora: lua; Arch: lua53)
#   bash test/run.sh                    all tests
#   bash test/run.sh "corridor"         only tests whose name contains this text
# The mutant check: python3 test/run.py --prove
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${1:-}" ]; then
  exec python3 "$HERE/run.py" --no-compile --only "$1"
fi
exec python3 "$HERE/run.py" --no-compile
