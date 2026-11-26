"""Game-file bestiary (2026-11-25): copy the isaac-bot-bestiary mod's dump to knowledge\\bestiary_game.json.

The mod (mod\\isaac-bot-bestiary) reads the game's own data from inside the game through REPENTOGON, because the
game's ResourceExtractor crashes on Repentance+ archives. It runs once per game version at the first run start.

  python bestiary_game.py          copy the newest dump and print a summary
  python bestiary_game.py --show   only print the summary of knowledge\\bestiary_game.json

The output is game-derived data: it stays local and is never committed (see .gitignore).
"""
import json
import sys
from collections import Counter
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "brain"))
import botconfig  # noqa: E402  (game folder: config.json "game_dir")

SRC = botconfig.GAME / "data" / "isaac-bot-bestiary"
OUT = botconfig.ROOT / "knowledge" / "bestiary_game.json"


def summary(d):
    ents = d.get("entities") or []
    anims = d.get("animations") or {}
    floors = d.get("floors") or []
    print(f"dump v{d.get('v')}  complete={d.get('complete')}  {d.get('ms')} ms  steps={d.get('steps')}")
    bosses = sum(1 for e in ents if (e.get("cfg") or {}).get("is_boss") or str(e.get("boss", "")) == "1")
    print(f"entities: {len(ents)} rows (types 10-999), {len({e.get('key') for e in ents})} type.variant keys, "
          f"{bosses} boss rows")
    n_anim = sum(len(v) for v in anims.values())
    with_ev = sum(1 for v in anims.values() for a in v if a.get("events"))
    ev_names = Counter(n for v in anims.values() for a in v for n in (a.get("events") or {}))
    print(f"sprites: {len(anims)} files ({d.get('anm2_missing')} failed to load), {n_anim} animations, "
          f"{with_ev} with event frames")
    if ev_names:
        print("  events found:", ", ".join(f"{n} x{c}" for n, c in ev_names.most_common(25)))
    for f in floors:
        types = f.get("by_room_type") or {}
        kinds = ", ".join(f"type {t}: {len(v)} enemies" for t, v in sorted(types.items(), key=lambda kv: kv[0]))
        print(f"  {f.get('name'):<17} rooms {f.get('rooms'):>5}  {f.get('error') or kinds}")
    sample = next((e for e in ents if e.get("key") == "261.0"), None)
    if sample:
        print("sample 261.0 (Dingle):", json.dumps({k: sample[k] for k in sample if k != "cfg"})[:400])
        print("  cfg:", sample.get("cfg"))
        for a in anims.get(sample.get("anm2"), [])[:12]:
            print("   ", a.get("name"), a.get("len"), a.get("events"))


def main():
    if "--show" in sys.argv:
        summary(json.loads(OUT.read_text(encoding="utf-8")))
        return
    src = sorted(SRC.glob("save*.dat"), key=lambda p: p.stat().st_mtime)
    if not src:
        sys.exit(f"no dump yet in {SRC}: the mod writes it at the first run start after the game loads it")
    d = json.loads(src[-1].read_text(encoding="utf-8"))
    OUT.write_text(json.dumps(d, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"saved {OUT} ({OUT.stat().st_size // 1024} KB) from {src[-1].name}")
    summary(d)


if __name__ == "__main__":
    main()
