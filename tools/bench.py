"""Benchmark: the measurement every change is judged on (2026-11-25, after the research report and the blind review:
"build the bench before the bot"; changes were judged on 2-4 runs, where luck is bigger than the effect).

  python tools/bench.py freeze [--rooms 20] [--name v1]
        lock a suite from knowledge/bench_rooms.json: every boss/miniboss room + the N worst normal rooms, written to
        knowledge/bench_suite_<name>.json. A suite never changes once used: make a new name instead.
  python tools/bench.py run --label NAME [--suite v1] [--reps 3] [--only boss] [--arm "A:key=v,key=v" --arm "B:key=v"]
        play the suite. Learning is frozen (learn=0) and the watcher paused, so every play starts from the same learned
        state. With two --arm options every room is played by both arms back to back, alternating which goes first,
        for a fair paired comparison of settings in ONE run. Results: runs/bench/NAME.jsonl, every row tagged with the
        bot version, git commit, suite and arm.
  python tools/bench.py report NAME [NAME2]
        per-room table, and (two runs, or two arms in one) paired differences with 90% bootstrap error bars and a
        verdict: better / worse / can't tell.
  python tools/bench.py gate BASE CANDIDATE
        exit 0 unless CANDIDATE is clearly worse than BASE (hits per room up, or clear rate down, beyond the error
        bars). Every behaviour change has to pass this before it ships (CLAUDE.md, docs/HOW_WE_WORK.md).

Reading the numbers: a difference only counts when its whole error bar is on one side of zero. "Can't tell" means
play more reps, not "it's fine".
"""
import argparse
import hashlib
import json
import random
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "brain"))
import rooms  # noqa: E402  (send, wait_for, lines, stage_cmd, load)
import watcher  # noqa: E402  (hit_cause)

ROOT = rooms.ROOT
OUT = ROOT / "runs" / "bench"
PAUSE = ROOT / "runs" / "watch" / "PAUSED"


# ---------------------------------------------------------------------------------------------------- suites
def suite_path(name):
    return ROOT / "knowledge" / f"bench_suite_{name}.json"


def freeze(n_rooms, name, floors=None):
    fp = suite_path(name)
    if fp.exists():
        sys.exit(f"{fp.name} exists: suites are locked once made. Pick a new --name.")
    all_rooms = rooms.load()
    if floors:  # e.g. "1,2": the floors the no-damage goal is about (stage "21" = floor 2, type 1)
        keep = set(floors.split(","))
        all_rooms = [r for r in all_rooms if r["stage"][:-1] in keep]
    bosses = [r for r in all_rooms if r["kind"] in ("boss", "miniboss")]
    normal = sorted((r for r in all_rooms if r["kind"] == "normal"), key=lambda r: -r["hits_seen"])[:n_rooms]
    items = [{"id": f"{r['stage']}.{r['kind']}.{r['variant']}", "stage": r["stage"], "kind": r["kind"],
              "variant": r["variant"], "name": r["name"]} for r in bosses + normal]
    fp.write_text(json.dumps({"name": name, "made": time.strftime("%Y-%m-%d %H:%M"), "items": items}, indent=1),
                  encoding="utf-8")
    print(f"{fp.name}: {len(bosses)} boss/miniboss rooms + {len(normal)} normal rooms")


def load_suite(name):
    fp = suite_path(name)
    if not fp.exists():
        sys.exit(f"no suite {fp.name}: run 'freeze' first")
    data = json.loads(fp.read_text(encoding="utf-8"))
    data["hash"] = hashlib.sha1(fp.read_bytes()).hexdigest()[:8]
    return data


# ---------------------------------------------------------------------------------------------------- playing
def git_commit():
    try:
        c = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain", "mod"], cwd=ROOT, capture_output=True, text=True).stdout
        return c + ("+dirty" if dirty.strip() else "")
    except OSError:
        return "?"


def bot_version():
    for l in reversed(rooms.lines()):
        m = re.search(r" start +([\d.]+)\|", l)
        if m:
            return m.group(1)
    # (a helper restart starts a fresh live.log with no "start" line yet: read the mod's own VERSION)
    try:
        m = re.search(r'VERSION = "([\d.]+)"', (ROOT / "mod" / "isaac-bot" / "main.lua").read_text(encoding="utf-8"))
        return m.group(1) if m else "?"
    except OSError:
        return "?"


