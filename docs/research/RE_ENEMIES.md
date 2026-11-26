# Decompiled enemy AI: our worst hit sources (2026-11-26)

Method, build and rules: see `RE_PILOT.md` (same build, same pipeline). This file has one section per enemy.

**Recording check (2026-11-26):** Sloth, Charger and the Gurgling charge trigger were checked against real recorded
fights. See "Recording check" at the end of this file for what's confirmed, contradicted or not covered.

**Check labels (added 2026-11-26; feeds `knowledge/enemy_cards.json`, see `docs/FORECAST_PLAN.md` "The fallback").**
- **Format:** every fact has `[category · batch address · checked]`.
  - **Category:** move / attack / timing / body / terrain.
  - **Checked:** `1 reader` / `2 readers` / `recording` / `contradicted`.
- **From Batch E3 on, the label sits on each bullet.**
- **Earlier batches (this file, `RE_CORE.md`, `RE_PILOT.md`) were labelled here, as tags only, with no re-reading.**
  Every fact from those batches is `2 readers` (both blind readers, or one reader plus the community decomp for the
  pilot), except the ones below.

| Fact | Label |
|---|---|
| Dingle: the Idle ≤ 30 gate; 3 dashes; the 12-15 pause; Tired 61-90; the dash aimed at Isaac's position; the Spit triple at ±16° | `[timing/move/attack · pilot 0x4898c0 · recording]` |
| Dingle: spit speeds 10 / 9 | `[attack · pilot 0x4898c0 · contradicted]` (really 12 / 10.8, the hidden ×1.2) |
| Haunt: attack gap > 60; no damage in State 4; pinned to the top wall; the spit straight down | `[timing/body/move/attack · pilot 0x4855e0 · recording]` |
| Lil' Haunt: 200 px shot range; no damage while orbiting; speed 10 | `[attack/body · pilot 0x4855e0 · recording]` |
| Lil' Haunt: shot led 5 updates | `[attack · pilot 0x4855e0 · contradicted]` (it aims at his position) |
| Sloth: StateFrame 5; the Charger spawn (30 px, already charging); attack end at 30; the lob shape | `[timing/attack · worst-8 0x4780e0 · recording]` |
| Sloth: the lob aimed at Isaac | `[attack · worst-8 0x4780e0 · contradicted]` (it isn't aimed at him) |
| Charger and Gurgling: the charge triggers; V1 1.3; the Gurgling charge speed and creep | `[timing/move/terrain · worst-8 + E1 0x534300 · recording]` |
| Shots: the spread tail ×1.2 / 0.4; the Host's shot speed; Gurdy's shot speed | `[attack · L1 0x6d2bb0, Host, E1 0x480bf0 · recording]` |
| Hazards: spikes 2; bomb damage 2; creep 1 damage; the curse door 1 damage | `[terrain · E2 0x725e10, E2/E2c 0x705fe0, A, E2c 0x7136e0 · recording]` |
| Physics and speed: the one-step enemy physics; the Gaper's angry speed | `[move · D 0x6b5720, B · recording]` |
| Isaac's top speed 2.07 | `[move · L2 0x781fc0 · contradicted]` (fixed to ≈ 8.8, the hidden sqrt in the friction) |

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

---

## Gapers (10.0 Frowning Gaper, 10.1 Gaper, 10.2 Flaming Gaper), and others sharing `ai_gaper`

`ai_gaper`, `0x50f730` (dispatcher case 0x0). It also runs 208 Fatty, 252, 257 Conjoined Fatty, 284 Cyclopia and 302
Stoney. Gaper 10.3 is handed to `0x4e0e20` (lines 73-78).

**Calibration: PASS.** The community `Isaac/Content/Actor/Enemy/Gaper.lua` has the same speed table (0.6 / 0.3 /
0.33 / 0.48 / 0.9 / 0.498 / 0.5478 / 0.72) and the same path marker (900, or 100 for Stoney).

**Movement** (lines 529-576):
- **It always chases.** There's no wander and no distance trigger: `PathChase(Isaac's position, speed, 900, true)`
  every update, which goes straight at him within 70 px with a clear line and follows the grid otherwise
  (`RE_CORE.md`).
- **Speed factor by variant:**
  - **10.0: 0.6, rising to 0.72** once its face overlay has played (lines 552-554, 615-620);
  - **10.1: 0.498**;
  - **10.2: 0.548**;
  - Fatty 0.3; Stoney 0.48 or 0.6; 252: 0.9.
- **Feared:** flees (`0x7ece80`), friction × 0.8.

**Attacks:** none for 10.x. Fatties and 257 have their own attack blocks (lines 268-460). On death, Gaper-family
entities can spawn or morph into 11.0 / 11.1 (Gusher / Pacer, line 226); the exact condition is in lines 207-267.

**Fields:** `+0xc34` = the current speed factor. No `I1`/`I2`/`V1`/`V2` use for 10.x. **Damage blocking:** none.

### Bot meaning
- A Gaper heads straight at Isaac whenever there's a clear line within 70 px, otherwise along the grid path: it
  **never stops chasing**.
- **Derived top speed** (`RE_CORE.md`, Batch D physics step): about **4.0 px/update for 10.0 (4.8 angry), 3.3 for
  10.1**. That's close to Isaac's walking speed, so measure it before relying on kiting.
- 10.0 speeds up (0.72) once angry.

**Review:**
- **All agree** (two blind readers, one on Sonnet).
- **Settled by calibration:** the community file matches every speed.
- **Unresolved:** the exact death-morph condition.

**Record:** Gaper speed per update while chasing (10.0 before and after its overlay, 10.1); that it always chases.

---

## Spiders (85.0 Spider; also 94 Big Spider, 215, 250 Ticking Spider, 869)

`ai_spider`, `0x530540` (dispatcher case 0x39).

**The cycle** (State 4, lines 135-359):
- **Wait:** it idles until `StateFrame` > 13 (lines 150-153), about **15 updates (0.5 s)** after each dart ends.
- **Then pick a dart:**
  - **At Isaac** (lines 155-178) if he's **within a random 100-200 px** (threshold `100 + 100 × rand`, re-rolled each
    pick) **and there's a clear line**.
  - **The dart point = Isaac's position + 10 × his velocity: it leads him by 10 updates** (lines 166-169).
  - Otherwise **a random spot 70-110 px away** that's free and in line (lines 182-221).
- **Dart:** accelerates at 6.0 per update toward the point (type 869: 4.5) over friction (× 0.6 per update) (lines
  311-340).
  - It ends within 14 px of the point, or when slow (speed < 3) with its timer run out (lines 316-331).
- **Jumpers (215, 250, 869):** 1 in 3 picks becomes a jump (State 6) to that point instead (lines 224-241).
- **94 Big Spider:** the same movement; splits into 85.0 spiders on death (lines 383-389).
- With collectible 377 held (and not friendly), spiders go "inert": random darts only (lines 58-104).

**Fields:** `TargetPosition` = the dart point (zero = idle); `StateFrame` = the idle/dart timer.
**Damage blocking:** none in this function.

### Bot meaning
- **A spider within 100-200 px with a clear line darts at where Isaac will be in 10 updates.** Running straight makes
  it intercept you. **Change direction right after it starts a dart**: it doesn't re-aim mid-dart.
- **It always pauses about 15 updates between darts:** a safe window to step past or shoot it.
- Beyond 200 px, or behind a rock, it only darts randomly.

**Review:** **all agree** (two blind readers, one on Sonnet): the 10-update lead, the 100-200 range, the 15-update
pause, 6.0 accel, the 14 px arrival.

**Record:**
- The dart target vs Isaac's position + 10 × velocity at the pick;
- no aimed darts beyond 200 px or without line of sight;
- the pause length between darts.

---

## Batch C (2026-11-26): Dart Fly, Ring Fly, Swarm, Squirt, Globin, Widow

Two blind readers per bundle (C1: the four fliers/Squirt; C2: Globin and Widow), one on Sonnet. My own read of the Dart
Fly matched both readers. **All agree** unless a line says otherwise.

**Shared fly prologue** (Dart Fly, Ring Fly, Swarm): with collectible 9 (Skatole) held and the fly not friendly, its
AI is switched off.

### Dart Fly (256.0), `0x5468e0`
- **Steering, every update** (lines 43-84):
  - accel = 0.0225 × (13.5 × direction to Isaac's **current position** + a figure-8 wobble of strength 10);
  - the wobble phase is +0.188 rad per update: a 33-update y cycle and a 67-update x cycle;
  - **speed cap 8 px/update**, friction × 0.95.
- **No lead, no line of sight, no pauses, no attack.**
- **Bot:** it homes at about 0.3 px/update² with a ±0.225 wobble and tops out at 8. A sharp sidestep beats it, because
  its turn is slow; it never predicts you.

### Ring Fly (222.0), `0x542340`
- **A group circles one moving centre** (lines 56-203). The first Ring Fly is the leader.
- **The centre moves toward Isaac at 2 px/update**, no lead.
- **The radius breathes 40 ↔ 70 px** at 0.5 px/update (about a 4 s cycle).
- **The ring spins 5.4° per update** (a turn every 2.2 s). The flies are spaced evenly and fly to their slot at
  6 px/update.
- It ignores rocks (grid class 0).
- **Bot:** the danger is the ring's band of 40-70 px around a centre that drifts at you. Stay outside 70 px of the
  centre (`TargetPosition`), or go through the middle when the radius is near 70.

### Swarm (281.0), `0x547600`
- **The leader spawns 4 followers** (5 in total) within 10 px (lines 45-84).
- **The centre moves toward Isaac at 5 px/update** (no lead). Each fly springs to it (0.03 × offset) with a random buzz
  of up to 0.8, orbiting at 5° per update (half of them each way), friction × 0.8.
- They repel each other within about 50 px. When the leader dies, a follower takes over.
- **Bot:** a cloud that follows Isaac's position at 5 px/update. Out-turn it rather than out-run it.

### Squirt (220.0, also type 871), `0x53bae0`
- **Idle (State 3):** a 1-in-5 roll on every 5th update starts the attack, so on average about 25 updates (0.8 s)
  between attacks. **No distance or line-of-sight check** (lines 262-306).
- **Wind-up (State 8):** at its animation's "Slide" event it adds **20 / friction** toward Isaac's **current
  position** (no lead) (lines 432-492).
- **The slide:** at least 10 updates with a small forward push, then it brakes. Back to idle when speed < 1.
- **Variant 1** leaves creep (1000.26) every 3rd update while sliding.
- **On death:** 2 × Dip 217.0; variant 1 makes 2 × Clot 15.1; 871 makes 2 × type 870.
- **Bot:** a dash at where you stand when the Slide event fires. Step sideways at that frame. The dash is fast (about
  20 px/update at the start) and short.

### Globin (24.0 Globin, 24.1 Gazing, 24.2 Dank, 24.3 Cursed; also 278 Black Globin), `0x514cd0`
- **Chase:** PathChase to Isaac's current position at speed factor **0.75** (Gazing 24.1: **1.1**; Black Globin 0.6).
  No lead (lines 245-271).
- **"Dies" into a pile** (lines 347-359): killed while walking (State 4) means **dead is cancelled, health set to 10,
  "ReGen" plays, State 3**. When the ReGen animation finishes it walks again.
  - **Killed while it's a pile (State 3), it dies for good.**
  - **There's no damage blocking**: the pile is fully damageable.
- **Gazing Globin's pile** slides away from Isaac at 0.5 per update while he's within 200 px (lines 296-316).
- **Dank Globin** drops black creep (1000.26) on every fall, and a Spider (85.0) on each revive while the room has under
  7 enemies.
- **Cursed Globin (24.3)** may split on death; the chance falls with each generation (subtype). The halves are briefly
  invulnerable (`isInvicible`, `I1` countdown).
- **Black Globin (278):** throws a spider at the point 75% of the way to Isaac every 5 HP lost; dies into a head
  (279) and a body (280).
- **Bot:** after it falls (`State == 3`), **keep shooting the pile**. Finishing it there kills it for good; otherwise
  it stands up with 10 HP.

### Widow (100.0; 100.1 The Wretched), `0x473b20`
- **Every update:** collision class 2, grid class 5; friction × 0.8.
- **Idle (State 4):**
  - **a 1-in-3 roll with Isaac more than 100 px away → jump;**
  - otherwise: the Widow (variant 0) jumps if the room has more than 5 enemies, or if she just summoned (`I1` ≥ 1);
  - failing those, she picks one of idle / State 8 / State 9 (lines 515-633).
- **Jump (State 6):**
  - velocity **7 × direction to Isaac's current position, fixed when the jump starts** (no lead);
  - **airborne (between its two animation events): collision class 0**, so no contact either way;
  - the landing crushes other NPCs (100 damage), not Isaac (lines 440-513, 617-633).
- **State 8, Widow (variant 0):** summons a Sack (30.2; 30.0 or 94.0 Big Spider by subtype) **30 px below herself**,
  if fewer than 3 exist. **The Wretched (variant 1):** an **8-way ring at speed 10** (fire mode 8, fixed angles).
  Then both spread a **creep ring** outward, 3 px per step (1000.25, slowing; 1000.26 for subtype 1).
- **State 9:** spiders (1-2 thrown near herself). The Wretched sometimes sends a Trite at Isaac. A Widow subtype sends
  Attack Flies, or a 6-shot ring at speed 8 (mode 9).
- **Bot:**
  - she's **untouchable mid-jump** (class 0);
  - her jump goes where Isaac was, so move after she leaves the ground;
  - **expect a jump whenever you're more than 100 px away** (1 in 3 per update);
  - The Wretched's ring is fixed: stand off its 8 lines;
  - the creep ring slows you.

**Review:** all agree, except:
- **the Widow jump rule: settled by C** (lines 519-535). Both readers' phrasings match the code once read together.

**Unresolved:**
- the creep lifetimes (`+0x45c` = 60 / 210, unconfirmed as timeouts);
- the Squirt's wind-up length (it's an animation event frame; not in our bestiary extract).

### Record to confirm (Batch C)
- **Dart Fly:** |velocity| ≤ 8; heading follows Isaac's position, not a lead.
- **Ring Fly:** centre speed 2, radius 40-70, spin 5.4° per update.
- **Swarm:** centre speed 5.
- **Squirt:** the dash at the Slide event toward Isaac's position then; about 25 updates between dashes.
- **Globin:** dies for good only when hit in State 3; revives with 10 HP.
- **Widow:** collision class 0 mid-jump; jump direction = Isaac's position at take-off; jumps only on a 1/3 roll when
  Isaac is beyond 100 px.

---

## Batch E1 (2026-11-26): Gurgling, Gurdy, Gurdy Jr., Duke of Flies / Husk, Gaping Maws

Two blind readers per bundle (E1a: Gurdy and Gurdy Jr.; E1b: Duke, Maws, Gurgling), one on Sonnet; all agree unless
noted.
- Gurdy Jr.'s states were read from annotated assembly, because its C stops at a jump table.
- **Gurdy calibration: PASS.** The community `Gurdy.lua` has the same y ≤ 200 / > 7 / < 14 conditions, the y = 400
  teleport, the ±40/−65 fly spawns at velocity −20, and the five-spread spray.

### Gaping Maw (235.0) and Broken Gaping Maw (236.0), `0x527530` (shared with 42 and 203)
- **It's pinned to its tile and can't be damaged** (`isInvicible` is set at init and never cleared here, lines
  76-121).
- **The suction** (lines 263-329), every update while active:
  - it pulls **every live player, tear and enemy projectile** toward the Maw;
  - **strength = k × (300 − distance) / 300**, clamped 0..k, with **k = 0.6 for Isaac** (0.9 for tears and shots);
  - so **0.6 at contact, 0.3 at 150 px, none beyond 300 px**;
  - **no line-of-sight check: it pulls through rocks;**
  - it's added as `velocity += speedMultiplier × strength × direction / friction`.
- **When it's active:**
  - **235** is always on while the room isn't cleared;
  - **236** runs a cycle of `StateFrame % 240`: **on for about 150 updates (5 s), off for 90 (3 s)**, and only pulls
    while its "Sucking" overlay plays.
- **It never shoots** (the shooting code in this function belongs to type 42).
- **Bot meaning:**
  - Isaac's own input accel is 0.6 × k per movement step (`RE_CORE.md`). **Near the Maw the pull equals his full
    walking acceleration:** within about 100 px he can barely move away.
  - **Stay beyond 300 px**, or at least far enough that the pull (0.6 × (300 − d)/300) is well under his acceleration.
  - Watch 236's on/off cycle.
  - **His own tears get bent toward it (0.9).**
  - This is likely what killed the furthest run: being pulled into enemies or shots while fighting near it.

### Gurgling (237.0 / 237.1 boss / 237.2 Turdling), in `ai_charger` `0x534300`
- **Idle:** random axis-aligned walking at 0.6 (the trigger is in `RE_CORE.md`).
- **The charge:** V1 = 1.3 × axis direction (boss subtype 1: 1.95), fixed. Each update friction × 0.9, then V1 is added
  again (line 680).
  - **Steady speed ≈ 12-13 px/update.**
  - **There's no lane centring for 237** (lines 692-706; other chargers snap to the tile centre).
- **Tears bend it:** a sideways push (knockback) is never corrected, so the Gurgling keeps charging in a shifted lane.
  Pushes along its axis are absorbed. (Unresolved: the size of the sideways drift.)
- **A charge ends** on a wall or rock hit, a stall (6 updates barely moving), or confusion/fear. Then State 3:
  - 237.0 fires a **ring, mode 9 (vector 7.5, 6): 6 shots at 7.5**;
  - the Turdling spawns 4 Dips (217.2);
  - the boss sometimes spawns flies.
- **The creep trail:** while its speed is above 3 px/update, it spawns **red creep (1000.22)** (Turdling: 1000.94) at
  sprite scale 1.23. It spawns at most once per update; the gate's rate is unresolved. Lifetime: the creep effect's
  defaults.
- **Bot meaning:**
  - a fast (≈ 12 px/update) straight charge that doesn't recentre;
  - shooting it from the side nudges it out of line;
  - **its charge path becomes red creep**, so don't cross its trail;
  - after it stops, a 6-shot ring.

### Gurdy (36.0), `0x480bf0`
- **Never moves** (pinned to its spot).
- **At room start it places Isaac at (Gurdy's x, y = 400)** (lines 83-116).
- **After each idle animation:**
  - **summon** if `rand % 3 == 0`, **or Isaac's y ≤ 200**, or there are more than 7 enemies. It summons only while
    there are fewer than 14 enemies: a Pooter, 2 Attack Flies, or 2 Boils at fixed spots.
  - Otherwise **a five-spread (mode 5, about 12 px/update), not aimed:**
    - down (when Isaac is below and more vertical than horizontal);
    - otherwise left or right, toward Isaac's side (lines 362-408, 297-332).
- **Bot meaning:**
  - stay **below y = 200 and level-ish with it**. Directly above, it only summons;
  - its sprays go in 3 fixed directions, picked by where Isaac is: stand diagonally below it, out of all three fans;
  - **killing its spawns keeps the count under 7**, which brings back the spray (not summon) pattern.

### Gurdy Jr. (99.0), `0x523bd0` (states from assembly)
- **Stationary** except for its charge.
- **The cycle:** every return to State 3 adds 1 to a counter. **It charges on the 3rd return, or always once its HP is
  below 100.** Otherwise it picks at random from:
  - State 6, a pause of 36 updates;
  - State 9, an **8-way ring at speed 10** (12 in one mode), fixed angles;
  - State 10, a Pooter.
- **The charge** (State 8): aimed at **Isaac's current position** when it starts (no lead), adding 4 per update over
  friction 0.8 (≈ **20 px/update** at most, during the launch animation). Then it slides with almost no friction until
  speed < 2 or 10 slide loops.
- **Bot meaning:**
  - **watch the counter (`ProjectileCooldown` +0xba0 == 2 means the next idle charges)**;
  - below 100 HP every idle charges;
  - sidestep at launch: the direction is fixed;
  - the 8-way ring is fixed: stand off its lines.

### The Duke of Flies (67.0) / the Husk (67.1), `0x472210`
- **Movement:** it **doesn't chase Isaac**. It drifts diagonally and bounces off walls (± sign kept until a wall).
  Speed per axis ≈ 2 (Husk 4; subtypes 2.5 or 5.5), clamped 40 px inside the room.
- **States** (each lasts 40 updates; it keeps moving):
  - **13, release** (at frame 20): **3 Attack Flies** (18.0) **parented to the Duke**, with no cap unless a game flag
    is set (then 6 − existing). The Husk swaps the 3rd fly for a spider thrown at Isaac.
  - **14, big spawn** (frame 18): one bigger fly (18 / 80 / 61 by subtype), if there are fewer than 5. The Husk instead
    fires **10 boss shots aimed at Isaac**.
  - **8, burst** (frame 17): **its attached flies are blasted outward at 18 and detached**. The Husk also fires a
    ring (mode 9, vector (8, 8)).
- **Picking a state:** random per update (1/40 release, 1/70 big spawn, ...), gated by enemy counts.
- **Why corners trap Isaac:**
  - the Duke itself ignores him;
  - its attached flies orbit it about 65 px out (Attack Fly AI);
  - **the burst throws them outward at 18**, then they chase Isaac at 0.3 px/update² (Attack Fly AI). In a corner the
    detached flies converge from the open side.
  - Unresolved (the Attack Fly AI is the driver).
- **Bot meaning:**
  - kill flies while they're still attached (they orbit slowly);
  - expect a burst (State 8) to scatter them fast;
  - fight in the open, not in a corner.

### Record to confirm (E1)
- **Maw:** Isaac's velocity change toward it ≈ 0.6 × (300 − d)/300 per update; none beyond 300 px; pulls through rocks;
  236's on/off timing.
- **Gurgling:** charge speed ≈ 12-13; sideways drift after a tear hit; red creep along the path while fast.
- **Gurdy:** summons whenever Isaac's y ≤ 200; the spray direction by Isaac's side; the start position y = 400.
- **Gurdy Jr.:** a charge every 3rd idle (always below 100 HP); charge peak speed.
- **Duke:** flies parented until State 8; burst speed 18; release every ~40 updates on average.

## Batch E3 (2026-11-26): the sins (Gluttony, Envy, Pride, Lust, Greed, Wrath)

Two blind readers (Sonnet and Haiku), per the reading policy for bosses and minibosses. Disagreements were settled in
the C by the write-up session; each is noted where it happened. Labels: `[category · batch address · checked]`.
- **No sin blocks damage or reads the damage queue.** Their hits all land normally. `[body · E3 all six · 2 readers]`
- **Speeds:** every sin multiplies its friction each update and adds `push / friction`, so the steady speed is
  `push / (1 − f)` (the physics step in `RE_CORE.md`, Batch D). The figures below use that formula, assuming the base
  friction is 1. A recording confirms them.
- **The lists below give variant 1 (Super) only where it differs.**

### Gluttony (49.0, Super 49.1), `0x532ed0` (shared with types 39 and 836)
- **Walk:** a random axis walk at 0.7, with friction × 0.8. No chase. `[move · E3 0x532ed0 · 2 readers]`
- **It decides only every 3rd update** (`IsFrame(3)`). `[timing · E3 0x532ed0 · 2 readers]`
- **The fat attack (State 8):**
  - **Trigger:** a 1-in-7 roll per decision, then **Isaac closer than a random 70-200 px**.
    `[timing · E3 0x532ed0 · 2 readers]`
  - **What fires:** on the anim's "Shoot" event, **an 8-way ring (mode 8) at 8 px/update**. It is 12 when an unknown
    helper (`0x6dfc20`) returns ≥ 1. `[attack · E3 0x532ed0 · 2 readers]`
  - **Super only:** it also fires **5 boss shots** at Isaac's current position (within ±30°, speed 3.5-10.5).
    `[attack · E3 0x532ed0 · 2 readers]`
- **The laser (State 9):**
  - **Trigger:** used when the fat attack didn't go (the 1/7 roll hit but Isaac was too far, or a 1/10 roll hit). It
    also needs all of these: `[timing · E3 0x532ed0 · 2 readers]`
    - **Isaac within 20 px of its row or column;**
    - **closer than 400 px;**
    - **Gluttony on screen;**
    - not under a status flag (`0x1000a00`; probably fear or confusion).
  - **Tell:** the "Attack01" Up/Down/Horiz animation ("Attack02" for Super). `[attack · E3 0x532ed0 · 2 readers]`
  - **The beam:** fixed at the "Shoot" frame, along the axis toward Isaac from its side (pos.x + 6 × dir.x, offset −20
    up). Very likely cardinal, not aimed. `[attack · E3 0x532ed0 · 2 readers]`
  - **Super fires two beams**, the second the mirror image (opposite side). `[attack · E3 0x532ed0 · 2 readers]`
  - The laser's lifetime and frame number are not in this function.
  - *Settled:* one reader read a laser angle of 190 / −10. The C writes 3000.0 or −10.0 into laser field +0x358,
    picked by the aim's y. It's probably the draw depth, not an angle.
- **It stands still** during both attacks until the animation ends. That's the opening.
  `[move · E3 0x532ed0 · 2 readers]`
- It stamps 900 into the room grid under itself (likely "blocked" for pathing). `[terrain · E3 0x532ed0 · 2 readers]`

### Lust (47.0, Super 47.1), `0x478cf0`: no states, pure chase
- **Line of sight clear:** it pushes 0.65 toward **Isaac's position + 10 × his velocity** (a 10-update lead), with
  friction × 0.95. That gives a **steady speed ≈ 13 px/update**, the fastest sin. `[move · E3 0x478cf0 · 2 readers]`
- **Line blocked:** the path chase toward Isaac's current position at 0.996 (≈ 6.6 px/update), with no lead.
  `[move · E3 0x478cf0 · 2 readers]`
- **No attack; contact damage only.** It never stops. `[attack · E3 0x478cf0 · 2 readers]`
- **Super:** spawns effect 1000.22 (red creep, as the Gurgling trail) every 7th update. `[terrain · E3 0x478cf0 · 2 readers]`
  - The readers didn't name that effect. The red-creep id comes from Batch A, so check it in a recording.

### Wrath (48.0, Super 48.1), `0x479000`
- **Walk:** a random axis walk at 1.0, with friction × 0.85. `[move · E3 0x479000 · 2 readers]`
- **After a bomb:** it walks randomly only within 130 px of its bomb, and otherwise stands still. `[move · E3 0x479000 · 2 readers]`
  - *Settled:* the "Wrath: Evade own bomb" line is only a debug log. There's no hidden evade code.
- **Plain bomb:** a 1 / max(60, distance) chance per update (≈ 1/60 when Isaac is within 60 px, rarer when far). It
  plays "Attack" and drops a bomb in place. `[timing · E3 0x479000 · 2 readers]`
- **Aimed attack:**
  - **Prediction:** it predicts Isaac at his position + a random 0-16 × his velocity.
  - **Conditions:** the prediction must be within 20 px of Wrath's row or column, **closer than 200 px**, and on a clear
    line. `[timing · E3 0x479000 · 2 readers]`
  - **50/50:** a **thrown bomb** (10 px/update along that axis) or a **charge** along it.
    `[attack · E3 0x479000 · 2 readers]`
- **The bomb:**
  - spawned at the 6th update of State 9 (stateFrame > 4) on Wrath's tile centre;
  - variant 0 (normal) or **4 (Super: mega troll bomb)**;
  - its fuse comes from `RE_CORE.md` E2c: 45 updates for variant 0, 45-74 for variant 4.
  `[attack · E3 0x479000 · 2 readers]`
- **The charge:**
  - push 1.5, friction × 0.68, so a **steady speed ≈ 4.7 px/update**;
  - it's **pulled 10% per update toward its lane's centre**;
  - **it ends only on a wall or rock hit**. `[move · E3 0x479000 · 2 readers]`
- **Rest:** **61 updates (≈ 2 s) after each bomb before the next attack**; none after a charge.
  `[timing · E3 0x479000 · 2 readers]`

### Greed (50.0, Super 50.1), `0x479910`
- **Walk:** a random axis walk at 1.0, with friction × 0.75. `[move · E3 0x479910 · 2 readers]`
- **Choosing an attack:** each update a 1-in-50 chance; then a 1-in-3 roll leads to **summon** if the room has fewer
  than 3 enemies (a room-counter sum), and otherwise to **shoot**. `[timing · E3 0x479910 · 2 readers]`
- **The shot:** `[attack · E3 0x479910 · 2 readers]`
  - aim locked at stateFrame 1 (the direction to Isaac × 10; likely cardinal, with 4 animations);
  - **fires at stateFrame 5**: **mode 2, a triple** (Super: **mode 4**, four);
  - ≈ 12 px/update after the ×1.2;
  - it ends at stateFrame > 24.
- **The summon:** at stateFrame 5, two **Hoppers (type 29)** (Super: **two type 86**) near Greed ±50 px; it ends at
  stateFrame > 26. `[attack · E3 0x479910 · 2 readers]`
  - *Settled:* one reader called these coins. They're NPC types; the pickup-spawn helper is only used to find a free
    spot.
- **The gun:** a promo-only gun (a game flag and a room-type check; the asset path is a promo folder). With it, Greed
  walks at 1.5, adds a 1/20 shot chance and fires at stateFrame 17 at double speed with recoil. Not normal play.
  `[attack · E3 0x479910 · 2 readers]`
  - *Settled:* one reader saw a contradiction in the exits. It was pointer arithmetic in the C; the exits are clean
    (> 24 without the gun, > 20 with it).
- **It stands still while shooting or summoning.** `[move · E3 0x479910 · 2 readers]`

### Envy (51.x: tens digit = size, units digit 1 = Super), `0x47a480`
- **Movement:** `[move · E3 0x47a480 · 2 readers]`
  - **no chase:** a constant diagonal push whose signs follow its current velocity, so it **drifts diagonally and
    bounces off walls**;
  - push size k × an unseen constant: k = 0.25 (biggest), 0.35 (10s and 30s), **0.45 (20s, fastest)**;
  - friction × 0.9;
  - it starts at a random angle.
- **When feared** (`flags & 0x1000800`), it pushes away from Isaac: full at ≤ 70 px, none at ≥ 120.
  `[move · E3 0x47a480 · 2 readers]`
- **No attack; contact damage only.** `[attack · E3 0x47a480 · 2 readers]`
- **The death split:** `[attack · E3 0x47a480 · 2 readers]`
  - **2 children** (variant + 10) at ±10 px along a random angle, **flying apart at 4 px/update**;
  - **Super variant 1 always adds a 3rd** (perpendicular); variant 11 adds one 50% of the time; variant 21 never;
  - variants 30+ don't split;
  - normal Envy goes 1 → 2 → 4 → 8.
  - *Settled:* one reader gave the child speed as 0.4 × 10 = 4 and the other as 4. Same number.
- **Child HP:** the 10s ÷ 3, the 20s ÷ 4, the 30s ÷ 5 (of the config HP). `[body · E3 0x47a480 · 2 readers]`
- **A wall at y = 320**, only when the room's boss id (+0x1bb0, `_bossId` in the field table) is 55. That is
  probably the Mega Satan arena (unconfirmed). Corrected in E3b from "room kind". `[terrain · E3 0x47a480 · 2 readers]`

### Pride (52.0, Super 52.1), `0x47e160`
- **Walk:** a random axis walk at 1.0, with friction × 0.75. `[move · E3 0x47e160 · 2 readers]`
- **Choosing an attack:** each update a 1-in-50 chance, then 50/50 between **lasers** (State 8) and **bombs**
  (State 9). Each state lasts 46 updates and Pride **stands still** throughout. `[timing · E3 0x47e160 · 2 readers]`
- **The lasers:** `[attack · E3 0x47e160 · 2 readers]`
  - a warning sound at stateFrame 12;
  - at **20**, **four beams on the diagonals (45°, 135°, 225°, 315°)** from 10 px above Pride;
  - Super adds a **6-shot ring at 8** from 20 px below it.
  - **8 updates of warning; the straight rows and columns are safe.**
- **The bombs:** **troll bombs (variant 3)** at stateFrame 6, 11, 16, 21 (four). Super: **mega troll bombs (4)** at
  6 and 11 (two). `[attack · E3 0x47e160 · 2 readers]`
  - They're placed at positions from `0x81baf0` (likely random), with no velocity; fuse 45-74 (E2c).
- The beams' lifetime is unresolved (one reader saw 17 in a register argument).

### Bot meaning (E3)
- **Gluttony:** don't stand on its row or column within 400 px (the laser), and keep out of 70-200 px (the 8-ring).
  Diagonal and mid-range is safest. Attack while it stands still after an animation.
- **Lust:** too fast to outrun in the open (≈ 13), and it leads Isaac by 10 updates. **Change direction rather than
  run straight.** Breaking line of sight halves its speed.
- **Wrath:**
  - don't line up within 200 px;
  - **after any bomb, 2 s of free damage**;
  - its charge is slow (≈ 4.7) and lane-locked, so step off the lane.
- **Greed:** a triple shot after a 5-update tell, aimed once. Sidestep after the tell. It summons Hoppers when the room
  has fewer than 3 enemies.
- **Envy:** a bouncer, like the Duke. The 20s are the fastest; don't sit in a corner where splits converge.
- **Pride:** on the laser tell, **stand on its row or column** (the diagonals are the beams). Bomb phase: troll bombs
  around the room; move away from new bombs.

### Record to confirm (E3)
- **Gluttony:** 8-ring speed 8 vs 12; the laser fires along an axis and both sides for Super; the attack range 70-200.
- **Lust:** steady speed ≈ 13 in open sight vs ≈ 6.6 around rocks; the lead point (10 updates); whether the Super
  trail is red creep.
- **Wrath:** the 61-update rest after a bomb; charge speed ≈ 4.7; 50/50 bomb or charge; the Super bomb variant.
- **Greed:** fire at stateFrame 5, ≈ 12 px/update; summon type 29 (Hoppers).
- **Envy:** child speed 4; the 3rd child for Super; push per size.
- **Pride:** diagonal beams at stateFrame 20 after a sound at 12; bomb count 4 vs 2; state length 46.

## Batch E3b (2026-11-26): the horsemen (Famine, Death, Pestilence, War, Conquest)

Two blind readers (Sonnet, Haiku). Disagreements and lost arguments were settled by the write-up session in the C and
the annotated assembly (`probe dis:`). Ghidra lost every spawn argument in Death and War's fire mode; the assembly
gave them back. Shared facts:
- **Friction and speeds:** all four multiply friction by 0.8. Steady speed = push / (1 − f), as in E3.
- **The hard-mode boost:** "×1.25 in hard mode" means `0x6dfc20 > 0` or `game+0x26e68` is 1 or 3. That's Hard or
  Greedier, likely but not confirmed.
- **Bit 60** of the entity flags, likely "friendly", swaps in other behaviour. The lists below cover normal (hostile)
  fights only.
- **The y = 320 floor** in their code applies only when the room's boss id is 55 (see the Envy note). It doesn't apply
  in normal fights.

### Famine (63.0; subtype 1 = the alternate colour), `0x45a8d0`
- **Phase 1, State 4, floating:** `[move · E3b 0x45a8d0 · 2 readers]`
  - an unnamed move helper (`0x7eeba0`);
  - y is held at ≥ 170 (it never goes into the top strip);
  - grid class 3.
- **The summon (State 13):** a 1-in-40 chance per update when the room has fewer than 3 enemies.
  `[timing · E3b 0x45a8d0 · 2 readers]`
  - On the anim's "Shoot" event it spawns **one Pooter (14.0) 50 px away** (subtype 1: a **6-shot ring at 8**
    instead).
  - It ends with the animation.
  - `[attack · E3b 0x45a8d0 · 2 readers]`
- **The dash (State 8):** `[timing · E3b 0x45a8d0 · 2 readers]`
  - **Trigger:** when Isaac is **within 20 px of its row** (subtype 1: or a 1-in-4 roll), then a 1-in-5 roll; not while
    confused or feared.
  - **Tell:** a sound and "AttackDashStart". The dash launches on that animation's "Shoot" event.
  - **Movement:** **velocity.x = ±18** (22.5 in hard mode), set every update, **toward Isaac's side**, grid class 2.
    `[move · E3b 0x45a8d0 · 2 readers]`
  - **Lap:** it **runs 200 px off-screen, reappears 80 px beyond the other edge, and stops when it gets back to its
    starting x**. One full lap across the screen.
  - **Subtype 1** also steers up or down toward Isaac (at most 0.4 per update before friction).
- **Below 33% HP: the head phase (State 9)**, permanent. The horse bursts (effect 1000.2) and the head stays.
  `[body · E3b 0x45a8d0 · 2 readers]`
  - **The shot:** `[attack · E3b 0x45a8d0 · 2 readers]`
    - **Trigger:** cooldown ≤ 0 and the can-shoot check passes (range set in a register, unreadable).
    - **Tell:** "HeadAttack"; the cooldown is re-armed to **8**.
    - **On the "Shoot" event:** a **triple (mode 2) aimed at Isaac: centre 10 × 1.2 = 12 px/update, sides 10.8 at
      ±16°** (subtype 1: 10 boss shots).
    - *Settled:* one reader read the aim as 10 / distance. With the hidden sqrt it's a unit vector × 10, which matches
      the 11.9 px/update shots in live run 1.2.49.
  - **Cadence:** a shot about every 9 updates while the can-shoot check passes. `[timing · E3b 0x45a8d0 · 2 readers]`
  - **Movement:**
    - it **only moves while it can't shoot** (cooldown ≤ 0 and check false);
    - then it chases at push 0.5, a **steady ≈ 2.5 px/update**;
    - in range it stands and shoots.
    `[move · E3b 0x45a8d0 · 2 readers]`

### Death (66.0 rider, 66.10 scythe, 66.20 horse, 66.30 on foot), `0x45d9b0`
- **Rider (66.0), at 50% HP or more, State 4:** it walks, and each update rolls three things in turn:
  `[timing · E3b 0x45d9b0 · 2 readers]`
  - 1/90 → **State 13**, when enemy count A − B < 1 or 2;
  - 1/180 → the **hourglass** (State 8), subtype 0 only, and only while the room slow timer is 0;
  - 1/100 → **State 14**, when A − B < 4.
- **State 13:** at stateFrame 20, **2 scythes (66.10)** at free spots more than 150 px from Isaac (subtype 1: **2
  Kamikaze Leeches, 55.1**, at ±50 px). It ends at stateFrame > 48. `[attack · E3b 0x45d9b0 · 2 readers]`
  - The spawn types come from the assembly.
- **State 14:** at stateFrame 18, **up to 4 scythes**, one at each room edge on Death's row and column: (left, y),
  (right, y), (x, top), (x, bottom). Each is skipped when within 80 px of Isaac. `[attack · E3b 0x45d9b0 · 2 readers]`
  - These wait and then home (below). The state ends at stateFrame > 48.
- **The hourglass (State 8):** at **stateFrame 22** (≈ 0.73 s of tell after the roll): `[timing · E3b 0x45d9b0 · 2 readers]`
  - **Isaac is slowed:** `AddSlowing(160 updates, value 0.9)` on every player, so **5.3 s** of slow.
    `[move · E3b 0x45d9b0 · 2 readers]`
    - What 0.9 means to the engine (×0.9 or a strength) is unresolved.
  - **The room slow timer** (`room+0x7244`) is set to at least 160. Two other game functions read it.
    `[move · E3b 0x45d9b0, 0x659930, 0x6c09f0 · 1 reader (write-up session)]`
    - While it's above 0, **friendly NPCs (entity flag `0x20000000`) and shots with projectile flags `0x80000080`
      run at half speed**.
    - **Ordinary enemies and enemy shots are not slowed by it.**
    - A third reader of the timer is a 46 KB function, probably the tear update, so **Isaac's tears are probably
      halved too (unproven)**.
  - **No re-cast while the timer runs:** 160 updates, then a 1/180 roll, so **about 11 s apart** on average. The
    state lasts 53 updates and Death attacks nothing else meanwhile.
- **Scythes (66.10):** `[move · E3b 0x45d9b0 · 2 readers]`
  - health 15, collision class 2 (touches Isaac and tears), **grid class 0 (flies over rocks)**, friction × 0.975;
  - **State 14 scythes** wait still for 80 − 0.1 × (distance to Isaac) updates, then push 0.75 along a helper's
    vector (`0xa29990`, likely toward Isaac) and vanish after 180 updates;
  - **State 13 scythes** push 0.5 every update and have no timer;
  - both vanish beyond 250 px of an anchor (unresolved which).
  - **Homing is likely but not proven:** the helper's body is unread, and the readers flag that the steady speed would
    be implausible (≈ 20-30) if it were a unit vector.
- **Below 50% HP (State 6):** an animation, then **it morphs to 66.30 and spawns the horse 66.20** 15 px to its side.
  `[body · E3b 0x45d9b0 · 2 readers]`
  - *Settled:* one reader called 66.20 a scythe. The assembly shows the split spawning 66.20 and morphing into 66.30.
- **The horse (66.20):** `[move · E3b 0x45d9b0 · 2 readers]`
  - **velocity.x = ±18** every update (22.5 in hard mode); collision class 4, grid class 2;
  - it **wraps 200 px off each side, and each wrap moves it down 0.3 × the room height** (back up near the bottom), so
    it sweeps lane by lane;
  - **it never aims in y**;
  - a sound plays once per pass when it's within 150 px of Isaac's x;
  - it drains 1 HP per update while within 40 HP of the rider.
- **On foot (66.30):** walks. 1/90 → State 13: at stateFrame 16, **2 Knights (41.0)** (subtype 1: 2 Red Maws, 26.1)
  at ±10 px. It ends at stateFrame > 41. No hourglass. `[attack · E3b 0x45d9b0 · 2 readers]`

### Pestilence (64.0; subtype 1 alternate), `0x45b4d0`
- **Phase 1:** a random axis walk at 1.0. Each update: `[timing · E3b 0x45b4d0 · 2 readers]`
  - 1/40 → **summon**, when the room has fewer than 4 enemies;
  - otherwise 1/20 and **Isaac within 230 px** → **Attack1**.
- **Attack1:** **one boss shot at Isaac, trajectory 10, lobbed and green** at stateFrame 22 (subtype 1: a 6-shot ring
  at 8, from 30 px above). It ends at 40. `[attack · E3b 0x45b4d0 · 2 readers]`
- **Summon:** at stateFrame 25, **2 of Charger (23.0) or Spitty (31.0)** at ±10 px (subtype 1: one Trite, 29.1). It
  ends at 57. `[attack · E3b 0x45b4d0 · 2 readers]`
- **Below 50% HP: headless** (i1 = 1). **Stationary**, with the same rolls: `[body · E3b 0x45b4d0 · 2 readers]`
  - **the shot** at stateFrame 9 (ends at 29);
  - **the summon** at 25: **1-2 Attack Flies (18.0)** 40 px to its side (subtype 1: a thrown spider at 19).
- Passive trail effects: 1000.7 every 3rd update (subtype 0), and 1000.23 (green creep) / 1000.25 every 7th. Whether
  they hurt is unresolved. `[terrain · E3b 0x45b4d0 · 2 readers]`

### War (65.0) and Conquest (65.1), `0x45c500`
- **State 4:** a walk; x is clamped inside the room. Each update, in order: `[timing · E3b 0x45c500 · 2 readers]`
  - 1/90 and **Isaac within 200 px** → the shot;
  - 1/200 when farther than 150 px, or 1/30 when **Isaac is within 20 px of its row** → the **dash**;
  - otherwise 1/180 → the **jump**.
- **The shot (State 8):** at stateFrame 5. `[attack · E3b 0x45c500 · 2 readers]`
  - **Mode 8, an 8-way ring at 10** (12 in hard mode), lobbed (height −45, fall 7.0). **Subtype 1 uses mode 6**.
  - *Settled from the assembly:* both readers had lost the mode.
  - It ends at 38.
- **The jump (State 6):** `[body · E3b 0x45c500 · 2 readers]`
  - **untouchable from stateFrame 21** (collision class 0, no shadow);
  - **drops** from stateFrame 32, one every 5 updates: `[attack · E3b 0x45c500 · 2 readers]`
    - War: **5 troll bombs (4.3)** at spots from `0x81baf0` (subtype 1: 2 mega troll bombs, 4.4);
    - **Conquest: 15 light beams (effect 1000.19)** at random spots, **every 5th aimed at Isaac's position + 0.2 ×
      distance × his velocity**;
    - *Settled:* 2.8e-45 is 2, not the "4" one reader read.
  - It lands after 5N + 113 updates: **War 138, Conquest 188**.
  - It then **charges in from the side away from Isaac** (x ≤ 320 → enters from the right).
- **The dash (State 9):** `[move · E3b 0x45c500 · 2 readers]`
  - **±18 px/update** (22.5 in hard mode) once "DashStart" ends;
  - **3 wraps, each moving it down 0.3 × the room height**;
  - it ends back at its start x.
  - **Conquest** spawns clones (65.1, parented, sharing damage) at the 2nd crossing, in spread lanes.
  - **War subtype 1** drops a troll bomb after each wrap.
- **Conquest shares damage:** a hit on one is applied to every clone. `[body · E3b 0x45c500 · 2 readers]`
- **War below 50% HP:** it morphs to **65.10, on foot**: `[move · E3b 0x45c500 · 2 readers]`
  - a path chase at 0.5 rising to ≈ 1.35;
  - it **re-enters State 8 after losing about 75-82 HP since its last attack**;
  - subtype 1 fires a 6-shot ring at 10 at stateFrame 3.

### Bot meaning (E3b)
- **Famine:**
  - **stay off its row** in phase 1: the dash is a full-screen lap at 18;
  - **below 33%, the head stands and fires a 12 px/update triple about every 9 updates while it can see Isaac.**
    Break line of sight or move sideways between shots; it only creeps (≈ 2.5) when it can't shoot.
- **Death:**
  - **the hourglass** slows Isaac for 5.3 s, about every 11 s at most. The bot's movement model must apply the slow
    while it lasts; record the real factor.
  - **State 14 scythes come from the four edges on Death's row and column after a delay**: step off its row and column
    when its State 14 animation starts.
  - **Below 50%, the horse sweeps rows at 18.** Watch its lane, which drops 0.3 × the room height per wrap.
- **Pestilence:** a slow single lobbed shot; its summons are the danger. Below 50% it's stationary: free damage.
- **War:**
  - stay off its row (the dash);
  - the 8-ring needs Isaac within 200 px;
  - **during the jump it's untouchable**, and bombs fall at random spots;
  - after landing it charges from the side away from Isaac.
  - **Conquest:** dodge the aimed light beam (every 5th) and the clone charges.

### Record to confirm (E3b)
- **Famine:** head-phase shot speed 12 / 10.8 (matches 1.2.49?); about 9 updates between triples; the can-shoot range
  (≈ 140 px in 1.2.49?); the 33% threshold; the dash lap at 18.
- **Death:**
  - Isaac's speed during the hourglass (the factor for 0.9), the 160-update duration and the ≈ 11 s gap;
  - **whether Isaac's tears halve while the room timer runs**;
  - whether the scythes home in, and their speed;
  - the horse lanes.
- **Pestilence:** the 230 px attack range; the summon types.
- **War:** the 8-ring at 10; the jump bomb count (5); the 138-update airtime; the dash entry side.

## Batch E4 (2026-11-26): Big Spider, Fatty, Round Worm, Wall Hugger, Boom Fly, Pooter, Horf, Maggot, Hopper; Fat Bat, Tumor, Mega Maw

**Reading:**
- One Haiku reader for the plain enemies. It flagged new logic in five (Round Worm, Wall Hugger, Boom Fly, Fat Bat,
  Tumor), so those got a second reader (Sonnet).
- Horf stayed at one reader.
- Mega Maw is a boss: two readers.

**Already decoded** (their functions were read in earlier batches; tags only, no re-reading):
- **Big Spider (94.0):** `ai_spider` `0x530540`. The Spiders section: spider movement; splits into 85.0 spiders on
  death. `[move · B 0x530540 · 2 readers]`
- **Fatty (208.x):** `ai_gaper` `0x50f730`. The Gapers section: path chase at 0.3. `[move · B 0x50f730 · 2 readers]`
- **Pooter (14.x):** the fly AI `0x50d3c0`. The Attack Fly section: cooldown 35, can-shoot range **200 px**.
  `[attack · worst-8 0x50d3c0 · 2 readers]`
- **Maggot (21.0):** `ai_charger` `0x534300`, in its non-charging group (`RE_CORE.md` charge trigger).
  `[move · L1 0x534300 · 2 readers]`
- **Hopper (29.0):** `0x52cd30`. The Trite section. `[move · worst-8 0x52cd30 · 2 readers]`

### Round Worm (244.0), `0x544cd0` (shared with 244.1-3, 255 Night Crawler, 276, 289)
- **The cycle:** "DigIn" → hidden (State 4) → "DigOut" with one shot → "DigIn". `[timing · E4 0x544cd0 · 2 readers]`
  - **Hidden:** collision class 0 and invisible, so **it can't be hit or touch Isaac**. `[body · E4 0x544cd0 · 2 readers]`
  - When the dig-in ends it hides only if an unnamed threshold (`+0x14`) is below its health; otherwise it re-emerges
    at once.
- **The teleport while hidden:** `[move · E4 0x544cd0 · 2 readers]`
  - each update, a 50% chance to jump to the **room centre + 60-310 px in a random direction** (clamped, a free spot);
  - **only if that spot is 100-1000 px from Isaac** (a squared compare; both readers agree).
  - The exit from hiding goes through a helper whose argument was lost, so **the hide duration is unresolved**.
- **The shot:** on the DigOut "Shoot" event (anim-timed), **one shot at 10 px/update**, mode 0. It needs line of sight.
  `[attack · E4 0x544cd0 · 2 readers]`
  - **Aim: Isaac's position + 10 × his velocity**, cut short where a wall would stop him (a laser-style ray), clamped
    20 px inside the room.
  - **It leads his movement.**
- Emerged: collision class 4.

### Wall Hugger (218.0), `0x51bbb0` (shared with type 40 and 862)
- **Invulnerable**, set at spawn and never cleared in this function. `[body · E4 0x51bbb0 · 2 readers]`
- **Movement:** `[move · E4 0x51bbb0 · 2 readers]`
  - it moves one 40 px grid cell at a time, with push 3.0 and friction × 0.6, so a **steady ≈ 7.5 px/update**;
  - it's snapped onto the grid line;
  - **at a blocked cell it turns a quarter (the side is kept by a flag)**;
  - it turns back toward the wall when the wall side opens. It never looks at Isaac.
  - It starts toward the first blocked neighbour.
  - A target it can't reach (< 2 px of progress) is dropped after ≈ 8 updates.
- **The spikes:** no contact damage for the first **30 updates after spawning** ("No-Spikes"); then contact damage
  from its config (sound 0xcd). `[timing · E4 0x51bbb0 · 2 readers]`
  - In a room with a flag bit set (likely cleared), or with trinket 151, it shows "No-Spikes" with no damage, and
    coasts.

### Boom Fly (25.x), `0x515a80`
- **Movement:** `[move · E4 0x515a80 · 2 readers]`
  - **no chase:** a diagonal bounce, push 0.45 per axis in the sign of its velocity, friction × 0.9, so **≈ 4.5 px/update
    per axis (≈ 6.4 diagonal)**;
  - Red Boom Fly (25.2) 0.4;
  - 0.25 when anyone holds collectible 9.
- **When feared:** it pushes away from Isaac, full within 70 px, none beyond 120.
  - *Settled:* one reader read this as a squared distance. The hidden sqrt is there, so it's the real distance.
- **Death effects:** `[attack · E4 0x515a80 · 2 readers]`
  - **25.0: an explosion, damage 40.** By `RE_CORE.md` E2, that's radius 75 and **half a heart to Isaac** (< 85).
  - **25.2:** the same explosion, plus a mode-6 burst at 8 (10 in hard mode), and a 1/3 chance of a Charger 23.1 at
    half HP.
  - **25.3:** one stationary shot.
  - **25.4:** a 3-shot ring (mode 9) at 9 (10 in hard mode), aimed by axis. 25.4 also shoots while alive: when Isaac is
    lined up within 20 px of its row or column, closer than 200 px (with a 0-16 update lead) and on a clear line, a
    single shot at 10.
  - **25.5:** explosion 40, a 6-ring at 10, and 8 drifting effects (1000.141).
  - **25.6:** a delayed blast. It goes **invulnerable** (collision 0) during "Explode", then explodes with damage 80 and
    radius × 1.5 (≈ 112 px).
    - *Settled:* one reader read 85.0. The constant is 80.0.
  - **Other variants:** a 6-ring at 8 (10 in hard mode).

### Horf (12.0), `0x519880` (1 reader)
- **Stationary turret** (friction only). `[move · E4 0x519880 · 1 reader]`
- **The shot:** `[attack · E4 0x519880 · 1 reader]`
  - **trigger:** cooldown ≤ 0 and the can-shoot check passes (range in a register, unreadable);
  - **cooldown 28 updates** (14 in hard mode);
  - **tell:** "Attack";
  - on its "Shoot" event, **one shot aimed at Isaac's position at 7 px/update** (10 in hard mode), mode 0.
  - The reader's velocity-pointer slip is a decompiler alias; the aim vector is built at lines 108-116.

### Fat Bat (258.0), `0x546d20`
- **Flies 30 px up** (a sprite offset).
- **Movement:** `[move · E4 0x546d20 · 2 readers]`
  - **chase toward Isaac's nearest row or column** (only 20% of the way along the main axis): push 0.45, applied
    before friction × 0.8, so **≈ 1.8 px/update**;
  - **it dodges sideways** (perpendicular) from up to 4 nearby things moving toward it within 100 px. What those
    "things" are is unresolved, likely tears.
- **The shot:** `[attack · E4 0x546d20 · 2 readers]`
  - **trigger:** cooldown 0, a 1/15 roll, **within 40 px of Isaac's row or column**, Isaac within 750 px;
  - "Shooting", then on its event **one aimed shot at 10**;
  - cooldown 30. No dive.

### Tumor (229.0, 229.1), `0x51f6e0` (shared with 91, 230, 253)
- **Movement:** `[move · E4 0x51f6e0 · 2 readers]`
  - **no chase:** a diagonal bounce (as the Boom Fly), push 0.45 (229.1: 0.81), friction × 0.77 × 0.9;
  - **≈ 1.5 per axis** (229.1: ≈ 2.6);
  - it nearly stops during "ShootDown".
- **229.0:** a 1/100 roll per update (not while confused or feared) → "ShootDown" or "ShootUp" toward Isaac's side. On
  its event, a **6-ring at 10**. `[attack · E4 0x51f6e0 · 2 readers]`
- **229.1:** "Shoot" spawns **1-2 orbiting shots at 8** (they circle it for up to 80 updates). "Blow" **releases every
  orbiting shot at 10** along its path. `[attack · E4 0x51f6e0 · 2 readers]`
  - "Blow" is picked once 3+ shots orbit (random) or 6+ (always).
  - Its orbiting shots are released when it dies.

### Mega Maw (262.0), `0x462df0` (boss, 2 readers)
- **A turret:** it's pulled back to its spawn point every update; it spawns 60 px higher. `[move · E4 0x462df0 · 2 readers]`
- **It decides every 20 updates** (10 below 30% HP). `[timing · E4 0x462df0 · 2 readers]`
  - **25%, only when Isaac is more than 40 px below it:** a **15-shot boss burst at Isaac** (aim dropped to Isaac.y + 100
    when he's level with or above it).
  - otherwise **1/3: "FireRing":** `[attack · E4 0x462df0 · 2 readers]`
    - 9 shots at 10, or 5 at 10 + 5 at 7;
    - **projectile variant 2**, height 18.5, **VelocityMulti 1.05, so the real speeds are 10.5 and 7.35**;
    - orbit/curve flags 0x800 / 0x1000.
    - These are the 9.2 shots at 10.5 in the hit log. `[attack · E4 0x462df0 · recording]`
  - The 15-shot burst is plain `FireBossProjectiles`: projectile variant 0, lobbed, speed 3.5-10.5. It matches the
    lobbed 9.0 shot at 7.7 in the hit log. `[attack · E4 0x462df0 · recording]`
  - **Summon:** on every 2nd tick, 50%, when there are 4 or fewer enemies: **one Hopper (29.0) thrown 150 px below it**.
    `[attack · E4 0x462df0 · 2 readers]`
- **Subtype 1** fires rings back to back: 9 at 15; 4 × 10 at 12, 10, 8, 6; 7 × 10 at 4-10 in a cone toward Isaac; or
  4 × 10 curving.
- **Subtype 2** throws 1-2 spiders near Isaac instead of summoning.
- *Settled:* one reader called the damage-7.0 switch a 50% coin. It's a flag check (`0x418940(0, 0x10000000)`), not
  random.

### Bot meaning (E4)
- **Round Worm:** untouchable while hidden. **It aims where Isaac will be in 10 updates**, so change direction when it
  surfaces.
- **Wall Hugger:** invulnerable; don't shoot it. It runs along walls and rocks at ≈ 7.5. Keep off the room edges and
  rock edges in its path. Its spikes are harmless only for its first 1 s.
- **Boom Fly:** **don't kill it at point blank.**
  - The blast is radius 75 (half a heart); 25.6 is ≈ 112 px after a delay.
  - 25.2, 25.4 and 25.5 add shot rings.
- **Horf:** a single shot at 7 about every 28 updates. Sidestep.
- **Fat Bat:** it lines up with Isaac's row or column (within 40 px), then shoots. Stay diagonal to it.
- **Tumor 229.1:** shots orbit it, then fly out at 10 when it "Blows". Don't stand next to it.
- **Mega Maw:** stand level with or above it (no 15-shot burst). Clear Hoppers to keep summons going instead of shots.

### Record to confirm (E4)
- Round Worm: hide duration; shot lead (10 updates); 100-1000 px teleport range.
- Wall Hugger: ≈ 7.5 px/update; spikes off for 30 updates.
- Boom Fly: blast radius 75 and half-heart damage; 25.6 delay and radius.
- Horf: 28-update cooldown and 7 px/update shot.
- Fat Bat: the 40 px line-up trigger; 1.8 px/update chase; what it dodges.
- Tumor: 6-ring at 10; orbit then release at 10.
- Mega Maw: the 15-shot burst only when Isaac is below; ring speeds 10 and 7.

(Also from this batch: **tears run at × 0.75 while Death's hourglass timer runs**. The tear update `0x66dc80`
multiplies a tear scale by 0.75 when `room+0x7244 > 0`. `[move · F1 0x66dc80 · 1 reader (write-up session)]`)

## Batch E5 (2026-11-26): floors 1-2 regulars

**Reading:** one Haiku reader per half. Both halves showed new logic, so every type except Embryo got a Sonnet second
reader. Clotty's fire mode was settled from the assembly.

**Already decoded** (earlier batches; tags only):
- **Sucker (61.0)** and **Moter (80.0):** the fly AI `0x50d3c0` (Attack Fly section). `[move · worst-8 0x50d3c0 · 2 readers]`
- **Night Crawler (255):** the Round Worm function. Its own branch is below.

**Shared blocks:**
- "flees when it sees Isaac" = `EvadeQ` (flee) after a can-see check;
- "wanders" = `MoveRandomlyBoss`;
- explosion damage 40 → half a heart to Isaac (`RE_CORE.md` E2).

### Clotty (15.0 Clotty, 15.1 Clot, 15.2 I. Blob, 15.3), `0x513b70`
- **Movement:** wanders (hop animation), friction × 0.9. It flees when feared. **It stands still while attacking.**
  `[move · E5 0x513b70 · 2 readers]`
- **Trigger:** it attacks whenever the wander routine reports a new target (no range or line-of-sight check).
  - 15.3 skips every 4th trigger.
  - The attack state lasts the "Attack" animation (timeout 30 updates, 15 for 15.3).
  `[timing · E5 0x513b70 · 2 readers]`
- **The shot** (on the "Shoot" event): `[attack · E5 0x513b70 · 2 readers + asm]`
  - **15.0:** mode 6, 4 shots on the axes (+);
  - **15.1:** mode 7, 4 on the diagonals (X);
  - **15.2:** mode 8, 8-way;
  - all at **7 px/update** (10 in hard mode);
  - **15.3:** a 4-shot ring at 7 (8 in hard mode), randomly rotated 0-9°.
  - One reader guessed mode 6 for every variant; the assembly gives the 6/7/8 split.
- 15.0 and 15.3 swap with each other depending on a room water amount (`room+0x7258` vs 0.2). `[body · E5 0x513b70 · 2 readers]`

### Mulligan (16.0; 16.1; 16.2 Mulliboom), `0x5123d0`
- **16.0 / 16.1:** **flees when it can see Isaac**, otherwise wanders; friction × 0.8. `[move · E5 0x5123d0 · 2 readers]`
  - While touching a wall, a 1/300 chance per update to **explode**:
    - "Explode" overlay → explosion damage 40 (radius 60) and a **mode-6 4-shot + at 7** (10 in hard mode);
    - then it dies.
    `[attack · E5 0x5123d0 · 2 readers]`
- **Death:** `[attack · E5 0x5123d0 · 2 readers]`
  - **16.0:** up to 4 flies, each a Fly 13 (7/11), Pooter 14 (1/11) or Attack Fly 18 (3/11), within 6 px;
  - **16.1:** a mode-7 4-shot X at 7 plus a troll bomb (4.3).
- **16.2 (Mulliboom):** **chases at 1.2**. **Within 40 px of Isaac it blows up** (damage 40, radius 60; no shots).
  `[attack · E5 0x5123d0 · 2 readers]`

### Hive (22.0; 22.1 Drowned; 22.2 Holy; 22.3), `0x512b60`
- **Movement:** **flees when it can see Isaac**, otherwise wanders; friction × 0.8 (22.1: × 0.76).
  `[move · E5 0x512b60 · 2 readers]`
- **The spawn attack:** `[timing · E5 0x512b60 · 2 readers]`
  - **Trigger:** cooldown ≤ 0, **Isaac within 300 px**, a clear line, and not feared or confused.
  - **Cooldown:** **75 updates** (22.3: 210). It's padded by 20-69 when the room already has many enemies (a chance
    that rises from 1/5 at 4 enemies to always at 8 or more).
  - Out of range, it re-checks after 3 updates; blocked line, after 7.
  - **What it spawns:** `[attack · E5 0x512b60 · 2 readers]`
    - 22.0: an Attack Fly (18);
    - 22.1: a Charger 23.1 at half HP;
    - 22.2: a type 38.1 launched sideways at 8;
    - 22.3: 6 linked type-222 minions.
- **Death:** ceil(4 / (enemies × 0.2 + 1)) flies (Fly / Pooter / Attack Fly); 22.1 drops Chargers, 22.2 drops Embryos
  (77). `[attack · E5 0x512b60 · 2 readers]`

### Embryo (77.0), `0x510ea0` (1 reader)
- It wanders; it flees when feared; it stops on its "Landed" event; friction × 0.8. No attack. `[move · E5 0x510ea0 · 1 reader]`

### Para-Bite (58.0; 58.1 Scarred), `0x52a980`
- **Movement:** **path chase at 0.8**. `[move · E5 0x52a980 · 2 readers]`
- **Digging:** each update a 1/30 chance to dig. `[timing · E5 0x52a980 · 2 readers]`
  - **"DigIn":** it re-rolls a random room spot each update, accepting only spots **130-1000 px from Isaac** on a free
    cell.
  - When DigIn ends it **teleports there** and plays "DigOut".
  - **Untouchable** (collision 0) from DigIn frame 8 until DigOut frame 3. It stands still while digging.
    `[body · E5 0x52a980 · 2 readers]`
- **58.1 only:** **one shot at 7 along its own movement direction** (not aimed at Isaac). Cooldown 40-59, start delay
  5-24; it only fires while moving and not feared. `[attack · E5 0x52a980 · 2 readers]`

### Mr. Maw (35.0 body, 35.1 head; 35.2 / 35.3 red; 35.10 neck), `0x51e6a0`
- **Body:** **chases at 0.6** (red: 0.8). The head rides it. `[move · E5 0x51e6a0 · 2 readers]`
- **The head lunge:** `[attack · E5 0x51e6a0 · 2 readers]`
  - **Trigger:** every 4th update, when **Isaac's position + 3 × his velocity is within 130 px** and the line to him is
    clear.
  - **Launch: 14 px/update** in that fixed direction.
  - It's pulled back toward the body (pull 0.7 → 1.4, rising friction): ≈ 40 updates, peaking ≈ 110 px out.
  - The neck is visual only.
- **Death:** `[body · E5 0x51e6a0 · 2 readers]`
  - when the head dies, the body becomes a Gusher (11) at full HP;
  - when the body dies, the head becomes a Maw (26; red → Red Maw);
  - the red head's death fires a mode-6 4-shot + at 8.

### Knight (41.0; 41.1 Selfless; 41.2 Loyal; 41.3; 41.4 Black), `0x519dd0`
- **Walk:** a random axis walk at 0.75 (41.1: 1.25; 41.2: 0.6; 41.4: 0.66), friction × 0.8. `[move · E5 0x519dd0 · 2 readers]`
- **The charge:** `[attack · E5 0x519dd0 · 2 readers]`
  - **Trigger:** every 3rd update, when Isaac's position + 0-16 updates of lead is **within 20 px of the Knight's row or
    column, within 200 px**, on a clear line.
  - **Movement:** along that axis, push 1.0 (41.1: 1.65), so **≈ 5 px/update** (41.1: ≈ 8.25); lane-centred.
  - **It ends only on a wall or rock hit.**
  - **41.4** accelerates up to push 4 (≈ 20). A hard wall hit stuns it for 45 updates.
- **Front armour is not in this function.** It's probably the directional-shield check (`CanBeDamagedFromVelocity`)
  seen in F1's tear collision. `[body · E5 0x519dd0 · 2 readers]`
- **41.3 is invulnerable**, bound to a type 840. A killed 41.2 turns into 41.3. `[body · E5 0x519dd0 · 2 readers]`

### Wall Creep (240.0-240.3), `0x542930`
- **Movement:** it sticks to the nearest wall and **crawls along it toward Isaac's x (top/bottom walls) or y (side
  walls) at a fixed 5 px/update** (240.1 / 240.3: 3.5). It stops within 10 px of lining up.
  `[move · E5 0x542930 · 2 readers]`
- **The attack:** `[timing · E5 0x542930 · 2 readers]`
  - **Trigger:** cooldown < 0 and **on screen**; no range or line-of-sight check, no aiming.
  - **Cooldown:** 15-59 updates after each attack.
  - **What it fires:** `[attack · E5 0x542930 · 2 readers]`
    - **240.0 / 240.2:** **one shot at 8 straight out of the wall** (240.2: homing 0.8);
    - **240.1:** a **90-update stream, a shot every 2 updates (≈ 45)**, at 8 out of the wall;
    - **240.3:** a shot every 3 updates (mode 4, unresolved).

### Spitty (31.0, 31.1) and Leech (55.0; 55.1 Kamikaze; 55.2), `ai_charger` `0x534300`
- **Spitty:** a random axis walk at 0.72, friction × 0.85. `[move · E5 0x534300 · 2 readers]`
  - **The spit:** a 1/35 chance per update (no range check) → **one shot at 8 along its facing axis** (not aimed).
    `[attack · E5 0x534300 · 2 readers]`
  - **31.1:** 10 shots at 18 down that axis, plus 3-4 boss shots. On death, two 8-shot rings at 8.
- **Leech:** a walk at 0.85. `[move · E5 0x534300 · 2 readers]`
  - **The charge:** checked every 4th update, when the led Isaac (0-16 updates) is **within 20 px of its row or column**
    on a clear line. **No range limit.** `[attack · E5 0x534300 · 2 readers]`
  - **Movement:** push 1.55, friction 0.9, so **≈ 15.5 px/update**, lane-centred.
  - It ends on a wall, 6 stuck updates, or fear.
  - **55.1 and 55.2 explode on death** (damage 40, radius 60). `[attack · E5 0x534300 · 2 readers]`

### Leaper (34.0, 34.1) and Ragling (246.0, 246.1), `ai_hopper` `0x52cd30`
- **Hops** (shared): `[move · E5 0x52cd30 · 2 readers]`
  - **Near Isaac** (Leaper: within 130 px): it hops at his position (Ragling overshoots by 0-60%).
  - Otherwise it hops 95 px (Ragling 95-215) in a random direction.
  - Ragling waits 15 updates between hops.
- **Leaper's big leap:** `[attack · E5 0x52cd30 · 2 readers]`
  - about 1/7 per landing (not while feared), **aimed at Isaac's position**;
  - **untouchable while airborne** (collision 0);
  - landing: **34.0 fires a mode-6 4-shot + at 9** (12 in hard mode); 34.1 fires 6 boss shots.
- **Ragling:** 1/3 per hop decision → "Appear", then **two shots at 7: one at Isaac, one directly away**.
  `[attack · E5 0x52cd30 · 2 readers]`
  - 246.1 revives (invulnerable) while its Rag Man parent lives.

### Night Crawler (255.0), `0x544cd0` branch
- **Cycle:** DigIn → hidden (untouchable; teleports 50% per update to room centre + 60-310 px, only 100-1000 px from
  Isaac) → DigOut. `[move · E5 0x544cd0 · 2 readers]`
- **On DigOut's "Shoot" event:** a **mode-6 4-shot + at 10** with orbit flag 0x800. Not aimed.
  `[attack · E5 0x544cd0 · 2 readers]`

### Bot meaning (E5)
- **Fleers (Mulligan, Hive):** they run when they see Isaac. Corner them.
  - A **Mulliboom explodes within 40 px**: shoot it from range.
  - A Hive spawns every 75 updates within 300 px. Kill it fast or break line of sight.
- **Mode-6 crosses** (Clotty 15.0, Leaper, Night Crawler, Red Mr. Maw, the Mulligan blast): stand diagonal to the
  source. **Clot 15.1's X**: stand on its row or column.
- **Lane chargers** (Knight ≈ 5-8, Leech ≈ 15.5): don't line up within 20 px of their row or column. The Leech has no
  range limit.
- **Mr. Maw:** keep more than 130 px from its head, allowing for his own 3-update lead.
- **Wall Creep:** never stand in front of it along its wall's normal; it lines up with you at 5 px/update.
- **Para-Bite:** untouchable while digging; it reappears 130-1000 px away.

### Record to confirm (E5)
- Clotty 6 / 7 / 8 modes at 7.
- Hive's 300 px range and 75-update cooldown.
- Mulliboom's 40 px trigger.
- Mr. Maw's 130 px lunge at 14.
- Knight charge ≈ 5 and Leech ≈ 15.5.
- Wall Creep 5 px/update and its shot at 8.
- Para-Bite teleport ranges.
- Leaper 4-shot at 9.

## Batch G1a (2026-11-26): first floors 3-6 commons

**Readers:** two Haiku readers on halves of the batch, then a Haiku second reader on every type that showed new logic
(everything below marked `2 readers`). Names are from the knowledge files.

### Bony (227.0), Holy Bony (227.1), Black Bony (277), `0x53f3d0`
- **Walk:** a random axis walk at 1.25, friction × 0.8. `[move · G1 0x53f3d0 · 2 readers]`
- **The shot:** every 3rd update, when Isaac's position + 0-16 updates of lead is **within 20 px of its row or column**,
  **under 200 px**, on a clear line. **One shot at 10** (mode 0), one per attack animation.
  `[attack · G1 0x53f3d0 · 2 readers]`
- 227.1 computes a lob from the distance, but the fixed speed 10 is what is passed to the shot. `[attack · G1 0x53f3d0 · 2 readers]`
- **Black Bony explodes on death:** damage 40 (half a heart), radius 60. `[attack · G1 0x53f3d0 · 1 reader]`

### Skinny (226.0) and Rotty (226.1), same function
- Path chase at 0.5; flees when feared; no attack. Rotty's death: 50% back to a full-HP Bony (227.0), otherwise 1-2
  Attack Flies. Skinny 226.2 runs its own function (`0x550b30`, unread). `[move/attack · G1 0x53f3d0 · 1 reader]`

### Death's Head (212.0), Dank Death's Head (212.1), `0x539550`
- **212.0 is invulnerable from spawn**; 212.1 is not. `[body · G1 0x539550 · 2 readers]`
- **Movement:** a diagonal bounce (push 0.45 per axis by velocity sign, friction × 0.9), so **≈ 4.5 px/update per axis**.
  No chase, no attack. `[move · G1 0x539550 · 2 readers]`
- When the room is clear, 212.0 goes untouchable and stops mattering. `[body · G1 0x539550 · 2 readers]`

### Buttlicker (89), Grub (239), Larry Jr. (19.0), The Hollow (19.1), `0x46e060`
- **Heads** walk a random axis walk at 2.0; followers do not steer. `[move · G1 0x46e060 · 2 readers]`
- **Grub charge:** after about 51 updates, when the led Isaac is within 20 px of its row or column on a clear line:
  push 3.7, friction × 0.9, **until a wall** (≈ 33 px/update by formula: check in recording).
  On death 2-5 spawns of Charger (23), Spitty (31) or 21. `[attack · G1 0x46e060 · 2 readers]`
- **Larry Jr. / The Hollow shots** (head, subtype 1): **7.5 px/update**, single (19.0) or triple (19.1), cooldown
  40-59, tried on a 1/3 roll once the cooldown is up. `[attack · G1 0x46e060 · 2 readers]`
- **The Hollow** also drifts toward Isaac within 160 px (full pull inside ≈ 93 px), bouncing off the room edges.
  `[move · G1 0x46e060 · 2 readers]`
- Tails drop poops. All segments share the lowest HP. `[body · G1 0x46e060 · 1 reader]`

### Maw (26.0), Red Maw (26.1), Psychic Maw (26.2), `0x5172e0`
- **Chases** with push 0.13/d toward Isaac (Red: 0.39). `[move · G1 0x5172e0 · 1 reader]`
- **26.0 / 26.2:** when it can shoot, one shot at **7** (10 in hard mode), cooldown 28. Psychic Maw's shot has homing
  params and it carries a type 96 buddy. `[attack · G1 0x5172e0 · 1 reader]`
- **Red Maw has no ranged attack**; on death it fires a 4-shot + (mode 6) at 8. `[attack · G1 0x5172e0 · 1 reader]`

### Needle (881.0) and Pasty (881.1), `0x555380`
- **Burrowed and untouchable** for 30-89 updates at the start (20-59 after a lunge). It surfaces at a spot **120-240 px
  from Isaac**. `[body · G1 0x555380 · 2 readers]`
- **Lunge:** velocity **8 px/update at Isaac**, an arc about 26 updates long; **hittable only while high** (height
  ≤ −6). `[attack · G1 0x555380 · 2 readers]`
- **Pasty** fires a 4-diagonal burst (mode 7) at 7 four updates into the lunge. `[attack · G1 0x555380 · 2 readers]`

### Boil (30.0), Gut (30.1), Sack (30.2), `0x51da10`
- **Stationary.** It shrinks to 7 HP at spawn and **regrows while not being hit**; it only attacks at full health.
  `[body · G1 0x51da10 · 2 readers]`
- **Attack:** a 1/50 roll (1/200 beyond 230 px). `[timing · G1 0x51da10 · 2 readers]`
  - **Boil:** 3-4 boss shots; **Gut:** one slow boss shot (× 0.55);
  - **Sack:** throws a type-85 (Spider) minion instead.
  - Beyond about 230-250 px the shots go to the room origin, not at Isaac (probably a decompiler slip; unconfirmed).

### Portal (306.0) and Lil Portal (306.1), `0x549f20`
- Stationary spawner. It keeps fewer than 3 children (4 for Lil), every 90-149 updates (60-89 for Lil). Portal makes
  1-5 spawns from a stage table and then removes itself. `[attack · G1 0x549f20 · 2 readers]`

### Others in this batch (one reader)
- **Blubber (210.0):** 3-5 boss shots along its own movement every 30-59; on death 50% becomes a Half Sack (211).
- **Half Sack (211), Pacer (11.1):** wander or flee only.
- **Splasher (238):** one shot at 5 along its movement every 60-89.
- **Black Globin's Body (280):** throws a spider when fewer than 5 enemies, cooldown 90 or 180.
  `[move/attack · G1 0x511780 · 1 reader]`

### Bot meaning (G1a)
- **Death's Head 212.0 is invulnerable:** don't shoot it; dodge its diagonal bounce.
- **Bony family:** don't line up within 200 px.
- **Needle:** only shoot it while airborne and high; it lands near, not on, Isaac.
- **Boil family:** keep hitting it to stop the regrowth.
- **Grub:** don't stand on its line once it has been alive about 2 s.

### Record to confirm (G1a)
- Bony shot speed 10 and the 20 px / 200 px gate.
- Grub charge speed.
- Larry Jr. / Hollow shots at 7.5.
- Needle's lunge at 8 and hittable window.
- Death's Head invulnerability and diagonal speed 4.5.

## Batch G1b (2026-11-26): the rest of the floors 3-6 commons

**Readers:** three Haiku readers (one per third of the batch), Haiku second readers on the bundles with new or doubtful
logic (marked `2 readers`), and two Sonnet readers for the Fistula family (a boss). Type 38 was first read from the
wrong function (a lookup slip) and then read once from the right one. Speeds with "×1.2" are mode 2/4/5 shots, which
get the fire-mode tail. Push values are per update before friction.

### Dip, Corn (217), `0x53b0c0` (also handles type 870)
- Slides: launches on a 10% roll per update while idle, 5-10 speed in a random direction (variant 1: double),
  friction × 0.95. Type 870 aims at Isaac 1/3 of the time (5-8). `[move · G1b 0x53b0c0 · 1 reader]`
- Variant 3 fires one shot at 10 on death, with a small lead. `[attack · G1b 0x53b0c0 · 1 reader]`

### One Tooth (234), `0x53ea20`
- Flies toward Isaac's position + 20 updates of lead, with a wobble. `[move · G1b 0x53ea20 · 1 reader]`
- **Dash:** after 100 updates, with Isaac **80-160 px** away and close to one of 4 fixed lines (± 11.5°): 20 updates at
  3.5 × speed. No shots. `[attack · G1b 0x53ea20 · 1 reader]`

### Fat Sack (209), `0x5372e0`
- Chases at 0.3. **Jump** on a 1/50 roll, to Isaac + 10 updates of lead; no contact while lifted.
  `[move · G1b 0x5372e0 · 1 reader]`
- **Landing:** a **6-shot ring at 12** (mode 9) plus 5 red creep patches within 50 px. `[attack · G1b 0x5372e0 · 1 reader]`

### Brain (32), Poison Mind (301), `0x518910`
- Brain: random axis walk 0.75; checked every 7th update, it dashes along an axis when Isaac is lined up within 200 px
  on a clear line, until a wall. `[attack · G1b 0x518910 · 1 reader]`
- Poison Mind: 45° diagonal wander; dashes when Isaac (led) is within 20 px of the diagonal; explodes on death
  (radius 40). `[attack · G1b 0x518910 · 1 reader]`
- Both leave creep (22 / 23). `[terrain · G1b 0x518910 · 1 reader]`

### Blister (303), `0x5498d0`
- Short lunges toward its child, else Isaac (target 0.2 × offset, at most 40 px). `[move · G1b 0x5498d0 · 1 reader]`
- On a 10% roll with no child out, it launches entity 404 (variant 1) at speed 4. Dying on a free tile leaves entity
  30 at half HP. `[attack · G1b 0x5498d0 · 1 reader]`

### Gurgle, Crackle (87), `0x521360`
- Chases at 0.6. Within **130 px**, 1/60 per update: one lobbed boss shot × 0.55. `[attack · G1b 0x521360 · 1 reader]`
- Variant 0 can revive (15% per update) and leaves a trail. `[body · G1b 0x521360 · 1 reader]`

### Mobile Host (204), Flesh Mobile Host (247), `0x538a30`
- Walks the path at 0.5. Fires on its Shoot event: **204 a 3-spread, 247 a 5-spread**, aimed, speed 7 (× 1.2). Cooldown
  70, then a 1/3 roll. `[attack · G1b 0x538a30 · 1 reader]`
- The shell's damage blocking uses damage records; which states are closed is unclear. `[body · G1b 0x538a30 · 1 reader]`

### Baby (38.0), Angelic Baby (38.1), 38.2, `0x5315d0`
- Variant 3 exits at once (no AI here). Drifts toward Isaac at 0.33 only when its cooldown is up.
  `[move · G1b 0x5315d0 · 1 reader]`
- Shot with cooldown 35, speed 8 (maybe 10 on one branch): 38.0 single, 38.1 3-spread (× 1.2), 38.2 single with a flag.
  Vanishes and reappears after a counter passes 40. `[attack · G1b 0x5315d0 · 1 reader]`

### Mushroom (300), `0x5493e0`
- **Never moves.** Hides 30-150 updates, then reveals and fires **4 shots at 7**, either + or × (50/50, mode 6/7), once
  per reveal. `[attack · G1b 0x5493e0 · 2 readers]`

### Walking Boil / Gut / Sack (88.0/1/2), `0x521e30`
- Wanders; attack on a 1/50 roll (beyond 230 px only 1/4 as often). Boil 3-4 boss shots, Gut one slow exploding lob
  (× 0.55), Sack throws a Spider (85). `[attack · G1b 0x521e30 · 1 reader]`

### Dukie (288), `0x548010`
- Flies, wandering at push 0.3. With 7 or fewer enemies, 1/10 per update once the cooldown (90-119) is up: it coughs
  out entity 256 at 3.5 in a random direction (+ its own velocity), a second one 1/3 of the time.
  `[attack · G1b 0x548010 · 2 readers]`

### Rock Spider (818.0 / tinted / coal), `0x5002f0`
- No shots. **Hops** on update 12, 24 or 36, aimed at Isaac ± 15° (5/6 of the time; 3/4 for variants 1, 2), else a
  random clear direction. Speed 3.0 (variant 1: 5.1; variant 2: 4.8-5.4). `[move · G1b 0x5002f0 · 2 readers]`
- On death: variant 0 comes back as a rock-like form on a free tile; variant 1 drops a pickup; variant 2 spawns 33.11.
  Landing on a rock may kill it (unclear). `[body · G1b 0x5002f0 · 2 readers]`

### Danny, Coal Boy (820), `0x502520`
- Chases at 0.6. Attack on a 1/60 roll (1/15 when a counter passes 6), under 200 px (200-400 px 1/10 as often),
  cooldown 150. Variant 1: 4 thrown rocks (speed 1-10); others: boss shots plus rocks, up to 6 in total.
  `[attack · G1b 0x502520 · 2 readers]`

### Faceless (827, and type 832), `0x5012e0`
- Stands until hurt or a player is **within 80 px**, then chases at 0.6. `[move · G1b 0x5012e0 · 2 readers]`
- Attack chance per update 0.08 × √counter + 0.008 (832: × 0.33; variant 1 awake: 100%): a **6-shot ring at 7**
  (variant 1: 8). Type 832 fires 2 aimed shots at 7. `[attack · G1b 0x5012e0 · 2 readers]`
- When dead it revives on a 50% roll per update while HP is above −25 (not variant 1). `[body · G1b 0x5012e0 · 2 readers]`

### Mr. Mine (311), `0x54fa90`
- Burrows between pits, with 8 orbiting segments (variant 10). **Lunge:** every 4th update, Isaac within **130 px** on
  a clear line: **14 px/update**, cooldown 30. `[attack · G1b 0x54fa90 · 2 readers]`
- Death: a 6-shot ring at 8. Not invulnerable. `[attack · G1b 0x54fa90 · 2 readers]`

### Poky (44.0), Slide (44.1), `0x528380`
- Poky: random axis walk 1.0; Slide: returns to its home spot. **Charge** when Isaac is within 20 px of its row or
  column, under 200 px, on a clear line (checked every 3rd update); Slide × 2.72 faster; ends at a wall.
  `[attack · G1b 0x528380 · 2 readers]`
- Invulnerable from spawn. When the room is clear (or with trinket 151) it goes to the no-spikes state.
  `[body · G1b 0x528380 · 2 readers]`

### Mask (93) and its Heart (92), `0x006ca240` case, `0x525bc0`
- The Mask spawns 1 or 2 linked Hearts (variant 1: two) and is **invulnerable**. `[body · G1b 0x6ca240 · 2 readers]`
- Heart: chases (path, 1.0). Checked every 3rd update, within 100 px: 4 shots at 12 (+ or × by variant); the Mask
  II's heart (98) fires 8-way at 12 or 4-way at 8. `[attack · G1b 0x525bc0 · 2 readers]`

### Baby Long Legs (206), Crazy Long Legs (207), `0x538310`
- Chase or flee at 0.6. About a 1/100-1/200 roll: Baby lays an egg that hatches Spiders (85); Crazy fires an 8-way or
  × burst at 8-10. Collectible 377 blocks attacks. `[attack · G1b 0x538310 · 1 reader]`

### Mom's Hand (213), Mom's Dead Hand (287), `0x53a3e0`
- Waits 0-149 updates, then **hovers on Isaac** (until update 78), slams at update 89, and stays down 51 updates before
  leaving. Contact only during the slam. `[attack · G1b 0x53a3e0 · 2 readers]`
- Dead Hand: shock effects on slam, throws 2-3 spiders on death. Briefly invulnerable in state 16.
  `[body · G1b 0x53a3e0 · 2 readers]`

### Mole (829), `0x504780`
- Underground it moves by digging (1/4 of moves at Isaac, else up to 90 px at random). While Isaac is within **90 px**
  (200 px after update 90), a **1/10 roll per update** makes it surface. `[move · G1b 0x504780 · 2 readers]`
- On surfacing: a **3-spread at 8** (× 1.2). Variant 1: up to 3 extra volleys and an explosion.
  `[attack · G1b 0x504780 · 2 readers]`

### Bomb Grimace (809), `0x4ff610`
- Stationary, invulnerable. Drops a throwable bomb pickup downward at 1.25, then waits until it is gone plus 30
  updates. `[attack · G1b 0x4ff610 · 2 readers]`

### Fistula / Teratoma (71 big, 72 medium, 73 small), `0x46a570`
- Diagonal drift: pushes each axis along its own velocity sign (71: 0.2, 72: 0.38, 73: 0.56), friction × 0.9
  (subtype 1: 0.81), so roughly 2 / 3.8 / 5.6 px/update per axis. Flees a little when feared. **No attacks.**
  `[move · G1b 0x46a570 · 2 readers]`
- **Split on death:** 71 → 4 × 72 (variant 1 or subtype 1: 3), 72 → 2 × 73, thrown at 4. Children keep variant and
  subtype. `[body · G1b 0x46a570 · 2 readers]`
- 73 on death: variant 1 releases 2 Spiders; otherwise a Charger (subtype 1: Boom Fly) at 75% HP, on a free tile only.
  `[attack · G1b 0x46a570 · 2 readers]`

### Bot meaning (G1b)
- **Line gates** (stay off the row or column): Brain, Poky / Slide.
- **Fixed-angle shots:** Mushroom (4-way), Crazy Long Legs, Mask hearts: stand between the lines.
- **Proximity triggers:** Mr. Mine (130 px), Faceless (80 px wake), Mole (90 px), Gurgle (130 px), Heart (100 px).
- **Mom's Hand:** move away just before the slam (about update 89 of the hover).
- **Don't shoot:** Mask, Poky, Bomb Grimace.

### Record to confirm (G1b)
- Fat Sack ring at 12; Mushroom 4-shot at 7; Mole 3-spread at 9.6 (8 × 1.2).
- Mr. Mine lunge 14 within 130 px; Mom's Hand slam timing.
- Mobile Host 3-spread at 8.4 / 7.6; Faceless ring at 7-8.
- Fistula split counts and drift speeds.
