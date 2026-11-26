"""Enemy behaviour recorder (2026-11-26): watch every enemy from the INSIDE and write a behaviour profile per enemy.

The game's files hold stats and animation timings, but the behaviour is compiled into the game, so the mod's recorder
(mod/isaac-bot/recorder.lua) logs each enemy's animation, AI state (NpcState) and timer, speed, AI scratch values
(V1, V2, I1, I2, TargetPosition) and everything it creates (projectiles with their arcs, creep, bombs, enemies).
This tool runs recording sessions and turns those lines into profiles: what each enemy does in each animation, what
it creates on which frame, and plain features the bot can use (moves in straight lines, charges, leaves creep, ...).

  python tools/recorder.py room <stage> <kind> <variant> [--secs 75]   record one saved room (e.g. 10 boss 2053)
  python tools/recorder.py suite [--suite quick] [--only boss]          record every room of a benchmark suite once
  python tools/recorder.py profile [KEY ...]                            build knowledge/behaviour_profiles.json and
                                                                       runs/recorder/REPORT.md from all logs

While recording, learning is frozen and the watcher only takes notes (runs/watch/PAUSED), like a benchmark.
Profiles are measurements of the game, so they're kept out of git (like the other game-derived files).
"""
import argparse
import collections
import json
import math
import statistics
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import rooms  # noqa: E402

ROOT = rooms.ROOT
OUT_JSON = ROOT / "knowledge" / "behaviour_profiles.json"
OUT_DIR = ROOT / "runs" / "recorder"
PAUSE = ROOT / "runs" / "watch" / "PAUSED"


# ------------------------------------------------------------------------------------------------ recording
def start(what):
    PAUSE.parent.mkdir(parents=True, exist_ok=True)
    PAUSE.write_text(f"recorder: {what}", encoding="utf-8")
    rooms.send("bot|combat")
    rooms.send("set|learn=0")
    rooms.send("record|1")


def stop():
    rooms.send("record|0")
    rooms.send("set|learn=1")
    rooms.send("bot|full")
    try:
        PAUSE.unlink()
    except OSError:
        pass


def record_room(stage, kind, variant, secs, state):
    if state.get("stage") != stage:
        s = len(rooms.lines())
        rooms.send("stage|" + rooms.stage_cmd(stage))
        rooms.wait_for(r" bench  stage ", s, 15)
        time.sleep(3)
        state["stage"] = stage
    rooms.send("heal")
    s = len(rooms.lines())
    rooms.send(f"goroom|{kind}|{variant}")
    m = rooms.wait_for(r" bench  (cleared|died|timeout|failed)", s, secs + 30)
    res = m.group(1) if m else "no answer"
    if res == "died":
        s2 = len(rooms.lines())
        rooms.wait_for(r" start  ", s2, 60)
        time.sleep(4)
        rooms.send("bot|combat")
        rooms.send("set|learn=0")
        rooms.send("record|1")
        state["stage"] = None
    time.sleep(2)
    return res


# ------------------------------------------------------------------------------------------------ parsing
def all_lines():
    return rooms.all_log_lines()


def fnum(x, default=0.0):
    try:
        return float(x)
    except (TypeError, ValueError):
        return default