def game_speed():
    """The Cheat Engine speedhack speed (D:\\...\\ce-bridge heartbeat), so 2x runs are never mixed up with 1x ones.
    1.0 when Cheat Engine isn't running or isn't attached."""
    try:
        cfg = json.loads((ROOT / "config.json").read_text(encoding="utf-8"))
        alive = Path(cfg.get("ce_bridge_dir") or (ROOT.parent / "ce-bridge")) / "outbox" / "alive.txt"
        if alive.exists() and time.time() - alive.stat().st_mtime < 10:
            vals = dict(l.split("=", 1) for l in alive.read_text(encoding="utf-8").splitlines() if "=" in l)
            if vals.get("pid", "0") != "0":
                return float(vals.get("speed", "1") or 1)
    except (OSError, ValueError):
        pass
    return 1.0


def apply_arm(settings):
    for kv in filter(None, (settings or "").split(",")):
        rooms.send(f"set|{kv.strip()}")


def items_now(since):
    """Item ids the bot holds, from the newest "power ... items ..." line after `since` (None = no line yet)."""
    for l in reversed(rooms.lines()[since:]):
        m = re.search(r" power  .*\|items ?([\d, ]*)\s*$", l)
        if m:
            return re.findall(r"\d+", m.group(1))
    return None


def fresh_run(tries=6):
    """A new run that really is item-free. 2026-11-26: 6 s after "newrun" the bot held Cupid's Arrow (item 48,
    piercing) and a whole benchmark half was played with it - an unfair A vs B. Restart until it holds nothing."""
    for k in range(tries):
        start = len(rooms.lines())
        # fight-only BEFORE the run starts: the autopilot had ~20 s after "newrun" to walk into a treasure room next
        # to the start (the author watched it grab Cupid's Arrow). Set again after, in case a new run resets it.
        rooms.send("bot|combat")
        rooms.send("newrun")
        rooms.wait_for(r" start  ", start, 30)
        rooms.send("bot|combat")
        rooms.send("set|learn=0")
        time.sleep(8)
        held = items_now(start)
        if not held:
            return True
        print(f"  fresh run holds items {held}: restarting ({k + 1}/{tries})", flush=True)
    return False


def setup_run():
    PAUSE.parent.mkdir(parents=True, exist_ok=True)
    PAUSE.write_text("benchmark running", encoding="utf-8")
    if not fresh_run():
        sys.exit("couldn't get an item-free run")


def finish_run():
    rooms.send("set|learn=1")
    rooms.send("bot|full")
    try:
        PAUSE.unlink()
    except OSError:
        pass


def play(item, arm_settings, state):
    """One room. Returns (result, seconds, hits, causes)."""
    if state.get("stage") != item["stage"]:
        start = len(rooms.lines())
        rooms.send("stage|" + rooms.stage_cmd(item["stage"]))
        rooms.wait_for(r" bench  stage ", start, 15)
        time.sleep(3)
        state["stage"] = item["stage"]
    apply_arm(arm_settings)
    # full health before EVERY play: health carried over, so B always started with A's damage, the risk layer played
    # it more carefully, and the first A-vs-A baseline (1.2.30) called identical bots "WORSE" (clear rate -14%)
    rooms.send("heal")
    start = len(rooms.lines())
    rooms.send(f"goroom|{item['kind']}|{item['variant']}")
    m = rooms.wait_for(r" bench  (cleared|died|timeout|failed)\|?([\d.]*)\|?(\d*)", start, 120)
    window = rooms.lines()[start:]
    causes = {}
    for l in window:
        h = re.match(r"^\S+ hit +(.*)$", l)
        if h:
            kind, key = watcher.hit_cause(h.group(1))
            causes[f"{kind}:{key}"] = causes.get(f"{kind}:{key}", 0) + 1
    res = m.group(1) if m else "no answer"
    secs = float(m.group(2)) if m and m.group(2) else None
    hits = int(m.group(3)) if m and m.group(3) else sum(causes.values())
    if res == "died":  # a new run starts: put the bench state back, item-free
        s2 = len(rooms.lines())
        rooms.wait_for(r" start  ", s2, 60)
        time.sleep(4)
        rooms.send("bot|combat")
        rooms.send("set|learn=0")
        time.sleep(4)
        if items_now(s2):
            fresh_run()
        state["stage"] = None
    time.sleep(2)
    return res, secs, hits, causes


