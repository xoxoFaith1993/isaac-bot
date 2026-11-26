#!/usr/bin/env python3
"""Offline logic tests on any OS: test/tests.lua against the bot's REAL Lua code with a fake Isaac (test/mock.lua).

The same run as test/run.ps1, but with a normal Lua 5.3 or 5.4 instead of the game's own 32-bit DLL, so it works on
Linux, macOS, Windows (with a Lua on PATH) and GitHub Actions. No game needed. Standard library only.

    python3 test/run.py                  every test (first: every mod Lua file compiles, no byte-order marks)
    python3 test/run.py --only corridor  only the tests whose name contains this text
    python3 test/run.py --prove          the mutant check (test/mutants.lua): undo each fix IN MEMORY, run the test
                                         that guards it, and check that it now FAILS
    python3 test/run.py --lua /path/lua5.4   pick the Lua (default: lua5.3, lua53, lua5.4, lua54, lua on PATH)

Install Lua: Debian/Ubuntu `sudo apt install lua5.3` (or lua5.4), Fedora `lua`, Arch `lua53`, macOS `brew install lua`.

Output and exit code match run.ps1 line for line: PASS / FAIL / CRASH / KNOWN lines, then "N passed, N failed, N
known bug(s)"; exit 1 on any failure. With --prove every mutant prints caught / NOT CAUGHT / STALE / NO TEST /
NOT LOADED (see run.ps1 for what each means).
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEST = ROOT / "test"
MOD = ROOT / "mod" / "isaac-bot"
LUA_NAMES = ["lua5.3", "lua53", "lua5.4", "lua54", "lua"]  # the game runs Lua 5.3.3, so 5.3 first


def find_lua(wanted):
    if wanted:
        return wanted
    for name in LUA_NAMES:
        path = shutil.which(name)
        if path:
            return path
    sys.exit("No Lua found. Install Lua 5.3 or 5.4 (Ubuntu: sudo apt install lua5.3; macOS: brew install lua), "
             "or pass --lua PATH.")


def lua_version(lua):
    out = subprocess.run([lua, "-v"], capture_output=True, text=True)
    return (out.stdout + out.stderr).strip()


def lua_str(text):
    """A Lua long-bracket string literal holding `text` exactly (paths with quotes or spaces are safe)."""
    level = 0
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    return "[" + eq + "[" + text + "]" + eq + "]"


def lua_path(p):
    return str(p).replace("\\", "/")


def run_chunk(lua, chunk, timeout=900):
    """Run one Lua chunk in a fresh interpreter (= a fresh Lua state, like run.ps1). Returns its output text."""
    fd, tmp = tempfile.mkstemp(suffix=".lua", prefix="isaacbot_test_")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            f.write(chunk)
        p = subprocess.run([lua, tmp], capture_output=True, text=True, timeout=timeout, cwd=ROOT,
                           encoding="utf-8", errors="replace")
    finally:
        os.unlink(tmp)
    out = p.stdout
    if p.returncode != 0:  # the chunk itself failed (run.ps1 prints "ERROR <message>" for this)
        out += ("\n" if out else "") + "ERROR " + (p.stderr.strip() or "lua exited with code %d" % p.returncode)
    return out


def invoke_tests(lua, tests, pre=""):
    """The exact chunk run.ps1 builds: set MOD_DIR (+ ONLY / MUTANT), load the fake game, run the tests."""
    chunk = "\n".join([
        "MOD_DIR = " + lua_str(lua_path(MOD)),
        pre,
        "local ok, res = xpcall(function() dofile(%s); return dofile(%s) end, debug.traceback)"
        % (lua_str(lua_path(TEST / "mock.lua")), lua_str(lua_path(tests))),
        "local tail = MUTANT and ('\\nAPPLIED ' .. tostring(MUTANT.applied or 0) .. '/' .. #MUTANT.patches) or ''",
        "io.write((ok and tostring(res) or ('CRASH ' .. tostring(res))) .. tail, '\\n')",
    ])
    return run_chunk(lua, chunk)


def compile_check(lua):
    """What tools/luacheck.ps1 checks: every mod Lua file compiles and has no byte-order mark."""
    files = sorted((ROOT / "mod").glob("*/*.lua"))
    bom = [f for f in files if f.read_bytes().startswith(b"\xef\xbb\xbf")]
    for f in bom:
        print("BYTE-ORDER MARK (the game's Lua can't read it): %s" % f.relative_to(ROOT).as_posix())
    listing = ", ".join(lua_str(lua_path(f)) for f in files)
    chunk = ("local bad = 0\nfor _, f in ipairs({%s}) do\n"
             "  local fn, err = loadfile(f)\n  if not fn then bad = bad + 1; io.write('COMPILE ', err, '\\n') end\n"
             "end\nio.write('BAD ', bad, '\\n')\n") % listing
    out = run_chunk(lua, chunk)
    for line in out.splitlines():
        if line.startswith("COMPILE") or line.startswith("ERROR"):
            print(line)
    m = re.search(r"^BAD (\d+)$", out, re.M)
    bad = (int(m.group(1)) if m else len(files)) + len(bom)
    if bad:
        print("%d of %d Lua files have problems" % (bad, len(files)))
        return False
    print("OK: %d Lua files compile, no byte-order marks" % len(files))
    return True


def count(out, pattern):
    return sum(1 for line in out.split("\n") if re.match(pattern, line))


def run_suite(lua, tests, only):
    pre = ("ONLY = " + lua_str(only)) if only else ""
    out = invoke_tests(lua, tests, pre)
    print(out.rstrip("\n"))
    fails = count(out, r"^(FAIL|CRASH|ERROR)")
    passes = count(out, r"^PASS")
    known = count(out, r"^(KNOWN|FIXED\?)")
    # KNOWN = a real bug written up in test/FOUND_BUGS.md, not fixed yet (doesn't count as a failure)
    print("\n%d passed, %d failed" % (passes, fails) +
          (", %d known bug(s) (test/FOUND_BUGS.md)" % known if known else ""))
    if passes == 0 and fails == 0 and not only:
        print("Nothing ran: the test file returned no results.")
        return 1
    return 1 if fails else 0


def prove(lua, tests, jobs):
    mutants = lua_str(lua_path(TEST / "mutants.lua"))
    listing = run_chunk(lua, "local M = dofile(%s)\nlocal out = {}\n"
                             "for i, m in ipairs(M) do out[#out + 1] = i .. '\\t' .. m.test .. '\\t' .. m.why end\n"
                             "io.write(table.concat(out, '\\n'))\n" % mutants)
    if re.search(r"^ERROR", listing, re.M):
        print("mutants.lua: " + listing)
        return 1
    entries = [line.split("\t", 2) for line in listing.split("\n") if line.strip()]

    def one(entry):
        i, test, why = entry
        out = invoke_tests(lua, tests, "MUTANT = dofile(%s)[%s]; ONLY = MUTANT.test" % (mutants, i))
        rows = out.split("\n")
        applied = next((r[len("APPLIED "):] for r in rows if r.startswith("APPLIED")), "")
        result = next((r for r in rows if re.match(r"^(PASS|FAIL)", r)), "")
        if "MUTANT PATCH NOT FOUND" in out:
            verdict = "STALE      "
        elif not result:
            verdict = "NO TEST    "
        elif applied and int(applied.split("/")[0]) < int(applied.split("/")[1]):
            verdict = "NOT LOADED "
        elif result.startswith("FAIL"):
            verdict = "caught     "
        else:
            verdict = "NOT CAUGHT "
        text = "%s [%s] without: %s" % (verdict, test, why)
        if verdict != "caught     ":
            text += "\n            " + result
        return verdict, text

    # each mutant runs in its own Lua process, so they can run side by side; results print in mutants.lua order
    with ThreadPoolExecutor(max_workers=max(1, jobs)) as pool:
        results = list(pool.map(one, entries))
    bad = 0
    for verdict, text in results:
        print(text)
        if verdict != "caught     ":
            bad += 1
    print("\n%d problem(s)" % bad)
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser(description="Offline Lua tests (cross-platform version of test/run.ps1)")
    ap.add_argument("--only", default="", help="run only the tests whose name contains this text")
    ap.add_argument("--prove", action="store_true", help="mutant check: each fix's test must fail without the fix")
    ap.add_argument("--tests", default="", help="a different scenario file (default test/tests.lua)")
    ap.add_argument("--lua", default=os.environ.get("LUA", ""), help="the Lua interpreter (default: found on PATH)")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 2, help="mutants run side by side (--prove)")
    ap.add_argument("--no-compile", action="store_true", help="skip the compile + byte-order-mark check")
    a = ap.parse_args()

    lua = find_lua(a.lua)
    version = lua_version(lua)
    print("Lua: %s (%s)" % (version, lua))
    if not re.search(r"5\.[34]", version):
        print("warning: the game uses Lua 5.3; results may differ on this version")
    tests = Path(a.tests).resolve() if a.tests else TEST / "tests.lua"

    if not a.no_compile and not compile_check(lua):
        return 1
    if a.prove:
        return prove(lua, tests, a.jobs)
    return run_suite(lua, tests, a.only)


if __name__ == "__main__":
    sys.exit(main())
