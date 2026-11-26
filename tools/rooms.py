"""Real-room bench (2026-11-25, after the author: "there has to be a better way than fixing every little bug").

Every room where the bot takes a hit gets saved by its layout ID; fixes are judged by replaying THOSE rooms, and
they stay in the list as a check so old problems can't come back.

  python rooms.py collect          add rooms with hits from runs\\live.log to knowledge\\bench_rooms.json
  python rooms.py run [N]          replay up to N saved rooms (default all), worst first; prints a summary
  python rooms.py list             show the saved rooms

The mod logs every room as "room IDX|TYPE|VARIANT|STAGE|NAME" (STAGE = stage + stage type, "10" = Basement I).
Replay: "stage|<1, 1a, 1b, ...>" then "goroom|normal|<variant>" (boss rooms: "goroom|boss|<variant>").
"""
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "brain"))
import botconfig  # noqa: E402  (bot folder: config.json "bot_dir", default this repo)
ROOT = botconfig.ROOT
LIVE = ROOT / "runs" / "live.log"
SEND = ROOT / "runs" / "send.txt"
LIST = ROOT / "knowledge" / "bench_rooms.json"
RESULTS = ROOT / "runs" / "bench.jsonl"
TYPE_NAMES = {1: "normal", 5: "boss", 6: "miniboss"}  # other room types aren't fights worth replaying
STAGE_SUFFIX = {0: "", 1: "a", 2: "b", 4: "c", 5: "d"}


def load():
    return json.loads(LIST.read_text(encoding="utf-8")) if LIST.exists() else []


def save(rooms):
    LIST.write_text(json.dumps(rooms, indent=1), encoding="utf-8")


def lines():
    return LIVE.read_text(encoding="utf-8", errors="replace").splitlines() if LIVE.exists() else []


def all_log_lines():
    """The current live.log plus every archived session log (runs\\logs\\live-*.log), oldest first."""
    out = []
    for f in sorted((LIVE.parent / "logs").glob("live-*.log")):
        out += f.read_text(encoding="utf-8", errors="replace").splitlines()
    return out + lines()


def collect():
    # counts are rebuilt from all logs every time (re-running used to count the same hits again); rooms seen only
    # in logs that have since been deleted keep their old counts
    rooms = load()
    known = {(r["stage"], r["kind"], r["variant"]): r for r in rooms}
    fresh = {}
    cur = None
    added = 0
    for l in all_log_lines():
        m = re.match(r"^\S+ room +(-?\d+)\|(\d+)\|(\d+)\|(\d+)\|(.*)$", l)
        if m:
            idx, rtype, variant, stage, name = m.groups()
            cur = None
            if idx != "-3" and int(rtype) in TYPE_NAMES:  # not bench replays themselves
                cur = (stage, TYPE_NAMES[int(rtype)], variant, name)
            continue
        h = re.match(r"^\S+ hit +([^|]+)", l)
        if h and cur:
            key = cur[:3]
            r = known.get(key)
            if not r:
                r = {"stage": cur[0], "kind": cur[1], "variant": cur[2], "name": cur[3], "hits_seen": 0,
                     "causes": {}}
                known[key] = r
                rooms.append(r)
                added += 1
            if key not in fresh:
                fresh[key] = True
                r["hits_seen"], r["causes"] = 0, {}
            r["hits_seen"] += 1
            r["causes"][h.group(1)] = r["causes"].get(h.group(1), 0) + 1
    save(rooms)
    print(f"{added} new rooms; {len(rooms)} in the bench list")


def send(cmd):
    SEND.write_bytes((cmd + "\n").encode())
    time.sleep(1.2)


def wait_for(pattern, start, timeout):
    end = time.time() + timeout
    while time.time() < end:
        time.sleep(1)
        for l in lines()[start:]:
            m = re.search(pattern, l)
            if m:
                return m
    return None


def stage_cmd(stage):
    s, t = int(stage[:-1]), int(stage[-1])
    return f"{s}{STAGE_SUFFIX.get(t, '')}"


def run(limit=None):
    rooms = sorted(load(), key=lambda r: -r["hits_seen"])
    if limit:
        rooms = rooms[:limit]
    # a fresh, item-free run first: every replay is plain Isaac vs that room, so results compare like for like
    # (the author: an item can make the bot look better or worse than it is, and hide bugs)
    start = len(lines())
    send("newrun")
    wait_for(r" start  ", start, 30)
    # fight-only straight away: in "full" mode it sometimes walked into the treasure room and took an item before
    # the replay started (hit review: Virgo, Fire Mind), so the "item-free" bench wasn't
    send("bot|combat")
    time.sleep(3)
    total_hits, cleared, rows = 0, 0, []
    current_stage = None
    for r in rooms:
        if r["stage"] != current_stage:
            start = len(lines())
            send("stage|" + stage_cmd(r["stage"]))
            wait_for(r" bench  stage ", start, 15)
            time.sleep(3)
            current_stage = r["stage"]
        start = len(lines())
        send(f"goroom|{r['kind']}|{r['variant']}")
        m = wait_for(r" bench  (cleared|died|timeout|failed)\|?([\d.]*)\|?(\d*)", start, 110)
        res = m.group(1) if m else "no answer"
        hits = int(m.group(3)) if m and m.group(3) else 0
        secs = m.group(2) if m else ""
        total_hits += hits
        cleared += res == "cleared"
        rows.append((r, res, secs, hits))
        print(f"{r['stage']} {r['kind']}.{r['variant']:<6} {r['name'][:24]:<24} {res:<8} {secs:>5}s hits {hits}"
              f"   (seen {r['hits_seen']}: {', '.join(r['causes'])})", flush=True)
        with open(RESULTS, "a", encoding="utf-8") as f:
            f.write(json.dumps({"when": time.strftime("%Y-%m-%d %H:%M:%S"), "room": f"{r['stage']}.{r['variant']}",
                                "result": res, "seconds": secs, "hits": hits}) + "\n")
        if res == "died":
            start = len(lines())
            wait_for(r" start  ", start, 60)
            time.sleep(4)
            current_stage = None
            send("bot|combat")
        time.sleep(2)
    send("bot|full")
    print(f"\nBENCH: {cleared}/{len(rows)} rooms cleared, {total_hits} hits in all")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    if cmd == "collect":
        collect()
    elif cmd == "run":
        run(int(sys.argv[2]) if len(sys.argv) > 2 else None)
    else:
        for r in sorted(load(), key=lambda r: -r["hits_seen"]):
            print(f"{r['stage']} {r['kind']}.{r['variant']:<6} {r['name'][:24]:<24} seen {r['hits_seen']} hits: {r['causes']}")


if __name__ == "__main__":
    main()
