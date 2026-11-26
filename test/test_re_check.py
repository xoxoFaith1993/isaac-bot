"""Offline tests for tools/re_check.py (no game): python test/test_re_check.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import re_check  # noqa: E402

results = []


def check(name, ok, detail=""):
    results.append(("PASS " if ok else "FAIL ") + name + (f"  ({detail})" if detail else ""))


def enemy(key, anim, af, state, sf, x, y, vx=0.0, vy=0.0, i1=0, hp=50):
    return f"{key},{anim},{af},{state},{sf},{x},{y},{vx},{vy},0,0,0,0,0,0,{i1},0,4,{hp},0,0"


def rows_for(lines):
    _, rows = re_check.run(lines)
    return {claim: v for claim, got, v in rows}


def dingle_log(attack_at_sf):
    """Dingle idles, then starts an attack (state 11) after the given Idle StateFrame."""
    out, f = [], 100
    for sf in range(0, attack_at_sf + 1, 2):
        out.append(f"00:00:00 rec    {f}|300,300|{enemy('261.0', 'Idle', 0, 3, sf, 200, 200)}")
        f += 2
    out.append(f"00:00:00 rec    {f}|300,300|{enemy('261.0', 'BeforeSlide', 0, 11, 0, 200, 200)}")
    return out


IDLE = "Dingle: no attack while Idle StateFrame <= 30"
v = rows_for(dingle_log(40))
check("an attack after Idle StateFrame 40 confirms the 30-update rule", v[IDLE] == "confirmed", v[IDLE])
v = rows_for(dingle_log(10))
check("an attack after Idle StateFrame 10 contradicts it", v[IDLE] == "CONTRADICTED", v[IDLE])
v = rows_for([])
check("no recording -> not covered", v[IDLE] == "not covered", v[IDLE])

# Lil' Haunt: shots starting 120-150 px away support the 200 px range (and rule out the community's 63 px)
lines, f = [], 500
for d in (120, 130, 140, 150):
    lines.append(f"00:00:00 rec    {f}|{100 + d},100|{enemy('260.10', 'FloatChase', 0, 4, 95, 100, 100)}")
    lines.append(f"00:00:00 rectrans {f}|260.10|FloatChase>Shoot|4>8|0|0|100,100")
    f += 20
LH = "Lil' Haunt: shoots within 200 px (not 63)"
v = rows_for(lines)
check("Lil' Haunt shots from 120-150 px confirm the 200 px range", v[LH] == "confirmed", v[LH])

# a Charger that charges with Isaac level with it (same tile row, 120 px away) fits the trigger
lines = [f"00:00:00 rec    {f}|320,200|{enemy('23.0', 'Move Hori', 0, 4, 0, 200, 200)}" for f in range(900, 912, 2)]
lines.append("00:00:00 rectrans 910|23.0|Move Hori>Attack Hori|4>8|0|0|200,200")
CH = "Charger 23.0: charges when Isaac (+0-16 updates lead) is in its tile row/col within 200 px"
v = rows_for(lines)
check("a charge with Isaac in its row fits the trigger", v[CH] == "confirmed", v[CH])

print("\n".join(results))
failed = sum(r.startswith("FAIL") for r in results)
print(f"\n{len(results) - failed}/{len(results)} passed")
sys.exit(1 if failed else 0)
