"""Check decompiled enemy rules (docs/research/RE_*.md) against the in-game recorder.

Read-only: it reads the recorder lines in runs/live.log (rec / rectra(ns) / recsho(t) / recnpc), written by
mod/isaac-bot/recorder.lua while "record|1" is on, and prints one verdict per claim:
  confirmed     the recording agrees
  CONTRADICTED  the recording disagrees (send the claim back to the decompile)
  not covered   no data for it yet (record that enemy)

  python tools/re_check.py              check runs/live.log
  python tools/re_check.py --log FILE   check another log (e.g. an archived runs/logs/live-*.log)

Recorder timing: enemies are sampled every 2 updates; a shot is logged on its first update (about 2 updates late),
spawns on the update they happen. The checks allow for that.
Owned by the outside-sources session (2026-11-26); offline test: python test/test_re_check.py
"""
import argparse
import bisect
import math
import re
import statistics as st
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "brain"))
import botconfig  # noqa: E402

LIVE = botconfig.ROOT / "runs" / "live.log"
LINE = re.compile(r"^\S+\s+(rec\w*)\s+(.*)$")


class Rec:
    """The parsed recording: samples by frame, transitions, shots, spawns."""

    def __init__(self, lines):
        self.samples, self.tra, self.shots, self.spawns = {}, [], [], []
        for line in lines:
            m = LINE.match(line.rstrip("\n"))
            if not m:
                continue
            kind, body = m.groups()
            try:
                self._add(kind, body.split("|"))
            except (ValueError, IndexError):
                continue  # a half-written line
        self.frames = sorted(self.samples)

    def _add(self, kind, p):
        if kind == "rec":
            ix, iy = map(float, p[1].split(","))
            ens = []
            for e in (p[2].split(";") if len(p) > 2 and p[2] else []):
                q = e.split(",")
                if len(q) >= 21:
                    ens.append(dict(key=q[0], anim=q[1], af=int(q[2]), st=int(q[3]), sf=int(q[4]),
                                    x=float(q[5]), y=float(q[6]), vx=float(q[7]), vy=float(q[8]),
                                    i1=int(float(q[15])), hp=float(q[18])))
            self.samples[int(p[0])] = (ix, iy, ens)
        elif kind.startswith("rectra"):
            x, y = map(float, p[6].split(","))
            self.tra.append(dict(f=int(p[0]), key=p[1], anims=p[2], x=x, y=y))
        elif kind.startswith("recsho"):
            x, y = map(float, p[2].split(","))
            vx, vy = map(float, p[3].split(","))
            s = p[7].split(",")
            self.shots.append(dict(f=int(p[0]), x=x, y=y, vx=vx, vy=vy, skey=s[0],
                                   sst=int(s[3]) if len(s) > 3 else -1, ssf=int(s[4]) if len(s) > 4 else -1))
        elif kind.startswith("recnpc"):
            x, y = map(float, p[2].split(","))
            s = p[3].split(",")
            self.spawns.append(dict(f=int(p[0]), key=p[1], x=x, y=y, skey=s[0],
                                    sst=int(s[3]) if len(s) > 3 else -1, ssf=int(s[4]) if len(s) > 4 else -1))

    def near(self, f, slack=4):
        i = bisect.bisect_left(self.frames, f)
        cands = [self.frames[j] for j in (i - 1, i) if 0 <= j < len(self.frames)]
        best = min(cands, key=lambda g: abs(g - f), default=None)
        return self.samples[best] if best is not None and abs(best - f) <= slack else None

    def isaac_vel(self, f):
        a, b = self.near(f - 2, 1), self.near(f, 1)
        return ((b[0] - a[0]) / 2, (b[1] - a[1]) / 2) if a and b else (0.0, 0.0)

    def track(self, key):
        """The first enemy with this key in each sample (fine for bosses)."""
        out = []
        for f in self.frames:
            ix, iy, ens = self.samples[f]
            for e in ens:
                if e["key"] == key:
                    out.append((f, ix, iy, e))
                    break
        return out


def angle_diff(a, b):
    return (a - b + 180) % 360 - 180


