# Isaac Bot: enemy playbook

All day the bot found enemy behaviours by taking hits, then got patched one enemy at a time: Chargers on lines,
burrowing worms and Pin, homing flies, Sloth's shot, Hosts. This playbook gives it a **baseline instead**. Every
enemy starts with known behaviour, and learning (tells, motion, hit reviews) only refines it.

- **Machine-readable half:** `enemy_playbook.json` (next to this file). Read it; don't hard-code enemy lists in Lua.
- **Made:** 2026-11-25. Sources:
  - entity types from the game's own `resources\scripts\enums.lua`;
  - which enemies appear on which floor from the wiki.gg floor pages;
  - behaviour from Isaac knowledge;
  - hit counts from `runs\hits.jsonl`.
- **Size:** 238 entries. 152 can appear on floors 1-2: Basement, Cellar, Burning Basement, Downpour, Dross, plus
  the sins and horsemen. The rest are floors 3-4 (Caves, Catacombs, Flooded Caves, Mines, Ashpit), with lighter
  detail.
- **Coverage:** every enemy cause in `hits.jsonl` has an entry. Non-enemy causes (spikes, own bombs, projectiles,
  creep) are in `non_enemy_hit_causes`.
- **Unsure:** 86 entries have an `unsure` field saying what isn't certain. It's mostly variant ids or attack
  details for the Repentance Downpour/Dross enemies. Trust the tags; check the `unsure` part in game or in the
  anm2 data before building on it.

## Entry format

Each entry is keyed by `"type.variant"`, the same key `hits.jsonl` uses (for example `"23.0"`).

```json
"23.0": { "name": "Charger", "type": 23, "variant": 0, "enum": "ENTITY_CHARGER", "kind": "enemy",
          "floors": [...], "stages": ["1-2","3-4"],
          "movement": ["charges_on_line","wanders"], "attacks": ["contact"], "defense": [],
          "danger": 4, "kill_priority": 3, "numbers": {"speed": "very_fast charge"},
          "how": "Stay off its row and column; shoot it from a diagonal.", "bot_hits_logged": 27 }
```

- **`kind`:** `enemy` / `boss` / `miniboss` / `hazard`.
- **`danger`:** 1-5, how likely it is to hit a careful no-hit bot (5 = top threat).
- **`kill_priority`:**
  - 3 = kill first (spawners, homers, shooters, line-chargers);
  - 2 = normal;
  - 1 = whenever;
  - 0 = can't be killed or shouldn't be shot (Stoney, Wall Hugger, TNT, Grimaces).
- **Unknown variant:** fall back to `type.0` and treat it as unsure.

## Vocabulary and what each tag should do to the bot

The JSON's `vocabulary` block has the one-line meaning of every tag. Below is how each one should change the bot's
behaviour.

### Movement

| Tag | Bot behaviour |
|---|---|
| `stationary` | Plain obstacle. Shoot from any safe lane. |
| `wanders` | Predict with the current velocity, plus a small circle of uncertainty. |
| `chases` | Kite in a loop through open floor and always keep a way out. Never back into a corner or an L-room's inner corner. |
| `flees` | Don't chase it into hazards. Cut it off, or shoot along its escape lane. |
| `flies` | Rocks and pits don't block it. Its path ignores the room grid. |
| `hops` | It's in the air mid-hop. Treat its landing spot as danger, not its current spot. |
| `jumps` | Long leaps at Isaac's spot. When it crouches or leaves the ground, **move**, and keep moving sideways until it lands. |
| `bursts` | Spiders. Its reach a moment later is a **circle** about one burst wide, not a line. Shoot it from 3+ tiles. |
| `dashes_at_isaac` | Sidestep at the pause before the dash. Never be in a corner when it's alive. |
| `charges_on_line` | Its row and column are **lanes to stay off** while it's alive. Attack from a diagonal, or line up only briefly when it's facing away. |
| `burrows` | Underground = untouchable, and it surfaces where Isaac is. **Never stand still** while it's under (`m_burrow`). Shoot it when it's up. |
| `orbits` | Predict along the circle around its parent, not in a straight line. |
| `tethered` | Its reach is a circle around its parent (the cord length). Stay out of that circle. Don't model it as a free mover. |
| `bounces` | Diagonal mover. Predict reflections off walls. |
| `wall_crawler` | Keep off the room's edge strip and off the line in front of it. |
| `teleports` | It can appear anywhere. Keep moving, and keep the middle of the room open. |
| `slides_on_line` | Like `charges_on_line`, but it can't be killed. Just stay off its lines. |
| `erratic` | Wide uncertainty circle. Shoot from range. |

