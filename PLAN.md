# Isaac Bot: plan and history

**Current goal:** no damage on floors 1-2, bosses included (so devil deals stay open), with natural, fast-but-safe
play and quick boss kills. Every behaviour change is measured on a locked benchmark and has to pass its gate
(`tools/bench.py`, see `docs/HOW_WE_WORK.md`).

**Why floors 1-2 are strict, and later floors aren't** (the author, 2026-11-26): "you don't have many resources to
protect yourself from losing the devil or angel deal... Soul hearts allow you to take damage without losing your devil
deal chance... you typically don't get a lot of those in the first 2 floors. You get a lot of resources as you progress
floors. Using abilities, checking secret rooms, the shop... So I can allow getting hit. But it can't be often." So:
floors 1-2 no damage; later floors, hits are rare and only when protection is up (soul hearts, Holy Mantle: `risk.lua`
already reasons about these).

**The measure we push to zero: avoidable hits per room** on the locked benchmark (agreed with the author,
2026-11-26). There's no "good enough at 90%": we keep going until the hits left are the unavoidable kind.

**The far goal (the author, 2026-11-26): The Lost and Tainted Lost, the perfect run.** "The Lost can only get hit once
per room. Tainted Lost can only get hit once... If you get hit twice in 1 room, you're dead... It's sort of what I want
to strive for, the perfect run. Only, I want this to be superhuman... insanely fast reflexes, faster than any human can
have. The only negative caveat to this is logic... I want to make it as intelligent as it is fast and agile." It's the
same metric with zero tolerance everywhere, so all the hit-avoidance work carries straight over. Fact for then (game
code, `docs/research/RE_CORE.md`): after a hit Isaac is invincible for 60 updates (half heart) or 120 (full heart), and
a Holy Mantle break gives 60, so for the Lost the 2 s after a mantle break is the only grace.

**Longer term:** whole runs on its own, played better than an average player, and a reusable method for building bots
for other games.

**The long goal (the author, 2026-11-26): beat Delirium, and post a proof video** (game + the bot's live log and
helper on screen, repo link in the description; failed attempts included). The road: no damage on floors 1-2 ->
beat Mom -> Mom's Heart in real runs -> an early Delirium drill on the bench (dropped into his room with set items,
measured like any other room) -> a full run that ends with Delirium dead.

The sections below are the working history: what was tried, what was measured, and what's next.

---

## Smarter than the average player: how
1. **Superhuman reflexes.** The bot knows the exact position and speed of every tear and reacts with no delay.
   Stage 2 doesn't simply step away from danger: it tries several possible moves a few frames ahead and picks the
   safest one (look-ahead dodging).
2. **Expert knowledge, written once.** A strategy guide goes into `knowledge\`: item tiers, strong
   synergies, items that quietly ruin a run, devil/angel deal rules, shop priorities, and boss patterns and counters.
   The local brain follows that guide instead of guessing, with no per-decision cost.
3. **Exact facts every time.** Every choice the brain sees includes the item descriptions (EID) and its current
   stats, so it never decides from fuzzy memory.
4. **Checked answers.** If the brain's pick contradicts the guide badly (for example skipping a top-tier item),
   it gets one retry with the reason, then autopilot decides.
5. **Room to grow.** If gemma3:12b is the weak link, try a bigger local model that still fits a 16 GB GPU.

**Yardstick (what "average" means here):** an average player beats Mom fairly often but dies a lot after that.
Targets: Level 2 beats Mom; Level 3 regularly beats Mom's Heart / It Lives; stretch goal: Satan or ??? (Blue Baby).

---

## How it works: four layers

| Layer | How often | What runs it | Job |
|---|---|---|---|
| Reflexes | Every frame (60x/s) | Lua code in the Isaac mod | Dodge tears and enemies, walk around rocks and pits, aim and shoot |
| Tactics | Every 1–2 s | Rules in the mod | Pick the target, when to bomb, grab a heart when hurt, which way to circle a boss |
| Strategy | Once per room or choice | Rules, plus a local LLM (Ollama) for odd cases | Items, doors, shops, devil/angel deals, pills and cards |
| Learning | After each death | The smartest model we choose | Reads the run log and retunes the reflex settings for the next run |

**Pieces:**
- `mod\isaac-bot\`: the Lua mod (eyes, reflexes, tactics). It's linked into the game's `mods` folder.
- `brain\`: a Python helper on the PC. It talks to Ollama, runs the watcher and the learning loop, and draws the live
  terminal dashboard.
- `runs\`: one log per run (seed, character, items, every hit taken, how it died).
- `settings\`: the reflex tuning file the learning loop edits, plus "best so far" copies.

**How the mod and the helper talk (no `--luadebug` needed):**
- **Mod → helper:** the mod writes tagged lines with `Isaac.DebugString`. They land in
  `Documents\My Games\Binding of Isaac Repentance+\log.txt`, and the helper tails that file.
- **Helper → mod:** the helper writes its answer into the mod's save-data file in the game's `data\isaac-bot\` folder.
  The mod checks it a few times a second with `Isaac.LoadModData`.
- This keeps file access locked for all other mods. `--luadebug` stays a fallback only if this pipe turns out too
  slow.

**Install facts (checked 2026-11-25):**
- The game folder (`game_dir` in `config.json`) has REPENTOGON (Workshop mod + `Repentogon\` folder), and the game is
  launched through the REPENTOGON launcher.
- 15 Workshop mods were on in the test setup, including **External Item Descriptions** (EID), which is the brain's item knowledge.
- Ollama has `gemma3:12b` (brain) and `qwen3-vl:8b-instruct`.

---

## Stages

### Stage 0: Groundwork ✅ DONE 2026-11-25
**One click:** `start-bot.cmd`
1. Opens the helper window (Windows Terminal).
2. Closes any idle leftover REPENTOGON launcher (a second copy fails with "already launching").
3. Starts the launcher with `StealthMode = 1`, then sets it back to 0 once the game is up.
4. The mod's menu autopilot loads **slot 2** and starts a run as Isaac, in under 1 s of menu time.

**Pipe test:** 20/20 pings, median **100 ms** round trip (target was under 500), result in `runs\pipe_test.json`.

**How the pipe really works (the plan's first idea, log.txt, failed: the game writes its log to disk late):**
- Game → PC: the second mod `mod\isaac-bot-out\` holds the newest ~60 messages and writes them into its save file
  `data\isaac-bot-out\saveN.dat` (`S|session`, then `id|kind|frame|body`).
- PC → game: the helper writes `seq|command|payload` into `data\isaac-bot\save1-3.dat`, and the mod reads it 10x/s.

**Menu facts learned:**
- At boot the game fires MC_POST_SAVESLOT_LOAD for every slot with `selected = false` (just drawing them); a real
  pick comes with `selected = true`.
- The title and save screens do NOT read MC_MENU_INPUT_ACTION (only RESTART 16 and FULLSCREEN 17 go through it).
  So the mod sends `need|enter|title` or `need|enter|saves N`, and the helper posts a real Enter key to the game window
  (PostMessage, no focus change). It only escalates to focus + keypress after 2 failed tries.
- `SaveMenu.SetSelectedElement(1)` = slot 2 (0-based). MainMenuType: 1 title, 2 saves, 3 game.
- Safety: Enter is only ever requested on the title and save screens (never the game menu, where it could
  "Continue" the player's own slot-1 run), and `StartNewGame` only runs when slot 2 was truly picked.
- One crash (exit `0xcfffffff`) during menu load right after a fast close and relaunch. The bot hadn't run yet, the
  retry worked, and the cause is unknown; keep an eye on it.

**Other changes made for unattended runs (backups saved as `.bak-isaacbot`):**
- `PauseOnFocusLost = 0` in `options.ini` and REPENTOGON's `vanilla_options.ini`, so Alt-Tab doesn't pause.
- `SkipIntro = 1` in REPENTOGON's `options.ini`.
- Helper pings every 0.5 s in a run (the author's choice).

**Earlier notes:**
- Mod `mod\isaac-bot\` is linked into the game's `mods` folder with a junction (same for `isaac-bot-out`).
- Helper `brain\helper.py`: `helper.cmd --auto` is live with auto-start; `helper.cmd --test 20` is the pipe test.
- REPENTOGON has a Lua ImGui API (its windows can even sit outside the game window). Use it for the "what the bot
  sees" overlay.
- The 15 mods in the test setup: all cosmetic or HUD except Vitiated Characters (new characters, only matters if picked) and GoodTrip
  (Tab + click travel; ignore it).
- **Still to do:** the pipe test inside a real run on slot 2.

**Original checklist:**
- Create the folders, an empty mod that loads under REPENTOGON, and the helper skeleton.
- Prove the two-way pipe and measure its delay (target: under ½ s round trip).
- Read REPENTOGON's docs for extra functions that make seeing or controlling the game easier.
- Check that nothing on the PC (a game-mode tool, for example) closes Ollama when `isaac-ng.exe` starts.
- Check which of the 15 installed mods change gameplay in ways that could confuse the bot.
- **To decide:** which save slot is the bot's (so its deaths and unlocks don't touch the player's own file), and
  whether it may earn Steam achievements on the account (achievements are account-wide, not per slot).

### Stage 1: Eyes ✅ built 2026-11-25 (mod 0.1.3); overlay still to be checked by eye
**Built:**
- `mod\isaac-bot\eyes.lua`: a snapshot 10x a second (player + stats + hearts + consumables, every enemy with
  position, speed and health, enemy shots with direction and height, enemy lasers and bombs, pickups with price,
  fireplaces, doors with target room type, open or locked). The room's tiles are sent separately (`#` rock, `~` pit,
  `^` spikes, `p` poop, `D` door, ...) whenever they change.
