"""Auto-tuner: the "hand-tune the weights" grind, automated (the game-AI field tunes utility weights by hand).

Changes ONE of the bot's numbers live (the mod's "set|key=value", no restart), runs the hardest enemies in the
gauntlet, and keeps the change only if the score improves. Winners go to knowledge\\tuned.json, which the helper
re-applies at every launch, so tuning accumulates across sessions.

Score per pass (lower is better): 40 per failed round + 10 per hit + seconds / 5.
Usage: python tune.py [rounds]      (default: keep going until stopped)
"""
import json
import random
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gauntlet  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "brain"))
import botconfig  # noqa: E402  (bot folder: config.json "bot_dir", default this repo)

ROOT = botconfig.ROOT
TUNED = ROOT / "knowledge" / "tuned.json"
LOG = ROOT / "runs" / "tune.jsonl"
HARD = ["79.0", "67.0", "261.0", "12.0", "24.0", "10.0"]  # Gemini, Duke, Dingle, Horf, Globin, Gaper

# knob: (current default, min, max, step)
KNOBS = {
    "touch_margin": (14, 6, 40, 4), "hit_margin": (10, 4, 24, 3), "crowd_r": (110, 70, 180, 15),
    "crowd_w": (2.0, 0.8, 4.0, 0.4), "orbit_w": (45, 0, 120, 15), "tele_w": (260, 80, 500, 60),
    "pref_dist": (150, 100, 220, 20), "escape_w": (22, 8, 50, 6), "stand_safe_r": (150, 90, 230, 20),
    "shooter_line_w": (70, 0, 160, 25), "calm_commit": (4, 1, 8, 1), "horizon": (12, 8, 18, 2),
}


def send(cmd):
    gauntlet.SEND.write_bytes((cmd + "\n").encode())
    time.sleep(1.2)


def score(rows):
    s = 0.0
    for r in rows:
        if r.get("result") != "cleared":
            s += 40
        s += 10 * r.get("hits", 0) + r.get("seconds", 90) / 5
    return round(s, 1)


def run_pass():
    rows = []
    for e in HARD:
        # fixed layout per enemy (same rocks/spawns every pass) so only the setting under test changes
        seed = sum(ord(c) for c in e) * 7919
        r = gauntlet.one(e, n=gauntlet.COUNT.get(e, gauntlet.DEFAULT_COUNT), seed=seed)
        rows.append(r)
        if r.get("result") == "died":  # wait for the bot's own new run, back to fight-only
            start = len(gauntlet.lines())
            end = time.time() + 120
            while time.time() < end and not any(" start  " in l for l in gauntlet.lines()[start:]):
                time.sleep(2)
            time.sleep(4)
            send("bot|combat")
        time.sleep(2)
    return rows


def main():
    rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 10 ** 6
    tuned = json.loads(TUNED.read_text(encoding="utf-8")) if TUNED.exists() else {}
    current = {k: tuned.get(k, v[0]) for k, v in KNOBS.items()}
    send("bot|combat")
    for k, v in current.items():
        send(f"set|{k}={v}")
    b1, b2 = score(run_pass()), score(run_pass())  # baseline = average of two passes
    base = (b1 + b2) / 2
    print(f"baseline score {base} ({b1}, {b2})", flush=True)
    for i in range(rounds):
        k = random.choice(list(KNOBS))
        _, lo, hi, step = KNOBS[k]
        new = round(min(hi, max(lo, current[k] + random.choice((-step, step)))), 2)
        if new == current[k]:
            continue
        send(f"set|{k}={new}")
        s = score(run_pass())
        # random rocks make every pass a bit different: only a CLEAR improvement counts, not a lucky room
        keep = s < base - max(5.0, base * 0.08)
        row = {"when": time.strftime("%Y-%m-%d %H:%M:%S"), "knob": k, "from": current[k], "to": new,
               "score": s, "best": base, "kept": keep}
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(row) + "\n")
        print(f"{row['when']}  {k}: {current[k]} -> {new}  score {s} vs best {base}  {'KEPT' if keep else 'reverted'}",
              flush=True)
        if keep:
            # confirm with a second pass before believing it (one lucky pass isn't proof)
            s2 = score(run_pass())
            if (s + s2) / 2 < base - max(5.0, base * 0.08):
                current[k], base = new, (s + s2) / 2
                TUNED.parent.mkdir(exist_ok=True)
                TUNED.write_text(json.dumps(current, indent=1), encoding="utf-8")
                print(f"   confirmed ({s2}): kept", flush=True)
            else:
                print(f"   second pass {s2}: not confirmed, reverted", flush=True)
                send(f"set|{k}={current[k]}")
        else:
            send(f"set|{k}={current[k]}")
    send("bot|full")


if __name__ == "__main__":
    main()