def parse(lines):
    """-> samples [(frame, (px,py), [enemy dict])], shots, creep, npcs, bombs (lists of dicts)"""
    samples, shots, creep, npcs, bombs, trans = [], [], [], [], [], []
    for l in lines:
        parts = l.split(None, 2)
        if len(parts) < 3:
            continue
        kind, body = parts[1], parts[2]
        # the helper's log cuts each message name to 6 letters (recshot -> recsho, rectrans -> rectra, ...)
        kind = {"recsho": "recshot", "reccre": "reccreep", "recbom": "recbomb", "rectra": "rectrans"}.get(kind, kind)
        try:
            if kind == "rec":
                f, pp, ens = body.split("|", 2)
                pvals = pp.split(",")  # x,y (older lines) or x,y,vx,vy (Isaac's velocity, since 2026-11-26)
                px, py = fnum(pvals[0]), fnum(pvals[1])
                out = []
                for e in ens.split(";"):
                    v = e.split(",")
                    if len(v) < 19:
                        continue
                    out.append({"key": v[0], "anim": v[1], "frame": int(fnum(v[2], -1)), "state": int(fnum(v[3], -1)),
                                "sf": int(fnum(v[4], -1)), "x": fnum(v[5]), "y": fnum(v[6]), "vx": fnum(v[7]),
                                "vy": fnum(v[8]), "v1x": fnum(v[9]), "v1y": fnum(v[10]), "v2x": fnum(v[11]),
                                "v2y": fnum(v[12]), "tx": fnum(v[13]), "ty": fnum(v[14]), "i1": int(fnum(v[15])),
                                "i2": int(fnum(v[16])), "coll": int(fnum(v[17])), "hp": fnum(v[18]),
                                "pcd": int(fnum(v[19])) if len(v) > 19 else 0,
                                "pdelay": int(fnum(v[20])) if len(v) > 20 else 0})
                samples.append((int(f), (px, py), out))
            elif kind == "rectrans":
                f, key, anims, states, fr, sf, pos = body.split("|", 6)
                a0, a1 = anims.split(">", 1)
                s0, s1 = states.split(">", 1)
                trans.append({"f": int(f), "key": key, "from": a0, "to": a1, "s0": int(fnum(s0, -1)),
                              "s1": int(fnum(s1, -1))})
            elif kind == "recshot":
                f, var, pos, vel, arc, scale, flags, sp = body.split("|", 7)
                vx, vy = (fnum(v) for v in vel.split(","))
                h, fs, fa = (fnum(v) for v in arc.split(","))
                shots.append({"f": int(f), "variant": int(var), "speed": math.hypot(vx, vy), "height": h,
                              "fall": fs, "accel": fa, "scale": fnum(scale), "flags": flags, **spawner(sp)})
            elif kind == "reccreep":
                f, name, pos, size, sp = body.split("|", 4)
                creep.append({"f": int(f), "creep": name, "size": fnum(size), **spawner(sp)})
            elif kind == "recnpc":
                f, key, pos, sp = body.split("|", 3)
                npcs.append({"f": int(f), "made": key, **spawner(sp)})
            elif kind == "recbomb":
                f, var, pos, sp = body.split("|", 3)
                bombs.append({"f": int(f), "variant": int(var), **spawner(sp)})
        except ValueError:
            continue
    return samples, shots, creep, npcs, bombs, trans


def spawner(text):
    if text == "-" or not text:
        return {"by": "-", "by_anim": "", "by_frame": -1, "by_state": -1}
    v = text.split(",")
    return {"by": v[0], "by_anim": v[1] if len(v) > 1 else "", "by_frame": int(fnum(v[2], -1)) if len(v) > 2 else -1,
            "by_state": int(fnum(v[3], -1)) if len(v) > 3 else -1}


# ------------------------------------------------------------------------------------------------ profiles
def mean(xs):
    return round(statistics.mean(xs), 2) if xs else None