def verdict(n, ok):
    return "not covered" if n == 0 else ("confirmed" if ok else "CONTRADICTED")


def pairs(track):
    """Consecutive samples of one tracked enemy, 2 updates apart."""
    for (f0, _, _, e0), (f1, ix, iy, e1) in zip(track, track[1:]):
        if f1 - f0 <= 2:
            yield f0, e0, f1, e1, ix, iy


def check_dingle(r):
    out = []
    tr = r.track("261.0")
    sf = [e0["sf"] for f0, e0, f1, e1, *_ in pairs(tr) if e0["st"] == 3 and e1["st"] in (9, 10, 11)]
    out.append(("Dingle: no attack while Idle StateFrame <= 30", f"last Idle sample before attack: {sorted(sf)}",
                verdict(len(sf), all(s >= 30 for s in sf))))
    tired, start, runs, run = [], None, [], None
    for f0, e0, f1, e1, *_ in pairs(tr):
        if e1["st"] == 16 and e0["st"] != 16:
            start = f1
        if e0["st"] == 16 and e1["st"] != 16 and start is not None:
            tired.append(f1 - start)
            start = None
        if e1["st"] == 4:
            run = (run or []) + [e1["i1"]]
        elif run:
            runs.append(max(run))
            run = None
    out.append(("Dingle: Tired lasts 61-90 updates", f"{sorted(tired)}", verdict(len(tired), all(55 <= t <= 92 for t in tired))))
    out.append(("Dingle: 3 dashes per sequence (max I1 = 2)", f"max I1 per sequence {runs}", verdict(len(runs), all(x == 2 for x in runs))))
    pause = [e["sf"] for f, ix, iy, e in tr if e["st"] == 4]
    out.append(("Dingle: 12-15 update pause between dashes", f"max State-4 StateFrame {max(pause) if pause else '-'}",
                verdict(len(pause), bool(pause) and 12 <= max(pause) <= 15)))
    bursts = defaultdict(list)
    for s in r.shots:
        if s["skey"] == "261.0":
            bursts[s["f"]].append(s)
    three = [ss for ss in bursts.values() if len(ss) == 3]
    gaps, centre, aim = [], [], []
    for ss in three:
        sp = sorted(ss, key=lambda s: -math.hypot(s["vx"], s["vy"]))  # the centre shot is the fastest
        c = sp[0]
        ca = math.degrees(math.atan2(c["vy"], c["vx"]))
        gaps += [abs(angle_diff(math.degrees(math.atan2(s["vy"], s["vx"])), ca)) for s in sp[1:]]
        centre.append(math.hypot(c["vx"], c["vy"]))
        smp = r.near(c["f"])
        if smp:
            aim.append(abs(angle_diff(ca, math.degrees(math.atan2(smp[1] - c["y"], smp[0] - c["x"])))))
    out.append(("Dingle: Spit is a triple, sides +-16 deg", f"{len(three)}/{len(bursts)} bursts of 3, side gaps "
                f"{min(gaps, default=0):.1f}-{max(gaps, default=0):.1f}", verdict(len(three), all(14 <= g <= 18 for g in gaps))))
    out.append(("Dingle: Spit centre at 12.0 (mode-2 tail x1.2)", f"centre speeds {min(centre, default=0):.1f}-{max(centre, default=0):.1f}",
                verdict(len(centre), all(11.5 <= c <= 12.5 for c in centre))))
    out.append(("Dingle: Spit aimed at Isaac's position", f"centre vs Isaac: max {max(aim, default=0):.0f} deg",
                verdict(len(aim), all(a <= 10 for a in aim))))
    return out