### Attacks

| Tag | Bot behaviour |
|---|---|
| `contact` | Keep the usual body clearance. |
| `shoots_single` | Aimed at Isaac, so step sideways (perpendicular) just after it fires. Don't idle on its line. |
| `shoots_spread` | A fan toward Isaac. Step wider than for a single shot, and stay at range so the gaps are big enough. |
| `shoots_ring` | Fixed directions (`numbers.pattern`: plus / X / ring). Stay off those lines. Sitting on a diagonal is safe from a plus. |
| `shoots_burst` | A shotgun or random cluster. Keep long range, and don't stand in front of it. |
| `homing_shots` | Shoot the shots, or keep moving sideways. Kill the source early. |
| `lobbed` | Arcing shots. Dodge the **landing spot** (its shadow), not the straight line. |
| `leaves_creep` | Mark creep tiles as danger, and don't plan paths across fresh trails. |
| `spawns_enemies` | Kill priority up. Kill the source first. |
| `explodes_on_death` / `shots_on_death` | Don't kill it near Isaac. Hold fire, or back off until it's more than ~3 tiles away. |
| `explodes_on_contact` | Top kill priority. Shoot it before it closes in, and back away. |
| `laser` | Its row and column are lanes, as with `charges_on_line`. |
| `stomp` | Move off the spot when it rises. |
| `fire` | Treat it as a solid hazard tile. |
| `slam` | Keep out of its melee ring. |
| `steals` | Not a damage threat, but kill it early. |

### Defense

| Tag | Bot behaviour |
|---|---|
| `invulnerable_until` | Don't waste aim while it's closed or underground. Bait it to open from off its line, then shoot. |
| `invulnerable` | Never a target. Treat it as a moving hazard (Stoney, Wall Hugger, Grimaces). |
| `knocked_back_by_tears` | **Shoot it away; don't flee.** Running from a fast flier leads into corners. |
| `heavy` | Tears won't push it, so kite instead. |
| `splits` | Expect 2+ smaller enemies on death. Kill it far from Isaac. |
| `reforms` | Keep shooting the puddle or pile until it's gone (Globin, Ragling). |
| `shielded_front` | Get beside or behind it before shooting. |
| `phases` | Expect new attacks at low health. |
| `linked` | Parts share behaviour or health. Track both parts. |
| `flees_when_hurt` / `speeds_up_when_hurt` | Finish it quickly once hurt, and keep a way out. |

## The 20 most dangerous floor 1-2 enemies for a careful bot

