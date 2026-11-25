"""Batch review (#5): turns the bot's logs into one report, grouped by KIND of problem, so fixes cover whole
categories instead of single cases.

Reads runs\\runs.jsonl, stuck.jsonl, hits.jsonl, brain.jsonl, arena.jsonl. Writes runs\\REVIEW.md.
Usage: python review.py
"""
import collections
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "brain"))
import botconfig  # noqa: E402  (bot folder: config.json "bot_dir", default this repo)

RUNS = botconfig.ROOT / "runs"
FLOORS = {1: "Basement I", 2: "Basement II", 3: "Caves I", 4: "Caves II", 5: "Depths I", 6: "Depths II",
          7: "Womb I", 8: "Womb II", 9: "Blue Womb", 10: "Sheol/Cathedral", 11: "Dark Room/Chest"}
ENEMIES = {10: "Gaper", 12: "Horf", 13: "Fly", 14: "Pooter", 15: "Clotty", 16: "Mulligan", 18: "Attack Fly",
           20: "Monstro", 21: "Maggot", 23: "Charger", 24: "Globin", 25: "Boom Fly", 26: "Maw", 27: "Host",
           29: "Hopper", 30: "Boil", 31: "Spittie", 9: "enemy shot", 7: "laser", 4: "bomb", 1000: "effect (creep)",
           217: "Dip", 261: "Dingle", 85: "Spider", 61: "Sucker", 80: "Moter", 88: "Walking Boil",
           33: "Fireplace (lit fire)"}


def load(name):
    p = RUNS / name
    if not p.exists():
        return []
    rows = []
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            rows.append(json.loads(line))
        except ValueError:
            pass
    return rows


def main():
    runs, stuck, hits, brain, arena = (load(n) for n in ("runs.jsonl", "stuck.jsonl", "hits.jsonl", "brain.jsonl", "arena.jsonl"))
    out = [f"# Isaac Bot review ({time.strftime('%Y-%m-%d %H:%M')})", ""]

    out += ["## Runs", ""]
    if runs:
        best = max(runs, key=lambda r: r["floor"])
        out.append(f"{len(runs)} runs. Furthest: {best['floor_name']} ({best['result']}, {best['seconds'] // 60} min). "
                   f"Average run {sum(r['seconds'] for r in runs) / len(runs) / 60:.1f} min.")
        for floor, n in sorted(collections.Counter(r["floor_name"] for r in runs).items()):
            out.append(f"- ended on {floor}: {n}")
    else:
        out.append("No finished runs logged yet.")

    out += ["", "## Damage taken, by what hit it", ""]
    by_src = collections.Counter()
    for h in hits:
        src = h["hit"].split("|")[0]
        t = int(src.split(".")[0]) if src.split(".")[0].isdigit() else -1
        by_src[ENEMIES.get(t, f"type {src}")] += 1
    out += [f"- {name}: {n} hit(s)" for name, n in by_src.most_common()] or ["No hits logged."]

    out += ["", "## Stuck moments, by kind", ""]
    kinds = collections.Counter()
    examples = {}
    for s in stuck:
        parts = s["report"].split("|")
        goal = parts[4] if len(parts) > 4 else "?"
        mode = parts[3] if len(parts) > 3 else "?"
        key = f"{mode}: {goal.split('(')[0].strip() or '(no goal)'}"
        kinds[key] += 1
        examples.setdefault(key, s)
    for k, n in kinds.most_common():
        ex = examples[k]
        out.append(f"- **{k}**: {n} time(s). Example {ex['when']}, report `{ex['report']}`")
    if not stuck:
        out.append("No stuck reports.")

    out += ["", "## Brain answers to stuck reports", ""]
    acts = collections.Counter(b.get("action", "error") for b in brain)
    out += [f"- {a}: {n}" for a, n in acts.most_common()] or ["None yet."]
    errs = [b for b in brain if "error" in b]
    if errs:
        out.append(f"- brain errors: {len(errs)} (latest: {errs[-1]['error']})")
    times = [b["seconds"] for b in brain if "seconds" in b]
    if times:
        out.append(f"- average thinking time {sum(times) / len(times):.1f} s")

    if arena:
        out += ["", "## Arena", ""]
        clear = [a for a in arena if a.get("result") == "cleared"]
        out.append(f"{len(clear)}/{len(arena)} waves cleared, {sum(a.get('hits', 0) for a in arena)} hits taken.")

    (RUNS / "REVIEW.md").write_text("\n".join(out) + "\n", encoding="utf-8")
    print("\n".join(out))


if __name__ == "__main__":
    main()
