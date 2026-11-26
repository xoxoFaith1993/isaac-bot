# Decompiled core rules: enemy building blocks and Isaac's own rules (2026-11-26)

**Check labels:** every fact in this file is `2 readers` unless the label table at the top of `RE_ENEMIES.md` says
`recording` or `contradicted` (shots ×1.2/0.4, hazards, physics, Isaac's top speed).

Same build and pipeline as `RE_PILOT.md`; per-enemy tables are in `RE_ENEMIES.md`. Approved by the author
2026-11-26 ("start with 1 and 2").

**How this was checked: built-in blind review.**
- **Two blind readers per function bundle**, each given only the decompiled `.c` files, `OFFSETS.md` (REPENTOGON's
  field table) and `READING_RULES.md` (y down, angles, hex to decimal, cite lines, mark slips).
  - One reader ran on Sonnet, so the two readers' errors are less correlated.
  - They never saw my notes or any `RE_*.md`.
- **The bundles and their files** are kept in `runs/research/re/core/B1..B8` (gitignored) for outside spot checks.
- **Review column:**
  - **all agree**: me and both readers;
  - **settled by C**: a disagreement or gap I settled by reading the C or the disassembly myself; how is noted;
  - **unresolved**: still open, and on the recording checklist.
- Every claim is still a hypothesis until a recording confirms it.

**Conventions:** 30 updates per second; y grows downward; angles 0° = right, 90° = down. Addresses are for the
2026-11-26 build (SHA-256 in `RE_PILOT.md`).

**A decompiler trap (found 2026-11-26 from a recording contradiction):** `0x439c90` is `sqrt`.
- It takes and returns its value in a register, so Ghidra shows the variable **unchanged** after the call.
- So **any value computed right before a `FUN_00439c90()` call has really been square-rooted.** Usually that's a
  squared distance (fine), but Isaac's friction factors were square-rooted too.
- Before trusting a constant, check the disassembly at such calls.

**Two warnings about REPENTOGON's tables in this build** (both settled by C):
- **Some function signatures now match a different function.** `Entity_NPC::CalcTargetPosition`'s signature lands
  on `0x7817c0`, which reads the controller's movement input. Treat any zhl name as a hint until the body agrees.
- **`Entity_Player` field offsets above about 0x1000 are shifted.**
  - `_damageCooldown` is really at **`0x13c0`** (the table says 0x13b8).
  - The player type is at 0x13c4 (the table says 0x13bc).
  - TemporaryEffects are at 0x1508 (the table says 0x1500).
  - The cache flags are at 0x1574.
  - Fields below 0x400 (the shared Entity fields) are correct.

---

## Level 1: the building blocks

### FireProjectiles, `0x6d2bb0`: `(position, velocity, mode, params)`

Each shot spawns as type 9 (projectile) with `params.Variant`, at position + `params.PositionOffset`. `Spread`
widens or narrows the side angles of modes 1-5.

| Mode | Shots | Directions (relative to the given velocity v) | Speed | Lines |
|---|---|---|---|---|
| 0 | 1 | v | 1.0 | 74-88 |
| 1 | 2 | ±16° | 1.0 | 89-114 |
| 2 | 3 | 0°, ±16° | 1.0 centre, **0.9 sides** | 115-143 |
| 3 | 3 | 0°, ±24° | 1.0 | 144-172 |
| 4 | 4 | ±8° (1.0), ±24° (0.9); no centre shot | as listed | 173-223 |
| 5 | 5 | 0°, ±12°, ±24° | 1.0 | 224-284 |
| 6 | 4 | **fixed** 0°, 90°, 180°, 270° | speed = v.x | 285-338 |
| 7 | 4 | **fixed** 45°, 135°, 225°, 315° | speed = v.x | 339-383 |
| 8 | 8 | modes 6 + 7 together (a fixed 8-way ring) | speed = v.x | 384-486 |
| 9 | N | ring of **N = round(v.y)** shots, speed v.x, starting at `params.CircleAngle` (random 0..π by default) | v.x | 487-547 |

**The shared tail** (lines 556-656). This is where **the hidden ×1.2 comes from**:
- **Modes 0-5**, unless the params byte at +0x98 is set: each shot's falling speed is set to **−3** and its falling
  acceleration to **0.1** (lines 569-580).
- **Modes 2, 4 and 5 only**, under the same condition: **velocity = 1.2 × shot velocity + 0.4 × the shooter's
  velocity**, and falling speed −1 more (lines 581-592).
  - So multi-shot spreads fly 20% faster than the code's base number and **inherit 40% of the enemy's own
    movement**.
  - Modes 0, 1, 3, 6-9 don't.
  - This matches the recordings: Dingle's mode 2 is 12.0 centre and 10.8 sides, the Haunt's mode-5 spit about 12,
    and the Lil' Haunt's mode 0 shot 10.
- Then, for every mode:
  - height, falling speed and acceleration += the params modifiers;
  - `Scale` = `params.Scale`;
  - **damage** = `params.Damage`, or 1 (2 if Scale > 1.15) when that is negative (the default);
  - velocity × `VelocityMulti`;
  - bullet flags OR'd in;
  - homing, curving, acceleration and change-flags copied.
- **The spawn-height rule** (lines 642-646): a shot whose height is **above 50** (height < −50) gets **collision
  class 0**, so it can't hit anything, unless bullet flag `0x20000` is set.

**Review: all agree** (both readers, every row and the tail). Recordings already match the ×1.2 and the mode-0 speed.

### FireBossProjectiles, `0x6d46a0`: `(count, targetPos, trajectory, params)`

For each of `count` shots (lines 44-166):
- **Aim:**
  - **target ≠ (0,0):** velocity = 7 × (direction to the target) + a random vector of length 0-3.5 in a random
    direction. So each shot is **within ±30° of the target line**, at speed **3.5-10.5**, bunched toward the line.
  - **target = (0,0):** a random direction at speed exactly 7 (an all-round burst).
- **Arc:** falling acceleration = 0.1 × trajectory + 0.32; falling speed = 5 − random(0..24) − trajectory. A bigger
  trajectory value gives a higher, faster-falling lob.
- **Scale:** random 0.90-0.95 or 1.30-1.35 (50/50), × `params.Scale` (× 0.8 if the shooter has entity flag bit 54).
- **None of FireProjectiles' tail:** no ×1.2, no −3/0.1 defaults, no −50 height rule.

**Review:**
- **The mechanics: all agree.**
- **The Sloth lob not being aimed (recording: 3-177° off in 20 shots): unresolved, but explained.**
  - The code can't scatter a FireBossProjectiles shot by more than 30°.
  - But Sloth (and Pin's Attack1) set bullet flag bit 2 on the lob. In the ProjectileFlags bit order that bit is
    **EXPLODE**: the lob bursts on landing.
  - So the recorded off-aim shots are probably the burst, not the lob. Record the lob's own first-update velocity to
    tell them apart.

### The "can I shoot?" check, `0x6d2730`: `(lead, everyN; range in a register)`

It returns false:
- while confused or feared (flags `0x200` / `0x1000a00`);
- unless the target is valid (`0x6df740`: a hostile NPC targets the player, bombs, familiars or friendlies; a
  friendly one targets enemies).

Otherwise (lines 26-48):
- **distance to Isaac < range**: with `lead`, it uses Isaac's position + 5 updates of his velocity, for the range test
  only;
- **and a clear `Room::CheckLine` to Isaac's current position**;
- with `everyN`, only on some updates.

Ranges found so far, read from the instruction before each call:

| Caller | Range | Lead |
|---|---|---|
| Gemini's baby | 300 | off |
| Pooter | 200 | off |
| Haunt, Charger, Hopper | 1000 | (player-controlled branch only) |

**Review: all agree.**

### Target position, `0x6c6390`

- **Normal:** **Isaac's current position, no lead.**
- **Confused:** a random point up to about 240 px away, re-rolled every 15 updates.
- **Feared:** the point the caller's distance directly away from Isaac; if a wall blocks that, a random point within
  100 px. Types 22, 205, and 16 (except variant 2) ignore fear here.

**Review: all agree.**

### Movement helpers (pathfinder, at entity + 0x414)

| Helper | What it does | Review |
|---|---|---|
| `0x7ebb70` PathChase(target, speed, ...) | **straight at the target when it's in clear line within 70 px** (750 px in "long" mode), otherwise grid steps toward cell centres. Accel = min(distance × 0.1, 2) × speed (× 0.7 when the tile ahead is costly), friction × 0.7; brakes inside 1 px | all agree |
| `0x7ed880` RandomAxisWalk(speed, ...) | **random straight runs of 0-11 tiles along an axis**, preferring open side space; while feared 1-4 tiles and never toward Isaac. Pushes toward the run's end at `speed` per update | all agree |
| `0x7ee850` MoveRandomlyBoss | random point about 40 px away, 0.5 per update toward it; confused/feared overrides | all agree |
| `0x7ef620` HasPathToPos | grid path exists? No randomness | all agree |
| `0x685f10` / `0x686010` / `0x43a210` | random unit vector / snap a vector to its nearest axis / clamp a point into the room with a margin | all agree |
| EvadeTarget, MoveRandomly | **not located**: their signatures are stale in this build | unresolved |

Friction-like field 0x36c: every push divides by it, and it gets multiplied down (×0.5-0.95) on the update.

### The charge-on-line trigger (`ai_charger`, `0x534300`; types 23, 55, 237, plus non-charging 21, 31, 243)

- **When it checks:** only 1 update in 4 (`IsFrame(4, index)`, line 992). The reference is the centre of the
  Charger's 40 px grid cell.
- **The aim point:** **Isaac's position + his velocity × random(0..1) × 16** (lines 1007-1014). That's a **real
  lead, up to 16 updates**.
- **The charge starts if** that point is **within 20 px of the cell centre in x or in y** (its tile row or column),
  **under 200 px away** (no cap for type 55 and Carrion), with a **clear line**, and the Charger isn't confused or
  feared (lines 1109-1116).
- **The charge:** along one of the 4 axes (the diagonals for Carrion Princess), adding 1.3 per update (Drowned 1.17,
  Dank 18.2, type 55 1.55), friction × 0.8, held on the tile line.
- **It ends** on a wall or rock hit, being stuck, or confusion/fear, then goes **straight back to State 4 with no
  pause**.

**Review:**
- **All agree:** both readers (one fully blind, on Sonnet), the earlier `RE_ENEMIES.md` reading, and **the recordings**
  (24/24 Charger and 18/18 Gurgling charges; only States 4 and 8 seen).
- **Unresolved:** what type 237's subtype-1 boss version adds.

---

## Level 2: the rules for Isaac

### Invincibility after a hit (`Entity_Player::TakeDamage`, `0x77ad70`)

- **The timer is field `0x13c0`** (not the table's 0x13b8). It **counts down 1 per update** in the player's Update
  (`0x78b2b0` lines 2673-2675), only while alive.
- **A hit is ignored while the timer is above 0**, unless the damage carries high-flag bit 3 (TakeDamage lines
  1194-1202). This check comes before the Lua callback.
- **Length after a normal hit** (lines 4893-4901): `GetDamageCooldown(min(2, damage) × 60)`.
  - `GetDamageCooldown` (`0x7e37f0`) returns its input unchanged in a normal run. When a game-wide value at
    `Game+0x26628` is 2 or more (some multiplayer mode), it divides by 8.
  - The damage term is the hit's rounded damage (lines 1014, 1096).
  - So: **60 updates (2 s) for a half-heart hit, 120 (4 s) for a full heart or more.**
- **What changes it:**
  - **trinket 81** multiplies it by 2 × its multiplier;
  - collectible 677 adds 60 (plus a room pause);
  - **Holy Mantle** (313) absorbing a hit sets 60;
  - a rotten-heart or reflect absorb sets 8;
  - one character special case sets 90.

**Review:**
- **The field, the countdown, the gate and the 60 × min(2, damage) shape: all agree.**
- **That `GetDamageCooldown` is the identity in a normal run: settled by C.** I decompiled it; the readers didn't
  have it.
- **That the multiplier is the rounded damage: settled by C** (the local is set from `damage + 0.5` at lines 1014 and
  1096). It is reused later in the function, so this is a likely reading, not a certain one: record it.

### Knockback

**TakeDamage doesn't change Isaac's velocity**, and neither does the player's collision handler in a normal hit.
Any push comes from elsewhere. **Review: all agree; where it lives is unresolved.**

### When contact counts (collision classes), `Entity::CollidePair`, `0x6b9310`

For each pair, in order:
1. A class 1 or 2 enemy that is charmed or friendly (flags `0x20000100`) is treated as class 4.
2. **Skip if either side is class 0.**
3. **A class-2 entity only collides with player-side things:**
   - the check (`0x6b9290`) runs on the **other** entity: the disassembly moves the partner into ECX before each call;
   - "player-side" means a player, tear, familiar, bomb or knife, a projectile with flag `0x80`, or a charmed or
     friendly entity.
4. **Class 1 only collides with the player**, and **class 3 only with other NPCs**.
5. Skip if either side is dead.
6. Otherwise both collision handlers run.

So:

| Enemy class | Touches Isaac? | Touches his tears? | Touches other enemies? |
|---|---|---|---|
| 0 | no | no | no |
| 1 | **yes** | no | no |
| 2 | **yes** | yes | no |
| 3 | no | no | yes |
| 4 | yes | yes | yes |

**This settles the Sloth/Trite "class 2" question: a class-2 enemy still touches Isaac** (and his tears). It only
stops touching other enemies.

**Review:**
- **The rules: all agree.**
- **Which entity `0x6b9290` tests: settled by C** (disassembly). Both readers flagged it as unclear from the C alone
  and guessed the same.

**Where contact damage is dealt:**
- **The player's own collision handler (`0x796e30`) never damages Isaac.** It only damages the other entity (both
  readers).
- So contact damage to Isaac comes from **the NPC's collision handler (`0x6d4ce0`)**. It reads the enemy's collision
  damage (`+0x388`) and calls the player's TakeDamage slot (`+0x20`) in several branches.
- **That function won't decompile** (a Ghidra error, typed or untyped), so its exact conditions (height, state,
  flags) are **unresolved**. The raw disassembly is saved locally for a later pass.

### Shots hitting Isaac, `Entity_Projectile::HandleCollision`, `0x662200`

A projectile hurts Isaac unless one of these applies (lines 119-176):
- a Lua callback says so;
- it's a friendly or charmed shot (flag bit 31 paths);
- **it's too high:** **`PositionOffset.Y < −50 × s`**, where s is Isaac's sprite scale clamped to 0.5-1.0. A
  full-size Isaac is hit only by shots at height ≥ −50. Exactly −50 still hits.

Then:
- **The shot always dies on contact**, even when the damage is then blocked:
  - flag bit 1 (EXPLODE-type) deals no damage;
  - collectibles 91 and 375 block high or falling shots;
  - collectible 242 blocks with a random chance.
- **Damage = the shot's `collisionDamage`** (default 1.0) through TakeDamage, with countdown 30 (line 231).

**Flight** (`Update`, `0x659bb0`, lines 2412-2419, 2634-2637; `Init`, `0x659530`):
- **At spawn:** height starts at −23, falling speed is random ±0.1, scale 1.0, collision damage 1.0.
- **Each update:** falling speed = 0.9 × falling speed + 0.1 + falling acceleration (built-in gravity 0.1, ×0.9
  damping); then height += falling speed.
- **It dies** when height goes above −5 (it hits the floor), or when it hits a rock while lower than 50 px.

**Review:**
- **All agree** (both readers).
- **Unresolved:** whether `PositionOffset.Y` is kept equal to the height field (+0x410) every update. Both readers
  saw that the hit test reads `PositionOffset.Y`, not +0x410. Record both.

### Isaac's movement, `0x781fc0` (called from the player's Update, `0x78b2b0` line 1558; input from `0x7817c0`)

Each call, on a normal floor (field 0x1660 = 0, no special effect), with input direction u (|u| ≤ 1, analog):
1. **Scale:** k = **0.75 + 0.25 × MoveSpeed** (speed stat 1.0 gives k = 1). The input is u × k (lines 165-167).
2. **Sideways damping:** the part of velocity across the input direction × **√0.8 ≈ 0.894**; the part along it is
   kept (lines 235-245; the square root is the same lost call as in step 4, see line 243).
3. **Accel:** velocity += u × k × 0.5 × a, with a = 1.2 (slightly more when reversing), so **+0.6 × k per call**
   (lines 252-277).
4. **Friction: velocity × √0.775 ≈ 0.880 per call**, with or without input (lines 297-300).
   - The C shows 0.775, but the machine code **takes its square root** first: at `0x782711` the friction value goes
     into `sqrt` (`0x439c90`), the result is stored at `[EBP-0x50]`, and velocity x and y are multiplied by it
     (`0x78282d`, `0x78286b`).
   - Ghidra lost that call's result, and so did the first version of this table and both blind readers.

Results:
- **Top |velocity|** ≈ 0.6 × k × 0.880 / (1 − 0.880) ≈ **4.41 × k**. That is exactly the 4.41 × MoveSpeed cap
  constant in the same function (line 273), so the formula and the designers' number agree.
- **Per game update:** square-rooting the friction only makes sense if the movement step runs **twice per 30-Hz
  update** (0.880² = 0.775). If so, Isaac moves about **8.8 px per update at speed 1.0**, about 11 at speed 2 (k =
  1.25). That "twice" is inferred, not proven from this function.
- **Stopping:** ×0.880 per call (×0.775 per update if twice), half speed in about 5.4 calls.
- **There's no hard speed cap on a normal floor** (the 4.41 cap only applies on slippery floors).

On slippery floors field 0x1660 counts 0..60, as t = 0..1:
- friction becomes √(0.775 + 0.185t);
- sideways damping becomes √(0.8 + 0.2t);
- accel shrinks to a quarter at t = 1;
- a cap of 4.41 × MoveSpeed applies.

Other pushes:
- some items/effects: a pulsed dash (null effect 63), a wall bounce (null effect 50);
- being carried: velocity snaps to the carrier;
- flying vs gravity: velocity.y += 0.225.

**Knockback isn't applied here** (it would decay through the same ×0.880 per call).

**Input** (`0x7817c0`): x = right − left, y = down − up, both analog.
- Both axes are inverted when confused (flag 0x200, in the `Game+0x26628` ≥ 2 mode) or under one room effect.
- Snapped to the 4 axes under another.
- x is mirrored on mirrored floors.

**Review:**
- **The accel, damping and friction numbers: all agree** (both B8 readers).
- **The first top-speed figure (2.07 px/update) was contradicted by the recording and is now corrected: settled by C**
  (disassembly).
  - The recorder's Isaac positions give a median of 6.7, p90 11.0 and p99 11.9 px/update (some runs with speed items).
  - The bot's movement learning measured about 7.7 at a run's start (`mover.lua`, 2026-11-25).
  - Both fit about 8.8 at speed 1.0 and about 11 with speed items.
- **Still unresolved:**
  - the "twice per update" step;
  - speed stats other than 1.0: both readers flagged that the sideways projection uses the scaled input.
  - Record Isaac's `Velocity` magnitude (expect about 4.4 at speed 1.0 under steady input) next to his position
    change per update.

---

## The Haunt's damage immunity (settles the open question from `RE_PILOT.md`)

**It lives in `ai_haunt` itself (`0x4855e0`, lines 394-413).**
- **The Haunt (variant 0):** whenever its **State is 4 or 16** and it has pending damage (field 0x14 > 0), it
  **empties the pending-damage list** (`+0xc = +0x8`) and **sets the pending amount and flags to 0** (+0x14, +0x18,
  +0x1c), with a white flash while Lil' Haunts are alive.
- **The orbiting Lil' Haunts** (State 3, lines 261-277): the same wipe. They are also class 1, so tears can't even
  touch them.

**Why the damage can be thrown away:** `Entity::TakeDamage` (`0x6b3e10`, lines 107-118) doesn't reduce HP. It
**queues** the damage (+0x14 += amount, flags OR'd, a record appended), and HP drops later. An AI that clears the queue
first makes its enemy immune.

This also decodes Dingle's and Gemini's "unknown field 0x14 > 0" check: it means **"was hit since the last update"**.

**Review:**
- **The wipe: all agree** (both B4 readers found it independently).
- **The recording backs it:** no HP loss in State 4 across 1,124 samples.
- `RE_PILOT.md`'s earlier "not in `ai_haunt`" was wrong; corrected there.

---

## The enemy grammar: 16 building blocks

| # | Block | Parameters | Bot meaning |
|---|---|---|---|
| 1 | **Aimed shot** (FireProjectiles mode 0) | speed | flies at the stated speed straight at **Isaac's position at fire time**: sidestep |
| 2 | **Spread** (modes 1-5) | count 2-5, angles 8-24°, speed | **flies at 1.2× speed and carries 0.4× the shooter's motion** (modes 2, 4, 5): add the enemy's velocity when predicting |
| 3 | **Fixed ring** (modes 6/7/8) | + / X / both, speed | not aimed: stand off its 4 or 8 lines |
| 4 | **N-ring** (mode 9) | count, speed, start angle | not aimed; gaps of 360°/N |
| 5 | **Boss burst** (FireBossProjectiles) | count, target, arc | loose cone ±30° around the target line (or all round), speeds 3.5-10.5, lobbed |
| 6 | **Height rule** | shot height | shots higher than 50 px pass over Isaac; spawned that high they can't hit anything |
| 7 | **Can-shoot gate** (`0x6d2730`) | range, lead, every N | no shot unless Isaac is in range **and in clear line**: a rock between you stops it |
| 8 | **Target position** (`0x6c6390`) | flee distance | Isaac's current position (no lead); flees when feared, wanders when confused |
| 9 | **Path chase** (`0x7ebb70`) | speed | straight at Isaac within 70 px with clear line, otherwise grid steps; accel ≤ 2 × speed |
| 10 | **Random axis walk** (`0x7ed880`) | speed | straight 0-11 tile runs along an axis, not toward Isaac |
| 11 | **Charge on line** (ai_charger) | band 20 px, range 200, lead 0-16 updates | never be in its tile row/column within 200 px, including where you'll be in 16 updates |
| 12 | **Hop to cell** (Monstro, Trite, Pin) | landing cell in `TargetPosition` | leave the cell before the landing frame |
| 13 | **Laser with warning** (`0x611e90` before a laser) | warning time | move off the line during the warning |
| 14 | **Damage wipe** (AI clears +0x14) | states | immune in those states: don't waste shots |
| 15 | **Collision class** | 0-4 | 0 harmless; 1 touches only Isaac; 2 touches Isaac and tears, not other enemies; 3 only other enemies; 4 everything |
| 16 | **Isaac's i-frames** | 60 × min(2, damage) | after a hit, 2-4 s with no further damage |

### Floor 1-2 enemies → AI function → building blocks called

From `tools/re/floor_map.py`:
- **Rows:** every NPC type in the chapter-1 room files (Basement, Cellar, Burning Basement, Downpour, Dross) from
  `bestiary_game.json`, with the number of rooms it appears in.
- **Case:** its byte in the dispatcher table at `0x6cbe5c`.
- **Building blocks:** the helpers that function calls directly.

**Limits:**
- "Calls a block" means the function contains the call; it doesn't mean every variant uses it.
- Some functions run many types.
- Blocks that are inline code rather than helper calls (Charge on line, Hop to cell, Damage wipe) are not detected by
  this scan.

**Coverage:** 7,620 enemy room appearances in chapter 1, run by 72 distinct AI functions. **The 12 most common
functions cover about 65%.** By share of appearances:

| Share | Function | Runs |
|---|---|---|
| 16% | `0x50f730` | Gaper, Fatty, Cyclopia, Stoney, Wraith, Conjoined Fatty |
| 9% | `0x50d3c0` | Fly, Pooter, Attack Fly, Moter, Level 2 Fly, Full Fly, Sucker family |
| 6% | `0x530540` | Spiders |
| 5% | `0x6d9000` | fireplaces |
| 5% | `0x53b0c0` | Dips |
| 4% | `0x513b70` | Clotty family |
| 4% | `0x52cd30` | Hopper, Trite, Flaming Hopper, Ministro, Ragling |
| 4% | `0x544cd0` | Round Worm, Ulcer, Roundy, Night Crawler |
| 3% | `0x519880` | Horf, Psychic Horf |
| 3% | `0x511780` | Gusher, Pacer, Blubber, Black Globin's body |

**Next to decode for the most coverage:** `0x50f730` (Gaper family), `0x530540` (Spiders), `0x544cd0` (worms),
`0x519880` (Horf).

<details><summary>Full table (104 types)</summary>

| Type | Enemies (chapter 1 room count) | Case | AI function(s) | Building blocks called |
|---|---|---|---|---|
| 10 | Frowning Gaper 10.0 (323), Gaper 10.1 (302), Flaming Gaper 10.2 (37) | 0x0 | 0x50f730 | Effect, FireProjectiles, GetPlayerTarget, PathChase, TargetPos |
| 11 | Gusher 11.0 (124), Pacer 11.1 (100) | 0x1 | 0x511780 | CanShoot, Effect, FireBossProjectiles, FireProjectiles, GetPlayerTarget, ThrowSpider, WanderBoss |
| 12 | Horf 12.0 (246) | 0x2 | 0x519880 | CanShoot, FireProjectiles, GetPlayerTarget |
| 13 | Fly 13.0 (89) | 0x3 | 0x50d3c0 | CanShoot, FireBossProjectiles, FireProjectiles, GetPlayerTarget, RandomDir, TargetPos |
| 14 | Pooter 14.0 (177), Super Pooter 14.1 (15) | 0x3 | 0x50d3c0 | CanShoot, FireBossProjectiles, FireProjectiles, GetPlayerTarget, RandomDir, TargetPos |
| 15 | Clotty 15.0 (132), Clot 15.1 (27), Grilled Clotty 15.3 (19), I.Blob 15.2 (14) | 0x4 | 0x513b70 | CanShoot, Effect, FireProjectiles, GetPlayerTarget, WanderBoss |
| 16 | Mulligan 16.0 (74), Mulliboom 16.2 (58), Mulligoon 16.1 (34) | 0x5 | 0x5123d0 | FireProjectiles, GetPlayerTarget, PathChase, TargetPos, WanderBoss |
| 17 | Shopkeeper 17.0 (25), Secret Room Keeper 17.1 (9), Special Shopkeeper 17.3 (3) | 0x6 | 0x6c99d0 | ThrowSpider |
| 18 | Attack Fly 18.0 (215) | 0x3 | 0x50d3c0 | CanShoot, FireBossProjectiles, FireProjectiles, GetPlayerTarget, RandomDir, TargetPos |
| 19 | Larry Jr. 19.0 (1) | 0x7 | 0x46e060 | AxisSnap, CanShoot, FireProjectiles, GetPlayerTarget, RandomAxisWalk, RandomDir |
| 20 | Monstro 20.0 (1) | 0x8 | 0x470020 | FireBossProjectiles, FireProjectiles, GetPlayerTarget, LaserWarning, TargetPos |
| 22 | Hive 22.0 (2) | 0xa | 0x512b60 | Effect, GetPlayerTarget, TargetPos, WanderBoss |
| 25 | Boom Fly 25.0 (66) | 0xc | 0x515a80 | CanShoot, FireProjectiles, GetPlayerTarget, WanderBoss |
| 29 | Hopper 29.0 (122), Trite 29.1 (95) | 0x10 | 0x52cd30 | CanShoot, Effect, FireBossProjectiles, FireProjectiles, GetPlayerTarget, PathChase, RandomDir, TargetPos |
| 30 | Sack 30.2 (68) | 0x11 | 0x51da10 | CanShoot, FireBossProjectiles, GetPlayerTarget |
| 33 | Blue Fire Place 33.2 (199), Fire Place 33.0 (153), White Fire Place 33.4 (38), Purple Fire Place 33.3 (7) | 0x13 | 0x6d9000 | - |
| 44 | Slide 44.1 (1) | 0x1b | 0x528380 | AxisSnap, GetPlayerTarget, RandomAxisWalk |
| 54 | Flaming Hopper 54.0 (16) | 0x10 | 0x52cd30 | CanShoot, Effect, FireBossProjectiles, FireProjectiles, GetPlayerTarget, PathChase, RandomDir, TargetPos |
| 61 | Bulb 61.5 (48), Sucker 61.0 (22), Spit 61.1 (13) | 0x3 | 0x50d3c0 | CanShoot, FireBossProjectiles, FireProjectiles, GetPlayerTarget, RandomDir, TargetPos |
| 62 | Pin 62.0 (1) | 0x29 | 0x47ac40 | FireBossProjectiles, FireProjectiles, GetPlayerTarget, LaserWarning, TargetPos |
| 67 | The Duke of Flies 67.0 (2) | 0x2e | 0x472210 | FireBossProjectiles, FireProjectiles, GetPlayerTarget, ThrowSpider, WanderBoss |
| 76 | Blastocyst Small 76.0 (3) | 0x32 | 0x476b30 | Effect, TargetPos, WanderBoss |
| 77 | Embryo 77.0 (44) | 0x33 | 0x510ea0 | GetPlayerTarget, WanderBoss |
| 79 | Gemini 79.0 (1), The Blighted Ovum 79.2 (1) | 0x35 | 0x4431a0, 0x96c4c0, 0x943210 | AxisSnap, CanShoot, Effect, FireProjectiles, GetPlayerTarget, LaserWarning, PathChase, TargetPos |
| 80 | Moter 80.0 (44) | 0x3 | 0x50d3c0 | CanShoot, FireBossProjectiles, FireProjectiles, GetPlayerTarget, RandomDir, TargetPos |
| 85 | Spider 85.0 (238) | 0x39 | 0x530540 | GetPlayerTarget, PathChase, RandomDir, TargetPos |
| 88 | Walking Sack 88.2 (17) | 0x3b | 0x521e30 | CanShoot, FireBossProjectiles, GetPlayerTarget, WanderBoss |
| 94 | Big Spider 94.0 (58) | 0x39 | 0x530540 | GetPlayerTarget, PathChase, RandomDir, TargetPos |
| 100 | Widow 100.0 (1) | 0x44 | 0x473b20 | FireProjectiles, GetPlayerTarget, TargetPos, ThrowSpider |
| 205 | Nest 205.0 (40) | 0xa | 0x512b60 | Effect, GetPlayerTarget, TargetPos, WanderBoss |
| 206 | Baby Long Legs 206.0 (33), Small Baby Long Legs 206.1 (19) | 0x4a | 0x538310 | CanShoot, FireProjectiles, GetPlayerTarget, PathChase, RandomDir, WanderBoss |
| 207 | Crazy Long Legs 207.0 (30), Small Crazy Long Legs 207.1 (27) | 0x4a | 0x538310 | CanShoot, FireProjectiles, GetPlayerTarget, PathChase, RandomDir, WanderBoss |
| 208 | Fatty 208.0 (207), Flaming Fatty 208.2 (30), Pale Fatty 208.1 (3) | 0x0 | 0x50f730 | Effect, FireProjectiles, GetPlayerTarget, PathChase, TargetPos |
| 210 | Blubber 210.0 (3) | 0x1 | 0x511780 | CanShoot, Effect, FireBossProjectiles, FireProjectiles, GetPlayerTarget, ThrowSpider, WanderBoss |
| 214 | Level 2 Fly 214.0 (55) | 0x3 | 0x50d3c0 | CanShoot, FireBossProjectiles, FireProjectiles, GetPlayerTarget, RandomDir, TargetPos |
| 215 | Level 2 Spider 215.0 (60) | 0x39 | 0x530540 | GetPlayerTarget, PathChase, RandomDir, TargetPos |
| 217 | Dip 217.0 (193), Big Corn 217.3 (55), Brownie Corn 217.2 (6) | 0x4f | 0x53b0c0 | FireProjectiles, GetPlayerTarget, RandomDir |
| 218 | Wall Hugger 218.0 (58) | 0x18 | 0x51bbb0 | AxisSnap, CanShoot, FireProjectiles, GetPlayerTarget |
| 220 | Squirt 220.0 (67) | 0x51 | 0x53bae0 | GetPlayerTarget, RandomDir, TargetPos |
| 222 | Ring Fly 222.0 (93) | 0x53 | 0x542340 | TargetPos |
| 226 | Crispy 226.2 (79), Skinny 226.0 (72) | 0x56 | 0x53f3d0 | CanShoot, FireProjectiles, GetPlayerTarget, PathChase, RandomAxisWalk, RandomDir, TargetPos |
| 231 | Nerve Ending 231.0 (2) | 0x58 | 0x53e680 | GetPlayerTarget |
| 237 | Gurgling (boss) 237.1 (1), Turdling 237.2 (1) | 0x9 | 0x534300 | AxisSnap, CanShoot, FireBossProjectiles, FireProjectiles, GetPlayerTarget, PathChase, RandomAxisWalk, TargetPos |
| 240 | Wall Creep 240.0 (35) | 0x5a | 0x542930 | CanShoot, FireProjectiles, GetPlayerTarget, LaserWarning, TargetPos |
| 242 | Blind Creep 242.0 (3) | 0x5a | 0x542930 | CanShoot, FireProjectiles, GetPlayerTarget, LaserWarning, TargetPos |
| 244 | Round Worm 244.0 (165), Tube Worm 244.1 (22) | 0x5b | 0x544cd0 | CanShoot, Effect, FireBossProjectiles, FireProjectiles, GetPlayerTarget, PathChase, RandomDir |
| 245 | Poop 245.0 (1) | 0x5c | 0x577b30 | RandomDir |
| 246 | Rag Man's Ragling 246.1 (2), Ragling 246.0 (2) | 0x10 | 0x52cd30 | CanShoot, Effect, FireBossProjectiles, FireProjectiles, GetPlayerTarget, PathChase, RandomDir, TargetPos |
| 248 | Psychic Horf 248.0 (10) | 0x2 | 0x519880 | CanShoot, FireProjectiles, GetPlayerTarget |
| 249 | Full Fly 249.0 (36) | 0x3 | 0x50d3c0 | CanShoot, FireBossProjectiles, FireProjectiles, GetPlayerTarget, RandomDir, TargetPos |
| 250 | Ticking Spider 250.0 (51) | 0x39 | 0x530540 | GetPlayerTarget, PathChase, RandomDir, TargetPos |
| 255 | Night Crawler 255.0 (3) | 0x5b | 0x544cd0 | CanShoot, Effect, FireBossProjectiles, FireProjectiles, GetPlayerTarget, PathChase, RandomDir |
| 256 | Dart Fly 256.0 (87) | 0x5d | 0x5468e0 | GetPlayerTarget, TargetPos |
| 257 | Conjoined Fatty 257.0 (8) | 0x0 | 0x50f730 | Effect, FireProjectiles, GetPlayerTarget, PathChase, TargetPos |
| 260 | Haunt 260.0 (2) | 0x5f | 0x4855e0 | CanShoot, Effect, FireProjectiles, GetPlayerTarget, LaserWarning, RandomDir, TargetPos, ThrowSpider |
| 261 | Dingle 261.0 (2), Dangle 261.1 (1) | 0x60 | 0x4898c0 | AxisSnap, FireProjectiles, GetPlayerTarget, RandomDir, TargetPos |
| 276 | Roundy 276.0 (44) | 0x5b | 0x544cd0 | CanShoot, Effect, FireBossProjectiles, FireProjectiles, GetPlayerTarget, PathChase, RandomDir |
| 279 | Black Globin's Head 279.0 (1) | 0x12 | 0x518910 | AxisSnap, GetPlayerTarget, PathChase, RandomAxisWalk, TargetPos |
| 280 | Black Globin's Body 280.0 (1) | 0x1 | 0x511780 | CanShoot, Effect, FireBossProjectiles, FireProjectiles, GetPlayerTarget, ThrowSpider, WanderBoss |
| 281 | Swarm 281.0 (83) | 0x6d | 0x547600 | TargetPos |
| 282 | Mega Clotty 282.0 (1) | 0x4 | 0x513b70 | CanShoot, Effect, FireProjectiles, GetPlayerTarget, WanderBoss |
| 284 | Cyclopia 284.0 (100) | 0x0 | 0x50f730 | Effect, FireProjectiles, GetPlayerTarget, PathChase, TargetPos |
| 288 | Dukie 288.0 (3) | 0x6e | 0x548010 | CanShoot, RandomDir, WanderBoss |
| 289 | Ulcer 289.0 (66) | 0x5b | 0x544cd0 | CanShoot, Effect, FireBossProjectiles, FireProjectiles, GetPlayerTarget, PathChase, RandomDir |
| 291 | Suction Pitfall 291.1 (3) | 0x70 | 0x4968f0 | - |
| 292 | Movable TNT 292.0 (23) | 0x71 | 0x6de080 | - |
| 297 | Blue Gaper 297.0 (3) | 0x76 | 0x4c2cb0 | GetPlayerTarget, PathChase, TargetPos |
| 299 | Greed Gaper 299.0 (3) | 0x78 | 0x5acc70 | GetPlayerTarget, PathChase, TargetPos |
| 302 | Stoney 302.0 (113) | 0x0 | 0x50f730 | Effect, FireProjectiles, GetPlayerTarget, PathChase, TargetPos |
| 305 | Ministro 305.0 (65) | 0x10 | 0x52cd30 | CanShoot, Effect, FireBossProjectiles, FireProjectiles, GetPlayerTarget, PathChase, RandomDir, TargetPos |
| 306 | Portal 306.0 (126) | 0x7b | 0x549f20 | - |
| 404 | Little Horn 404.0 (2) | 0x83 | 0x494a10 | GetPlayerTarget, TargetPos |
| 405 | Rag Man 405.0 (1) | 0x84 | 0x4975a0 | FireBossProjectiles, FireProjectiles, GetPlayerTarget, PathChase, TargetPos, WanderBoss |
| 806 | Bubbles 806.0 (135) | 0x90 | 0x561510 | CanShoot, FireBossProjectiles, GetPlayerTarget, PathChase, RandomDir, TargetPos |
| 807 | Wraith 807.0 (110) | 0x0 | 0x50f730 | Effect, FireProjectiles, GetPlayerTarget, PathChase, TargetPos |
| 808 | Willo 808.0 (53) | 0x91 | 0x55eeb0 | - |
| 810 | Small Leech 810.0 (157) | 0x93 | 0x561f30 | GetPlayerTarget, RandomDir, TargetPos |
| 811 | Deep Gaper 811.0 (156) | 0x94 | 0x566d70 | - |
| 812 | Sub Horf 812.0 (138) | 0x95 | 0x566360 | FireProjectiles, TargetPos |
| 813 | Blurb 813.0 (184) | 0x96 | 0x560810 | FireBossProjectiles, GetPlayerTarget |
| 814 | Strider 814.0 (92) | 0x97 | 0x563000 | GetPlayerTarget, RandomDir |
| 816 | Polty 816.0 (72) | 0x99 | 0x563a30 | CanShoot, GetPlayerTarget, TargetPos |
| 817 | Prey 817.0 (128), Mullighoul 817.1 (27) | 0xa | 0x512b60 | Effect, GetPlayerTarget, TargetPos, WanderBoss |
| 818 | Coal Spider 818.2 (1) | 0x9a | 0x5002f0 | PathChase, TargetPos |
| 837 | Henry 837.0 (1) | 0xab | 0x56c3c0 | - |
| 838 | Level 2 Willo 838.0 (38) | 0xac | 0x55fbb0 | FireProjectiles, GetPlayerTarget, TargetPos |
| 868 | Army Fly 868.0 (84) | 0xbe | 0x551570 | GetPlayerTarget, RandomAxisWalk |
| 869 | Migraine 869.0 (21) | 0x39 | 0x530540 | GetPlayerTarget, PathChase, RandomDir, TargetPos |
| 870 | Drip 870.0 (126) | 0x4f | 0x53b0c0 | FireProjectiles, GetPlayerTarget, RandomDir |
| 871 | Splurt 871.0 (108) | 0x51 | 0x53bae0 | GetPlayerTarget, RandomDir, TargetPos |
| 872 | Cloggy 872.0 (118) | 0x4 | 0x513b70 | CanShoot, Effect, FireProjectiles, GetPlayerTarget, WanderBoss |
| 873 | Fly Trap 873.0 (72) | 0xbf | 0x5674a0 | CanShoot, PathChase, TargetPos |
| 874 | Gas Dwarf 874.0 (68) | 0xc0 | (inline) | - |
| 875 | Poot Mine 875.0 (43) | 0xc1 | 0x568a80 | - |
| 876 | Dump 876.0 (65), Dump Head 876.1 (25) | 0xc2 | 0x5696f0 | - |
| 879 | Bloaty 879.0 (49) | 0xc5 | 0x56a590 | CanShoot, FireBossProjectiles, GetPlayerTarget, PathChase |
| 881 | Needle 881.0 (2) | 0xc7 | 0x555380 | FireProjectiles, RandomDir, TargetPos |
| 884 | Swarm Spider 884.0 (53) | 0xca | 0x556dc0 | TargetPos |
| 901 | Lil Blub 901.0 (2) | 0xd5 | 0x4549b0 | FireBossProjectiles, FireProjectiles, GetPlayerTarget, WanderBoss |
| 902 | Rainmaker 902.0 (1) | 0xd6 | 0x57f310 | FireBossProjectiles, FireProjectiles, GetPlayerTarget, RandomDir |
| 908 | Baby Plum 908.0 (1) | 0xdc | 0x443330 | - |
| 913 | Min Min 913.0 (1) | 0xe1 | 0x4d5e70 | GetPlayerTarget, PathChase, TargetPos |
| 914 | Clog 914.0 (1) | 0xe2 | 0x4a57a0 | FireProjectiles |
| 918 | Turdlet 918.0 (1) | 0xe6 | 0x5a2d50 | TargetPos |

</details>

---

## Recording checklist (what confirms or breaks each claim)

1. **Spreads:** a mode-2/4/5 shot's speed = 1.2 × base, plus 0.4 × the enemy's velocity at fire time (fire from a
   moving enemy). A mode-0 shot has none of that.
2. **FireBossProjectiles:** the lob's own first-update direction is within 30° of Isaac; the burst on landing
   (EXPLODE) is what scatters. Log the lob and its children separately.
3. **Height rule:** shots with `PositionOffset.Y` < −50 pass over Isaac. Log both `PositionOffset.Y` and the height
   field.
4. **Collision class 2:** contact damage from a Trite in the air and from Sloth after its summon (expect: yes, it
   hurts).
5. **I-frames:** after a half-heart hit no damage for 60 updates; after a full-heart hit, 120. Log the gap to the next
   accepted hit, and Isaac's flag/timer if exposed.
6. **The Haunt:** HP unchanged in State 4 and 16 even when hit (already confirmed: 1,124 samples); the orbiting Lil'
   Haunts likewise.
7. **Can-shoot:** Gemini's baby never shoots beyond 300 px or with a rock between; the Pooter beyond 200 px.
8. **Charger:** already confirmed (24/24); add the 16-update lead test (cross its column at speed from 30-60 px
   short).
9. **Isaac's movement:**
   - `Velocity` magnitude under steady input: expect about 4.4 at speed 1.0.
   - Position change per update: expect about 8.8 if the movement step runs twice per update.
   - The decay with no input: ×0.880 per step.

## Gaps (for the next pass)

- Projectile `PositionOffset.Y` vs the height field: whether they are kept in sync.

---

## Batch A (2026-11-26): creep and contact damage

Both were read from **annotated disassembly** (`probe dis:`), because the decompiler fails on both. Each had two blind
readers (bundles B10 and B11, one reader on Sonnet).

### Creep (effect 1000.22 red, 1000.23 green, 1000.24 yellow; 25/26/56 slow; 44/45/46/53/54/169/204 enemy-side)

**Where it is:**
- `Entity_Effect::Update` (`0x5da490`) switches on the variant through a jump table at `0x60d388` (index variant − 1).
- Variants 22-26 and 46 all jump to one block at **`0x5f1143`**. It also holds the code for 44, 45, 53, 54, 56, 92, 94,
  169 and 204.
- That function is about 200 KB and is on the never-decompile list.

**Size** (first update only, `0x5f1143`-`0x5f1886`):
- `size = 20 × s × scale`. Here s is the sprite scale the creep was spawned with, after an optional trinket-106
  bonus; scale is field `+0x478`.
- The animation (small / normal / big / bigger puddle, 1 of 6 random frames) is picked by s.
- **The size never grows or shrinks while the creep is alive.**

**Lifetime:**
- **No timeout is counted in this block.** Whatever sets the creep's `dead` flag lives elsewhere.
- This block only kills it on room clear or in water (`0x5f188c`-`0x5f19a7`), and not if it's friendly.
- Once dead it **fades over 40 updates** (alpha lerps to 0, sprite scale × 0.98 per update, then Remove at
  `0x5f3454`). It does no damage while fading.
- Field `+0x45c` gets a random 0-29 for some variants and may be the lifetime, but nothing here counts it.

**Damage to Isaac: variants 22, 23, 24** (and 169 when not friendly) (`0x5f1a2c`-`0x5f1d44`). It checks every player
**every update**:
- **Skip if the player's grid collision class is not 5 (ground)** (`0x5f1aeb`; `0x4450e0` simply returns
  `entityGridCollisionClass`). **Flying Isaac (grid class 3) is immune.** There's no height test.
- Also skipped: trinket 14 (`0x5f1afd`), collectible 571 (`0x5f1b15`), and a per-player test `0x7e3ef0`.
- **Coarse range:** distance < `size × sprite scale (+0xe4) + a player term` (probably his size) (`0x5f1b30`-`0x5f1bcf`).
- **Fine test:** the creep sprite is sampled at Isaac's position, and **hits only where its alpha is > 0.5**
  (`0x5f1bd5`-`0x5f1cb8`). **The hit shape is the painted puddle, not a circle.**
- **Damage: a flat 1.0** (not the creep's collision damage), flags `0x10`, countdown 30
  (`TakeDamage(1.0, 0x10, 0, source, 30)`, `0x5f1d23`-`0x5f1d44`).
- The source is the creep's parent if it has one, else the creep.
- There's no timer of its own: **Isaac's invincibility after the hit (60-120 updates) is what spaces repeat hits.**
- **Slowing creep (25, 26, 56):** the same tests, then slows the player to 0.75× (variant 25) or 0.85×, with no damage.
  Variant 94 sets a player flag instead (probably slippery).
- **Enemy-side creep** (Isaac's own creep, e.g. 46/53/54) damages enemies, inside an ellipse whose y distance is
  stretched ×1.75.

**Review:**
- **All agree** on the size formula, the 40-update fade, the flat 1.0 damage, flags 0x10, countdown 30, the
  every-update check, and the alpha > 0.5 sample.
- **The flying immunity: settled by C.**
  - Reader A read the `== 5` test as the grid class.
  - Reader B couldn't name `0x4450e0`.
  - Its body returns `entityGridCollisionClass`, and the player's Update sets class 3 while flying (`RE_CORE.md`,
    B6).
- **Unresolved:** where the creep's lifetime timer lives.

**Bot meaning:**
- Red/green/yellow creep hurts only where it's actually painted, so the sprite's own shape matters, not a radius.
- One hit, then Isaac's i-frames cover the rest of the puddle.
- **Flying makes Isaac immune.**
- A puddle doesn't spread after it's spawned.

### Contact damage (`Entity_NPC::HandleCollision`, `0x6d4ce0`, player branch)

**Touching an enemy hurts Isaac when** the collision pair passes `CollidePair` (classes, `RE_CORE.md` Level 2), and
then (`0x6d65e9`-`0x6d67ed`):
- the `low` argument is 0 (the normal call);
- **the enemy's `collisionDamage` (+0x388) is above 0**;
- none of the exceptions below apply.

**Damage:** `TakeDamage(collisionDamage, 0 (2 = fire for fireplaces), 0, enemy, 30)`.
- **No multiplier, and no height, state or collision-class check on this path.**

**No damage** when:
- **a friendly enemy** (flag 0x20000000) passes a source test (`0x6d62d3`);
- an enemy with flag 0x1000000 that isn't a boss kills itself instead (`0x6d62a7`);
- **in ambush / boss-rush / greed wave rooms** (room types 11 and 17), the enemy is in State 1, **or spawned under 10
  updates ago** (`0x6d6349`);
- both are in minecarts;
- some items: Skatole vs flies, Bursting Sack vs spiders, by config flag;
- **per-type cases:**
  - Boom Fly (25) in State 5 explodes instead;
  - type 881 only hurts in State 6;
  - 291, 808, 810, 308 and 866 each have their own conditions (full table in the B11 reader reports).

**There's no knockback on Isaac here.**

**So the "airborne" cases come from collision classes, not from a height check here:**
- **Monstro mid-jump** is class 0: no pair, no damage.
- **A Trite mid-hop** is class 2: the pair happens and it **does hurt**.
- **Orbiting Lil' Haunts** (class 1) hurt; that's 81 recorded hits.

**Review:**
- **All agree** (both readers): the gates, `collisionDamage` × 1, countdown 30, the 10-update spawn grace in wave rooms.
- **Unresolved:** what the friendly-source test `0x6b3ca0` checks exactly, and whether charmed enemies are excluded
  elsewhere (probably in the player's TakeDamage).

**Recording checklist (Batch A):**
- Creep: no damage while Isaac flies; a hit only inside the painted puddle; 1 damage per hit regardless of the creep's
  collision damage; the puddle size constant while alive.
- Creep: log the creep's lifetime (spawn → fade start), to locate the timer.
- Contact: a Trite hurts mid-hop; Monstro doesn't mid-jump.
- Contact: in a wave room, no contact damage in an enemy's first 10 updates; contact damage = the enemy's
  `CollisionDamage`.

---

## Batch D (2026-11-26): knockback, the physics step, flee, height sync, "two steps"

Two blind readers (bundle D1, one on Sonnet); all agree unless noted.

### The per-update physics step (`Entity::EntityUpdate`, `0x6b5720`, lines 189-204)
For every entity, every update:
1. **velocity × f**, where f = the friction field `+0x36c` (adjusted for `speedMultiplier` when that isn't 1);
2. **then position += speedMultiplier × velocity**;
3. **then f is reset to its base `+0x368`.**

So any helper that multiplies `+0x36c` (×0.7, ×0.8 ...) only changes **that update's** damping. A helper that adds
a / f to velocity and sets friction f gives the steady speed **v = a / (1 − f)**.

**Derived enemy top speeds** (base friction 1.0, the config default):

| Enemy | Formula | Top speed |
|---|---|---|
| PathChase (`0x7ebb70`) far from its target | accel 2 × speed, f = 0.7 | **v ≈ 6.7 × speed** |
| Gaper 10.0 | 6.7 × 0.6 / 0.72 | **≈ 4.0 px/update, 4.8 when angry** |
| Gaper 10.1 | 6.7 × 0.498 | ≈ 3.3 |
| Gaper 10.2 | 6.7 × 0.548 | ≈ 3.7 |
| Globin | 6.7 × 0.75 | ≈ 5.0 |
| Gazing Globin | 6.7 × 1.1 | ≈ 7.3 |
| Spider dart | accel 6, f = 0.6 | up to ≈ 15 px/update, but it stops within 14 px of a 70-200 px target |
| Dart Fly | 0.30 accel, f = 0.95 | ≈ 6, capped 8 |

These are calculations from the code (**unresolved** until recorded). Compare Isaac's ≈ 4.4 × k velocity (`RE_CORE.md`,
movement): **a Gaper is close to Isaac's speed.**

### Knockback (`Entity::AddKnockback`, `0x6be8c0`, and `EntityUpdate` lines 121-187)
- **AddKnockback(source, vector, countdown, bounce)** stores the vector and the countdown and sets the "knockback"
  flag.
  - It does nothing if the source test `0x6b3ca0` passes, if countdown is 0, or if the entity has flag bit 0 (unless
    bit 49 is set).
  - **Mass above 10 scales the vector and the countdown by 1 / log10(mass).**
- **While active, each update:**
  - velocity = the knockback vector, which decays ×0.95 per update (no decay with flag 0x20000);
  - friction = 0.95 × base;
  - a wall hit halves the countdown; with the bounce flag, the first wall hit reflects at 0.8 and **damages the entity
    itself** (wall slam).
  - **It ends** when the countdown runs out, the vector falls below 2.0, or the entity's own opposite motion is
    stronger.
- **Knockback on Isaac:** his TakeDamage and collision handlers call `AddKnockback` only on **other** entities (the
  reflect item 690 knocks back the attacker; contact pushes enemies at 18 px). **A normal hit gives Isaac no
  knockback.** What he feels is the physical separation of two solid bodies (`CollidePair`).

**Review:**
- all agree (both readers) on the mechanism, the 0.95 decay, the 2.0 stop and the mass rule;
- **"no knockback on Isaac from a hit": settled by C** (the callers of `0x6be8c0`: Tear, player TakeDamage paths for
  item 690 only, the player's collision handler on the other entity, the NPC collision handler on the other entity).

### Flee (`0x7ece80`, very likely REPENTOGON's EvadeTarget)
What a feared NPC does (called with Isaac's position):
- **The threat check** runs every 14 updates. If Isaac is within **250 px with a clear line, or 170 px behind
  cover**, the flee timer is refilled to 3. Otherwise it drains about 1 per check, so roughly 1.4 s of fleeing after
  Isaac backs off. Then it wanders (`MoveRandomlyBoss`).
- **Picking a refuge:** up to 7 tries (fewer under "stress"):
  - a random point 30-480 px from a spot 30 px away from Isaac (the y extent halved), snapped to a 40 px cell;
  - the cell must be empty and reachable in a straight line;
  - it must be at least about 100 + r/3 farther from Isaac than the NPC is now, preferring points **out of Isaac's
    line of sight**.
- **Moving there:** a one-time kick of 1.5 away from Isaac, then PathChase at 1.08.
- **Review:** all agree. **MoveRandomly** (the plain random walk) is `0x7ed880` (`RE_CORE.md`, "RandomAxisWalk").

### Projectile height vs `PositionOffset.Y`
- `Entity_Projectile::Update` writes `PositionOffset.Y` only in one special-flag branch (line 2676, flag hi 0x100).
- The normal copy of height (+0x410) into `PositionOffset.Y` is **not in Update**: probably Render or a shared helper.
- **Unresolved:** record both fields for the same shot.

### "Two movement steps per update"
- `0x781fc0` has one caller, the player's Update (`0x78e4b2`), with no loop around it.
- Whether the player's Update itself runs twice per 30-Hz game update is decided by the caller loop, which wasn't
  traced.
- **Unresolved.**
- Evidence for "twice": the square-rooted friction, Move's `speedMultiplier / 60` charge counter (line 527), and the
  recorded positions.
- The decisive test: record Isaac's `Velocity` magnitude (≈ 4.4 at speed 1) next to his position change per update
  (≈ 8.8 if twice, ≈ 4.4 if once).

### Recording checklist (Batch D)
- Gaper / Globin chase speed vs the derived 4.0-5.0 px/update.
- No knockback on Isaac after a hit: his velocity doesn't jump in the hit's direction.
- A feared enemy flees for about 1.4 s after Isaac is beyond 250 px (170 behind cover).
- A projectile's height vs `PositionOffset.Y`.
- Isaac's `Velocity` vs his position change per update (the two-steps test).

---

## Batch E2 (2026-11-26): hazards (explosions, TNT, spikes, fireplaces, stone shooters)

Two blind readers per bundle (E2a: explosions and TNT; E2b: spikes, fireplaces, stone shooter), one on Sonnet; all
agree unless noted.

### Explosions (`Game::BombExplosionEffects` `0x706f90` → the damage pass `0x705fe0`)
- **Radius:** **75 px** for a normal bomb (90 if 140 < damage < 175, 105 if ≥ 175; Giga 130) × a scale argument,
  **measured centre to centre plus the target's size** (`radius + size`, line 118).
  - Optionally a line check (`Room::CheckLine`): a target behind cover takes nothing.
- **Damage to Isaac:** **1 (half a heart) if the bomb damage is < 85, else 2 (a full heart)** (lines 231-236). It is
  not the bomb's raw damage. Damage flag 0x10000000 forces 1.
  - **Isaac's own bombs hurt him**: the only exclusion is the bomb entity itself.
  - An item-immunity check (`0x7e3ef0`, probably Pyromaniac/Host Hat) can cancel it; the ids weren't visible.
- **Push:** min(radius + size − distance, 15) away from the centre. For Isaac it's added to half his velocity and
  capped at 10. It applies before damage, even during i-frames.
- **Other entities:** take the full bomb damage.
- **Grid:** rays every 20 px out to the radius break the tiles in line.
- **TNT** (`GridEntity_TNT::Hurt`): each hit ≥ 1 adds 1 (a 1-in-3 chance of +2) to a 0-4 counter. The blast is
  triggered elsewhere, at 4.
- **Bot meaning:**
  - **stay more than 75 px + Isaac's size from any bomb (yours too)** when it goes off;
  - a full heart from big blasts;
  - cover blocks it when the line check is on.

### Spikes (`GridEntity_Spikes::Update` `0x725e10`)
- **While up, they hurt every update** via `GridEntity::hurt_surroundings(2, flags 0x80, ...)`: **2 = a full heart**
  (matching the logged 2-damage spike hits). Isaac's i-frames space the repeats.
- **Retracting spikes (grid type 9):** **60 updates up, 60 down** (2 s each), flipping on a timer. An animation at
  timer 5 warns about 5 updates before each flip (lines 41-52).
- **Plain spikes (type 8):** always up.
- **Bot meaning:**
  - never path over raised spikes;
  - retracting spikes are safe for the 60-update down phase; cross early in it, not in its last 5 updates.

### Fireplaces (33.x, `0x6d9000`)
- **Only red (33.1) and purple (33.3) shoot** (lines 390-464):
  - when ready (an 84-update cooldown after each shot; 60-89 at spawn), each update a 1-in-5 roll, then:
  - **Isaac within 160 px** (the squared value goes through the hidden sqrt, so 160 px) **with a clear line**;
  - then a 1-in-15 roll: the Shoot overlay, then **one shot at speed 5 aimed at the nearest player's current
    position** (no lead);
  - **purple's shot homes** (flag bit 0, strength 1.5).
- **Putting them out:**
  - normal and red: hits cost health per hit (1-2, or 2-3 for hits > 10); out below 1.5;
  - **blue and purple: only explosions put them out**;
  - **white: never**.
- Contact damage comes from the entity config (class 4 while burning, 0 when out).
- **Bot meaning:**
  - red and purple fires snipe within 160 px with line of sight, about every 3-5 s;
  - put red ones out or stay out of range;
  - don't waste tears on blue or purple;
  - white is a permanent obstacle.

### Stone shooters (202, `0x50cb10`)
- **No player check at all:** they fire on a timer, along their fixed facing (subtype 0 = left, 1 = up, 2 = right,
  3 = down). One shot (mode 0) at speed 7 × 1.07 ≈ 7.5 at the Shoot event. Then the next one fires as soon as the
  animation ends.
- Variants 10/11 alternate a + ring and an X ring (modes 6/7) at speed 10.
- They're invulnerable, and close their eyes when the room is cleared.
- **Bot meaning:** a constant stream along one row or column; stay off it.

### Unresolved
- **The "0.0" damage source:** not found yet. Candidates: an explosion or hazard whose source reference has no entity.
  Next: find the TakeDamage callers that pass an empty source.
- The TNT blast's own radius and damage.
- The spike flag 0x10000000 in room type 13.
- The stone shooter's real fire rate (its animation length).

### Record to confirm (E2)
- Bomb damage to Isaac = 1 (or 2 for big bombs) within 75 + his size; none behind cover.
- Spikes: 2 damage; retracting spikes up and down 60 updates each.
- Red/purple fires: shots only within 160 px with line of sight; speed 5; purple homes.
- Stone shooter: fixed direction, about 7.5 speed.

---

## Batch E2c (2026-11-26): the curse-room door ("0.0" source), bomb damage, the devil-deal penalty

Two blind readers (bundle E2c, one on Sonnet); all agree with my reading.

### The curse-room door (`GridEntity_Door::Update` `0x7136e0`, lines 321-376)
- **For a door with flag bit 0x4** (the spiked curse door), every update, for every player whose centre is inside a
  box at the doorway (about 58 × 40 px, reaching about 43 px out on one side): **TakeDamage(1.0, flags 0x10010000, 0,
  an empty source, 30)**.
- **The empty source is the logged "0.0" source.**
- **Flying:** the hit needs the player's grid class == 5 (ground) and no minecart. **But inside a curse room (room type
  10) the class test is skipped, so leaving a curse room hurts even while flying.** (So does a third condition,
  `local_c1`, not decoded.)
- It's a per-update position test, not an "enter" event: it hits on the way in and the way out. Isaac's i-frames stop
  the repeats.

### Bomb damage (`Entity_Bomb::Init` `0x6a8d40`)
- **100 for normal bombs, troll bombs (variant 3) and mega-troll bombs (variant 4).** So Isaac takes **2** (≥ 85),
  which matches all 19 logged bomb hits.
- Variant 15: 20. Giga bombs (17, 20): 300.
- **Fuse:** 45 updates (1.5 s). Troll-type variants 3, 4, 8 and 18: 45-74 updates.

### The devil-deal "took damage" penalty (`Entity_Player::TakeDamage`, lines 1187-1188, 3845-3858)
- A hit counts as a **penalty hit** unless its damage flags include **bit 5 (0x20)** or **bit 28 (0x10000000)**:
  `penalty = (flags & 0x10000020) == 0`.
- **A penalty hit:**
  - calls `0x42cbf0(5, 1)` (lines 3845-3851), most likely `Level::SetStateFlag(5, true)`. In the LevelStateFlag order
    5 is `STATE_DAMAGED`, the "took damage this floor" flag the deal chance reads;
  - adds to two damage counters (+0x16b0, +0x16b4);
  - triggers some on-hit item effects.
- **Exempt (no deal penalty):**
  - **curse-room door hits** (0x10010000 carries bit 28);
  - **sacrifice-room spikes** (room type 13 adds 0x10000000 to the spike flags; see E2 spikes);
  - anything with bit 5 (0x20), most likely self-damage items and blood donation.
- **Not exempt:** normal spikes (0x80 only), explosions, contact, shots, creep (0x10).
- **Unresolved:**
  - what the deal-chance code does with flag 5 (that's level 4; not started);
  - which item and donation hits use bit 5;
  - the meaning of bit 16 (probably CURSED_DOOR).

### Bot meaning
- **Curse-room doors cost half a heart in and half a heart out (even flying on the way out) but don't hurt the devil
  deal.**
- **Sacrifice-room spikes don't hurt the deal either.**
- Every other hit (spikes, bombs, enemies, creep) sets the floor's "damaged" flag.

### Record to confirm
- Damage 1 at a curse door, with source type 0; while flying, no hit entering but a hit leaving.
- A devil room still appearing at full chance after only curse-door hits on a floor.

## Batch F1 (2026-11-26): tear physics

Two blind readers (Sonnet, Haiku). The write-up session filled the gaps from annotated assembly (`probe dis:`) and the
player's tear-params builder `0x7c8250`. Functions:
- `Entity_Player::FireTear` `0x799750`;
- `Entity_Tear::Init` `0x66cc50`;
- the tear update `0x66dc80`: 46 KB, read only as an assembly excerpt;
- `Entity_Tear::HandleCollision` `0x67a310`;
- the tear-params builder `0x7c8250`.

**Field-offset warning (affects every Isaac-stat read):** in this build the player's stat block sits **8 bytes after**
the REPENTOGON field table. Real offsets: `[body · F1 0x799750, 0x7c8250 · 2 readers]`
- damage **0x1474**;
- tear height **0x1478**;
- tear falling speed **0x147c**;
- falling accel **0x1480**;
- tear range **0x1484**;
- recent-movement vector **0x1650**.
(The table's 0x1470 is a per-player shot counter here. The E2c i-frame field 0x13c0 matches the same +8 shift.)
**From the speed/luck block on, the shift is +0xc**, confirmed in TakeDamage's luck-scaled chances: move speed 0x1568,
**luck 0x156c**, **canFly 0x1570**, tear displacement 0x1578. Check each field before reading memory directly.
`[body · F1/F2 0x77ad70 · 1 reader (write-up session)]`

- **Firing** (`FireTear`): `[move · F1 0x799750 · 2 readers]`
  - **Spawn:** the tear spawns as type 2 one velocity-step ahead of the muzzle, then runs one update and steps back,
    so it starts at the muzzle with one tick of fall applied.
  - **Velocity:** **the caller's velocity × the params' velocity multiplier** (`params+0x5c`, 1.0 unless an item
    changes it).
  - **When Isaac fires it himself,** his recent-movement vector (`player+0x1650`) is added to the aim vector. That's
    the movement inheritance; its size is set elsewhere. `[move · F1 0x799750 · 2 readers]`
  - **Shot speed is applied by the caller** (the weapon code, not decoded). The bot's live tear-speed reading stays the
    source for it.
- **Starting values:** `[move · F1 0x799750, 0x7c8250 · 2 readers]`
  - **height = the player's tear height** (0x1478);
  - **falling speed = −tearFallingSpeed (0x147c) + uniform 0-0.2** (exact, with no random part, under some tear flags);
  - **falling accel = 0x1480**;
  - **range = 0x1484**;
  - damage = multiplier × player damage (0x1474);
  - knockback multiplier 1.7;
  - scale ≥ 0.01.
  - **Room type 16:** sprite offset −18, height capped at −5.1.
- **Init defaults** (overwritten by FireTear): `[body · F1 0x66cc50 · 2 readers]`
  - damage 3.5;
  - height −23;
  - falling speed ±0.1;
  - homing friction 0.85;
  - knockback multiplier 1.7;
  - range 260;
  - grid collision class 4.
- **Each update** (when not waiting), with speed multiplier m = 1: `[move · F1 0x66dc80 · 2 readers]`
  - **fallingSpeed = 0.9 × fallingSpeed + 0.1 + fallingAccel** (a pure `fs + accel` for one tear mode);
  - **height += fallingSpeed**;
  - **velocity.y += fallingAccel** (when ≥ 0.001), so the ground track bends downward.
  - So a tear rises, then drops in a parabola. **It dies when height > −5.0** (one tick early under one flag; it
    bounces with fs × −1.6 under another).
  - **No plain range countdown was seen:** range is only compared inside flag-gated blocks. The landing height is what
    ends a normal tear. `[timing · F1 0x66dc80 · 2 readers]`
- **Death's hourglass:** a tear speed scale × 0.75 while `room+0x7244 > 0`. `[move · F1 0x66dc80 · 1 reader (write-up session)]`
- **Hitting an enemy** (`HandleCollision`): `[attack · F1 0x67a310 · 2 readers]`
  - **damage = the tear's collisionDamage**, through the target's TakeDamage (flags 0, countdown 30);
  - a directional-shield check (`CanBeDamagedFromVelocity`) can block it;
  - **an ordinary tear dies on its first enemy hit**;
  - **piercing tears lose damage equal to the enemy's health** and keep going, shrinking with the remaining damage;
  - more than 15 tears already registered on an enemy blocks further hits;
  - enemy shots (type 9) hit by a tear are destroyed unless protected.
- **Knockback on enemies:** not in `HandleCollision`, which never reads the tear's 1.7 multiplier. The flag-specific
  pushes found are 26 (in `ApplyTearFlagEffects` `0x681de0`) and 18 (in the NPC collision handler).
  `[attack · F1 0x681de0, 0x6d4ce0 · 1 reader (write-up session)]`
  - **The ordinary tear's knockback formula is unresolved**, likely inside TakeDamage using the source tear. Measure
    it from recordings.

### Bot meaning (F1)
- **The tear arc:** use fallingSpeed = −0x147c (+ 0-0.2), accel = 0x1480, then fs = 0.9 fs + 0.1 + accel; height +=
  fs; dead at height > −5. That gives each tear's real reach, so the bot can predict which tears land before reaching a
  target. Feed it Isaac's live stats from the +8 offsets.
- **A normal tear stops at the first enemy**; piercing tears keep going with less damage.
- **Shooting while moving** adds Isaac's recent movement to the aim. Lead targets with that in mind.

### Record to confirm (F1)
- Tear flight time and landing distance against the formula at default stats (height and fall values from the live
  player at +8 offsets).
- velocity.y gain of fallingAccel per update.
- Enemy knockback per tear hit (unresolved).
- Tears at × 0.75 during Death's hourglass.