- In-game overlay: enemy health above each enemy, `o` on each enemy shot plus `.` where it'll be in a third of a
  second, `$` on pickups, and a "sees: N enemies, N shots" line.
- Two windows, each remembering its spot (`tools\helper_window.json`, `tools\log_window.json`):
  - **Isaac Bot helper:** a dashboard that redraws in place (hearts, stats, doors, an ASCII room map with `@` you,
    `E`/`B` enemies, `o` shots, plus threats with time to impact, and recent events).
  - **Isaac Bot log:** everything scrolling (pings every 0.1 s, every eyes snapshot, events).
- `restart-bot.cmd` closes the game and both windows, then starts everything fresh (never two of a window).
- Test tool: lines `command|payload` written to `runs\send.txt` are forwarded once. `spawn|14.0` spawns an enemy
  in a slot-2 run.

**Verified:** spawned a Pooter, a Clotty and a Gaper. All three were tracked with live position, speed and health,
Clotty shots were tracked in 4 directions, and Isaac's hearts dropped as he was hit.

**Bugs found and fixed:**
- Python's `write_text` on Windows wrote `\r\n`, so every command except the last in the inbox carried a hidden
  `\r` and didn't match. The helper now writes bytes, and the mod strips `\r`.
- The outbox keeps 40 events, so at 10 pings a second they roll over in about 4 s. The helper keeps up, but
  after-the-fact checks should read `runs\live.log`, not the outbox file.

**Original checklist:**
- Every frame, the mod reads: the player (position, speed, damage, tears, range, health), every enemy (position,
  movement, health, boss or not), every projectile and its direction, rocks, pits, spikes, fires, pickups and doors.
- A debug overlay in game draws what the bot "sees": danger zones, its target, where it wants to stand.
- The terminal dashboard streams the same data live.
- **Milestone:** stand in a room and watch the overlay track everything correctly.

