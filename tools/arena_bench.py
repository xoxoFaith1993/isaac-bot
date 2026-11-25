"""Arena benchmark: runs a series of enemy waves in the bot's slot-2 run and records the results.

Usage: python arena_bench.py 5 5 6 6 8 8      (one wave per number = enemies in that wave)
Needs the game in a slot-2 run with the helper running (it forwards runs\\send.txt).
Results: printed, and appended to runs\\arena.jsonl (one line per wave) for the learning loop later.
"""
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "brain"))
import botconfig  # noqa: E402  (bot folder: config.json "bot_dir", default this repo)

RUNS = botconfig.ROOT / "runs"
LIVE = RUNS / "live.log"
SEND = RUNS / "send.txt"
RESULT = re.compile(r"arena  (cleared|died|timeout)\|(\d+)\|(\d+)\|(\d+)\|([\d.]+)\|(.*)$")
HIT = re.compile(r" hit    (\S+)\|")


def lines():
    return LIVE.read_text(encoding="utf-8", errors="replace").splitlines() if LIVE.exists() else []


def run_wave(n, timeout=110):
    start_len = len(lines())
    SEND.write_bytes(f"arena|{n}\n".encode())
    end = time.time() + timeout
    while time.time() < end:
        time.sleep(1)
        new = lines()[start_len:]
        for row in new:
            m = RESULT.search(row)
            if m:
                hits_by = [h.group(1) for r in new if (h := HIT.search(r))]
                return {"when": time.strftime("%Y-%m-%d %H:%M:%S"), "result": m.group(1), "enemies": int(m.group(2)),
                        "seconds": round(int(m.group(3)) / 30, 1), "hits": int(m.group(4)),
                        "damage": float(m.group(5)), "wave": m.group(6), "hit_by": hits_by}
    return {"result": "no answer", "enemies": n}


def main():
    sizes = [int(x) for x in sys.argv[1:]] or [5, 5, 6, 6]
    results = []
    for n in sizes:
        r = run_wave(n)
        results.append(r)
        print(json.dumps(r), flush=True)
        with open(RUNS / "arena.jsonl", "a", encoding="utf-8") as f:
            f.write(json.dumps(r) + "\n")
        if r["result"] == "died":
            print("Isaac died; stopping the benchmark.")
            break
        time.sleep(3)
    done = [r for r in results if r.get("result") == "cleared"]
    print(f"\nSUMMARY: {len(done)}/{len(results)} waves cleared, "
          f"{sum(r.get('hits', 0) for r in results)} hits taken, "
          f"avg clear {sum(r['seconds'] for r in done) / max(1, len(done)):.1f} s")


if __name__ == "__main__":
    main()