def run(label, suite_name, reps, arms, only):
    suite = load_suite(suite_name)
    items = suite["items"]
    if only:
        items = [i for i in items if only in i["kind"] or only.lower() in i["name"].lower()]
    arms = arms or [("main", "")]
    # settings stick between plays, so every arm must set the same keys (else arm B inherits arm A's leftovers)
    keysets = {frozenset(kv.split("=")[0].strip() for kv in filter(None, s.split(","))) for _, s in arms}
    if len(keysets) > 1:
        sys.exit("every --arm must set the same keys, e.g. A:plant_feet=1 B:plant_feet=0")
    OUT.mkdir(parents=True, exist_ok=True)
    if (OUT / f"{label}.jsonl").exists():
        sys.exit(f"{label}.jsonl exists: pick a new --label (results are never mixed)")
    out = OUT / f"{label}.jsonl"
    meta = {"label": label, "suite": suite["name"], "suite_hash": suite["hash"], "version": bot_version(),
            "commit": git_commit(), "speed": game_speed()}
    print(f"== bench {label}: suite {suite['name']} ({len(items)} rooms) x {reps} reps x {len(arms)} arm(s), "
          f"bot {meta['version']} @ {meta['commit']}, game speed {meta['speed']}x", flush=True)
    setup_run()
    state = {}
    try:
        for rep in range(reps):
            # same rooms every rep, order shuffled per rep (fixed seed) so drift doesn't line up with the order
            order = items[:]
            random.Random(1000 + rep).shuffle(order)
            order.sort(key=lambda i: i["stage"])  # fewer stage switches; the shuffle still decides order within a stage
            for idx, item in enumerate(order):
                # who goes first swaps room by room (and rep by rep): with one rep, A always went first before
                arm_order = arms if ((rep + idx) % 2 == 0) else list(reversed(arms))
                for arm_name, arm_settings in arm_order:
                    res, secs, hits, causes = play(item, arm_settings, state)
                    row = dict(meta, arm=arm_name, settings=arm_settings, rep=rep, item=item["id"], name=item["name"],
                               result=res, seconds=secs, hits=hits, causes=causes,
                               when=time.strftime("%Y-%m-%d %H:%M:%S"))
                    with open(out, "a", encoding="utf-8") as fh:
                        fh.write(json.dumps(row) + "\n")
                    print(f"  rep {rep + 1} {arm_name:>6} {item['name'][:24]:<24} {res:<9} "
                          f"{(secs or 0):5.1f}s hits {hits}", flush=True)
    finally:
        finish_run()
    print(f"\nwrote {out}")
    report([label])


# ---------------------------------------------------------------------------------------------------- statistics
def load_rows(name):
    # "label:B" = only arm B of that run, so a paired A/B run can be gated arm against arm (2026-11-26)
    arm = None
    if ":" in name and not (OUT / f"{name}.jsonl").exists():
        name, arm = name.rsplit(":", 1)
    fp = OUT / f"{name}.jsonl"
    if not fp.exists():
        sys.exit(f"no results {fp}")
    rows = [json.loads(l) for l in fp.read_text(encoding="utf-8").splitlines() if l.strip()]
    if arm is not None:
        rows = [r for r in rows if r.get("arm") == arm]
        if not rows:
            sys.exit(f"no rows for arm {arm} in {fp}")
    return rows


def per_item(rows):
    """item -> {hits, clear, secs} means over its plays (no-answer plays left out)"""
    acc = {}
    for r in rows:
        if r["result"] in ("no answer", "failed"):
            continue
        a = acc.setdefault(r["item"], {"name": r["name"], "hits": [], "clear": [], "secs": []})
        a["hits"].append(r["hits"])
        a["clear"].append(1.0 if r["result"] == "cleared" else 0.0)
        a["secs"].append(r["seconds"] if r["seconds"] is not None else 90.0)
    return {k: {"name": v["name"], "n": len(v["hits"]), "hits": statistics.mean(v["hits"]),
                "clear": statistics.mean(v["clear"]), "secs": statistics.mean(v["secs"])} for k, v in acc.items()}


def bootstrap_ci(values, iters=4000, lo=5, hi=95, seed=7):
    if not values:
        return (0.0, 0.0, 0.0)
    rnd = random.Random(seed)
    n = len(values)
    means = sorted(statistics.mean(rnd.choice(values) for _ in range(n)) for _ in range(iters))
    return (statistics.mean(values), means[int(iters * lo / 100)], means[int(iters * hi / 100) - 1])


