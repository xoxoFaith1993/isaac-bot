"""Deal report (2026-11-26, the deal work levels 1-2; mod/isaac-bot/deals.lua).

Reads the bot's "deal" lines from runs/live.log and the archived runs/logs/live-*.log and sums up, per log file:
bosses beaten on deal floors, the game's devil and angel chance after each, which door opened, the deal rooms
entered, and every deal item with its price, worth and decision (and why).

    python tools/deals.py            all logs
    python tools/deals.py --last 3   the newest 3 logs only
"""
import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LINE = re.compile(r"^(\d\d:\d\d:\d\d) deal\s+(.*)$")


def logs(last):
    files = sorted((ROOT / "runs" / "logs").glob("live-*.log"))
    live = ROOT / "runs" / "live.log"
    if live.exists():
        files.append(live)
    return files[-last:] if last else files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--last", type=int, default=0)
    args = ap.parse_args()
    total = {"boss": 0, "door": 0, "rooms": 0, "bought": 0, "skipped": 0}
    for path in logs(args.last):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        rows = [m.groups() for m in map(LINE.match, text.splitlines()) if m]
        if not rows:
            continue
        print(f"\n## {path.name}")
        for t, body in rows:
            if body.startswith("after boss"):
                total["boss"] += 1
                if "|door none" not in body:
                    total["door"] += 1
                print(f"  {t} {body}")
            elif body.startswith("entered"):
                total["rooms"] += 1
                kind, _, items = body.partition("|")
                print(f"  {t} {kind}")
                for it in items.split("; "):
                    print(f"      {it}")
                    total["bought"] += it.count("-> BUY")
                    total["skipped"] += it.count("-> skip")
    print(f"\nBosses on deal floors: {total['boss']}, a deal door opened: {total['door']}, "
          f"deal rooms entered: {total['rooms']}, devil items bought: {total['bought']}, skipped: {total['skipped']}")


if __name__ == "__main__":
    main()