def check_haunt(r):
    out = []
    tr = r.track("260.0")
    sf = [e0["sf"] for f0, e0, f1, e1, *_ in pairs(tr) if e0["st"] == 3 and e1["st"] in (8, 9)]
    out.append(("Haunt: no attack while IDLE StateFrame <= 60", f"before attack: min {min(sf, default='-')}",
                verdict(len(sf), all(s >= 60 for s in sf))))
    drops = Counter()
    for f0, e0, f1, e1, *_ in pairs(tr):
        if e1["hp"] < e0["hp"] - 0.01 and e1["st"] == e0["st"]:
            drops[e0["st"]] += 1
    n4 = sum(1 for _, _, _, e in tr if e["st"] == 4)
    out.append(("Haunt: no damage in State 4 / 16", f"HP drops by state {dict(drops)} ({n4} State-4 samples)",
                verdict(n4, drops[4] == 0 and drops[16] == 0)))
    ys = [e["y"] for _, _, _, e in tr if e["st"] in (3, 8, 9)]
    out.append(("Haunt: pinned to the top wall outside State 4", f"y {min(ys, default=0):.0f}-{max(ys, default=0):.0f}",
                verdict(len(ys), bool(ys) and max(ys) - min(ys) <= 10)))
    return out


def check_lil_haunt(r):
    out = []
    d = []
    for t in r.tra:
        if t["key"] == "260.10" and t["anims"].endswith(">Shoot"):
            smp = r.near(t["f"])
            if smp:
                d.append(math.hypot(smp[0] - t["x"], smp[1] - t["y"]))
    inside = sum(1 for x in d if x < 215)
    out.append(("Lil' Haunt: shoots within 200 px (not 63)", f"{sum(1 for x in d if x > 70)}/{len(d)} beyond 70 px, "
                f"{inside}/{len(d)} under 215", verdict(len(d), any(x > 70 for x in d) and inside >= 0.85 * len(d))))
    drops, last = Counter(), []
    for f in r.frames:
        cur = [e for e in r.samples[f][2] if e["key"] == "260.10"]
        for e in cur:
            prev = min(last, key=lambda p: math.hypot(p["x"] - e["x"], p["y"] - e["y"]), default=None)
            if prev and math.hypot(prev["x"] - e["x"], prev["y"] - e["y"]) < 20 and e["hp"] < prev["hp"] - 0.01:
                drops[e["st"]] += 1
        last = cur
    out.append(("Lil' Haunt: no damage while orbiting (State 3)", f"HP drops orbiting {drops[3]}, chasing {drops[4]}",
                verdict(drops[3] + drops[4], drops[3] == 0)))
    return out


def check_sloth(r):
    out = []
    sp = [n for n in r.spawns if n["skey"] == "46.0"]
    out.append(("Sloth: summon acts at State 8, StateFrame 5", f"{Counter((n['sst'], n['ssf']) for n in sp)}",
                verdict(len(sp), all((n["sst"], n["ssf"]) == (8, 5) for n in sp))))
    sh = [s for s in r.shots if s["skey"] == "46.0"]
    out.append(("Sloth: shot acts at State 9, StateFrame 5 (logged ~7)", f"{Counter((s['sst'], s['ssf']) for s in sh)}",
                verdict(len(sh), all(s["sst"] == 9 and 5 <= s["ssf"] <= 7 for s in sh))))
    side = []
    for n in sp:
        smp = r.near(n["f"])
        sl = next((e for e in smp[2] if e["key"] == "46.0"), None) if smp else None
        if sl:
            side.append((round(n["x"] - sl["x"]), round(n["y"] - sl["y"])))
    out.append(("Sloth: Charger spawns 30 px to its side", f"offsets {side}",
                verdict(len(side), all(28 <= abs(dx) <= 32 and abs(dy) <= 3 for dx, dy in side))))
    ends = [e0["sf"] for f0, e0, f1, e1, *_ in pairs(r.track("46.0")) if e0["st"] in (8, 9) and e1["st"] == 4]
    out.append(("Sloth: attack ends at StateFrame 30", f"last attack StateFrame {Counter(ends)}",
                verdict(len(ends), all(28 <= s <= 30 for s in ends))))
    return out


def _cell(x, y):
    return round((x - 40) / 40) * 40 + 40, round((y - 120) / 40) * 40 + 120