def build(samples, shots, creep, npcs, bombs, trans=(), only=None):
    per = collections.defaultdict(lambda: {"anims": collections.defaultdict(lambda: {
        "n": 0, "states": collections.Counter(), "speed": [], "axis": [], "toward": [], "v1_toward": [], "v1_len": [],
        "tgt_to_isaac": [], "frames": []}), "trans": collections.Counter(), "samples": 0, "coll": collections.Counter()})
    last = {}  # key -> (frame, anim) when exactly one of that key is on screen
    for f, (px, py), ens in samples:
        counts = collections.Counter(e["key"] for e in ens)
        for e in ens:
            k = e["key"]
            if only and k not in only:
                continue
            P = per[k]
            P["samples"] += 1
            P["coll"][e["coll"]] += 1
            A = P["anims"][e["anim"]]
            A["n"] += 1
            A["states"][e["state"]] += 1
            A["frames"].append(e["frame"])
            sp = math.hypot(e["vx"], e["vy"])
            A["speed"].append(sp)
            dx, dy = px - e["x"], py - e["y"]
            dist = math.hypot(dx, dy) or 1
            if sp > 1:
                A["axis"].append(1.0 if min(abs(e["vx"]), abs(e["vy"])) / sp < 0.25 else 0.0)
                A["toward"].append((e["vx"] * dx + e["vy"] * dy) / (sp * dist))
            v1 = math.hypot(e["v1x"], e["v1y"])
            if v1 > 1:
                A["v1_len"].append(v1)
                A["v1_toward"].append((e["v1x"] * dx + e["v1y"] * dy) / (v1 * dist))
            if e["tx"] or e["ty"]:
                A["tgt_to_isaac"].append(math.hypot(e["tx"] - px, e["ty"] - py))
            if counts[k] == 1:
                prev = last.get(k)
                if prev and prev[1] != e["anim"] and f - prev[0] <= 4:
                    P["trans"][f"{prev[1]}>{e['anim']}"] += 1
                last[k] = (f, e["anim"])
    # what each enemy creates, by its animation at that moment
    made = collections.defaultdict(lambda: collections.defaultdict(lambda: {
        "shots": 0, "bursts": collections.Counter(), "fire_frames": collections.Counter(), "speed": [], "height": [],
        "fall": [], "accel": [], "scale": [], "flags": collections.Counter(), "creep": collections.Counter(),
        "npcs": collections.Counter(), "bombs": 0}))
    burst = collections.Counter((s["by"], s["by_anim"], s["f"]) for s in shots)
    for s in shots:
        M = made[s["by"]][s["by_anim"]]
        M["shots"] += 1
        M["fire_frames"][s["by_frame"]] += 1
        for k in ("speed", "height", "fall", "accel", "scale"):
            M[k].append(s[k])
        M["flags"][s["flags"]] += 1
    for (by, anim, _f), n in burst.items():
        made[by][anim]["bursts"][n] += 1
    for c in creep:
        made[c["by"]][c["by_anim"]]["creep"][c["creep"]] += 1
    for n in npcs:
        made[n["by"]][n["by_anim"]]["npcs"][n["made"]] += 1
    for b in bombs:
        made[b["by"]][b["by_anim"]]["bombs"] += 1

    # exact changes (logged on the update they happen): which animation follows which, the AI state it switches to,
    # and how long each animation lasts (from one change of that enemy to its next, when the chain is unbroken)
    exact = collections.defaultdict(lambda: {"trans": collections.Counter(), "state_of": collections.defaultdict(
        collections.Counter), "dur": collections.defaultdict(list)})
    lastT = {}
    for t in trans:
        X = exact[t["key"]]
        X["trans"][f"{t['from']}>{t['to']}"] += 1
        X["state_of"][t["to"]][t["s1"]] += 1
        prev = lastT.get(t["key"])
        if prev and prev["to"] == t["from"] and 0 < t["f"] - prev["f"] < 600:
            X["dur"][t["from"]].append(t["f"] - prev["f"])
        lastT[t["key"]] = t

    profiles = {}
    keys = set(per) | {k for k in made if k != "-"} | set(exact)
    for k in sorted(keys):
        if only and k not in only:
            continue
        P = per.get(k)
        anims = {}
        for a, A in (P["anims"].items() if P else []):
            anims[a] = {"samples": A["n"], "states": dict(A["states"].most_common(4)),
                        "speed_mean": mean(A["speed"]), "speed_max": round(max(A["speed"]), 1) if A["speed"] else None,
                        "straight_lines": mean(A["axis"]), "toward_isaac": mean(A["toward"]),
                        "v1_len": mean(A["v1_len"]), "v1_toward_isaac": mean(A["v1_toward"]),
                        "target_to_isaac_px": mean(A["tgt_to_isaac"]),
                        "length_frames": (max(A["frames"]) + 1) if A["frames"] else None}
        creates = {}
        for a, M in made.get(k, {}).items():
            entry = {}
            if M["shots"]:
                entry["shots"] = {"count": M["shots"], "per_burst": dict(M["bursts"].most_common(3)),
                                  "fires_on_frame": dict(M["fire_frames"].most_common(3)), "speed": mean(M["speed"]),
                                  "height": mean(M["height"]), "fall_speed": mean(M["fall"]),
                                  "fall_accel": mean(M["accel"]), "scale": mean(M["scale"]),
                                  "flags": dict(M["flags"].most_common(3))}
            if M["creep"]:
                entry["creep"] = dict(M["creep"])
            if M["npcs"]:
                entry["enemies"] = dict(M["npcs"])
            if M["bombs"]:
                entry["bombs"] = M["bombs"]
            if entry:
                creates[a] = entry
        X = exact.get(k)
        if X:
            for a, d in X["dur"].items():
                anims.setdefault(a, {"samples": 0, "states": {}, "speed_mean": None, "speed_max": None,
                                     "straight_lines": None, "toward_isaac": None, "v1_len": None,
                                     "v1_toward_isaac": None, "target_to_isaac_px": None, "length_frames": None})
                anims[a]["lasts_updates"] = round(statistics.median(d), 1)
            for a, c in X["state_of"].items():
                if a in anims:
                    anims[a]["ai_state"] = c.most_common(1)[0][0]
        transitions = dict(X["trans"].most_common(16)) if X else (dict(P["trans"].most_common(12)) if P else {})
        profiles[k] = {"samples": P["samples"] if P else 0, "animations": anims, "transitions": transitions,
                       "creates": creates, "features": features(anims, creates)}
    return profiles


