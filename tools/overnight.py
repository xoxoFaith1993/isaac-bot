"""Overnight batch (the author, 2026-11-25: "Yes, tonight"). One FIXED bot version all night, so results compare fairly.

Until END_HOUR (default 8:00), alternate:
  A. bench: every room in knowledge\\bench_rooms.json, REPEATS times each, from a fresh item-free run
  B. ~45 min of scored real play (fresh runs on save slot 2)
Watchdog: if runs\\live.log stops growing for 3 minutes (game frozen/crashed, helper gone), restart the bot via
restart-bot.cmd (through Explorer, so it outlives any shell). Safety (PC stability rules): before starting and every
round, C: must have 15+ GB free and Windows 3+ GB of commit headroom, else it stops cleanly.
Writes runs\\overnight\\<date>\\: bench.jsonl, real.jsonl, overnight.log, and MORNING_REPORT.md at the end
(also rewritten after every round, so a crash still leaves a report).

Run detached:  pythonw tools\\overnight.py  [END_HOUR] [REPEATS]
"""
import collections
import ctypes
import json
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUNS = ROOT / "runs"
LIVE = RUNS / "live.log"
SEND = RUNS / "send.txt"
BENCH_LIST = ROOT / "knowledge" / "bench_rooms.json"
RESTART = ROOT / "restart-bot.cmd"
END_HOUR = int(sys.argv[1]) if len(sys.argv) > 1 else 8
REPEATS = int(sys.argv[2]) if len(sys.argv) > 2 else 3
REAL_MINUTES = 45
STAGE_SUFFIX = {0: "", 1: "a", 2: "b", 4: "c", 5: "d"}

now = datetime.now()
END = now.replace(hour=END_HOUR, minute=0, second=0, microsecond=0)
if END <= now:
    END += timedelta(days=1)
OUT = RUNS / "overnight" / now.strftime("%Y-%m-%d")
OUT.mkdir(parents=True, exist_ok=True)
LOG = OUT / "overnight.log"


def log(msg):
    line = time.strftime("%H:%M:%S ") + msg
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")


# ---------------------------------------------------------------- safety (PC stability rules)
class MEMSTATUS(ctypes.Structure):
    _fields_ = [("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong), ("ullTotalPhys", ctypes.c_ulonglong),
                ("ullAvailPhys", ctypes.c_ulonglong), ("ullTotalPageFile", ctypes.c_ulonglong),
                ("ullAvailPageFile", ctypes.c_ulonglong), ("ullTotalVirtual", ctypes.c_ulonglong),
                ("ullAvailVirtual", ctypes.c_ulonglong), ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]


def safe_to_continue():
    c_free = shutil.disk_usage("C:\\").free / 1e9
    m = MEMSTATUS()
    m.dwLength = ctypes.sizeof(MEMSTATUS)
    ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m))
    commit_free = m.ullAvailPageFile / 1e9
    ok = c_free >= 15 and commit_free >= 3
    if not ok:
        log(f"SAFETY STOP: C: {c_free:.1f} GB free, commit headroom {commit_free:.1f} GB")
    return ok


# ---------------------------------------------------------------- talking to the bot
def lines():
    try:
        return LIVE.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []


def send(cmd):
    SEND.write_bytes((cmd + "\n").encode())
    time.sleep(1.5)


def wait_for(pattern, start, timeout):
    end = time.time() + timeout
    while time.time() < end:
        time.sleep(1)
        ls = lines()
        if len(ls) < start:  # the log was rotated (restart): look from the top
            start = 0
        for l in ls[start:]:
            m = re.search(pattern, l)
            if m:
                return m
    return None


def log_age():
    try:
        return time.time() - LIVE.stat().st_mtime
    except OSError:
        return 9999


def restart_bot(why):
    log(f"restarting the bot ({why})")
    subprocess.Popen(["explorer.exe", str(RESTART)])
    t0 = time.time()
    time.sleep(10)
    while time.time() - t0 < 180:
        time.sleep(3)
        if any(" start  " in l and "|false|" in l for l in lines()[-400:]) and log_age() < 5:
            time.sleep(5)
            log("bot is back")
            return True
    log("bot did not come back within 3 minutes")
    return False


