#!/usr/bin/env bash
# Linux / macOS version of test\run.ps1: the offline logic tests (test/tests.lua against the bot's real Lua code
# with a fake Isaac, test/mock.lua), run by the system's Lua 5.3 instead of the game's DLL. No game needed.
#   sudo apt install lua5.3          (Debian/Ubuntu/Mint; Fedora: lua; Arch: lua53)
#   bash test/run.sh                 all tests
#   bash test/run.sh "corridor"      only tests whose name contains this text
# (The -Prove mutant check is in run.ps1 only for now.)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LUA="$(command -v lua5.3 || command -v lua53 || command -v lua || true)"
if [ -z "$LUA" ]; then echo "Lua 5.3 not found: sudo apt install lua5.3"; exit 1; fi
case "$("$LUA" -v 2>&1)" in *5.3*|*5.4*) ;; *) echo "warning: the game uses Lua 5.3; found: $("$LUA" -v 2>&1)";; esac

ONLY="${1:-}"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
{
  echo "MOD_DIR = '$ROOT/mod/isaac-bot'"
  if [ -n "$ONLY" ]; then printf "ONLY = %s\n" "'${ONLY//\'/\\\'}'"; fi
  echo "local ok, res = xpcall(function() dofile('$ROOT/test/mock.lua'); return dofile('$ROOT/test/tests.lua') end, debug.traceback)"
  echo "io.write(ok and tostring(res) or ('CRASH ' .. tostring(res)), '\n')"
} > "$tmp"

out="$("$LUA" "$tmp" 2>&1)"
echo "$out"
fails=$(printf '%s\n' "$out" | grep -cE '^(FAIL|CRASH|ERROR|lua)')
passes=$(printf '%s\n' "$out" | grep -cE '^PASS')
known=$(printf '%s\n' "$out" | grep -cE '^(KNOWN|FIXED\?)')
echo
if [ "$known" -gt 0 ]; then
  echo "$passes passed, $fails failed, $known known bug(s) (test/FOUND_BUGS.md)"
else
  echo "$passes passed, $fails failed"
fi
[ "$fails" -eq 0 ]