def features(anims, creates):
    """Plain facts the bot can use, from the measurements (thresholds kept simple and visible)."""
    fast = [a for a in anims.values() if (a["speed_max"] or 0) > 6]
    f = {
        "charges": bool(fast),
        "straight_line_moves": any((a["straight_lines"] or 0) > 0.8 and (a["speed_mean"] or 0) > 3
                                   for a in anims.values()),
        "chases": any((a["toward_isaac"] or 0) > 0.6 and (a["speed_mean"] or 0) > 1 for a in anims.values()),
        "leaves_creep": sorted({c for m in creates.values() for c in m.get("creep", {})}),
        "shoots_in": sorted(a for a, m in creates.items() if "shots" in m),
        "lobbed_shots": any((m["shots"]["fall_accel"] or 0) > 0.2 for m in creates.values() if "shots" in m),
        "spawns": sorted({e for m in creates.values() for e in m.get("enemies", {})}),
        "makes_bombs": any(m.get("bombs") for m in creates.values()),
        # warning time: the frame each attack animation fires on (most common), i.e. frames between the tell and the hit
        "fire_frame": {a: max(m["shots"]["fires_on_frame"], key=m["shots"]["fires_on_frame"].get)
                       for a, m in creates.items() if "shots" in m},
        # does the AI's V1 point at Isaac during an animation (a locked-on dash/aim direction)?
        "v1_aims_at_isaac_in": sorted(a for a, x in anims.items() if (x["v1_toward_isaac"] or 0) > 0.8),
    }
    return f


def report(profiles):
    lines = ["# Enemy behaviour profiles (measured)", "",
             "Built by `tools/recorder.py profile` from the in-game recorder. Speeds in px per update (30 a second).", ""]
    for k, p in profiles.items():
        if not p["samples"] and not p["creates"]:
            continue
        lines.append(f"## {k}  ({p['samples']} samples)")
        f = p["features"]
        facts = [n for n in ("charges", "straight_line_moves", "chases", "lobbed_shots", "makes_bombs") if f.get(n)]
        if f["leaves_creep"]:
            facts.append("creep " + "/".join(f["leaves_creep"]))
        if f["spawns"]:
            facts.append("spawns " + "/".join(f["spawns"]))
        if f["fire_frame"]:
            facts.append("fires " + ", ".join(f"{a}@{fr}" for a, fr in f["fire_frame"].items()))
        if f["v1_aims_at_isaac_in"]:
            facts.append("V1 aims at Isaac in " + "/".join(f["v1_aims_at_isaac_in"]))
        lines.append("- **Features:** " + (", ".join(facts) or "none measured"))
        for a, x in sorted(p["animations"].items(), key=lambda kv: -kv[1]["samples"])[:8]:
            lines.append(f"- `{a}`: {x['samples']} samples, states {x['states']}, speed {x['speed_mean']} (max "
                         f"{x['speed_max']}), straight {x['straight_lines']}, toward Isaac {x['toward_isaac']}, "
                         f"V1 {x['v1_len']} (aims {x['v1_toward_isaac']})")
        for a, m in p["creates"].items():
            lines.append(f"- creates in `{a}`: {json.dumps(m)}")
        if p["transitions"]:
            lines.append("- transitions: " + ", ".join(f"{t} x{n}" for t, n in p["transitions"].items()))
        lines.append("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("room")
    r.add_argument("stage")
    r.add_argument("kind")
    r.add_argument("variant")
    r.add_argument("--secs", type=int, default=75)
    s = sub.add_parser("suite")
    s.add_argument("--suite", default="quick")
    s.add_argument("--only", help="kind or name filter, e.g. boss")
    p = sub.add_parser("profile")
    p.add_argument("keys", nargs="*")
    a = ap.parse_args()
    if a.cmd in ("room", "suite"):
        start(a.cmd)
        state = {}
        try:
            if a.cmd == "room":
                print(record_room(a.stage, a.kind, a.variant, a.secs, state))
            else:
                import bench
                items = bench.load_suite(a.suite)["items"]
                if a.only:
                    items = [i for i in items if a.only in i["kind"] or a.only.lower() in i["name"].lower()]
                seen = set()
                for i in sorted(items, key=lambda i: i["stage"]):
                    if (i["kind"], i["variant"]) in seen:
                        continue
                    seen.add((i["kind"], i["variant"]))
                    print(f"{i['name'][:26]:<26} {record_room(i['stage'], i['kind'], i['variant'], 90, state)}", flush=True)
        finally:
            stop()
    else:
        profiles = build(*parse(all_lines()), only=set(a.keys) or None)
        old = json.loads(OUT_JSON.read_text(encoding="utf-8")) if OUT_JSON.exists() and a.keys else {}
        old.update(profiles)
        OUT_JSON.write_text(json.dumps(old, indent=1), encoding="utf-8")
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        (OUT_DIR / "REPORT.md").write_text(report(profiles), encoding="utf-8")
        print(f"{len(profiles)} enemy profiles -> {OUT_JSON.name}, runs/recorder/REPORT.md")


if __name__ == "__main__":
    main()