def watchdog():
    if log_age() > 180:
        restart_bot("log silent for 3 minutes")


def fresh_run(mode):
    s = len(lines())
    send("newrun")
    if not wait_for(r" start  ", s, 40):
        watchdog()
    send("bot|" + mode)
    time.sleep(3)


def stage_cmd(stage):
    s, t = int(stage[:-1]), int(stage[-1])
    return f"{s}{STAGE_SUFFIX.get(t, '')}"


# ---------------------------------------------------------------- A. bench
def bench_round():
    rooms = json.loads(BENCH_LIST.read_text(encoding="utf-8")) if BENCH_LIST.exists() else []
    for rep in range(REPEATS):
        for r in rooms:
            if datetime.now() >= END or not safe_to_continue():
                return
            fresh_run("combat")
            s0 = len(lines())
            send("stage|" + stage_cmd(r["stage"]))
            wait_for(r" bench  stage", s0, 20)
            time.sleep(3)
            s1 = len(lines())
            send(f"goroom|{r['kind']}|{r['variant']}")
            m = wait_for(r" bench  (cleared|died|timeout|failed)\|?([\d.]*)\|?(\d*)", s1, 130)
            row = {"when": time.strftime("%Y-%m-%d %H:%M:%S"), "room": f"{r['stage']}.{r['kind']}.{r['variant']}",
                   "name": r.get("name", ""), "result": m.group(1) if m else "no answer",
                   "seconds": float(m.group(2)) if m and m.group(2) else None,
                   "hits": int(m.group(3)) if m and m.group(3) else None}
            with open(OUT / "bench.jsonl", "a", encoding="utf-8") as f:
                f.write(json.dumps(row) + "\n")
            if not m:
                watchdog()
            elif m.group(1) == "died":
                wait_for(r" start  ", len(lines()) - 5, 60)
                time.sleep(3)


# ---------------------------------------------------------------- B. scored real play
def score_lines(ls):
    runs, cur, floor, roomtype = [], None, 0, 0
    for l in ls:
        m = re.match(r"^\S+ floor +(\d+)\|", l)
        if m:
            floor = int(m.group(1))
            if floor == 1 and (cur is None or cur["max_floor"] > 1 or cur["hits"]):
                cur = {"start": l[:8], "max_floor": 1, "hits": collections.Counter(), "boss": 0, "causes": [],
                       "end": "running", "power": None}
                runs.append(cur)
            if cur:
                cur["max_floor"] = max(cur["max_floor"], floor)
        m = re.match(r"^\S+ room +-?\d+\|(\d+)", l)
        if m:
            roomtype = int(m.group(1))
        m = re.match(r"^\S+ power +dmg ([\d.]+)\|tears ([\d.]+)\|speed ([\d.]+)\|range (\d+)\|items (.*)$", l)
        if m and cur:
            cur["power"] = {"dmg": float(m.group(1)), "tears": float(m.group(2)),
                            "items": [x for x in m.group(5).split(",") if x]}
        m = re.match(r"^\S+ hit +([^|]+)", l)
        if m and cur:
            cur["hits"][floor] += 1
            if roomtype == 5:
                cur["boss"] += 1
            cur["causes"].append(f"F{floor}{'B' if roomtype == 5 else ''}:{m.group(1)}")
        m = re.match(r"^\S+ runend +(\w+)\|", l)
        if m and cur:
            cur["end"] = m.group(1)
            cur = None
    return runs


def real_round():
    fresh_run("full")
    start = len(lines())
    t_end = min(datetime.now() + timedelta(minutes=REAL_MINUTES), END)
    while datetime.now() < t_end:
        time.sleep(30)
        watchdog()
        if not safe_to_continue():
            break
        if len(lines()) < start:  # restarted: the old part is archived; keep going on the new log
            start = 0
    runs = score_lines(lines()[start:])
    with open(OUT / "real.jsonl", "a", encoding="utf-8") as f:
        for r in runs:
            pw = r["power"] or {}
            carried = pw.get("dmg", 0) >= 5 or pw.get("tears", 0) >= 4 or len(pw.get("items", [])) >= 4
            f.write(json.dumps({"start": r["start"], "max_floor": r["max_floor"], "end": r["end"],
                                "f1": r["hits"][1], "f2": r["hits"][2], "boss": r["boss"],
                                "causes": r["causes"], "carried": carried}) + "\n")