def summary(name, items):
    hits = [v["hits"] for v in items.values()]
    clear = [v["clear"] for v in items.values()]
    m_h, l_h, u_h = bootstrap_ci(hits)
    m_c, l_c, u_c = bootstrap_ci(clear)
    print(f"{name}: {len(items)} rooms | hits per room {m_h:.2f} [{l_h:.2f}, {u_h:.2f}] | "
          f"clear rate {m_c:.0%} [{l_c:.0%}, {u_c:.0%}]")


def paired(name_a, a, name_b, b):
    """B minus A over the rooms both played; returns dict of (mean, lo, hi) and a verdict."""
    common = sorted(set(a) & set(b))
    if not common:
        print("no rooms in common")
        return None
    d_hits = [b[k]["hits"] - a[k]["hits"] for k in common]
    d_clear = [b[k]["clear"] - a[k]["clear"] for k in common]
    d_secs = [b[k]["secs"] - a[k]["secs"] for k in common]
    res = {"hits": bootstrap_ci(d_hits), "clear": bootstrap_ci(d_clear), "secs": bootstrap_ci(d_secs)}
    worse = res["hits"][1] > 0 or res["clear"][2] < 0
    better = (res["hits"][2] < 0 or res["clear"][1] > 0) and not worse
    verdict = "WORSE" if worse else ("BETTER" if better else "can't tell (play more reps)")
    print(f"\n{name_b} vs {name_a} on {len(common)} rooms (B - A, 90% error bars):")
    print(f"  hits per room  {res['hits'][0]:+.2f} [{res['hits'][1]:+.2f}, {res['hits'][2]:+.2f}]   (lower is better)")
    print(f"  clear rate     {res['clear'][0]:+.0%} [{res['clear'][1]:+.0%}, {res['clear'][2]:+.0%}]   (higher is better)")
    print(f"  seconds        {res['secs'][0]:+.1f} [{res['secs'][1]:+.1f}, {res['secs'][2]:+.1f}]   (lower is better)")
    print(f"  verdict: {verdict}")
    res["verdict"] = verdict
    return res


def report(names):
    groups = {}
    for n in names:
        rows = load_rows(n)
        arms = sorted({r.get("arm", "main") for r in rows})
        for arm in arms:
            key = n if len(arms) == 1 else f"{n}:{arm}"
            groups[key] = per_item([r for r in rows if r.get("arm", "main") == arm])
    for key, items in groups.items():
        print(f"\n{key}")
        for k, v in sorted(items.items(), key=lambda kv: kv[1]["name"]):
            print(f"  {v['name'][:22]:<22} {k:<16} plays {v['n']}  clear {v['clear']:4.0%}  hits {v['hits']:.1f}  "
                  f"{v['secs']:5.1f}s")
        summary(key, items)
    keys = list(groups)
    if len(keys) == 2:
        return paired(keys[0], groups[keys[0]], keys[1], groups[keys[1]])
    return None


def gate(base, cand):
    a, b = per_item(load_rows(base)), per_item(load_rows(cand))
    res = paired(base, a, cand, b)
    if res is None or res["verdict"] == "WORSE":
        print("\nGATE: FAIL - the candidate is clearly worse (or nothing to compare). Don't ship it.")
        return 1
    print("\nGATE: pass" + (" (better)" if res["verdict"] == "BETTER" else " (not worse; can't tell if better)"))
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("freeze")
    f.add_argument("--rooms", type=int, default=20)
    f.add_argument("--name", default="v1")
    f.add_argument("--floors", help='only these floors, e.g. "1,2"')
    r = sub.add_parser("run")
    r.add_argument("--label", required=True)
    r.add_argument("--suite", default="v1")
    r.add_argument("--reps", type=int, default=3)
    r.add_argument("--arm", action="append", help='"NAME:key=v,key=v" (give two for a paired A/B)')
    r.add_argument("--only", help="only rooms whose kind or name contains this (e.g. boss, Dingle)")
    p = sub.add_parser("report")
    p.add_argument("names", nargs="+")
    g = sub.add_parser("gate")
    g.add_argument("base")
    g.add_argument("candidate")
    a = ap.parse_args()
    if a.cmd == "freeze":
        freeze(a.rooms, a.name, a.floors)
    elif a.cmd == "run":
        arms = [tuple(x.split(":", 1)) if ":" in x else (x, "") for x in (a.arm or [])]
        run(a.label, a.suite, a.reps, arms, a.only)
    elif a.cmd == "report":
        report(a.names)
    elif a.cmd == "gate":
        sys.exit(gate(a.base, a.candidate))


if __name__ == "__main__":
    main()
