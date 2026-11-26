"""Offline tests for tools/bench.py statistics (no game): python test/test_bench.py"""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import bench  # noqa: E402

results = []


def check(name, ok, detail=""):
    results.append(("PASS " if ok else "FAIL ") + name + (f"  ({detail})" if detail else ""))


def fake(hits_by_room, clear=1.0, reps=3, seed=1):
    rnd = random.Random(seed)
    rows = []
    for room, h in hits_by_room.items():
        for _ in range(reps):
            rows.append({"item": room, "name": room, "result": "cleared" if rnd.random() < clear else "died",
                         "seconds": 30.0, "hits": max(0, h + rnd.choice((-1, 0, 0, 1)))})
    return bench.per_item(rows)


base = {f"r{i}": random.Random(i).randint(0, 4) for i in range(30)}
a = fake(base)

# 1. the same bot against itself: no verdict either way
b = fake(base, seed=2)
res = bench.paired("A", a, "B", b)
check("same bot twice -> can't tell", res["verdict"].startswith("can't"), res["verdict"])

# 2. one more hit in every room -> worse, and the gate fails
b = fake({k: v + 1 for k, v in base.items()}, seed=3)
res = bench.paired("A", a, "B", b)
check("one more hit per room -> WORSE", res["verdict"] == "WORSE", f"{res['hits']}")

# 3. one fewer hit in every room -> better
b = fake({k: max(0, v - 1) for k, v in base.items()}, seed=4)
res = bench.paired("A", a, "B", b)
check("fewer hits per room -> BETTER", res["verdict"] == "BETTER", f"{res['hits']}")

# 4. clearing far less often is worse even with the same hits
b = fake(base, clear=0.4, seed=5)
res = bench.paired("A", a, "B", b)
check("clear rate down -> WORSE", res["verdict"] == "WORSE", f"{res['clear']}")

# 5. no-answer plays are left out, not counted as zero hits
rows = [{"item": "x", "name": "x", "result": "no answer", "seconds": None, "hits": 0},
        {"item": "x", "name": "x", "result": "cleared", "seconds": 20.0, "hits": 2}]
pi = bench.per_item(rows)
check("no-answer plays are left out", pi["x"]["n"] == 1 and pi["x"]["hits"] == 2, str(pi))

print("\n".join(results))
fails = sum(r.startswith("FAIL") for r in results)
print(f"\n{len(results) - fails} passed, {fails} failed")
sys.exit(1 if fails else 0)
