# Decompiled enemy AI: our worst hit sources (2026-11-26)

Method, build and rules: see `RE_PILOT.md` (same build, same pipeline). This file has one section per enemy.

**Recording check (2026-11-26):** Sloth, Charger and the Gurgling charge trigger were checked against real recorded
fights. See "Recording check" at the end of this file for what's confirmed, contradicted or not covered.

**How to read these tables:**
- Every claim is a **hypothesis** until the recorder (`record|1`) confirms it. Each section ends with what to record.
- The AI runs **30 updates per second** (30 updates = 1 s).
- **y grows downward.** Angles: 0° = right, 90° = down, 180° = left, 270° = up.
- "Line N" means the line in that enemy's decompiled file (local only: `runs/research/re/<type.variant>_<name>_<address>.c`).
- Entity types are written in decimal (the code has them in hex).
- Shots name the projectile helper's **fire mode** (`0x6d2bb0`): 0 single, 2 triple (centre plus two at 0.9 speed,
  ±16°), 5 five-spread, 8 eight-way ring (+ and X). `FireBossProjectiles` is a separate helper: a loose burst toward a
  position.
- "Aimed at Isaac" means at his position on that update, **no lead**, unless it says "led".
- A shared helper, `0x6d2730`, is the "can I shoot?" check used by several enemies: false while confused or feared
  (flag bits `0x200` and `0x1000a00`), true only when Isaac is within a range the caller passes **and** the room's line
  check between them is clear, and with its second argument 7, only tested on some updates (`Entity::IsFrame`).

Finding each function: the AI dispatcher `0x6ca240` reads a case byte at `0x6cbe5c + (Type - 10)`:

| Type | Case | Function |
|---|---|---|
| 18 Attack Fly | 0x03 | `0x50d3c0` |
| 20 Monstro | 0x08 | `0x470020` |
| 23 Charger | 0x09 | `0x534300` |
| 29 Hopper / Trite | 0x10 | `0x52cd30` |
| 46 Sloth | 0x1d | `0x4780e0` |
| 62 Pin | 0x29 | `0x47ac40` |
| 79 Gemini | 0x35 | inline in the dispatcher, then `0x474f90` (variants 0-9) or `0x475bb0` (variants 10-19) |

---

## Gemini (79): Gemini, Steven, the Blighted Ovum and their babies

Three functions:
- the dispatcher's own block for type 79 (dispatcher lines 237-280): friction and the death shots;
- `ai_gemini`, `0x474f90`: the big twin's body (variants 0-2);
- `ai_gemini_parts`, `0x475bb0`: the babies (10-12).

The cord (79.20) only gets flags set (dispatcher line 276).

| Variant | Name | Runs in |
|---|---|---|
| 79.0 | Gemini (body) | `0x474f90` |
| 79.1 | Steven (body) | `0x474f90` |
| 79.2 | The Blighted Ovum (body) | `0x474f90` |
| 79.10 | Gemini's baby | `0x475bb0` |
| 79.11 | Steven's baby | `0x475bb0` |
| 79.12 | The Blighted Ovum's baby | `0x475bb0` |
| 79.20 | Umbilical cord piece (18 of them for Gemini) | dispatcher only |

**Friction** (dispatcher line 238): ×0.8 every update; champions (`subtype` ≠ 0, variants under 10) get an extra ×0.92.

### The body (79.0 / 79.1 / 79.2), `0x474f90`

