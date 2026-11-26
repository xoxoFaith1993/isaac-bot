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

**Keep going (the author, 2026-11-26, after the E3 -> E4 stall):**
- When a batch lands (commit + note), the next open batch goes to the Ghidra session in the same turn.
- Stop only when the queue is empty, the author says stop, or we're blocked. When blocked, write `BLOCKED: <reason>` in
  the log below so it shows up.
- During a long batch, keep writing notes and partial reads to `runs/research/re/`. The watcher
  (`brain/watcher.py`) files a "decompile stalled" problem when `[ ]` batches remain and nothing in `docs/research/`
  or `runs/research/re/` has changed for an hour.

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
| E3 | **Gluttony** | 49.0 | 12-16 | attack tells and windows | [x] ccb19e7 |
| E3 | Envy, Pride, Lust, Greed, Wrath | 51, 52, 47, 50, 48 | 0-5 | | [x] ccb19e7 |
| E3b | **Famine** (+ variants) | 63.0 | 1 (live 1.2.49) | first: the low-HP blood-shot fan (seen at 11.9 px/update from ~140 px), its tells, the dash | [x] 67d32e4 |
| E3b | **Death** (+ variants) | 66.0 | 0 (never met) | next: the hourglass slowdown (what it slows, for how long), scythes, the horse phase | [x] 67d32e4 |
| E3b | Pestilence, War, Conquest (+ variants) | 64.0, 65.0, 65.1 | 0 | bosses: two readers each | [x] 67d32e4 |
| E4 | Big Spider, Fatty, Round Worm (shots), Wall Hugger, Boom Fly, Pooter, Horf, Maggot, Hopper | 94, 208, 244, 218, 25, 14, 12, 21, 29.0 | 2-13 each | in that order | [x] da2babc |
| E4 | Fat Bat, Tumor, Mega Maw (shooters seen in the logs) | 258, 229, 262 | 2-3 shot hits | | [x] da2babc |
| E5 | Mulligan, Hive, Clotty, Sucker, Spitty, Embryo, Leaper, Knight, Mr. Maw, Night Crawler, Para-Bite, Ragling, Kamikaze Leech, Moter, Wall Creep | | 0 logged | the author's list; floors 1-2 regulars | [x] 243fb5d |

## Tier 2: Isaac's own side
| Batch | Item | Status |
|---|---|---|
| F1 | Tear physics: range, height, fall, shot speed; the knockback tears give enemies (`AddKnockback` from Tear is known) | [x] 6adb633 |
| F2 | Item effects coming up soon: Chocolate Milk and other charge weapons, flight (exactly what flying ignores), Cupid's Arrow / piercing | [x] f755a66 |

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
- 2026-11-26: E3 done (ccb19e7; 2 readers each, Sonnet + Haiku). Checked: 2 Gluttony shot hits at 8.0 (its ring speed); 1 at 12.0 (another attack); 1 Greed shot at 11.3 (triple ~12). Back-labels added to RE_ENEMIES.md. E4 next (one reader per plain enemy).
- 2026-11-26: the queue stalled after E3 (nothing started E4). The author: every enemy and boss on the road to
  Delirium, no stopping. Added **E3b, the four horsemen** ahead of E4 (Famine first: it hit the bot in live run
  1.2.49; Death next: his slowdown matters to the bot's timing). Sent to the Ghidra session; E4 and E5 follow without
  a pause.
- 2026-11-26: E3b done (67d32e4; 2 readers each). Checked: the one Famine hit (live run 1.2.49, 14:29) was a 9.0
  shot from 63 at 11.9 px/update, height -38: fits the centre shot of the low-HP triple (code: 10 x 1.2 = 12), not
  the 10.8 sides. The recorder wasn't on for that fight, so the cadence, the dash, Death's hourglass, the scythes and
  War's ring aren't covered yet. E4 is already running (Mega Maw read).
- 2026-11-26: E4 done (da2babc; 1 reader, a 2nd where there was new logic). Checked against the hit logs: Round Worm
  shots 6/6 at 10.0, Horf 2/2 at 7.0, Fat Bat 3/3 at 10.0, Tumor 3/3 at 10.0 (all as the code says). Boom Fly: both
  hits did 1 (half a heart) at 51 and 77 px from its centre, which fits the 75 + Isaac-size blast. Wall Hugger: 6 contact hits, 1
  each. **Mega Maw doesn't quite fit:** 3 hits at 10.5 (code: 10) and 1 lobbed shot at 7.7 (code: 7); asked the
  Ghidra session for the missing multiplier. E5 and F1 are running.
- 2026-11-26: Mega Maw settled: the ring is FireRing with VelocityMulti 1.05 (10 -> 10.5, 7 -> 7.35, variant 2 =
  the 9.2 hits); the 7.7 lobbed hit is the 15-shot burst (FireBossProjectiles, 3.5-10.5). Both now fit the recordings.
- 2026-11-26: F1 done (6adb633; 2 readers). The tear fall rule is the same one already confirmed for enemy shots
  (fs = 0.9 fs + 0.1 + accel, dies above -5). Tear knockback wasn't found in the code, so measured from recordings
  instead: across 747 recorded hits (an HP drop of 1-10 between two samples), an enemy's velocity jumps by a median 1.1
  px/update (0.14 on normal steps). Bosses: +0.6-1.2 (Haunt, Dingle, Monstro, Duke, Gluttony); Gemini/Steven 79.x and
  Lil' Haunts +2.3-2.4; Pin and 263 ~0. Read 2 updates after the hit, so the raw kick is a little larger. E5 next.
- 2026-11-26: E5 done (243fb5d; 2 readers for all but Embryo). Checked: all 40 recorded Leaper shots are 9.0 along
  the 4 axes at BigJumpDown frame 24 (the landing +); 5 Mulliboom 16.2 hits did 1 at 27-50 px (its blast, radius 60);
  3 Mr. Maw head 35.1 contact hits did 1. The rest isn't in the logs yet. F2 is running; G1-G4 after it.
- 2026-11-26: F2 done (f755a66): charge weapons, tear period fireDelay+1, flight = grid class 0-3, piercing/spectral. Not checked against recordings. G1a is in its second read.
- 2026-11-26: G1a done (294a96c; RE_ENEMIES.md Batch G1a). Not checked against recordings. G1b-G4 handover in runs/research/re/HANDOVER.md; the Ghidra session proposed a fresh Sonnet session (waits on the author).
