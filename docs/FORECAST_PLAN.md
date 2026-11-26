# The new base: forecast cards + fixed goals (agreed 2026-11-26)

## Why

Until now every behaviour was a weight in one shared score (corner cost, crowd cost, aim reward, ring lane, line
costs, per-boss tactics...). They all push on the same number, so a change for one enemy moves the others: tonight a
commitment weight that fixed Gluttony's rock gap broke Gemini's pant window, the ring-kite and the spike check. With
five times the enemies that only gets worse, and more decompiled facts poured into the same pile of weights would make
it worse still. The author, 2026-11-26: "Imagine having 60 behaviors and 5 of those conflict each other... Now multiply
that by 5."

The decompiled facts so far are **forecasts** (where Dingle's slide ends, where Sloth's lob lands, how hard the Maw
pulls, when spikes are up), not decisions. Forecasts don't conflict: two enemies' danger simply adds up on the map. So:

1. **Facts go into prediction:** one card per enemy, independent of every other card.
2. **Decisions use a few fixed goals** that never change per enemy: don't get hit, keep a way out, deal damage.
3. **Positioning first** (the author: "This game is solely made on positioning properly"; "They know the map... They
   have a game plan ready at any situation"): a slow layer picks where to be; the fast layer (reflexes) dodges.

We do **not** decompile the whole game. Enemies are built from shared parts (RE_CORE: 16 building blocks), so a card is
mostly "these blocks, these numbers". Needed: the building blocks and Isaac's own rules (mostly done), and every enemy
and boss on the road to Delirium. Items, menus and graphics never.

## The pieces

| Piece | What it is | Where |
|---|---|---|
| Cards | per `type.variant`: its building blocks with numbers, the source (which RE batch), confirmed by a recording yes/no, known gaps | `knowledge/enemy_cards.json` (game facts as numbers only, no decompiled code) |
| Forecast | per enemy, per block: where its body and attacks will be over the next ~35 updates (circles, lines, arcs, puddles, pull fields). No card: the learned circle we use now | `mod/isaac-bot/forecast.lua` |
| Room map | the tiles; who gets where first; creep, spikes (with timing), poops, bomb blasts, pull zones | from tonight's escape-room code |
| Positioning brain | twice a second: a home spot + a backup way out, scored by the three goals; kept until clearly worse, dropped at once when an attack starts | `mod/isaac-bot/position.lua` |
| Reflexes | today's planner, slimmed: dodge the forecast, otherwise steer to the home spot | `mover.lua` |

## Steps (each one must pass the gate before the next)

0. **Tonight's gate** (1.2.30 vs 1.2.40, item-free). If not worse: commit and push 1.2.40.
1. **Cards + forecast.** The card format, the forecast for the 16 blocks, and cards for every enemy already decoded
   (Haunt, Dingle, Gemini, Sloth, Monstro, Attack Fly, Trite/Hopper, Charger, Pin, Host, Gapers, Spiders, Dart Fly, Ring
   Fly, Swarm, Squirt, Globin, Widow, Gurglings, Gurdy, Gurdy Jr., Duke, Gaping Maw, hazards). Test: each card's forecast
   against a recording (one check per card, independent). No behaviour change yet.
2. **Reflexes read the forecast** where a card exists, instead of the learned circle. A/B forecast on/off.
   - *Result (2026-11-26, fc-1.2.41 A vs B, quick suite x2):* can't tell (hits +0.06 [-0.28, +0.44], clears -5%
     [-14%, +3%]). Stays off (`forecast = 0`) until step 3 gives the forecast something to plan with; only the
     dart / wall slide / charge line / bounce kinds were on.
   - *Found on the way:* the recordings show Isaac moves his Velocity **twice** per update (enemies once), so the
     planner had been moving him at half speed. `isaac_steps = 2` (fc-1.2.41 A vs C): hits per room **-0.94**
     [-1.31, -0.58], clears **+11%** [+3%, +20%]. On by default since 1.2.42, with the offline mock fixed the same way
     and three other half-speed spots (top-speed starting guess, drift collision filter, fallback scorer).
