"""A/B test: run the same enemy N times with setting A, then N times with setting B (changed live), and compare.
For high-variance fights (bosses) where one round per change proves nothing.

Usage: python ab_test.py ENEMY[xCOUNT] N "key=value,key=value" "key=value,key=value"
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gauntlet  # noqa: E402


def send(cmd):
    gauntlet.SEND.write_bytes((cmd + "\n").encode())
    time.sleep(1.2)


def run(enemy, n, settings):
    enemy, _, many = enemy.partition("x")  # "29.1x6" = six Trites per round
    many = int(many or 1)
    for kv in filter(None, settings.split(",")):
        send(f"set|{kv}")
    rows = []
    for i in range(n):
        r = gauntlet.one(enemy, n=many)
        rows.append(r)
        print(f"  [{settings}] round {i + 1}: {r.get('result')} {r.get('seconds')}s hits {r.get('hits')}", flush=True)
        if r.get("result") == "died":
            start = len(gauntlet.lines())
            end = time.time() + 120
            while time.time() < end and not any(" start  " in l for l in gauntlet.lines()[start:]):
                time.sleep(2)
            time.sleep(4)
            send("bot|combat")
            for kv in filter(None, settings.split(",")):
                send(f"set|{kv}")
        time.sleep(2)
    wins = sum(1 for r in rows if r.get("result") == "cleared")
    hits = sum(r.get("hits", 0) for r in rows)
    return wins, hits


def main():
    enemy, n, a, b = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
    send("bot|combat")
    wa, ha = run(enemy, n, a)
    wb, hb = run(enemy, n, b)
    print(f"\nA [{a}]: {wa}/{n} cleared, {ha} hits")
    print(f"B [{b}]: {wb}/{n} cleared, {hb} hits")
    for kv in filter(None, b.split(",")):  # end on B: B is the code default in practice (A is the old way)
        send(f"set|{kv}")
    send("bot|full")


if __name__ == "__main__":
    main()
