"""Offline tests for tools/recorder.py (no game): python test/test_recorder.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import recorder  # noqa: E402

results = []


def check(name, ok, detail=""):
    results.append(("PASS " if ok else "FAIL ") + name + (f"  ({detail})" if detail else ""))


def enemy(key, anim, frame, state, x, y, vx, vy, v1x=0, v1y=0):
    return f"{key},{anim},{frame},{state},5,{x},{y},{vx},{vy},{v1x},{v1y},0,0,0,0,0,0,4,50,0,0"


# a Gurgling-like enemy: walks, then charges along a row (straight line, fast, toward Isaac) dropping red creep;
# a lobbing shooter: fires a 3-shot arc on frame 12 of its Attack
lines = []
f = 100
for i in range(30):  # walking slowly, any direction
    lines.append(f"00:00:00 rec      {f}|500,280|{enemy('237.0', 'Walk', i % 20, 4, 200 + i, 300 + i, 1.0, 1.2)}")
    f += 2
lines.append(f"00:00:00 rectrans {f}|237.0|Walk>Attack|4>8|0|0|230,330")
for i in range(15):  # the charge: along +x toward Isaac at (500,280), V1 = the locked-on direction
    lines.append(f"00:00:00 rec      {f}|500,280|{enemy('237.0', 'Attack', i, 8, 230 + 9 * i, 300, 9.0, 0.0, 9, 0)}")
    lines.append(f"00:00:00 reccreep {f}|CREEP_RED|{230 + 9 * i},300|20.0|237.0,Attack,{i},8,5")
    f += 2
lines.append(f"00:00:00 rectrans {f}|237.0|Attack>Walk|8>4|0|0|360,300")
lines.append(f"00:00:00 rectrans {f + 30}|237.0|Walk>Attack|4>8|0|0|300,300")
for k in range(3):
    lines.append(f"00:00:00 recshot  {f}|0|100,100|{k - 1}.0,4.0|-30.0,-8.00,0.600|1.00|0|30.0,Attack,12,8,12")

# (the live log cuts message names to 6 letters: test the shortened form for half of the lines)
lines = [l.replace(" rectrans ", " rectra ").replace(" reccreep ", " reccre ") for l in lines]
profiles = recorder.build(*recorder.parse(lines))
g, lob = profiles.get("237.0", {}), profiles.get("30.0", {})
gf, lf = g.get("features", {}), lob.get("features", {})

check("charges in straight lines toward Isaac, leaving red creep",
      gf.get("charges") and gf.get("straight_line_moves") and gf.get("leaves_creep") == ["CREEP_RED"],
      str(gf))
check("V1 holds the locked-on direction during the charge", gf.get("v1_aims_at_isaac_in") == ["Attack"],
      str(gf.get("v1_aims_at_isaac_in")))
check("exact animation length and AI state from the change lines",
      g["animations"]["Attack"].get("lasts_updates") == 30 and g["animations"]["Attack"].get("ai_state") == 8,
      str({k: g["animations"]["Attack"].get(k) for k in ("lasts_updates", "ai_state")}))
check("lobbed 3-shot burst fired on frame 12 of Attack",
      lf.get("lobbed_shots") and lf.get("fire_frame") == {"Attack": 12}
      and lob["creates"]["Attack"]["shots"]["per_burst"] == {3: 1}, str(lob.get("creates")))

print("\n".join(results))
fails = sum(r.startswith("FAIL") for r in results)
print(f"\n{len(results) - fails} passed, {fails} failed")
sys.exit(1 if fails else 0)
