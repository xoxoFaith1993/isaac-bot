# Reverse-engineering queue (standing job, 2026-11-26)

The author's standing job: keep the Ghidra decompile **ahead** of what the bot will need, so reverse engineering is
never the bottleneck. This file is owned by the outside-sources session. It runs the Ghidra session batch by batch
and ticks items off here.

**Method (unchanged):**
- the Ghidra session decompiles a copy of the game;
- two blind readers per bundle (one on Sonnet);
- disagreements are settled in the C;
- the write-up goes to `RE_ENEMIES.md` / `RE_CORE.md` ("Bot meaning" plus "Record to confirm");
- then a recording check (`tools/re_check.py`).

**Reading policy (the author, 2026-11-26, to cut usage):**
- two blind readers only for shared building blocks, Isaac's own rules and bosses;
- plain enemies get one reader (on a cheaper model) plus the recording check, escalating to two if the reader finds
  new logic;
- every written fact carries three labels: category (`move`/`attack`/`timing`/`body`/`terrain`), source (batch +
  function address), checked (`1 reader`/`2 readers`/`recording`/`contradicted`). See `docs/FORECAST_PLAN.md`,
  "The fallback".

**Safety:** one Ghidra job at a time, 6 GB heap, the watchdog, low CPU priority while a benchmark gate is running.
Only confirmed facts become bot rules (the main session folds them in).

**Order:** by tier, then by how often the source shows up in our hit logs. The counts are all-time hits from
`runs/hits.jsonl` and the archived `runs/logs/`, so they cover old bot versions too. A death or a live report from
the author can move an item up.

## Done
- [x] The Haunt + Lil' Haunt, Dingle (pilot) · Gemini/Steven/Ovum, Sloth, Pin, Monstro, Attack Fly, Trite, Charger
  (+ Gurgling trigger), Host
- [x] Core: fire modes, boss bursts, the can-shoot check, the charge trigger, i-frames, contact classes, the shot hit
  test, Isaac's movement
- [x] Batch A: creep, contact damage · B: Gapers, Spider · C: Dart Fly, Ring Fly, Swarm, Squirt, Globin, Widow ·
  D: the physics step, knockback, flee

## Tier 1: hurting us now

| Batch | Item | Type | Hits (all-time) | Why / what to find | Status |
|---|---|---|---|---|---|
| E1 | **Gurglings, full AI** | 237.0/237.1 | 33-37 | the chase line, the creep trail, how tear knockback bends a charge | [x] f0406fe |
| E1 | **Gurdy**, Gurdy Jr. | 36.0, 99.0 | 7 shot hits + 4 | the best run's hits; Gurdy Jr.'s charge | [x] f0406fe |
| E1 | **The Duke of Flies** (+ its flies), the Husk | 67.0/67.1 | few | swarm movement, release timing, corner lock | [x] f0406fe |
| E1 | **Gaping Maw** (+ Broken Gaping Maw) | 235.0, 236.0 | 0 logged | **killed the furthest run**: suction strength and range as a force on Isaac | [x] f0406fe |
| E2 | **Spikes, retracting spikes** | grid 8/9 ("0.8" source) | **43** | timing, damage (2), i-frame interaction | [x] 839ce47 |
| E2 | Unknown source "0.0" | 0.0 | 28 | find what deals damage with no entity (pits? explosions?) | [x] d7216e5 (curse door) |
| E2 | **Bombs / TNT** blast radius and damage to Isaac | 4.x, TNT grid | 19 | the bot keeps bombing itself | [x] 839ce47 |
| E2 | Fireplaces (red/blue/purple: which shoot, when) | 33.x | 7 | | [x] 839ce47 |
| E2 | Stone shooters, Stone Grimace, Brimstone Head, Stoney | 202, 42, 203, 302 | few | | [x] 839ce47 |
| E2 | Red/gold chest and curse-room door damage | | few | | [x] d7216e5 (curse door) |
| E3 | **Gluttony** | 49.0 | 12-16 | attack tells and windows | [ ] |
| E3 | Envy, Pride, Lust, Greed, Wrath | 51, 52, 47, 50, 48 | 0-5 | | [ ] |
| E4 | Big Spider, Fatty, Round Worm (shots), Wall Hugger, Boom Fly, Pooter, Horf, Maggot, Hopper | 94, 208, 244, 218, 25, 14, 12, 21, 29.0 | 2-13 each | in that order | [ ] |
| E4 | Fat Bat, Tumor, Mega Maw (shooters seen in the logs) | 258, 229, 262 | 2-3 shot hits | | [ ] |
| E5 | Mulligan, Hive, Clotty, Sucker, Spitty, Embryo, Leaper, Knight, Mr. Maw, Night Crawler, Para-Bite, Ragling, Kamikaze Leech, Moter, Wall Creep | | 0 logged | the author's list; floors 1-2 regulars | [ ] |

## Tier 2: Isaac's own side
| Batch | Item | Status |
|---|---|---|
| F1 | Tear physics: range, height, fall, shot speed; the knockback tears give enemies (`AddKnockback` from Tear is known) | [ ] |
| F2 | Item effects coming up soon: Chocolate Milk and other charge weapons, flight (exactly what flying ignores), Cupid's Arrow / piercing | [ ] |

## Tier 3: floors 3-6 and the bosses to Delirium
| Batch | Item | Status |
|---|---|---|
| G1 | Common enemies of Caves, Catacombs, Flooded Caves, Mines (incl. the mole floors) and Depths, by future hit counts | [ ] |
| G2 | Bosses: Chub, Pestilence, Peep, Loki, Mask of Infamy, Gurdy Jr. variants, Bloat, The Hollow, Carrion Queen, Mom | [ ] |
| G3 | Mom's Heart / It Lives, Satan, Isaac, ???, The Lamb, Hush | [ ] |
| G4 | **Delirium**: how it picks and copies bosses | [ ] |

## Log
- 2026-11-26: queue made, from the main session's list, reordered by hit counts. "0.8" = grid type 8 (spikes):
  likely, since every such hit did 2 damage. E1 sent to the Ghidra session.
- 2026-11-26: E1 done (f0406fe). Checked: the Gurgling charge peaks at 12-12.7 px/update (code: 12-13) and drops red creep while charging; all 7 Gurdy shot hits were at 12.0-12.2 (the five-spread with the x1.2 tail). The Maw, Gurdy Jr. and Duke aren't recorded yet. E2 next.
- 2026-11-26: E2 done (839ce47). Checked: 43/43 spike hits (0.8) and 1 retracting (0.9) did 2; normal and blue fireplace hits are touch damage (only red and purple shoot); all 19 bomb hits did 2 (fits if base bomb damage >= 85, asked). TNT blast and Stone Grimace/Brimstone Head/Stoney are not covered yet. **'0.0' is mostly curse-room doors** (13 of 21 room-walk cases were entering a type-10 room); a targeted hunt is running (damage flag, devil-deal effect).
- 2026-11-26: E2c done (d7216e5). '0.0' = the spiked curse-room door (1.0 dmg, empty source, both ways; flight avoids it except when leaving a curse room). 23/28 '0.0' hits did 1. **Curse-door and sacrifice-room damage don't count against the devil deal**; spikes, bombs, contact, shots and creep do. Bomb base damage is 100 (Isaac takes 2: matches 19/19). Red/gold chest damage not covered yet. E3 next.