| State | Animation | What it does | Leaves to |
|---|---|---|---|
| 0 init (line 77) | — | spawns its baby (same type, variant + 10) 8 px above itself, links it as `child`. Gemini 79.0 (not subtype 1) also spawns 18 cord pieces (79.20) (lines 105-135) | 4 |
| **4 MOVE** (line 171) | WalkHori/WalkVert | **paths toward Isaac** (helper `0x7ebb70`, target = Isaac's position from `0x6c6390`) at speed factor 1.4 × 0.83 ≈ **1.16** (Ovum 1.6 × 0.83 ≈ 1.33) (lines 218-227). Each update, a **1-in-60** chance to rage (Ovum: 1 in 60, then 1 in 4 more, so 1 in 240) (lines 232-239) | 8 |
| **8 rage** (line 241) | RageBody overlay | chases faster: the speed factor grows each update as `(s + 0.04) × 0.98`, toward about 1.96 (Ovum +0.2), × 0.83 (lines 242-251). Lasts **100 updates (3.3 s)** (lines 299-303) | Gemini/Steven 3; Ovum straight back to 4 |
| **3 tired** (line 157) | a 2-frame idle (probably Pant, which the Ovum lacks) | **stands still** (speed 0, line 161) for **100 updates (3.3 s)** (line 162) | 4 |

**Tether** (lines 362-410): the body pulls on its baby like a spring.
- **Steven (79.1):** a strong spring that keeps the baby about **26 px** away (force (distance − 26) × 0.1).
- **Gemini and the Ovum:** no pull until the baby is more than **76 px** away, then (distance − 76) × 0.01.
- The pull acts on the baby's velocity, so an attached baby swings about inside that radius.
- `subtype` 1 returns before the tether (line 321): that champion's baby is free.

**Blighted Ovum creep** (lines 64-73): every 7 updates it drops effect 1000.22 (probably red creep, which hurts) where
it stands.

**Death shots** (dispatcher lines 244-268):
- **Steven (79.1)** fires two 8-way rings (mode 8): speed 8 and speed 4.
- **Steven's baby (79.11)** fires one 8-way ring at speed 10.

The rings go in fixed directions (0°, 45°, 90°, ...), not aimed.

**Fields:** `State`, `StateFrame` (rage and tired timers); `child` = the baby; field `0xc34` = the current speed factor.
`I1`, `I2`, `V1`, `V2`, `TargetPosition` are not used. **Damage blocking:** none in this function.

### The babies (79.10 / 79.11 / 79.12), `0x475bb0`

**Attached Gemini/Steven baby** (79.10, 79.11 while the body lives; lines 417-521):
- Drifts toward Isaac at 0.25 per update (over friction), held by the body's tether.
- **Shot** (state 4 → 8, lines 436-444): only when `ProjectileCooldown` < 1 **and** the can-shoot check passes with a
  **300 px range** (constant at `0xbcfd04`) and a clear line to Isaac, tested every 7 updates.
- At the Shoot event of Attack01 (frame 17 of 35, so about 0.57 s of wind-up): **one shot (mode 0) aimed at Isaac**.
  Speed **10** in one game mode, **7** otherwise (`0x6dfc20` checks a game-wide mode value of 1 or 3, maybe hard mode;
  not decoded). Lines 446-482.
- Then `ProjectileCooldown` = **35 updates** (line 519).
- Steven's baby sets projectile variant 12 (line 456); the red Gemini champion (`bosscoloridx` 1) sets extra
  projectile flags (lines 458-460).

**Detached baby** (lines 251-416): when there's no body, or for **Steven's baby when Steven's health is 60 or less**
(line 254).
- It plays its rage animations and stays clamped inside the room.
- It **chases Isaac hard**: 0.5 per update over friction, with velocity × 1.18 each update (lines 393-414).
- It does no shooting in this branch: the threat is body contact.

**Blighted Ovum's baby** (79.12; lines 63-93 init, 125-250):
- **Invulnerable:** `isInvicible` is set at init (line 69) and never cleared in this function. It also stops being a
  boss and unlinks from the body. It dies when the body dies (lines 126-129).
- **Wander** (state 4):
  - for the first 160 updates it drifts toward Isaac at 0.65 (y at 0.9 of that) when he's within 300 px (lines 136-148);
  - after that it slides vertically toward **Isaac's row** at up to 0.2 per update (lines 150-165);
  - random resets between the phases (lines 166-175).
- **Laser trigger** (lines 178-221): `StateFrame` > 40, **Isaac within 20 px of its row or column**, within 300 px, and
  the baby on screen. It takes the cardinal direction toward Isaac (`0x686010`). It **only fires if that direction is
  horizontal** (line 192): a column match gives a vertical direction and no laser.
- At the start of the attack it shows a **warning line** in that direction (`0x611e90`, line 218, the same helper the
  Haunt uses before its laser). Then at the Shoot event of Attack01 (**frame 15 of 55, 0.5 s**) it fires a **laser**
  (`Entity_Laser::ShootAngle`, lines 227-240), left (180°) or right (0°).
- Then back to state 4, `StateFrame` 0.

**Fields:** `V1` = the Ovum baby's laser direction (±1, 0); `ProjectileCooldown` = the attached baby's 35-update gap.

### Bot meaning
- **Gemini's tired phase (State 3, 100 updates, standing still) is a guaranteed 3.3 s window** after every rage. The
  Ovum has none: it goes straight back to chasing.
- **Rage is State 8**, readable: back off for 3.3 s.
- **The attached baby only shoots with a clear line within 300 px**, once per 35+ updates, unled. Break line of sight
  (a rock between) or stay beyond 300 px, or sidestep the single shot.
- **Steven's baby breaks free at Steven health ≤ 60** and then chases hard.
- **The Ovum's baby can't be hurt.** Never aim at 79.12 (`never_aim`). Its laser only goes **sideways along its row**:
  stay more than 20 px off its row (and its column, which also arms the trigger). The warning line gives 0.5 s.
- The Ovum leaves creep every 7 updates: path around its trail.

### Record to confirm
- `State` sequence of the body: 4 → 8 (100 updates) → 3 (100 updates, still) → 4; Ovum 4 → 8 → 4.
- Rage onset rate: about once per 60 updates in State 4 (Ovum about once per 240).
- Baby shot: only with clear line, within 300 px; at least 35 updates between shots; speed 7 or 10 (note the game mode).
- Steven's baby: `parent` cleared when Steven's HP ≤ 60.
- Ovum baby: health never drops when hit; lasers only at 0° or 180°, only when Isaac is within 20 px of its row.
- The death rings' speeds (8 and 4; 10).

---

## Sloth (46): Sloth, Super Sloth, Ultra Pride

One function, `ai_sloth`, `0x4780e0`: 46.0 Sloth, 46.1 Super Sloth, 46.2 Ultra Pride.

| State | Animation | What it does | Leaves to |
|---|---|---|---|
| 0 init (line 67) | — | sets colours | 4 |
| **4 MOVE** (line 305) | WalkHori/WalkVert | walks with a pathfinding helper (`0x7ed880`, speed 1.0; it reads Isaac's position and velocity, so it probably heads for him; uncertain). Friction ×0.75 (line 79). Each update, a **1-in-50** chance to attack (line 355); never while confused (flag `0x200`); while feared, only 1 in 10 of those (lines 357-362) | 8 or 9 |
| **8 summon** (line 87) | Attack (30 f) | acts at **`StateFrame` 5** (line 88) | 4 when `StateFrame` > 29 |
| **9 shoot** (line 162) | Attack (30 f) | acts at **`StateFrame` 5** (Ultra Pride: frames 6-14) | 4 when `StateFrame` > 29 |

**Which attack** (lines 363-387): on the attack update it faces Isaac (left or right, line 364) and starts Attack.
- **50%:** if a room counter (offsets 0x12c0 + 0x12c4, probably the live enemy count) is **3 or less**: summon (8).
  Otherwise shoot (9).
- **50%:** shoot (9).
- **Ultra Pride exception:** it shoots only when **Isaac is within 60 px of its row** (`abs(dy) ≤ 60`, line 382);
  otherwise it summons.

**Summon (state 8, at `StateFrame` 5):**
- **Sloth (46.0)** (lines 123-159): spawns a **Charger (23.0) 30 px to the side it faces**, already in its charging
  state (`State` 8) with `V1` = (±1, 0). **The Charger launches immediately, sideways toward Isaac's side.** It also sets
  Sloth's own entity collision class to 2 (line 158), and nothing in this function sets it back. Class 2 still touches
  Isaac (settled in `RE_CORE.md`).
- **Super Sloth (46.1)** (lines 99-122): throws **1 or 2 spiders** (50/50) at free spots near the **midpoint between
  it and Isaac**.
- **Ultra Pride (46.2)** (lines 89-98): `FireBossProjectiles`, **3 shots toward Isaac's position**, trajectory 10,
  scale 1.2.

**Shoot (state 9):**
- **Sloth and Super Sloth** (lines 259-299): at `StateFrame` 5, **1 shot (Sloth) or 2 (Super Sloth)**. The projectile
  flag it sets (bit 2) is EXPLODE in the ProjectileFlags order, so the lob bursts on landing; the recorded "unaimed"
  shots are probably the burst (`RE_CORE.md`).
  `FireBossProjectiles(1, Isaac's position)`, then made into a **big, slow, high lob**: velocity × 0.55, height × 0.7
  − 13, fall changed by −0.3, scale 1.6, and a projectile flag (2). Aimed at his position, no lead.
- **Ultra Pride** (lines 165-258): at frames 6-14, a **line of creep (effect 1000.23) along its row toward Isaac**,
  25 px further each update, out to about 225 px, plus splash effects. That's why it only picks this with Isaac
  within 60 px of its row.

**Fields:** `State`, `StateFrame` (the attack timer). `I1`, `I2`, `V1`, `V2`, `TargetPosition` are not used.
**Damage blocking:** none in this function.

### Bot meaning
- **The wind-up is tiny: the shot or Charger comes 5 updates (0.17 s) after Attack starts.** The animation can't be
  dodged on reaction. The bot has to stay **out of the lines it will use before it attacks**: not level with it
  horizontally (the spawned Charger runs along its row), and not at the end of a lob.
- **The spawned Charger runs along Sloth's row**, toward the side Isaac is on. Never stand level with Sloth (within a
  Charger's height) on open ground. This likely explains many "Sloth" hits that were really the Charger or the lob.
- It **only summons while there are 3 or fewer enemies**: kill the Chargers it makes, or it keeps making them.
- **The lob is slow (0.55 × speed) and aimed where Isaac was:** a sidestep after it's thrown works.
- **Ultra Pride's creep line only happens with Isaac within 60 px of its row:** stay off its row.
- **Safe window:** after any attack, `StateFrame` runs to 30 with no new attack possible. Then about 2% per update
  (1 in 50), so on average about 1.7 s between attacks.

### Record to confirm
- Attacks fire on `StateFrame` 5 after the change to State 8/9; State returns to 4 at `StateFrame` 30.
- A Charger (23.0) appearing 30 px beside Sloth with `State` 8 and moving horizontally at once.
- The summon only happens with ≤ 3 enemies in the room (log the count).
- Lob: 1 projectile (Super Sloth 2), speed about 0.55 of a normal boss shot, toward Isaac's position at the throw.
- Ultra Pride: creep line along its row; chosen only when `abs(dy) ≤ 60`.

---

## Monstro (20.0)

One function, `ai_monstro`, `0x470020`, shared with Monstro II and Gish (type 43); only the type-20 branches are
described. Strings checked against the exe: the events are `Jump`, `Land`, `Shoot`, and nothing our bestiary missed.

| State | Animation | What it does | Leaves to |
|---|---|---|---|
| 0 init (lines 960-1048) | — | `subtype` 1 (unless spawned by another Monstro) **splits into two Monstros 48 px apart** (±24 px) | 3 |
| **3 IDLE** (lines 823-934) | Walk, held | lasts **1 update**: picks `rand % 3` into `I2`: 0 hop, 1 spit, 2 big jump. **`subtype` 2 never big-jumps** (its 2 becomes 1, so 1/3 hop, 2/3 spit; lines 859-861) | 4, 8 or 6 |
| **4 hop** (lines 352-482) | Walk (45 f, Jump @6, Land @22) | hops to a target (below). When Walk ends: 50% hop again, else 3 | 4 or 3 |
| **6 take-off** (lines 492-510) | JumpUp (15 f, Jump @10) | on the ground until frame 10, then leaves | 7 |
| **7 big jump / landing** (lines 511-803) | JumpDown (64 f, Land @32, Shoot @34) | in the air, homing on the target, then lands and fires | 3 |
| **8 spit** (lines 281-351) | Taunt (66 f, Shoot @21) | faces Isaac, fires at frame 21 | 3 |

**Targets** (lines 357-365, 515-540): for both the hop and the big jump, **Isaac's position at the first update of the
state, no lead**, snapped to the centre of its 40 px grid cell (stored in `TargetPosition`, cleared after). A blocked
cell is retried the next update.
- **Hop:** a push of 1.2 per update (over friction) toward the target until the Land event (frames 0-21).
- **Big jump:** a strong homing pull (0.006 × offset + 0.3 × direction) per update until Land (JumpDown frames 0-31).
  Both have friction ×0.9 every update (line 108).

**No collision while airborne** (lines 372-383, 499-509): the entity collision class is 0 (it touches nothing, and
Isaac's tears pass through) and the grid class 3 (it flies over rocks):
- hop: Walk frames 6-21;
- big jump: JumpUp frame 10 until JumpDown frame 31.

Contact comes back on landing (class 4).

**Shots** (all through `FireBossProjectiles`, whose speed and spread are inside the helper, not decoded):
- **Spit (state 8, Taunt frame 21):** **13 shots toward Isaac's position at that update** (no lead) (lines 283-299).
- **Big-jump landing (JumpDown frame 34):** **18 shots with a zero target vector** (lines 625-632), probably an
  all-round random burst (unconfirmed).
- **Hops fire nothing** for type 20.

**Fields:** `I2` = the last pick; `I1` = 2 only for a drop-in entrance (lines 997-1005; its trigger isn't decoded);
`TargetPosition` = the landing cell. **`StateFrame` is not used:** read the animation frame. **Damage blocking:** none
in this function (airborne it simply has no collision).

### Bot meaning
- **The landing spot is fixed at take-off and readable** from `TargetPosition` (hop: from the first update of
  State 4; big jump: from the first update of State 7). Get out of that 40 px cell (plus Monstro's 40 px radius)
  before landing: hop frame 22, big-jump frame 32.
- **Spit:** 21 frames of warning (0.7 s), aimed where Isaac is at frame 21. Move across the line at that moment.
- **Big jump:** after landing (frame 32) an 18-shot burst at frame 34. Be away from the landing cell, not just off
  it.
- **Shooting it while it's airborne is wasted:** the tears pass through.
- After a hop, 50% chance of another at once; State 3 is never a resting window.

### Record to confirm
- The pick split (about 1/3 each; subtype 2 never State 6).
- `TargetPosition` = Isaac's grid cell at the first update of State 4 / 7, fixed after.
- Collision class 0 while airborne (tears pass through), back to 4 on landing.
- 13 shots at Taunt frame 21 toward Isaac; 18 shots at JumpDown frame 34 (all round or aimed?), their speeds.
- Subtype 1: two Monstros 48 px apart. Which colour each subtype is.

---

## Attack Fly (18.0)

`0x50d3c0` is shared by many flies: 13 Fly, 14 Pooter, 18 Attack Fly, the 61 Sucker family, 80 Moter, 214, 249
and 819.
- **Moter** (80) splits into two 18.0 on death, 10 px either side, at right angles to the line to Isaac (lines 345-380).
- **Pooter** shots are in here too: cooldown 35, can-shoot range **200 px** (constant `0xbcfc90`).

For 18.0:
- **State 0 → 3, then never changes** (lines 132-136, 187). Grid collision class 3: it flies over rocks and pits.
- **Target:** `TargetPosition` = Isaac's position, refreshed only **every 3rd update** (`IsFrame(3)`, lines 677-679,
  755-757). **No lead.**
- **Chase, every update** (lines 805-872):
  - offset d = target − position, with the **vertical part halved** (line 832; unusual, check it);
  - L = the length of that;
  - **no pull while L ≤ 25** (line 812; so up to 25 px sideways or 50 px vertically);
  - otherwise it adds **(L − 25) × 0.08 per update, capped at 1.2** (lines 861-865), along the flattened direction.
  - There's no speed cap in this function: its top speed comes from the engine's damping (measure it).
- **Wobble** (lines 934-978): a small random drift (`V1`, at most about 0.4, applied every 3rd update), plus a weak
  pull toward a fixed screen box (x 80-540, y 230-420).
- **Flies with a parent** orbit it about 65 px out (lines 681-713, 833-836) and barely chase.
- **Fear:** it flees to a point away from Isaac (lines 766-804).
- **Damage blocking:** none here; contact damage only.

### Bot meaning
- It steers toward where Isaac was up to 2 updates ago, with a turn rate of at most 1.2 per update, so **a sharp
  sideways cut makes it overshoot**.
- **Vertical dodges should shake it more than horizontal ones**, because its pull is flattened (if line 832 holds).
- Inside about 25 px it coasts on momentum: don't stop right next to it.

### Record to confirm
- |Δvelocity| ≤ 1.2 per update far away; ≈ (L − 25) × 0.08 for L between 25 and 40 (test the halved-y L).
- The direction of Δvelocity against atan2(dy/2, dx) and atan2(dy, dx).
- The steering target steps every 3 updates and lags Isaac (no lead).
- Top speed on a long straight chase.

---

## Trite (29.1), with the Hopper (29.0)

`ai_hopper`, `0x52cd30`, runs types 29 (Hopper 0, Trite 1, Eggy 2, Tainted Hopper 3) and several others (34, 54
Flaming Hopper, 86, 246, 305, 840). Strings checked: `Idle`, `Hop`, `Jump`, `Land`.

| State | Animation | What it does | Leaves to |
|---|---|---|---|
| 0 (line 117) | — | init | 3 |
| **3 IDLE** (lines 660-690) | Idle | **waits exactly 15 updates** (Trite; Hopper 0, Eggy 8, Tainted 26; lines 309-318), no randomness. Then tries to hop every update | 4 |
| **4 hop** (lines 772-995) | Hop (26 f, Jump @4, Land @18) | springs to the landing cell | 3 when within 10 px of it, or a 1-in-10 chance per update once slow or `StateFrame` > 30 (lines 919-947) |

**Where it lands** (lines 321-346, 660-690, 772-782). Each update it rolls a range r = 50·rand + 70·rand (0-120,
peaking near 60; plus an unnamed term `local_260`, probably 0). Threshold T = 1.3·r + 130 px (130-286 px).
- **Isaac closer than T:** it aims at **Isaac's position plus r/200 of the Trite-to-Isaac gap**, so it lands **past
  him by 0-60%** of the gap. **No velocity lead** (only the Flaming Hopper, type 54, adds 5 updates of his velocity,
  lines 677-681).
- **Isaac farther than T:** it hops 95-215 px in a direction from `0x685f10` (probably random).
- The point is snapped to its 40 px grid cell and stored in **`TargetPosition`, fixed from take-off** (lines
  772-782). A blocked cell means it tries again the next update.

**Motion** (lines 802-809, 978-995): a spring toward the cell, 0.05 × offset per update (over friction), only 10% of
that before the Jump event (frames 0-3). **The landing does nothing** but play a sound (lines 813-815): no shots and
no creep.

**Collision** (lines 903-912): before Jump, entity class 4 and grid class 5. **From the Jump event on, entity class 2**
and grid class 3 (it clears rocks and pits). Nothing here sets class 4 again until the next hop's wind-up.
- **Settled (RE core pass, `RE_CORE.md`):** class 2 still touches Isaac and his tears; it only stops touching other
  enemies. So the Trite **can hit Isaac during the whole hop and while idle**.

**Fields:** `TargetPosition` = the landing cell (zero = none pending); `StateFrame` = the idle gate and hop timeout.
`I1`, `I2`, `V1`, `V2` are not used by the Trite. **Damage blocking:** none here.

### Bot meaning
- **After landing, 15 updates (0.5 s) of guaranteed idle** (`State 3, StateFrame < 15`).
- **The landing cell is readable from `TargetPosition` from the first hop update, 4 frames before it leaves the
  ground:** step out of that cell then.
- **It aims past Isaac along its line toward him**, by up to 60% of the gap: backing straight away from it is the
  wrong dodge. Step sideways.
- Minimum cycle: 15 idle + about 26 hop ≈ 41 updates (1.4 s).

### Record to confirm
- The idle gap from State 3 to 4 is never under 15 updates (Hopper: about 0).
- `TargetPosition` is a grid-cell centre along the Trite-to-Isaac line, 0-60% past him, with no lead (run sideways).
- `EntityCollisionClass` 4 → 2 at Jump; and **whether Isaac takes contact damage from an idle or airborne Trite**.
- Far hops (Isaac beyond about 290 px): 95-215 px, random direction?

---

## Charger (23.0)

`ai_charger`, `0x534300`, also runs types 21, 31, 55, 237 and 243. Type 23: 23.0 Charger (`subtype` 1 adds only a
push apart from nearby NPCs, lines 1292-1340), 23.1 Drowned, 23.2 Dank, 23.3 Carrion Princess.

| State | Animation | What it does | Leaves to |
|---|---|---|---|
| 0 | — | init (line 220) | 4 |
| **4 wander** (lines 914-954) | Move Hori/Up/Down | moves with a pathfinding helper (`0x7ed880`, speed 0.6; probably axis-aligned random movement). The charge check below | 8 |
| **8 charge** (lines 648-718) | Attack Hori/Up/Down | each update friction ×0.8 and velocity += `V1`; the sideways part is pulled onto its tile line | 4 |
| 16 (Dank only) | Recover | — | 4 |

**The charge trigger** (lines 991-1116). All of these must hold:
1. **Only 1 update in 4** (`IsFrame(4, index)`, line 992).
2. The reference is the **centre of the Charger's 40 px grid cell** (lines 1002-1004).
3. The aim point is **Isaac's position + his velocity × random(0-1) × 16** (lines 1007-1014). **This leads him by up
   to 16 updates**; then a helper `0x43a210(..., 20)` adjusts it (not decoded).
4. **Within 20 px of the cell centre in x or in y** (that is, inside its tile row or tile column; line 1112),
   **under 200 px away** (squared distance < 40000, line 1113), **a clear `Room::CheckLine`** (line 1115), and not
   confused or feared (flags `0x1000a00`, line 1109).
5. **No random roll and no cooldown.**

**The charge** (lines 1131-1142): direction = `0x686010` (snap to the nearest axis) of the offset, so **one of the 4
axes toward the aim point**. `V1` = 1.3 × that axis. **No wind-up.** It never re-aims. Top speed is about
1.3 / (1 − 0.8) ≈ 6.5 px/update if base friction is 1 (unverified).
- **It ends** on a grid or wall hit, being stuck for 6 updates, confusion, fear or slow (lines 662-672), then goes
  **straight back to State 4 with no pause**. It can charge again 1-4 updates later.

**Variants:**
- **Drowned (23.1):** slower (wander 0.54, charge ×0.9). On death, fire mode 7 (probably 4 diagonal shots) at speed 8
  (10 in the `0x6dfc20` game mode) (lines 135-146).
- **Dank (23.2):** an Alert wind-up, then a charge at 18.2 that bounces off walls, slows, leaves black creep
  (1000.26), then Recover (State 16).
- **Carrion Princess (23.3):** the same test rotated 45°, so it charges **diagonally**, with no 200 px cap (lines
  1035-1108).

**Fields:** `V1` = the charge step; `V2` = the charge start; `StateFrame` cleared on a charge (only Dank reads it).
**Damage blocking:** none here.

### Bot meaning
- **The rule is exact:** a charge needs Isaac's *predicted* point (up to 16 updates ahead) inside the Charger's 40 px
  tile row or column, within 200 px, with nothing in between.
  - So: **don't stand in, or run toward, its tile row or column within 200 px.**
  - **Crossing its line at speed triggers it early**, because of the lead.
- **A rock between you blocks it.**
- **There is no telegraph and no recovery.** Treat a Charger lined up within 200 px as already charging; it can go
  again a few updates after hitting a wall.
- This is also what Sloth spawns (already in State 8, see Sloth).

### Record to confirm
- Stand still 19 px vs 21 px off its cell centre (clear line, under 200 px): a charge at 19, none at 21. Aligned at
  190 vs 210 px: a charge vs none.
- A rock between you while aligned: no charge.
- Walk across its column fast while 30-60 px short of it: does it fire early (the lead)?
- The trigger update: (frame + index) % 4 constant. The charge axis is always one of 4; top speed; it goes straight
  to State 4 after a wall hit.

---

## Pin (62.0), with Scolex (62.1) and The Frail (62.2)

`ai_pin`, `0x47ac40`. **Wormwood (62.3) is not here:** line 162 hands variant 3 to `0x5b58d0`. Gameplay runs on
`StateFrame` counters. The only events checked are `Dive` and `Popup`, which only play sounds (lines 1739-1750).

**Body:**
- The head spawns a chain at init (lines 199-303): Pin and Frail have 5 body segments plus a hole marker; Scolex has
  8 plus the hole.
- Segments replay the head's path with a delay (Pin: 0, 2, 4, 6, 8 history steps).
- They are solid only while above ground (`PositionOffset.Y` < 16) and the head is in State 4 (lines 1325-1412).

| State | What it does | Leaves to |
|---|---|---|
| **3 decide** (lines 957-1097) | 1 update. **After a leap (`I1` = 4): 50% attack, otherwise leap again. After an attack: always leap** (line 959) | 4 or 8/9 |
| **4 leap → underground** (lines 867-953, 1031-1096) | starts at `PositionOffset.Y` 6 and flies **in a straight line at 8 px/update** (Frail 10 or 6) toward `TargetPosition` on a height arc (vertical speed `V1.Y` starts at −(2 + 0.02 × distance), +0.4 per update). Solid (class 4) while `PositionOffset.Y` < 16. **Underground** (≥ 16): class 0 and invisible. It keeps about **250 px** from Isaac (accel (L − 250) × 0.003 toward or away) and drifts toward the room centre | when `V1.Y − L/20 > 15` **and L > 100 px** (L = distance to Isaac): `TargetPosition` = Isaac's position at that moment → 3 (lines 907-912) |
| **8 Attack1** (lines 1099-1108, 1162-1293) | pops up where it is, solid from the first update, still. **Shot at `StateFrame` 46** (1.5 s). Hidden (class 0) once Attack1 (91 f) ends | at `StateFrame` 105: `TargetPosition` = Isaac's position → 3 |
| **9 Attack2** (Scolex, Frail phase 2) | volley at `StateFrame` 20 (Scolex) or 47 (Frail) | at 105, as above |
| 8 / 10 lasers (Frail phase 2) | lasers, below | 3 |

**Leaps aim at Isaac's position when the previous phase ended** (stored in `TargetPosition`), **no lead**, and never
re-aim.

**Shots:**
- **Attack1, Pin (subtype 0), Scolex, Frail phase 1** (lines 1162-1276): `FireBossProjectiles(1, Isaac's position,
  trajectory 10)`, then turned into a **big high lob**: velocity × 0.55, height −40, scale 1.6, flag bit 2. Scolex fires
  it on 3 updates (46-48). Where it actually lands is unclear, because the speed is cut after aiming.
- **Pin `subtype` 1** (lines 1208-1219): fire mode 9, a **6-shot ring at speed 8**, not aimed.
- **Body segment 4** (lines 1413-1446): while the head is in State 4, high in the arc (`PositionOffset.Y` < −20),
  cooldown 30 and a 50% roll each update.
  - Pin and Frail: **fire mode 7, 4 diagonal shots at speed 5** (45°, 135°, 225°, 315°).
  - Pin `subtype` 1: a mode-9 ring at speed 8.
  - About one burst per leap.
- **Scolex Attack2:** 15 lobbed shots at Isaac's position.
- **Frail Attack2:** 12 shots with a zero target, probably scattered around itself.
- **Frail phase-2 lasers** (lines 549-827):
  - State 8: one beam **steered toward Isaac** for about 60 updates (the turn rate is unclear).
  - State 10: two fixed beams aimed at Isaac, **each after a 10-update warning line**.

**Fields:** `I1` = the last action (4 leap, 8 Attack1, 9 Attack2, 10 laser); `V1.Y` = the arc's vertical speed, which
is also the resurface timer; `TargetPosition` = the next leap's landing point; `StateFrame` = the attack timer;
`PositionOffset.Y` = height. Frail: `I2` = phase and laser countdown, `V2.X` = laser angle.

**Damage blocking:**
- **Pin:** `isInvicible` is never touched. It's protected only by collision class 0 (underground, or hidden after an
  attack).
- **Scolex** (lines 465-485): outside State 8, damage to any segment more than 2 links from the hole is set to 0. Only
  its tail end takes damage, and the head only during Attack1.
- **Frail:** revives once as phase 2.

### Bot meaning
- **Attack1 is a 46-update (1.5 s) window with the head solid and still**: the best time to shoot Pin, and the lob
  comes at `StateFrame` 46.
- **Every leap goes to where Isaac stood when the last phase ended**, read it from `TargetPosition`. It travels at a
  fixed 8 px/update in a straight line: step off that line.
- **The body's X burst** (4 diagonal shots, speed 5) comes from segment 4 at the top of the arc: stay off the
  diagonals of the body while it leaps.
- **Underground, it keeps about 250 px away.** It comes up only when Isaac is more than 100 px away, so staying
  close doesn't make it surface.
- **Scolex:** shoot the tail end; the rest takes no damage.

### Record to confirm
- After each leap ~50% Attack1; after each Attack1 always a leap; Attack1 lasts 105 updates with the shot at 46.
- `TargetPosition` = Isaac's position at the end of the previous phase (no lead); leap speed 8 px/update.
- Resurfacing: `V1.Y − L/20` crossing 15 with L > 100; the distance it keeps underground (~250 px).
- Segment 4's X bursts: speed 5, diagonals, at most every 30 updates, only high in the arc.
- Where the big lob lands. Damage to Scolex's segments in each state.

---

## Summary for the main session

Biggest bot-relevant findings, each from the code (hypotheses until recorded):

| Enemy | Key finding |
|---|---|
| Gemini 79.0/1 | **3.3 s still "tired" window (State 3, 100 updates) after every 3.3 s rage (State 8)**; the attached baby shoots only within 300 px with a clear line, ≥ 35 updates apart |
| Blighted Ovum 79.2 | its baby (79.12) is **invulnerable**: `never_aim`. Its laser **only goes sideways along its row**, triggered when Isaac is within 20 px of its row or column, with a 0.5 s warning line |
| Sloth 46.0 | attacks land **5 updates after the animation starts**; it **spawns a Charger already charging along its row** toward Isaac's side; it summons only with ≤ 3 enemies |
| Pin 62.0 | after a leap, 50% a 1.5 s still, solid Attack1; leaps go to Isaac's old position in a straight line; the body throws 4 diagonal shots at the arc's top |
| Monstro 20.0 | **landing cell readable in `TargetPosition`** at take-off; no collision while airborne (tears pass through); 13 shots at Taunt frame 21; 18 on big-jump landing |
| Attack Fly 18.0 | steers at Isaac's position from up to 2 updates ago, turn limit 1.2 per update: sharp cuts make it overshoot |
| Trite 29.1 | **15 updates of guaranteed idle after each landing**; it aims **past** Isaac (0-60%), so step sideways, not back; landing cell readable in `TargetPosition` |
| Charger 23.0 | **exact trigger:** Isaac's position + up to 16 updates of his velocity inside its 40 px tile row or column, within 200 px, clear line; no telegraph, no cooldown |

Suggested knowledge edits (for the main session, once a recording confirms them):
- `boss_tactics.json`:
  - `79.12` → `never_aim`, laser along its row only;
  - `79.0` → an attack window of `State == 3` (tired);
  - `62.0` → attack window `State == 8 and StateFrame < 46`;
  - `20.0` → dodge to leave `TargetPosition`'s cell;
  - `46.0` → stay off its row (spawned Charger).
- Enemy rules:
  - Charger → avoid its tile row and column within 200 px, including the 16-update lead;
  - Trite → sidestep, idle window `StateFrame < 15`.
- Bestiary: add the event names the code uses (`Slide` for Dingle, `Dive`/`Popup` for Pin).

---

## Recording check (2026-11-26)

Checked against real recorded fights by the outside-sources session.
- **The recording:** Sloth and its Chargers, Gurglings (237.1) and their Attack Flies, from `runs/live.log`. Samples
  are taken every 2 updates.
- **The script:** a local cross-check script (not committed).
- **Shot timing:** shots are logged on their first update, about 2 updates late. Spawns are logged on the update they
  happen.

| Claim | Recording | Verdict |
|---|---|---|
| Sloth: summon (State 8) acts at `StateFrame` 5 | 8/8 spawns at (State 8, `StateFrame` 5) | **confirmed** |
| Sloth: shoot (State 9) acts at `StateFrame` 5 | 20/20 shots logged at (State 9, `StateFrame` 7) = 5 + the logging lag | **confirmed** |
| Sloth: back to MOVE at `StateFrame` 30 | the last attack sample is 29-30, in 28 of 28 attacks | **confirmed** |
| Sloth spawns a Charger 30 px to its side, already charging (State 8, `V1` = ±1, 0) | 8/8 at ±30 px level with Sloth, State 8 on the next sample, moving sideways at 1.0-1.8 px/update | **confirmed** |
| Summons only with ≤ 3 enemies | 1-4 enemies counted in the room, Sloth included; ≤ 3 if Sloth isn't counted | consistent |
| The lob: big, slow, high (scale 1.6, flag 2) | scale 1.6, flags 2, height -45, fall -21.9, accel 1.02, speed 4.15 | **confirmed** |
| The lob is aimed at Isaac's position | **the angle error is spread over 3-177° (20 shots)**, so it isn't aimed at him on the throw update | **contradicted**; `FireBossProjectiles` scatters (see "How to read these tables") |
| Charger trigger: Isaac (+ up to 16 updates of his velocity) in its 40 px tile row or column, within 200 px | **24/24** natural charges fit in the 8 updates before the charge (the 4 misses are the Chargers Sloth spawns already charging); by chance about 40% would. Line-of-sight not tested | **confirmed** |
| `V1` = the charge step, 1.3 | `V1` length 1.3 in every Charger sample | **confirmed** |
| The same trigger runs Gurglings (type 237) | 18/18 Gurgling charges fit (by chance about 35%) | **confirmed** |
| Gurglings leave red creep while charging | main session: CREEP_RED, 16-25 per charge direction | measured (not in these tables) |
| Gemini, the Blighted Ovum, Monstro, Pin, Trite, Attack Fly | not recorded yet (Attack Flies only appeared as Gurgling spawns) | **not covered** |
---

## Host (27.0), Red Host (27.1), Hard Host (27.3)

`ai_host`, `0x5179b0` (dispatcher case `0xe` = byte at `0x6cbe5c + 17`). Shared with type 859.

**"Armored" variants** (lines 62-68): **Host (27.0) and Hard Host (27.3)**. The **Red Host (27.1)** is never armored:
it is always damageable, never wipes damage, and isn't slowed down by hits. Any variant with subtype 99 is also
unarmored.

| State | What it does | Leaves to |
|---|---|---|
| 0 init (69-85) | Idle; `isInvicible` for that one update only | 3 |
| **3 closed** (236-295) | entity flag 0x10 set (armored); the open check below; `StateFrame` = an open **delay** that counts down 1 every 7 updates (286-293) | 8 (or 9) |
| **8 attack** (321-511) | plays Shoot (61 f; Open @9, **Shoot @24**, Close @55; Hard Host 71 f), flag 0x10 cleared | 3 when the animation ends |
| 9 fake open (296-319) | the same animation with no shot; only while confused or feared, 1 in 50 per update | 3 |

### 1. The open trigger (lines 242-276)
All of these:
- `StateFrame` < 1, i.e. no hit delay left;
- checked **only 1 update in 7** (`IsFrame(7, index)`);
- **`ProjectileCooldown` < 1**: it is set to 7 at each attack and counts down only on those 1-in-7 checks, so **about
  50-56 updates closed between attacks at minimum**;
- **Isaac within 240 px** (squared distance < 57600, line 263; no square root, so exactly 240);
- **a clear line**: `Room::CheckLine` from the Host to Isaac, mode 3 (Hard Host mode 0). Champion colour 8 skips
  this check.

**No random chance, and no check of Isaac shooting or of tears flying nearby.**

What "attacking it keeps it closed" really is (lines 87-121, armored only):
- **each hit that lands on a closed Host** adds `round(damage) / 2` (integer) to its open delay, capped at 10;
- each delay unit is 7 updates, so **up to 70 updates (2.3 s) of extra delay**;
- hits under 1.5 damage add nothing; a 3.5-damage tear adds 2 (14 updates);
- more than 20 damage in one update (a bomb) plays "Bombed".
- The author's observation matches for hits. Shots that miss don't matter.

### 2. The attack (lines 471-502)
- **At the Shoot event, animation frame 24**: about 24 updates after the open starts, plus up to 7 updates from the
  1-in-7 check.
- **Aim: Isaac's current position, no lead** (475-476). The base speed is 7.0 (483-491).
- **Host: fire mode 2 (triple: 0°, ±16°). Red Host: mode 5 (five: 0°, ±12°, ±24°)** (lines 218-222).
- The params set `VelocityMulti` 1.07 (230). With FireProjectiles' ×1.2 tail for modes 2 and 5 (`RE_CORE.md`), the
  real speed is **7 × 1.2 × 1.07 ≈ 9.0** (Host's side shots 0.9 × that ≈ 8.1; all five Red Host shots ≈ 9.0). The
  Host doesn't move, so the 0.4 × shooter-velocity term is 0.
- **This matches the recorded Host shot speed of 8-9.**
- **Hard Host:** no Shoot event, so no projectiles. On its Close event (frame 54) it slams instead: an effect aimed at
  Isaac, debris, and a push on players within 120 px (lines 372-470).

### 3. How long it stays open
- **Damageable from the Open event (frame 9) until the Close event (frame 55): about 46 updates (1.5 s).**
- The whole attack lasts 61 updates, then it's back to State 3 with `StateFrame` 0.

### 4. Vulnerability (lines 87-103, armored only)
While closed (State 3), or in the attack before Open or after Close, **every queued damage record is zeroed**. That
is the same queue wipe as the Haunt's, with one exception: records whose damage flags include `0x8000` (probably
burn/poison-type damage) keep their damage.

There's no collision-class change: tears still hit it and are used up, they just do nothing. Flag 0x10 (probably
NO_TARGET) is set while closed, so homing tears ignore it.

### Bot meaning
- **The bait spot:** the trigger needs Isaac **within 240 px with a clear line**. Bait from about 200-230 px, not 100.
  - The attack fires 24 updates after opening.
  - The triple then needs about 22-25 updates to cross 200-230 px at about 9 px/update.
  - That's roughly 1.5 s from the open to the shots arriving, to sidestep the ±16° spread.
- **At 100 px the shots arrive about 11 updates after firing, with the spread only about 28 px wide**, which fits the
  recorded hits at 6-14 px.
- **Holding fire while it's closed is right.** Each landed hit (≥ 1.5 damage) delays the open by up to 2.3 s, and the
  damage is thrown away anyway.
- Shoot only between frames 9 and 55 of its Shoot animation (`State == 8`). It then stays closed for at least about
  50 updates.
- **The Red Host can be shot any time** (no armour), but fires 5 shots.

### Record to confirm
- Opens only with Isaac within 240 px and a clear line; never beyond 240; a rock between blocks it.
- Shots at animation frame 24: Host 3 shots, about 9.0 centre and 8.1 sides; Red Host 5 at about 9.0; aimed at
  Isaac's position, no lead.
- At least about 50 updates closed between attacks; each landed hit while closed adds about 7 × round(damage)/2
  updates of delay.
- HP unchanged when hit closed (Host, Hard Host); always damageable (Red Host).

**Review:** **all agree** (me and both blind readers: one on Sonnet, B9 bundle in `runs/research/re/core/B9`) on
every number above.
- **Settled by C:** the "Open" event name (`DAT_00b82628` is the string "Open").
- **Settled by C:** the real shot speed, from the ×1.2 tail in `RE_CORE.md`. The readers couldn't see it, so both
  said "7 × 1.07 if applied".
