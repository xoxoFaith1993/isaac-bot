"""Enemy gauntlet: fights each common early enemy type in the start room (random rocks, 2 at a time, Globins 1)
and builds a table: cleared?, seconds, hits taken, and AIM QUALITY (% of shots fired that could actually hit).
So bad fighting against any enemy shows up as a number, without anyone having to spot it by eye.

Usage: python gauntlet.py            (all enemies below)
       python gauntlet.py 21.0 15.0  (just these)
Needs the game in a slot-2 run with the helper running. Appends to runs\\gauntlet.jsonl.
"""
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "brain"))
import botconfig  # noqa: E402  (bot folder: config.json "bot_dir", default this repo)

RUNS = botconfig.ROOT / "runs"
LIVE, SEND = RUNS / "live.log", RUNS / "send.txt"
ENEMIES = {
    "10.0": "Gaper", "12.0": "Horf", "13.0": "Fly", "14.0": "Pooter", "15.0": "Clotty", "16.0": "Mulligan",
    "18.0": "Attack Fly", "21.0": "Maggot", "23.0": "Charger", "24.0": "Globin", "26.0": "Maw", "27.0": "Host",
    "29.0": "Hopper", "30.0": "Boil", "85.0": "Spider", "217.0": "Dip",
    # Basement bosses, one at a time (so a change that breaks a boss shows up here, not in real runs)
    "20.0": "Monstro", "79.0": "Gemini", "261.0": "Dingle", "67.0": "Duke of Flies",
    # (Larry Jr. dropped: a one-line spawn doesn't build the multi-part worm, so it "cleared" in 0.9 s - bogus)
}
# How many at once. The author (2026-11-25): "Isaac at base won't survive three [Globins]... for proper testing,
# 1 or 2 at a time." Default 2; the nasty ones 1.
COUNT = {"24.0": 1, "20.0": 1, "79.0": 1, "261.0": 1, "67.0": 1, "19.0": 1}
DEFAULT_COUNT = 2

DONE = re.compile(r"gaunt\S*\s+(cleared|died|timeout)\|(\d+)\|(\d+)\|(\d+)\|([\d.]+)\|([\d.]+)\|(.*)$")
HIT = re.compile(r" hit    (\S+)\|")


def lines():
    return LIVE.read_text(encoding="utf-8", errors="replace").splitlines() if LIVE.exists() else []


def one(enemy, n=3, rocks=6, timeout=170, seed=None):
    start = len(lines())
    items = None
    # seed = same rocks + spawn spots every time (the auto-tuner uses this); None = random layout
    SEND.write_bytes(f"gauntlet|{enemy}|{n}|{rocks}{'|' + str(seed) if seed is not None else ''}\n".encode())
    end = time.time() + timeout
    while time.time() < end:
        time.sleep(1)
        new = lines()[start:]
        for row in new:
            mi = re.search(r"gaunt\S*\s+start\|.*\|items (\d+)", row)
            if mi:
                items = int(mi.group(1))
            m = DONE.search(row)
            if m:
                aim = {}
                for part in filter(None, m.group(7).split(",")):
                    k, v = part.split("=")
                    pct, fired = v.split("%/")
                    aim[k] = (int(pct), int(fired))
                own = aim.get(enemy, (None, 0))
                return {"enemy": enemy, "name": ENEMIES.get(enemy, enemy), "result": m.group(1), "items": items,
                        "seconds": round(int(m.group(3)) / 30, 1), "hits": int(m.group(4)),
                        "aim_pct": own[0], "shots": own[1], "aim_all": aim,
                        "hit_by": [h.group(1) for r in new if (h := HIT.search(r))]}
    return {"enemy": enemy, "name": ENEMIES.get(enemy, enemy), "result": "no answer"}


def main():
    todo = sys.argv[1:] or list(ENEMIES)
    rows = []
    # Clean bench: fight-only mode first (no wandering into a treasure room), then a brand-new item-free run.
    SEND.write_bytes(b"bot|combat\n")
    time.sleep(2)
    start = len(lines())
    SEND.write_bytes(b"newrun|\n")
    end = time.time() + 60
    while time.time() < end and not any(" start  " in l for l in lines()[start:]):
        time.sleep(1)
    time.sleep(3)
    SEND.write_bytes(b"bot|combat\n")
    time.sleep(1)
    for e in todo:
        r = one(e, n=COUNT.get(e, DEFAULT_COUNT))
        r["when"] = time.strftime("%Y-%m-%d %H:%M:%S")
        rows.append(r)
        with open(RUNS / "gauntlet.jsonl", "a", encoding="utf-8") as f:
            f.write(json.dumps(r) + "\n")
        print(f"{r['name']:<11} {r['result']:<9} {r.get('seconds', '-'):>6}s  hits {r.get('hits', '-')}  "
              f"aim {str(r.get('aim_pct')) + '%' if r.get('aim_pct') is not None else '-':>5} of {r.get('shots', 0)} shots"
              + (f"   (!! {r['items']} items: not base Isaac)" if r.get("items") else ""),
              flush=True)
        if r["result"] == "died":
            # the bot gets past the death screen and starts a new run by itself: wait for it, then carry on
            start = len(lines())
            end = time.time() + 120
            while time.time() < end and not any(" start  " in l for l in lines()[start:]):
                time.sleep(2)
            time.sleep(4)
            SEND.write_bytes(b"bot|combat\n")
        time.sleep(3)
    SEND.write_bytes(b"bot|full\n")
    ok = [r for r in rows if r.get("result") == "cleared"]
    aims = [r["aim_pct"] for r in rows if r.get("aim_pct") is not None]
    print(f"\nSUMMARY: {len(ok)}/{len(rows)} cleared, {sum(r.get('hits', 0) for r in rows)} hits, "
          f"average aim {sum(aims) / max(1, len(aims)):.0f}%")


if __name__ == "__main__":
    main()