| # | Enemy (key) | Hits logged | Why it's dangerous | What the bot should do |
|---|---|---|---|---|
| 1 | Pin (62.0) | 11 | Underground most of the time and surfaces under you. A burrowed Pin isn't "moving", so the standing-still guard doesn't fire. | `burrows`: never stand while it's under. |
| 2 | Sloth (46.0) + its Chargers | 87 | Its single big shot slips past straight-line prediction (bot said danger 0). Its Chargers line up at walls. | Off its row and column; sidestep each shot; Charger lanes. |
| 3 | Gemini / Blighted Ovum (79.0 / 79.2, babies 79.10 / 79.12) | 332 | Big twin chases while the baby swings on its cord. Modelled as two free movers, the hits come from everywhere. | `tethered`: reach circle around the parent; circle the room centre. |
| 4 | Dingle / Dangle (261.0 / 261.1) | 223 | Wind-up then a fast slide across the room, plus spit spreads. | `charges_on_line`: off its line at the wind-up. |
| 5 | Monstro (20.0) | 33 | Big jump lands where you stood; spit burst of ~10 shots. | `jumps` + `shoots_burst`: move on lift-off, dodge wide. |
| 6 | Charger (23.0) | 27 | Very fast dash the moment you line up; hits were all at walls and corners. | Row and column are lanes. |
| 7 | Trite (29.1) | 41 | Long leap straight at your spot, from far away. | Keep moving sideways after it crouches. |
| 8 | Crazy Long Legs (207.0) | 11 | Erratic, then a stomp on your spot after a wind-up. | Learn its stomp tell from the anm2; move on wind-up. |
| 9 | Spider / Big Spider (85.0 / 94.0) | 31 | Random bursts that start after the plan is made. | `bursts`: circle reach; shoot from 3+ tiles. |
| 10 | Attack Fly (18.0) | 95 | Faster than Isaac and follows him into corners. | `knocked_back_by_tears`: shoot it away; don't flee. |
| 11 | Dart Fly (256.0) | 6 | Pause, then a very fast dart. | Sidestep on the pause; stay out of corners. |
| 12 | Widow (100.0) | 6 | Jumps and lands on you; spiders and creep fill the room. | Move on jump; kill spiders. |
| 13 | Gurglings boss (237.1) | 4 + creep | Two dashers leaving red creep; the creep traps you. | `leaves_creep` + `dashes_at_isaac`. |
| 14 | Ticking Spider (250.0) | 5 | Hops at you and explodes. | Top kill priority; back away. |
| 15 | Mulliboom (16.2) | 5 | Runs at you and explodes; tanky enough to reach you. | Shoot early from range. |
| 16 | Gluttony (49.0) | 4 | Beam along its line; the bot stood still in 3 of 4 hits. | Off its lines; keep moving. |
| 17 | The Haunt + Lil Haunts (260.0 / 260.10) | 4 | Three fast ghosts first, then a beam boss. | Shoot ghosts as they come; never stand. |
| 18 | Wormwood (62.3) | 0 | Downpour/Dross Pin: dives in and out on arcs. | Same as Pin. |
| 19 | Gurdy Jr. (99.0) | 0 | Fast dashes along rows and columns, plus flies. | `charges_on_line`. |
| 20 | Round Worm (244.0) | 0 | Common on floor 1. Pops up under or near you and shoots at once. | `burrows`: keep moving; sidestep on surfacing. |

**Hit counts include tests.** 77% of today's hits were gauntlet, A/B or bench rounds (see `runs\HIT_REVIEW.md`),
so the counts show where the bot struggled, not how often each enemy appears. Gemini and Dingle are high because
they're gauntlet staples.

## Notes for wiring it in

- **Lanes.** `charges_on_line`, `laser` and `slides_on_line` give the same rule: the enemy's row and column are
  lanes while it's alive. That rule covers Chargers, Sloth's Chargers, Dingle, Gurdy Jr., Gluttony and Slide.
- **Never stand.** `burrows`, `jumps`, `stomp` and `teleports` together decide "never stand still" (feed `ctx.hidden`
  / `m_burrow`).
- **Reach.** `bursts` and `tethered` change the reach shape in `Mover.predict`: a circle for bursts, a circle
  around the parent for tethered.
- **Kill priority.** `kill_priority` 3 is "kill first". 0 means never aim at it (that covers invulnerable things
  and TNT).
- **Exact frames.** Shoot, jump and land frames come from the game's anm2 files (the main session's work). This
  file only says which behaviour to expect.
- **Rebuilding.** The generator that builds the JSON (with a vocabulary check and an enums check) is in the shared
  session notes folder as `build_playbook.py`. Edit its table and rerun it rather than hand-editing the JSON.