# ---------------------------------------------------------------- morning report
def report():
    def jl(name):
        p = OUT / name
        return [json.loads(x) for x in p.read_text(encoding="utf-8").splitlines() if x.strip()] if p.exists() else []
    bench, real = jl("bench.jsonl"), jl("real.jsonl")
    out = [f"# Overnight report ({OUT.name})", "", f"Bot version: {version()}. Window: {now:%H:%M} to {END:%H:%M}.", ""]
    out += ["## Bench rooms (fresh item-free run each time)", "", "| Room | Rounds | Cleared | Avg hits | No-hit clears |",
            "|---|---|---|---|---|"]
    by = collections.defaultdict(list)
    for b in bench:
        by[(b["room"], b["name"])].append(b)
    for (room, name), rows in sorted(by.items(), key=lambda kv: -sum((x["hits"] or 0) for x in kv[1]) / len(kv[1])):
        cl = sum(1 for x in rows if x["result"] == "cleared")
        hits = [x["hits"] for x in rows if x["hits"] is not None]
        nohit = sum(1 for x in rows if x["result"] == "cleared" and x["hits"] == 0)
        out.append(f"| {name or room} ({room}) | {len(rows)} | {cl} | {sum(hits) / max(1, len(hits)):.1f} | {nohit} |")
    done = [r for r in real if r["end"] != "running"]
    reached3 = [r for r in real if r["max_floor"] >= 3]
    clean = [r for r in reached3 if r["f1"] + r["f2"] == 0]
    out += ["", "## Real runs (save slot 2)", "",
            f"- runs: {len(real)} ({len(done)} finished); reached floor 3+: {len(reached3)}; "
            f"**no damage on floors 1-2: {len(clean)} of {len(reached3)}**",
            f"- floors reached: {dict(collections.Counter(r['max_floor'] for r in real))}",
            f"- carried by items: {sum(1 for r in real if r['carried'])}",
            f"- average hits floor 1: {sum(r['f1'] for r in real) / max(1, len(real)):.1f}, "
            f"floor 2: {sum(r['f2'] for r in real) / max(1, len(real)):.1f}, in boss rooms: "
            f"{sum(r['boss'] for r in real) / max(1, len(real)):.1f} per run"]
    causes = collections.Counter(c.split(":", 1)[1] for r in real for c in r["causes"] if c[1] in "12")
    out += [f"- floor 1-2 hits by cause: {dict(causes.most_common(12))}", ""]
    events = LOG.read_text(encoding="utf-8").splitlines() if LOG.exists() else []
    out += ["## Night log (restarts, safety)", ""] + [f"- {e}" for e in events if "restart" in e or "SAFETY" in e
                                                       or "bot did not" in e][-20:]
    (OUT / "MORNING_REPORT.md").write_text("\n".join(out) + "\n", encoding="utf-8")


def version():
    for l in reversed(lines()):
        m = re.search(r" start  ([\d.]+)\|", l)
        if m:
            return m.group(1)
    return "?"


def main():
    # keep the PC from idle-sleeping while this runs (Windows' own "busy" flag: no settings change, ends with the job)
    ES_CONTINUOUS, ES_SYSTEM_REQUIRED = 0x80000000, 0x00000001
    ctypes.windll.kernel32.SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)
    log(f"overnight batch start: until {END:%Y-%m-%d %H:%M}, bench repeats {REPEATS}, real play {REAL_MINUTES} min")
    if not safe_to_continue():
        report()
        return
    if log_age() > 60:
        restart_bot("not running at start")
    try:
        while datetime.now() < END and safe_to_continue():
            bench_round()
            report()
            if datetime.now() >= END:
                break
            real_round()
            report()
    finally:
        send("bot|full")
        report()
        log("overnight batch done")


if __name__ == "__main__":
    main()