3. **Room map + positioning brain.** Tests from the live notes: Gluttony's rock gap, the corner pin of bench room
   d.410, Gurgling creep, Larry Jr.'s poops, "sure way out = push in and shoot" (no more timeouts). A/B.
   - *Design (2026-11-26):*
     - **Room map** (`roommap.lua`, once per update while fighting): for each tile, open or not (rocks, poops, pits
       closed), a hazard or not (spikes, harmful creep, fires: `danger.lua`), when Isaac can get there (walking
       distance at his real speed), and when the nearest enemy can (straight line at its speed). A tile is **ours**
       when Isaac is there clearly first and it's no hazard. **Room to move** from a tile = how many of our tiles can
       be reached from it, still first.
     - **Positioning brain** (`position.lua`, twice a second, or at once when the home spot stops being ours): picks
       a **home spot** with the three goals, in order:
       1. *no hit*: only tiles that are ours, and not in a line attacker's row or column without a sidestep;
       2. *way out*: the most room to move, up to "plenty" (a sure way out);
       3. *damage*: with plenty of room, prefer a tile in line with the target at a good distance ("If you have an
          escape plan that you know for certain... focus on laying damage down"); with little room, way out wins.
       The home spot is kept until another is clearly better.
     - **Reflexes:** unchanged, except that the home spot is their firing spot / walking goal (instead of the middle
       of the room). Dodging still decides every move.
     - Switch: `position = 0/1`, A/B on the quick suite. Few numbers on purpose: how much room is "plenty", how much
       the damage goal is worth, how much better a new spot must be.
4. **Retire the old weights one at a time** (corner, ways out, crowd, sandwich, ring lane, per-boss tactics, commitment):
   each removal must not be worse on the gate. The list of hand weights should only shrink from here.
5. **From then on a new enemy = a new card**, plus its recording check. No new weights.

Rough cost: a few days of work over several sessions, plus a gate run (~1 h unattended) per step.

## Keeping the decompile cost down (the author: the blind readers "eat up all my usage")

**Agreed 2026-11-26:** plain enemies get **one reader**, with a fallback so a misread is found by category, not guessed
(the author: "Plan for failure. Have an escape plan. Fix it. Learn from it... so we can know why something is the way
it is almost immediately").

### The fallback: every fact is labelled, every hit is sorted

**1. Each fact on a card carries three labels:**
- **category** (what part of the enemy it describes):
  - `move`: how it moves (chase, hop, charge, orbit, burrow, flight, speed, friction);
  - `attack`: what it fires or makes (shot count, spread, speed, arc, laser, ring, creep, spawns);
  - `timing`: when (tells, wind-ups, cooldowns, states, safe windows, spike phases);
  - `body`: its hitbox, contact damage, when it can't be hurt, knockback taken;
  - `terrain`: what it does to the room (poops, creep trails, rocks it ignores, pull or push fields).
- **source**: which RE batch and which function (the decompiled code itself stays private in `runs/research/re/`), so
  one block can be re-read alone.
- **checked**: `1 reader`, `2 readers`, `recording` (forecast matched recorded behaviour), or `contradicted`.

**2. Every hit is sorted automatically** (a hit review after each run, written to a report):
- **forecast miss**: the forecast said the spot was safe when Isaac got hit. The card is wrong or incomplete, and
  the hit says which category: hit by its body = `move`/`body`, by a shot = `attack`, at an unexpected moment =
  `timing`. That block gets a targeted second read: one small function, not the whole enemy again.
- **decision miss**: the forecast saw the danger and the bot was there anyway. Not a card problem: positioning or
  reflexes (the goals in step 3).
- **no card**: an enemy we haven't decoded yet. It moves up the queue by hit count.
- **hazard**: spikes, creep, bombs, doors: the room map's job.

**3. The recording check runs on every recorded room:** each card's forecast against what really happened, per
category. A mismatch marks that fact `contradicted` before it costs a hit.

So a wrong single read shows up as a forecast miss or a recording mismatch, pointing at one enemy and one category.
The second reader is then spent only where something has already gone wrong.

### The rest of the cost plan
- **Two blind readers stay** for the building blocks, Isaac's rules and bosses (unique code, where a wrong read costs
  most).
- **Plain enemies** that turn out to be known blocks with new numbers: **one reader + the recording check** (agreed).
  The recording is the second source, and it comes for free while the bot plays.
- **Only enemies we actually meet**, in hit-count order (RE_QUEUE.md already does this).
- **Cheaper models for readers** where the code is simple; the strongest model only for writing up and settling
  disagreements.

## What carries over from tonight's work (the separate copy at F:\Tools\isaac-bot-dev)

- The **line trap** (no sidestep in a known attack's line, checked along the whole plan): test 70 passes. It becomes a
  goal check in step 3.
- The **escape-room map** (who gets where first, flood fill from a plan's end): becomes the room map in step 3.
- The **commitment weight**: dropped; the positioning brain's "keep the home spot until clearly worse" replaces it.