def _in_lane(r, f, e):
    smp = r.near(f, 1)
    if not smp:
        return False
    ix, iy, _ = smp
    cx, cy = _cell(e["x"], e["y"])
    vx, vy = r.isaac_vel(f)
    for k in range(17):
        dx, dy = ix + vx * k - cx, iy + vy * k - cy
        if (abs(dx) < 20 or abs(dy) < 20) and dx * dx + dy * dy < 40000:
            return True
    return False


def check_charge(r, key, name):
    starts, fits, spawned = [], 0, 0
    sloth_spawns = {n["f"] for n in r.spawns if n["key"] == key}
    for t in r.tra:
        if t["key"] != key or ">" not in t["anims"]:
            continue
        a, b = t["anims"].split(">", 1)
        if not b.startswith(("Attack", "Charge")) or a.startswith(("Attack", "Charge")):
            continue
        if any(0 <= t["f"] - s <= 4 for s in sloth_spawns):
            spawned += 1  # spawned already charging (Sloth), not triggered
            continue
        starts.append(t["f"])
        ok = False
        for g in range(t["f"] - 8, t["f"] + 1, 2):
            smp = r.near(g, 1)
            e = min((e for e in smp[2] if e["key"] == key), default=None,
                    key=lambda e: math.hypot(e["x"] - t["x"], e["y"] - t["y"])) if smp else None
            if e and _in_lane(r, g, e):
                ok = True
                break
        fits += ok
    base = [_in_lane(r, f, e) for f, _, _, e in r.track(key)[::7] if e["st"] == 4
            and not any(0 <= s - f <= 10 for s in starts)]
    rate = sum(base) / len(base) if base else 0
    chance = 1 - (1 - rate) ** 5
    return [(f"{name}: charges when Isaac (+0-16 updates lead) is in its tile row/col within 200 px",
             f"{fits}/{len(starts)} fit (by chance ~{chance:.0%}; {spawned} spawned already charging)",
             verdict(len(starts), fits >= 0.9 * len(starts) and fits / max(1, len(starts)) > chance + 0.2))]


def check_isaac(r):
    sp = []
    for a, b in zip(r.frames, r.frames[1:]):
        if b - a == 2:
            (x1, y1, _), (x2, y2, _) = r.samples[a], r.samples[b]
            v = math.hypot(x2 - x1, y2 - y1) / 2
            if v < 30:  # room changes
                sp.append(v)
    sp.sort()
    p90 = sp[int(0.9 * (len(sp) - 1))] if sp else 0
    return [("Isaac: top speed ~8.8 px/update at speed 1.0 (more with speed items)",
             f"p90 {p90:.1f}, median {st.median(sp) if sp else 0:.1f} ({len(sp)} samples)", verdict(len(sp), 7.0 <= p90 <= 12.5))]


CHECKS = [check_dingle, check_haunt, check_lil_haunt, check_sloth,
          lambda r: check_charge(r, "23.0", "Charger 23.0"),
          lambda r: check_charge(r, "237.1", "Gurgling 237.1"), check_isaac]


def has_recording(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return any(LINE.match(line) and line.split()[1] == "rec" for line in fh)


def newest_recording():
    """Logs rotate per session (runs/logs/live-*.log), and each run restarts the frame count, so check one log."""
    if LIVE.exists() and has_recording(LIVE):
        return LIVE
    for f in sorted((LIVE.parent / "logs").glob("live-*.log"), reverse=True):
        if has_recording(f):
            return f
    return None


def run(lines):
    r = Rec(lines)
    rows = []
    for c in CHECKS:
        rows += c(r)
    return r, rows


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--log", type=Path, default=None,
                    help="default: runs/live.log if it has recorder lines, else the newest runs/logs/live-*.log that does")
    a = ap.parse_args()
    log = a.log or newest_recording()
    if not log or not log.exists():
        sys.exit("no log with recorder lines (turn the recorder on with record|1 and play a room)")
    r, rows = run(log.read_text(encoding="utf-8", errors="replace").splitlines())
    print(f"{log.name}: {len(r.samples)} samples, {len(r.tra)} transitions, {len(r.shots)} shots, {len(r.spawns)} spawns\n")
    for claim, got, v in rows:
        print(f"{v:<13} {claim}\n              {got}")


if __name__ == "__main__":
    main()
