#!/usr/bin/env bash
# Linux / macOS: what tools\reload.ps1 checks before a live reload: every Lua file compiles, offline tests pass.
#   bash tools/check.sh             check only
#   bash tools/check.sh --reload    check, then reload the mod in the running game (the helper must be running)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LUAC="$(command -v luac5.3 || command -v luac53 || command -v luac || true)"
if [ -z "$LUAC" ]; then echo "luac not found: sudo apt install lua5.3"; exit 1; fi
bad=0; n=0
for f in "$ROOT"/mod/*/*.lua; do
  n=$((n + 1))
  "$LUAC" -p "$f" || bad=$((bad + 1))
done
[ "$bad" -eq 0 ] || { echo "$bad of $n Lua files don't compile"; exit 1; }
echo "OK: $n Lua files compile"
bash "$ROOT/test/run.sh" | tail -n 1
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "NOT reloaded: a logic test failed"; exit 1; }
# --reload: ask the running bot (through the helper) to reload the mod, like tools\reload.ps1
if [ "${1:-}" = "--reload" ]; then
  mkdir -p "$ROOT/runs"; printf 'reload\n' > "$ROOT/runs/send.txt"
  echo "Reload sent; the log shows 'start ...|reload|' when it's done."
fi