### Stage 2: Reflexes ✅ first version built 2026-11-25 (mod 0.2.0)
**Built:** `mod\isaac-bot\reflex.lua`
- Every update it tries 16 directions + standing still, plays each forward 12 updates (0.4 s) against predicted
  shots, enemy bodies, lasers and bombs, plus rocks/pits/walls/spikes, and adds a "good fighting spot" cost
  (preferred distance, lined up on the target's row or column, away from crowds and corners).
- Aiming: nearest enemy it can hurt, led for its movement, along the main axis.
- Controls go through MC_INPUT_ACTION (move = analog values, shoot = pressed). Every number is in `Reflex.S`, and
  `set|key=value` tunes it live.
- **Combat mode:** the bot drives only while there's a fight in its slot-2 run. A clear room gives the player back the
  controls (Stage 3 replaces that with auto-walking).
- Arena tool: `arena|N` heals and spawns N random Basement enemies (Gaper, Horf, Fly, Pooter, Clotty, Attack Fly,
  Charger, Maw, Hopper, Dip) at least 150 px away; it reports clear time, hits taken and what hit it.
  `tools\arena_bench.py 5 5 6 6 8 8` runs a series and appends to `runs\arena.jsonl`.

**First results (2026-11-25):**
- 7 arena waves (4–8 enemies, 43 in total) all cleared with **0 hits**, 18 s average per wave. Checked against
  health readings: never below full across 1,841 snapshots, with up to 13 enemy shots on screen at once.
- **Monstro** (spawned in the start room) killed in about 45 s with **0 hits**.
- Caveat: the arena is an empty start room, and enemies spawn at a distance. Not yet tested: real rooms with rocks
  and pits, champions, enemy lasers (Brimstone-style), more bosses, and anything that isn't a Basement enemy.

**Original checklist:**
- **Dodging:** predict where every projectile and charging enemy will be a few frames ahead, then step to the safest
  nearby spot.
- **Walking:** pathfinding around rocks, pits and spikes on the room grid.
- **Shooting:** Isaac fires in 4 directions, so the bot lines up with its target on a row or column and keeps a safe
  distance. Special weapons (Brimstone, Mom's Knife, charge shots) come later as their own cases.
- **Control:** the mod presses buttons through the game's input callback (`MC_INPUT_ACTION`).
- **Milestone (Level 1 done):** it clears normal Basement rooms alone. **Check-in: is it fun to watch?
  Keep going?**

### Stage 3: Autopilot floors ✅ first version 2026-11-25 (mod 0.6.2)
**Built (`nav.lua`, `rescue.lua`, `rules.lua`):**
- Walks rooms with pathfinding (around rocks, pits, spikes and lit fires; never brushes other doors).
- Picks up what the rulebook says: pills, cards and trinkets only into an empty slot (this fixed the swap loop);
  drops the goal the moment an item is taken (this fixed standing on the empty pedestal).
- Explores using only visible doors: treasure first, then everything reachable, boss last, then the trapdoor.
  Curse rooms only as a last resort.
- **Bombs, weighed:** blasts through rocks to an item or chest with 1+ bomb, to small stuff with 4+.
  - Secret rooms: guessed from its own map (empty square touching 3+ rooms, not next to the boss).
  - Siege: only when every lane to the enemies is stone (a poop lane gets shot instead).
- **Line of fire:** shoots along a row or column whose path is clear (tears fly over pits; rocks block them; poop
  breaks).
- **Exit plan (the author's rule):** each spot it considers scores how many of 8 directions are open; corners cost more.
- Shielded enemies (e.g. a fly tied to a poop): breaks the nearest poop or fire.
- Death or win screen: asks the helper for Enter and starts a new run. `runs\runs.jsonl` logs the result, floor
  reached and time.

**The "logic, not tests" layer (the author's 5 points, all done 2026-11-25):**
1. **Watchdog** (`rescue.lua`): no progress (new room, damage dealt, something collected) for 8 s walking / 10 s
   fighting climbs the ladder replan → shake → bomb → leave → report. In fights it only changes aim.
2. **Game data:** the `isaac-bot-data` mod dumps every item, trinket and card (name, quality, type, EID
   description) once per launch, saved as `knowledge\gamedata.json` (772 items, 195 trinkets, 112 cards).
3. **Rulebook:** `mod\isaac-bot\rules.lua` (data the bot runs on) + `knowledge\RULES.md` (the reasoning; the brain
   reads it).
4. **Brain when stuck:** a "stuck" report goes to gemma3:12b (`brain\rescue_brain.py`, in the background) with a
   text map, doors, goal and the rulebook. It picks replan / bomb / door N / goto col,row / shake / wait, and the
   mod does it. About 14 s the first time. Its first answer was valid but not clever: expect to tune the prompt.
5. **Batch review:** `runs\hits.jsonl`, `stuck.jsonl`, `brain.jsonl` and `runs.jsonl`. `tools\review.py` writes
   `runs\REVIEW.md` grouped by kind. It already caught lit fires as a hit cause, and fixed them as one category.

**Real-play results so far:**
- Beat Basement I fully on its own (boss Dingle, about 1.5 hearts lost) and reached Basement II in 3 min.
- Bombed its way to a golden chest it had a key for.
- Takes more hits in real rooms than in the arena (Hoppers, Attack Flies, fires). Next: tune from the reviews.

**Fight upgrades (0.7.x, 2026-11-25, from the author's Horf and shielded-fly rooms):**
- **Firing-position planner:** every 0.5 s it sweeps all walkable squares and lists the squares lined up with a
  target (same row or column, in range, no rock between; poop counts as soft). It walks the real path to the
  closest safe one and shoots down the lane once lined up. It sticks to its plan unless a clearly better one turns
  up.
- **Slow steps:** 16 extra moves at 0.3 speed for fine positioning (full-speed moves overshot a spot 24 px away).
- **Watchdog mid-fight:** replan = switch target; bomb = siege; report = brain. The brain's "goto" becomes the
  firing spot.
- **Planner readout:** the log line during fights shows `fire from c,r at c,r` or `no firing spot: <reason>`.
- **First batch review:** all 12 stuck moments were fights against stationary enemies behind rocks, and the brain
  chose "bomb" 9 of 12 times. It's now told bombs are scarce and to prefer firing squares.
- **Open:** a shielded Eternal Fly (type 96) sealed in a rock pen with poops. The bot targeted the right poop but
  stood still; watch the readout the next time it happens.
- **Gotcha:** PowerShell `Set-Content -Encoding utf8` writes a byte-order mark. Write Lua files without one (Isaac's Lua can't read it).

**Principles instead of patches (0.8.x, 2026-11-25), after the author: "there has to be a smarter way":**
- **Danger map** (`danger.lua`): one map of what hurts (spikes, creep at its real size, lit fires, bombs,
  unkillable leftovers), in half hearts, read by walking, fighting and the brain's options.
- **Worth it?** (`R.risk`, `R.value`): every pickup has a value (penny 1 ... item 30 + 15 x quality). The damage
  there and back is priced by current health (lethal = never), plus `per_hit` = 25 for the lost devil/angel deal
  chance (the author: "the goal is to just not get hit at all").
- **Multiple-choice brain** (`options.lua` + `rescue_brain.choose`): when the watchdog runs out, the code lists
  the real options (targets with a firing square, poops to shoot, doors with route cost, pickups with value/risk,
  bombs within budget) and the model picks a letter. The first live use unstuck a Clotty fight.
- **Model exam** (`tools\exam.py`, `knowledge\exam.json`, 28 questions): gemma4:12b scored 28/28 and is now the
  brain, run with think off (~1.3 s).
- **Shoot straight:** tears carry Isaac's movement, so once lined up and not threatened it stands still to fire.
  With no enemy shots in the air, lining up counts 3x (it used to stand a tile off a Clotty's row).
- **Bugs fixed:**
  - The planner crashed on poop targets (that's why the Eternal Fly pen never got a plan).
  - A stuck fight was unlocking curse rooms for the whole floor; it took 2 hits in one.
- **Tests:** two Clottys dead in 20 s with 0 hits (0.8.1). In 0.8.0 it beat the Basement I boss with 1 hit and
  reached Basement II at 89 s.

**Measuring instead of eyeballing (0.8.3-0.9.6, 2026-11-25), after the author: "I don't want to go through every
single enemy":**
- **Gauntlet** (`tools\gauntlet.py`): every common Basement enemy plus 4 bosses, in a clean item-free run with
  random rocks. Normal enemies 2 at a time, Globins and bosses 1 (the author's call). It reports result, time, hits,
  aim % and items held, and appends to `runs\gauntlet.jsonl`.
- **Aim quality:** the share of shots that could actually land. It found 40-45%; now 100% (hold fire when a shot
  can't land, lead the target, stand still only when safe).
- **Results, clean base Isaac (0.9.3):** 18/21 cleared, 14 hits. Regular enemies were nearly all 0 hits. Monstro
  had 0 hits. Bosses were weak: Gemini died (6 hits), Dingle 3, Duke of Flies 3.
- **Fixes from the numbers:**
  - Horfs: no firing spot when bunched → clearance by movement.
  - Horfs and Boils: jitter looked like movement → measure NET movement (velocity vector average).
  - Maggots took 45 s → the planner only handles truly still enemies.
  - Globins: hit while standing → never stand with a mover close, and assume chasers charge (not bosses: that
    broke Monstro's jump).
  - Hosts: bait them open from close range (the author's tip).
  - Learn from hits: each enemy type that hurts us gets a bigger berth for the session.
- **Curved shots (the author's tip):** tears inherit Isaac's sideways movement. Measured from 266 real shots: they
  keep **1.16x** Isaac's sideways speed. The bot now fires curved shots while drifting toward a near-miss target
  (pivot), and self-calibrates the factor.
- **Circle-strafe:** against movers it's rewarded for circling at fighting distance, instead of parking and
  waiting for a clean line.
- **Tells (`tells.lua`, the Elden Ring idea):** it learns which enemy animation precedes its shots (and hits),
  then steps off its spot during a learned wind-up, before the shot exists. What it's learned is written to
  `knowledge\telegraphs.txt`.
- **Test-bench fixes:**
  - A test never carries into a new run.
  - The gauntlet waits through a death.
  - It locks "fight only" and starts a fresh run first (an item had skewed results).
  - Larry Jr. dropped (a one-line spawn makes a broken worm).
- **0.9.6-1.0.2 (same night):**
  - All 16 regular enemy types: 0 hits in one full pass (0.9.8).
  - **Persistent learning:** tells, respect and the auto-tuner's numbers are saved by the helper (`knowledge\*.dat`,
    `tuned.json`) and handed back at every run start.
  - **"Never solid" filter:** Gemini spawns 18 cord pieces that the game lists as enemies. The bot saw 20 enemies
    and got cornered. Ignore things that have NEVER had collision (Monstro loses collision mid-jump, so "right
    now" wasn't enough).
  - Bosses keep real-movement prediction. Learned "hurtful" animations only widen the berth: turning them into
    assumed charges re-broke Monstro's jump.
  - Gauntlet: each round clears leftovers first (a timed-out Duke + flies crashed the next round), and the round
    limit is 150 s for bosses.
  - Bosses at 1.0.1:
    - Gemini cleared 2/2 (3 hits each; it used to die every time).
    - Dingle 1/2.
    - Monstro mostly clean.
    - Duke slow.
- **Auto-tuner** (`tools\tune.py`): changes one number live, runs the 6 hardest, and keeps it only on a clear
  improvement. Results go to `runs\tune.jsonl` and `knowledge\tuned.json`.
  - **Finding:** boss randomness swamps single-change effects. The same settings scored 433 / 217 / 182, and with
    fixed seeded layouts (`gauntlet|T.V|N|ROCKS|SEED`) still 347 vs 261. It needs many passes per setting, so it's
    only worth running overnight in long batches.
- **A/B tool** (`tools\ab_test.py ENEMY N "A settings" "B settings"`): N rounds each, switched live.
  - Dingle, stronger dash-dodge (warn_w 650 / dash_side 50): 0/4 vs 2/4. Rejected.
  - Dingle, look-ahead 20 vs 12: 2/4 vs 3/4. Rejected.
  - Dingle, straight-dash prediction (dash_speed 5) vs homing: 1/4 vs 0/4. Kept.
- **The respect feedback loop (big one):** every boss and Attack Fly had maxed out at 3x respect, which meant 3x
  berth and avoidance. The bot got cornered, took more hits, and grew more respect. Capped at 1.6 (step 0.15) and
  reset. Bosses went 2/8 → 7/8 cleared.
- **Boss hits are bodies, not shots** (about 75%: Gemini 79, Dingle 70, Monstro 19, Suture 18, plus 63 Attack Fly
  swarm hits). Changes:
  - Swarm rule: 3+ light enemies close aren't "harmless".
  - A bigger boss berth was WORSE (more corners); the knobs are left in, set to neutral.
  - Grounded slow hurtful boss moves count as homing (Gemini's walk); fast ones are straight dashes.
- **Warning animations (`Tells.warning`):** it learns which animation leads into a hurtful one (Dingle
  "BeforeSlide" → "Slide"; Slide = 64 hits) and steps out of the dash line during the warning. Transitions are
  saved too.
- **Bosses at 1.0.5-1.0.7:**
  - Monstro: mostly 0 hits.
  - Duke of Flies: 0-2 hits.
  - Gemini: about 3 hits, sometimes dies.
  - Dingle: the hardest, 25-75% clears. It's hit in the room's middle (dash paths), by dashes (32) and spit (14).
- **Real-play test, 1.0.7 → 1.0.8 (2026-11-25, 11:00-12:00):**
  - The "many floor-1 restarts" in the first 30 minutes were the A/B gauntlet rounds dying, not real runs.
  - Real play reached floor 2 (246 s), then **bounced between two rooms for 25 minutes**. Cause: a door that didn't
    work out (locked / walled off / deadly route) was only remembered for that room visit. Room A routed via B,
    B gave up and routed back via A, forever. The watchdog never fired because every room change reset it.
  - Fix (1.0.8): failed doors are remembered for the whole floor (`deadEdge`, forgiven when keys, bombs or health
    go up). A loop breaker (8+ entries in 25 s, none new) refuses to step straight back. Doors walled off by poop
    get shot open; by rocks, bombed (`R.bombs.door_boss` 1, `door_explore` 3).
  - **Trites** (29.1) hit it 5 times in 11 s in a big room. The touch prediction bent every fast mover toward the
    bot, so it fled along the leap line. Now fast non-boss movers keep their real line too (`dash_all`).
    A/B with 6 Trites per round, 5 rounds: 9 hits → 3. One Trite, 6 rounds: 3 → 1. Kept.
  - `ab_test.py` takes `ENEMYxCOUNT` (e.g. `29.1x6`). It finishes on setting B (the code default).
  - Full gauntlet after the leap rule: all 16 regular enemies 0 hits; bosses 19/20 total with 8 hits. No regression.
  - **Boils** had silently broken (0/3, "no firing spot", not even in the enemy list): they spawn small with no
    collision, and the "never solid = cord piece" filter hid them. Now a never-solid enemy is skipped only if it
    hangs off a parent or can't be hurt (1.0.9): Boils 3/3, 0 hits; Gemini still clears (3-4 hits).
  - 1.0.10: "door X>Y no good: <why>" notes go into the log (`nav` events). Gauntlet/A-B deaths are tagged
    `"test": true` in runs.jsonl so real-run stats can leave them out.
  - Real play on 1.0.10: floor 2 at 151 s, **floor 3 at 437 s**, no deaths in 25 min. Then a 15-minute stall in
    one room: the secret-room guess was a wall with pits in front. It couldn't walk there, dropped the goal, and
    re-picked the same guess every update. When the rescue ladder made it leave, it came straight back.
  - Fix (1.0.11): a secret guess needs a walkable spot in front of the wall, else that wall/room pair is crossed
    off for the floor (`secretBlocked`). When the rescue makes it leave a room, whatever it was stuck on there
    stays failed for the floor.
  - Real play on 1.0.11: **floor 4 at 610 s** (best yet), no stalls over 80 s. But 4 earlier deaths, 3 of them
    floor-1 boss fights: Gurglings (red creep), Blighted Ovum, a Trite + Attack Fly boss room.
  - **Creep (1.0.12):** the square-based danger map only marks squares whose centre is inside a puddle, so small
    puddles were invisible. The dodge scoring now checks each puddle by exact distance. Gurglings: 0 hits, 2/2.
  - **Blighted Ovum (79.2):** measured live: it HOMES on Isaac at ~6 px/update (Isaac is faster). The "fast
    = straight dash" rule treated it like Dingle's slide. A per-enemy homing score (average heading-to-us cosine
    while moving) now tells chasers from dashers (`homing_min` 0.8). A/B 4+4: 19 hits → 13, 2/4 → 3/4.
    Wall bounces in straight predictions (`bounce`): 17 → 15, kept. A kiting reward (`kite_w`): no gain, off.
    Still the weakest boss: most hits are in corners. Dingle A/B on homing: 21 → 19 hits, no harm.
- **1.0.16-1.0.22 (2026-11-25, watched live):** run-and-gun (shoot any enemy a shot would hit while
  fleeing), relax ladder for "no firing spot" (pocketed spider), runway rule + stronger corner costs (Gemini
  2/4 → 4/4 cleared), 2-step look-ahead (written, not yet A/B'd), corner cost for firing spots, two-pass scoring
  + per-update timer (avg 4-7 ms, spikes 24 ms), fire fix (relax had dropped the gap around fires to 0: it
  walked into one), active items (rules.lua R.active), skipped-pickup notes. Measured: corners are 8% of the
  floor but 26% of hits (143 of 530 today).
- **The author, 2026-11-25: "There has to be a better way... this still comes down to fixing every little bug."**
  Fair point: ~40 hand-tuned weights that fight each other; tests use one enemy in an empty room while real rooms
  mix poop, fire, rocks and enemies. Proposed rebuild of the movement core (waiting on a go-ahead):
  1. **Learned motion per enemy, from recorded play** (no per-enemy code): log every enemy's path in every room
     the bot plays, fit how far each type can get in 0.5/1/1.5 s (speed, bursts, leaps, homing). Unknown types
     start with a safe default and learn after one room.
  2. **One goal for movement, searched deeper:** "never be where something can reach", over ~1.5 s with a beam
     search over move sequences (continuous positions, not tiles), instead of 0.4 s plus a pile of corner,
     crowd, edge, runway and kite weights. Corners lose on their own (no way out within 1.5 s).
  3. **Shooting as a second goal** inside the same search (lined up / curved shot = reward), not a separate
     planner that walks to tile centres.
  4. **Real-room bench:** every room where it takes a hit or stalls is saved by its room ID and replayed with
     the debug console (`goto s.normal.<id>` on the right floor type); fixes are judged on those rooms, and
     they stay as a check so old problems can't come back. Overnight: replay all of them unattended.
- **The author said "Yes, rebuild it" (2026-11-25). Built 1.1.0-1.1.1:**
  - `mover.lua`: learned reach per enemy type (keeps-velocity vs stays-put guess, drift toward Isaac, 95% radius,
    at 0.2/0.5/1/1.5 s) + 3-move beam search (~1.2 s, 33 → 9 → 9, best 6 kept) with one safety cost; aim is a
    reward inside it. Learning runs every update whichever core drives. `set|core=2` switches to it live.
  - Learned movement is saved to `knowledge\motion.dat` (every 30 s) and reloaded on start.
  - **Faster testing:** `reload` command reloads the bot's code in the running game (`luamod`): 0.5 s, the run
    goes on. Restarts now wait for the bot's "start" line (24 s) instead of a fixed 95 s.
- **1.1.2-1.1.13 (watched live):** closed trapdoor under Isaac (step off, come back); full speed by
  default (slow steps only when lining up), turning cost (flow, not twitching), ways-out check at every plan's
  end (corners), smaller margin + bigger aim reward; a shield must be within 70 px (a Host made it bomb a fire
  across the room), never siege-bomb a fire/poop; no aim reward on a closed target (bait the Host instead);
  search trimmed by the FULL score (with no danger, all plans tied and it kept 6 random ones); back to a cleared
  boss room for the trapdoor; the floor map now survives reloads (a reload had wiped it: "nothing to do").
- **Seeing the game (the author's idea):** `tools\look.py` pulls frames from Steam's background recording (~3 s
  behind). The helper saves 3 frames ~4 s after every hit into `runs\hitframes\` (newest 15 kept). `why` log
  lines explain each move choice once a second; `map` prints the bot's floor map.
- **1.1.14-1.1.23:** poop "gates" (boxed-in enemies → shoot the poop/fire next to them), always walk to the firing
  spot, ways-out uses each enemy's likely spot (jumpy spiders had closed every way), spray when roughly in line
  (`loose_aim` 40: it never fired at spiders), spawners first (`SpawnerEntity`: the Sack making spiders),
  progress measured to the FINAL firing spot (a one-tile waypoint made walking "overshoot": it stood still).
- **Real-room bench (built 2026-11-25):** every room logs `room IDX|TYPE|VARIANT|STAGE|NAME`. `goroom|normal|<v>`
  replays a layout (console `goto d.<v>`; boss rooms `goto s.boss.<v>`) from full health and reports
  `bench|cleared/died/timeout|secs|hits`; `stage|1a` switches floor first. `tools\rooms.py collect` saves every
  room with a hit to `knowledge\bench_rooms.json`; `rooms.py run` replays them all, worst first. Judge every change
  on this list; rooms stay in it so old problems can't come back.
- **Lag fixed (1.1.24-1.1.32), measured on the same 28x16 room (Cellar layout 825):** 12-26 ms avg / 30-68 ms
  spikes → **3.5 ms avg**, and the room went from 53 s to 14.5 s clear time, 0 hits. Causes, in order: walking
  pathfinder rescanned its open list and asked the game per tile (now a heap + per-update tile cache + path memo);
  danger map re-read every tile each update (now every 10); the v2 core asked the game ~1,500 times per update
  (wall, hazard and ways-out answers now cached per patch of floor) and now thinks every 2nd update
  (`m_every`). The `perf` line splits the time: planner vs moves.
- **Fairness (the author: items are outliers):** every floor logs `power` (damage, tears/s, speed, item ids); the score
  report flags runs "carried by items"; the room bench starts from a fresh, item-free run.
- **Sloth (Cellar II miniboss, layout 2030) is the current hard case:** hits are its body + the Chargers its shot
  turns into. Old core 3 hits; new core 2-6 hits, sometimes dies (high variance). Tells weren't wired into v2;
  now wind-ups make the shooter's line costly (`m_line` always-on cost tried, made it worse, set to 0).
- **Offline checks (idea from an earlier Isaac mod's offline tests):**
  Isaac ships its own Lua engine (`Lua5.3.3r.dll`, 32-bit). `tools\luacheck.ps1` compiles every bot file with it
  (catches syntax errors and byte-order marks in ~1 s); `tools\reload.ps1` = check → reload in game → wait for the
  start line → scan the game log for Lua errors. Use it for every reload. Not yet: a fake-Isaac harness (their
  `mock.lua`) to RUN the logic on scripted situations; that would also catch load-order mistakes and logic bugs
  (tied beam, overshoot, room bounce) in seconds. Dodging quality still needs the real game (room bench).
- **Offline logic tests built (2026-11-25):** `test\mock.lua` (fake Isaac: rooms from grid letters, real enum
  numbers and room geometry, chasers, shots) + `test\tests.lua` (scenarios) + `test\run.ps1` (runs the bot's REAL
  code in Isaac's own Lua engine, ~2 s, no game). 6 scenarios from today's bugs: button room, far pennies, shot at a
  standing Isaac, chaser near a corner, closed Host, still target. All pass; re-adding the penny bug makes its test
  fail. `tools\reload.ps1` now runs compile check + tests before every reload (blocks on a FAIL unless -Force).
- **1.1.35-1.1.44 (late afternoon):** unkillable shooters in cleared rooms = dodge-only, no fight (Constant Stone
  Shooter); weak written-off doors expire + forgive once per situation (K1 bounce fixed); corridor spray in all 4
  directions (K2); buttons guarded by unkillable heads (nothing hurtable + unpressed plate = walk to it); the walk
  pull works without a target; shots learned per type and shooter; spikes checked under Isaac's edges; bench
  stays fight-only (item-free). Hit log now says what really touched Isaac + the nearest shot: **Sloth's hits are
  all its shot** (Sloth 99-216 px away). No bursts. **Big find: the planner assumed Isaac moves 4.6 px/update;
  real top speed (item-free, speed 1.0) is ~7.7**, and he accelerates over several updates. Now learned live
  (`Mover.top` per speed stat, `Mover.acc`) and simulated with acceleration.
- **Side sessions (2026-11-25):** hit review (`runs\HIT_REVIEW.md`), item ratings (`knowledge\item_ratings.json`,
  `ITEMS.md`), offline tests (31 passing; `run.ps1 -Prove` = each fix's test fails without it).
- **Secret rooms (the author, 2026-11-25), done in 1.1.50:** from inside a secret room only OPEN doors count (leave the
  way you came in; it walked into unbombed walls), and the dodge code no longer walks back to a bomb it just placed
  (it bombed itself). **Later idea (the author's):** bombing OUT of a secret room can be worth a bomb when the wall leads to
  a curse room (no door damage) or a treasure room (no key needed, or few keys left); otherwise leave the way in.
- **First after the core work (the author, 2026-11-25): devil/angel deals.** The bot skips both rooms on purpose
  (`rules.lua` R.room 14/15 `visit = nil`). Plan: angel room = always enter, take the best-rated item
  (`knowledge\item_ratings.json`); devil room = buy only items rated great for this bot and only if at least one
  heart container stays; log every deal taken/skipped with the reason.
- **Later (the author: core logic first, "little things" after):** two-step active items (Bob's Rotten Head lifts on
  the first press and needs a shot direction to throw; the bot presses once). Item names in the log show as
  `#..._NAME` keys (cosmetic).
- **Next on the list:**
  - Bosses (Gemini, Dingle, Duke): tells should help; then per-boss checks.
  - Position evaluation for all enemies (Killzone-style: score squares for line of fire, distance, escape routes
    and staying out of other enemies' lines).
  - The overnight auto-tuner.

**Fixed bugs:**
- "New room" fires before "new level", so the door map got wiped.
- The game reports hidden secret doors as "open" (now checked by whether the wall is still solid).
- The bot stood still next to its own bomb.
- `\r` in inbox commands.

**Original checklist:**
- After a room is cleared: pick up what's worth it (hearts only when hurt, coins, keys, bombs), then pick the next
  door.
- Floor map from the game's room list: explore, find the treasure room and boss room, use keys on locked doors.
- Simple default rules for every choice, so the bot can finish floors **without** the LLM. This is the fallback
  whenever the brain is slow or gives a bad answer.
- **Milestone:** it clears Basement 1 → Basement 2 on its own.

### Stage 4: The brain (about 1 session)
- Pull every item's description out of EID's files into one lookup table.
- At each choice, the helper builds a short text briefing (character, stats, health, items held, consumables, floor
  map, the options with their EID descriptions) and asks `gemma3:12b` for a JSON answer: the choice and a one-line
  reason.
- Choices it makes: take or skip items, shop buys, devil and angel deals, route, when to use pills, cards and active
  items.
- Safety net: if the answer is invalid or takes over 3 s, autopilot decides instead.
- **Milestone:** a run where every big choice came from the brain, with its reasons shown on the dashboard.

### Stage 6: Run logs (about ½ session)
- Every run saves its seed, character, items, rooms, every hit taken (what hit it and where it was standing), cause
  of death, floor reached and time.

### Stage 7: Learning loop (about 1–2 sessions)
- Every reflex number lives in the settings file: danger radius, how far ahead it predicts, preferred distance per
  enemy type, aggression, and per-boss overrides.
- After each death, the coach model reads the run summary plus the current settings and suggests small changes.
  The next run uses them.
- Keep the best settings so far. If new settings do worse over several runs, roll back automatically.
- **Overnight mode:** the bot restarts runs by itself. It runs detached, with a watchdog and pre-flight
  checks. **Each overnight session is approved first.**
- **Milestone:** the run board shows floors reached going up over a night of runs.

### Stage 8: Progress board (about ½ session)
- A run-history board: floors reached per run, deaths by cause, best run, items it loves.

---

### Offline practice (the author's idea, 2026-11-25): "feed the LLM offline tests"
Yes, and it fits the plan:
1. **An exam for the brain:** a set of Isaac situations with known good answers (take or skip this item, is this
   devil deal worth it, which door next). Run any model against it offline in minutes and score it. This picks the
   best local model and prompt, and checks the strategy guide, before a single real run. (Add in Stage 4.)
2. **Replays for the reflexes:** the eyes already record every room 10x a second. Saved rooms can be replayed
   offline, much faster than the game, to test and tune dodging. That fixes the "game runs in real time" bottleneck
   for the learning loop. (Add in Stages 6–7.)
3. **Fine-tuning a small model** on many examples is possible on a consumer GPU, but it's the heaviest option. Only
   worth it if the exam shows the guide + item descriptions aren't enough.

### Later: fully self-running (the author, 2026-11-25)
The end goal: the bot runs completely by itself (launch, menu, play, death or win screen, next run) and see how
long it takes to "complete the game". Pieces still missing: getting past the death and victory screens, auto-restart,
and a total-playtime counter in the run logs (Stage 6). "Complete the game" could mean beating the main endings or
full 100% (Dead God). That's a huge goal, so scope it once the bot can beat Mom.

### Done since the first upload (bot 1.2.x, 2026-11-25)
- **Enemy playbook** (`knowledge/enemy_playbook.json`, 238 enemies): tags, danger 1–5 and kill priority, sent to the
  mod at start. Chargers get danger lines, spawners are killed first, unkillable shooters switch to dodge-only.
- **Movement core v2** (`mover.lua`): learned enemy reach and shots, Isaac's own learned top speed and acceleration,
  a 3-move beam search, graded danger circles (so flies don't push it into corners), crowd and sandwich pressure,
  aimed-shot lines from learned animation tells (Dingle's spit).
- **Real-room bench** (`tools/rooms.py`): replay real rooms item-free with the console `goto` command.
- **Overnight batch** (`tools/overnight.py`): bench repeats + real play with a watchdog and a morning report.
- **Offline tests** (`test/`): 37 scenario tests run in the game's own Lua DLL; `tools/reload.ps1` checks before reloading.
- **Privacy guard** (`tools/privacy_check.py`, hook via `tools/install_hooks.py`).

Still open: walls counted as a sandwich side (test K3), Sloth item-free, devil/angel deals, two-input active items.

### Risk layer (bot 1.2.6, 2026-11-25): play risky when it's safe to
The author: "it is taking such a safe route that it's unbearable to watch... Is it worth playing risky? Do I have soul
hearts so I don't lose my devil deal chance? Will playing risky kill me? Risky does not mean reckless."
- **Level 1** (`risk.lua`): one number, 0 careful .. 1 bold, worked out twice a second from the whole run: a hit that
  would kill or leave one hit -> careful; the deal at stake (deal floor 2-8, red hearts next, no red damage yet this
  floor) -> the old careful play (0.25); otherwise bolder with every hit of buffer (soul/black/bone hearts go first,
  Holy Mantle blocks one). It scales 16 safety settings (hit cost, gaps, corner and crowd costs, relax time, fighting
  distance, aim reward). 0.25 = exactly the old settings. Logged as `risk` lines; hits log the level.
- **Level 2:** pace (a room taking much longer than our damage says -> push harder, inside the caps) and "worth a hit"
  (`Danger.cost`: a hit with soul hearts in front, or no deal to lose, is cheap for good loot).
- Tests: 9 offline risk checks. `risk|0.25` pins it (A/B), `risk|auto` lets it think.

### Next behaviour change: "future space" (the author, 2026-11-26)
The author's way of seeing a fight: judge a spot by the space you'll have AFTER the next attack, not the space you
have now. "When you aggro those gurglings, they will chase after you in a straight or sideways line... the creep
effectively cuts you off. If you're in a bad position when the gurgling goes off, it's inevitable you will take damage."
- **Predicted creep:** enemies tagged charges_on_line/dashes + leaves_creep (Gurglings first) project creep along the
  row/column they'll charge down; that strip counts as soon-to-be floor danger, and `waysOut` counts it too, so a spot
  that will be boxed in scores like a corner.
- **Aggro on our terms:** only line up with a Gurgling when the sidestep after its charge still leaves open floor.
- **Knockback (the author: "you can also affect the gurglings' sideways and straight lines... by shooting it because
  of the knockback"):** never lock a predicted line in; re-predict from its real position and speed every update.
  And use it: shooting a charge head-on slows it, from the side bends it, so aim so the creep lands away from the
  open side of the room and our escape route.
- **Dead-end pockets** (the author, 2026-11-26: "stuck in the pot... going right into the bottom pot in this gurgling
  fight"): it hugged the bottom wall, sliding right while shooting left, with the Gurglings chasing along the wall,
  into the pocket between the bottom-right pot and the corner, and was hit there. The 1.2 s look-ahead can't see that
  a wall run ends in a pocket; count a pocket (wall + obstacle + corner) ahead on the current run as a closed way.
- Same principle covers Gemini (where you'll be when he wakes), Gluttony's laser and Dingle's dash. Measured with
  the benchmark like everything else.

### To do later (not core)
The author, 2026-11-25: "some of them are not priority and can be added at a later date to not mess with the true
priority of the core fundamentals." Core = no damage on floors 1-2, natural movement, no loops. These wait:
- **Purple fires:** they shoot homing tears and tears don't put them out (a bomb does, the author thinks). Bomb one
  when it's a threat and the bomb budget allows (a new `R.bombs.fire_purple`).
- **Blue fires:** a small chance of soul hearts when put out (bomb only). "Always worth bombing if you have enough
  bombs": a cleared-room goal with its own bomb minimum (`R.bombs.fire_blue`, about 3).
- **Burrowers:** plan the firing spot on the hole where a burrowed enemy last surfaced (Round Worms; mirror chat).
- **Play style per item:** like the invincible window, e.g. homing tears = spray freely, flight = ignore pits.
- **Two-input active items** (Bob's Rotten Head and similar).
- **Pre-seed tells from the game's animation events** (bestiary: e.g. Dingle Spit Shoot@3, Haunt LaserNoSkin
  Shoot@17) so the bot knows when each attack fires before it ever gets hit; kept in a gitignored file.
- **Check the 201 draft playbook entries** (local AI from wiki text) before the helper sends them.
- **Leading shots on the Haunt:** still not strong (the author, 2026-11-25: "doesn't have to change immediately").
  It slides and turns at the walls; the lead uses a settled average velocity clamped to the room.
- **Laptop as a second test machine** (parked: usage cost).
- **Flying items: rocks and pits are open terrain** (the author, 2026-11-26: "when he gets flying items, he can walk
  over the terrain, just not fire"). Today `blocked()` only lets a flier over pits; with flight, rocks (and spikes)
  are passable too, but lit fires still burn. Part of "play style per item".
- **Shoot chargers from just outside their trigger range** (watcher, 2026-11-26: a minute with no damage dealt vs
  Chargers at one heart). They only charge within 200 px of their row/column (R.charge_reach), so a firing spot in
  their line at 210-250 px is safe; the planner skips moving dashers, so it never plans one.
- **Curse rooms: open the red chest** (the author, 2026-11-26: "skipped the red chest, which is typically a reason
  why you go into the curse room to begin with"). The entry/exit spike hit is the price; the chest is the reward, so
  once inside, opening it is part of the deal (Risk.allows already decides whether to go in at all).
- **Delirium as a reflex stress test** (the author, 2026-11-25: the hardest boss, "the unfair": it shifts into almost
  every boss, not quite as the real ones, with projectiles everywhere). Not a cheat sheet for single bosses and not
  core (floor 11+), but a good later benchmark drill for pure dodging: a `bench_suite_delirium` once floors 1-2 pass
  the gate, scored on hits per minute survived.
- **From outside sources, once the recorder has profiles** (2026-11-26, Gemini handoffs checked in
  `docs/research/OUTSIDE_SOURCES.md`): dash lines from `V1`/`TargetPosition` during wind-ups, only where a profile
  shows they predict the dash; tells on `NpcState` changes; the exact fall of lobbed shots (decompiled rule, checked
  against `recshot` lines first); chasers blocked by rocks (`Room:CheckLine`), measured before changing anything.
Done from this list: red fires are shot out like enemies (1.2.17).

### Situations to watch: surprise bombs (noted 2026-11-25)
The author: "In that TNT room... I don't know what spawns the random troll bomb and how often, if it's RNG or a
scripted room in a seed. But it's something to make note of. Things like that can happen."
- **What happened:** 2026-11-25, floor 1, a trap room (layout 765, "trap room (copy)"): 3 s after walking in, a hit
  for a full heart with no enemy as the source (`hit 0.0|2`), i.e. an explosion. Most likely a troll bomb.
- **What we know about where they come from:** the game's room files list each layout's spawns (some entries have
  weighted random alternatives, so a layout can have a bomb only sometimes). Troll bombs also drop from chests,
  beggars and some pickups, and certain enemies and plates can spawn them. So it can be either.
- **Collecting the answer:** from 1.2.8 every bomb the player didn't drop is logged as a `bomb` line (variant, what
  spawned it, how many updates after entering the room, the room layout). After a few runs that shows which layouts
  spawn them, how soon, and whether it repeats.
- **To check in the bot:** troll bombs are live bombs, so the movement core already avoids their blast. But one that
  appears the moment Isaac walks in (or under him) gives about 1.5 s to react; the first update after entering a room
  must already count it. If a layout spawns them reliably, add it to the knowledge so the bot steps away on entry.

### Level 3: whole-run strategy (next, in this order)
1. **Run profile** each floor: stats, items (rating, carry and tags from `item_ratings.json`), hearts, consumables,
   curses, floor. Works out the build's weaknesses (low damage, slow tears, short range, no flight, no defence) and
   strength. Logged as a `run` line; a strong build lets the risk layer play bolder, a weak one more careful.
2. **Run-aware item value:** an item's worth = its rating for this bot, plus how well it fixes this run's weaknesses,
   plus synergy tags. Used for choice pedestals (taking one removes the others), whether to pick up items with
   downsides, and swapping actives.
3. **Devil and angel deals:** visit the rooms; angel items are free; a devil item's heart price is paid only if its
   run value is high and 2+ full hearts stay after paying. Deal chance itself is managed by the risk layer.
4. **Shop:** spend coins by need (keys for locked rooms and chests seen, bombs for likely secret rooms, hearts when
   low, items by run value), keeping a small reserve.
5. **Optional rooms by risk and strength:** challenge rooms (strong, healthy, deal not at stake), curse rooms (soul
   hearts in front or nothing at stake), sacrifice rooms (only when no deal is at stake and health is high), arcades
   and beggars with spare coins.
6. **Consumables:** cards and pills by known effects; unknown pills only when healthy and nothing is at stake.
7. **Measure:** run logs record floor reached, time per floor, hits, red hits per floor, items (with carry) and deals.

## Open decisions
| When | Decision |
|---|---|
| Stage 0 | ✅ Decided 2026-11-25: bot uses **save slot 2** (empty); Steam achievements are fine |
| Stage 2 | Check-in: fun to watch? Keep going? |
| Stage 7 | OK each overnight session |

## Risks and honest limits
- **Dodging is the hard part.** Bullet-hell bosses (Delirium, Hush, Mega Satan) may stay out of reach for a rule-based
  dodger, even with learning.
- **The game runs in real time.** Learning is slow: roughly as many runs per night as the bot survives short runs.
- **Weird items** (Brimstone, Mom's Knife, Tech, homing, flight, Soy Milk) change how it has to aim. Each one is extra
  work, so we add them as they show up.
- **Characters:** start with plain Isaac. Others later (avoid The Lost and tainted characters early on).
- **The PC:** Ollama on a GPU plus the game is light, but long overnight runs need a stable machine.

## Working rules
- Build in stage order; fighting well comes before everything else.
- Never change the player's own save slot or normal mod setup without asking. Anything switched off for bot runs gets
  switched back.

