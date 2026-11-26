# RE pilot: reading enemy AI out of isaac-ng.exe (2026-11-26)

**Question:** can we read the exact behaviour of our worst enemies (Dingle, Gemini, Sloth, Pin, Monstro, ...)
straight from the game's compiled code, the way the community decompiled the Haunt by hand? Go/no-go in one sitting.

**Answer: GO.** In about 35 minutes of work the pipeline found the per-enemy AI dispatcher and decompiled both the
Haunt and Dingle into readable C with named fields. The Haunt matched the community's hand translation on every
number but one, and on that one the machine code proved the hand translation wrong. Dingle's full behaviour is below.

**Rules we kept:**
- Only a **copy** of `isaac-ng.exe` was opened. Nothing in the game folder was touched.
- The decompiled C, the Ghidra project and REPENTOGON's files stay outside the repo (a local work folder, plus
  copies in the gitignored `runs/research/re/` for a blind second reading). They are never committed.
- What we commit is our own scripts (`tools/re/`) and what we learned, in our own words (this file).
- Every finding below is a **hypothesis** until the recorder (`recorder.lua`, `record|1`) confirms it in a real fight.
  The checklist is at the end.

**Build these addresses belong to:** `isaac-ng.exe`, 9,539,592 bytes, SHA-256
`C8337B957B7805AEE1EAC0C49CC7A8EA7BA2E195C7F84A0AB41051406DF9426A` (the Steam update of 2026-11-26).
REPENTOGON `libzhl` at commit `9da2f46`. A game update moves every address; re-run the steps below to find them again.

## Method

1. **Tools:** Ghidra 12.2 (the official NSA GitHub release, SHA-256 checked) on the Java 26 already installed. It runs
   headless (no window), with its temp files and project in the work folder. Analysis took about 5 minutes and about
   3.3 GB of RAM (capped at 6 GB). The project is about 320 MB.
2. **Names from REPENTOGON:** `tools/re/zhl_extract.py` reads REPENTOGON's `libzhl/functions/*.zhl` (a sparse clone)
   into two plain tables: 1,632 function signatures and 1,910 struct fields.
3. **Analyse once:** `tools/re/run_ghidra.py --ghidra <dir> --work <dir> analyse` imports the exe, runs Ghidra's
   normal analysis, then `tools/re/ghidra/ApplyZhl.java`:
   - names every function whose signature matches exactly one place: **965 applied**, 568 no match (many are stale
     after the same-day game update), 99 ambiguous;
   - builds `Entity`, `Entity_NPC`, `Entity_Player` and `Entity_Projectile` structs from the known offsets (`State`
     0xb64, `StateFrame` 0x410, `V1` 0xbb0, `V2` 0xbb8, `I1` 0xbc0, `I2` 0xbc4, `ProjectileDelay` 0xba4,
     `TargetPosition` 0x334, `Position` 0x33c, `Velocity` 0x360, ...).
4. **Decompile on demand:** `run_ghidra.py ... decompile npc:0xADDR+name` runs `tools/re/ghidra/DecompileFns.java`.
   The `npc:` prefix types the function's first argument as `Entity_NPC*`, so the C reads `this->state`,
   `this->i1` instead of `*(int *)(param_1 + 0xb64)`. (`+` renames; `=` gets split off by Windows batch files.)
5. **Look things up:** `run_ghidra.py ... probe <cmd>` runs `tools/re/ghidra/Probe.java`: `xrefs:` (who references an
   address), `dump:` (read a vtable), `consts:` (functions using a number), `floats:` (float constants a function
   reads), `dis:` (raw instructions).

**How the AI was found** (repeat this after a game update):
1. `Entity_NPC::Update`'s signature was stale, but `Entity_NPC::Init` matched (`0x6bfb50`). The NPC vtable holds it at
   `0xb8bb54`, so the table starts at `0xb8bb50` and slot 3 (`0xb8bb5c`) is **`Update` = `0x6cc3e0`**.
2. `Entity_NPC::Hornfel_UpdateAI` matched (`0x4bd220`); its only caller is the **AI dispatcher, `0x6ca240`**. It calls
   `LuaEngine::PreNPCUpdate`, then switches on `Type`: for types 10 to 967, a byte table at `0x6cbe5c + (Type - 10)`
   gives the case number.
3. The bytes for 260 and 261 are `0x5f` and `0x60`: **Haunt AI = `0x4855e0`** (it also shows up in the "uses 260"
   constant search, a cross-check), **Dingle AI = `0x4898c0`**.
4. **For the next enemy:** read the dispatcher's byte at `0x6cbe5c + (Type - 10)`, find that case, decompile its call.

## Calibration: the Haunt (260) — PASS

The decompiled `ai_haunt` (`0x4855e0`) against the community `Haunt.lua` and our summary in `OUTSIDE_SOURCES.md`:

| Rule | Haunt.lua | Real code | Match |
|---|---|---|---|
| Lil' Haunts at start | 3 (subtype 1: 2, subtype 2: 1), orbit 50 px | same | yes |
| `TargetPosition` = wall-slide push | 0.3 sideways | `(0.3, 0)`; flips and adds 15× on a wall bump | yes |
| `I1` = live Lil' Haunts | recount every 4 updates | `frame & 3 == 0`, `QueryNPCsType(260, 10)` | yes |
| Invulnerable phase | `STATE_MOVE` (4) and Peel (16) | the state path 4 → AngrySkin → 16 → 3 matches, but **no damage blocking here**: `isInvicible` is set at init and cleared at the top of every later update | **not in `ai_haunt`; unconfirmed** (the game may block damage in its damage path instead) |
| Pinned to the top wall | top + 30 | `Y = top + 30` whenever State ≠ 4 | yes |
| Side dash | within 40 px vertically, 1 in 40, 10-15 px/update | `abs(dy) < 40`, `rand % 40`, `10 + rand*5` | yes |
| Attack gap | no attack while StateFrame ≤ 60, then 1 in 60 | `StateFrame++ > 60`, `rand % 60`; reset to 0 after each attack | yes |
| Spit | 5-spread straight down, speed 10 | mode 5, velocity `(0, 10)` | yes |
| Laser | straight down; Pink two diagonals; Black 1-2 spiders to the midpoint | 90°; 135° and 45°; `ThrowSpider` at the midpoint | yes |
| Lil' Haunt detach | after 90 updates; the controller check | `> 0x5a`; real code compares the controller to **-1** | yes (the community's `~= 1` is its slip) |
| Lil' Haunt lead | Isaac's position plus velocity × distance | `+ playerVel × dist × 0.5` | yes |
| Lil' Haunt shot aim | Isaac's position + 5 updates of velocity, speed 10 | same | yes |
| **Lil' Haunt shot range** | `distance < sqrt(4000)` ≈ **63 px** | `dx²+dy² < 40000.0` (`0x486c4f`, constant at `0xbcfe5c`) → **200 px** | **no: real is 200 px** |

**Verdict:** the pipeline works. It reproduces a careful hand translation, and it settles the one place where the
hand translation slipped (a dropped zero). One claim it can't settle: where the Haunt's invulnerability comes from.
`ai_haunt` doesn't block damage, so it must happen elsewhere (for example a damage handler that checks `State`), or not
at all. That needs a recording. (Pointed out by a blind second reading of the C, checked against the code.) **Correction for `OUTSIDE_SOURCES.md`'s Haunt table:** the Lil' Haunt
shoots within **200 px**, not 63, so the suggested "70 px berth" won't stop its shots. A berth of more than 200 px
does, or keep `how: change_direction` for the led shot.

## Dingle (261.0): behaviour table

One function, `ai_dingle` (`0x4898c0`), runs **Dingle (variant 0)** and **Dangle (variant 1)**. The champions are
**subtypes**: subtype 1 = Red and subtype 2 = Black (matched to the champion descriptions in `boss_tactics.json`). The
AI runs 30 updates per second, so 30 updates ≈ 1 s.

### States

| State | Animation | What it does | Leaves to |
|---|---|---|---|
| 0 (init) | — | sets `State` 3, clears `StateFrame`, `I1`, `I2` | 3 |
| **3 IDLE** | Idle | stands still (friction 0.7). `StateFrame` counts up from 0. **No attack while `StateFrame` ≤ 30** (Dangle 15). After that, each update has a 1-in-20 chance (Dangle 1 in 10), plus a second 1-in-10 chance (Dangle 1 in 5) while an unknown field at 0x14 is above 0 (meaning not decoded). The whole check is skipped while entity flag bit 60 is set (not decoded either). When it fires: 1/3 Whistle, otherwise 1/2 BeforeSlide (not while it has flag bits `0x1000a00`, probably confusion/fear), otherwise Dance | 9, 11 or 10 |
| **11** (ATTACK4) | BeforeSlide (21 f) | the dash wind-up; plays once | 4 |
| **4 MOVE** | Slide (22 f) | one dash per Slide animation (details below). Between dashes `StateFrame` is a 12-15 update pause, then Slide plays again | 4 again, then 16 |
| **16 SPECIAL** | Tired (24 f, loops) | stands still for **61-90 updates (2-3 s)**, no attacks. The limit is re-rolled (60-89) every update, so it usually ends early, around 65-70 updates (Dangle: half) | 3 |
| **10** (ATTACK3) | Dance (29 f) | no attack of its own; plays once | 8 |
| **9** (ATTACK2) | Whistle (31 f, Spawn @17) | summons at the Spawn event (below) | 8 |
| **8 ATTACK** | Spit (16 f, Shoot @3) | fires once at the Shoot event (below) | 3 |

Every change into a new state resets `StateFrame` to 0, so in IDLE, **`StateFrame` = updates since the last attack
ended**.

### Fields

| Field | Meaning in this AI |
|---|---|
| `State` | the table above |
| `StateFrame` | IDLE: time since the last attack. MOVE: the countdown of the pause between dashes (12-15, counting down). Tired: time spent tired |
| `I1` | dashes already done in this sequence (0, 1, 2); back to 0 at Tired |
| `I2` | Red champion only: red poops placed by Whistle (it stops placing them at 6 once the room has 5+ enemies) |
| `TargetPosition` | set to a random room position whenever a dash hits a wall or rock; this function never reads it (probably used elsewhere, or left over) |
| `V1`, `V2`, `ProjectileDelay` | not used |

### The attacks

**Dash sequence** (the `State == 4` branch of `0x4898c0`):
- **Count:** 1 + `I1` limit. Dingle **3 dashes**, Red champion **4**, Black champion **1**, Dangle 2.
- **Wind-up:** BeforeSlide (21 frames) before the first dash only. Later dashes follow a **12-15 update pause**
  (friction 0.9, so it slows almost to a stop), then the Slide animation restarts.
- **Aim:** at the Slide animation's `"Slide"` event it adds **10 px/update** (Black: **15**) toward **where Isaac is
  at that moment. No lead.** After the event it keeps pushing, probably along its own current direction (1 per update,
  Black 1.5, over the friction-like field at 0x36c, ×0.98 per update), so a wall or rock bounce would change its course
  mid-dash.
- **Ends:** when the Slide animation finishes, or early if it has flags `0x1000a00` (probably confused/feared).
- **First dash only:** a 1-in-5 chance to drop a Poop (grid type 14) where it stands. Dangle instead spawns entity
  type 295 and leaves a creep trail while sliding (which creep is not yet decoded).

**Spit** (the `State == 8` branch of `0x4898c0`, at Spit's Shoot event, frame 3):
- **Normal and Red:** a **triple shot aimed at Isaac's position at that frame (no lead)**: one shot at speed 10 straight
  at him, two at speed 9 rotated **about ±16°** (fire mode 2 in the projectile function `0x6d2bb0`: rotate by (0.961, 0.276), ×0.9, times a spread
  multiplier from the projectile parameters, presumably 1 here).
  Normal uses projectile variant 3 (the puke shot, 9.3, which matches our hit logs); Red uses variant 0 (plain blood).
  Dangle uses variant 5.
- **Black:** an **8-way ring (fire mode 8), speed 10, not aimed:** the four straight and four diagonal directions.

**Whistle summon** (the `State == 9` branch of `0x4898c0`, at Whistle's Spawn event, frame 17). Normal and Black always
summon; Red places its poop only while `I2` < 6 (a room counter below 5 is also checked, but `I2` < 6 lets the others
through anyway):
- **Normal:** 1-2 Dips (217.0; Dangle 217.2), capped so no more than 3 Dips are out when entity flag bit 60 is set
  (not decoded). Dangle throws them at Isaac at speed 15.
- **Red:** one red Poop grid next to it (`I2` += 1).
- **Black:** 1-2 Spiders (85.0) near it.
- Then it always spits (state 8).

### Safe windows (for the bot)

1. **The first 30 updates (1 s) of every IDLE:** nothing can start. Read `State == 3 and StateFrame <= 30`. After that,
   about 5% per update, so typically under 1 s more.
2. **Tired (State 16): about 2-3 s**, no attacks, nearly still. The best time to close in and shoot (the guides say the same).
3. **Dance (29 f) or Whistle (31 f), then Spit's 3 frames:** about 1 s of warning before a triple shot. Because the
   shot isn't led, **any sideways movement during Spit's first 3 frames dodges the centre shot**. The ±16° side shots
   are what catch a short sidestep up close, so sidestep from farther away.
4. **Between dashes:** a 12-15 update pause each time. The dash goes where Isaac **was** at the Slide event, so a late
   90° sidestep works, as `boss_tactics.json` already says.

### Suggested `boss_tactics.json` changes (for the main session; not applied here)

For `261.0`, once one recording confirms them:
- `attack_windows`: keep Tired and Idle, and make the Idle window concrete: **`State == 3 and StateFrame <= 30`**.
- `dodge` "triple shot": add `aimed: "position at fire time, no lead"`, `speed: 10 (sides 9)`, `spread_deg: 16`, and
  note that Dance also leads to Spit.
- `dodge` "dash x3": `count: 3 (Red 4, Black 1)`, `speed: 10 (Black 15)`, `aim: "Isaac's position at the Slide
  event, no lead"`, `pause_between: "12-15 updates"`. Add the `"Slide"` animation event (see below).
- `champions`: name them by subtype (`.1` Red, `.2` Black) so the bot can read `SubType` instead of guessing the colour.
  Nothing in this function makes the Red champion's dashes slower or shorter (same speed 10, same push). Either the
  guide is wrong or it happens elsewhere: check it in a Red recording.
- **Bestiary gap:** `bestiary_game.json` lists no event for Slide because `"Slide"` isn't in the event names the
  extractor tries (`event_names_tried`). Add `"Slide"` (and in general, the event strings the AI code passes to its
  event check) so the dash moment gets a frame number.

## What to record to confirm it (`record|1`)

**Haunt (one fight):** shots that hit the Haunt while `State` is 4 or 16 should do **no damage** (its health stays the
same). `ai_haunt` doesn't show this, so only a recording can confirm the invulnerable phase. Also check the Lil' Haunt
shot range: no shots from more than 200 px.

**Dingle (one fight, ideally also one champion):**

- `State` sequence: only 3, 11, 4, 16, 10, 9, 8 should appear; 11 → 4 (x3) → 16 → 3; 10 → 8 → 3; 9 → 8 → 3.
- `StateFrame` when each attack starts from IDLE: **never 30 or less**.
- `I1` counting 0 → 1 → 2 during a dash sequence and back to 0 at Tired; the pause between dashes 12-15 updates.
- Tired length: 61-90 updates, mostly near the low end.
- The velocity jump at the start of each dash: about 10 px/update (Black 15), pointing at Isaac's position on that
  update (compare with Isaac's position, not his position plus velocity).
- The Spit shots: 3 projectiles of variant 3, speeds 10/9/9, at ±16°, aimed at Isaac's position on the shot update.
- `SubType` of a Red and a Black champion (expected 1 and 2), `I2` rising when the Red champion whistles.

## Time and go/no-go

- **Time:** about 35 minutes from the download to both decompiles. The one-off setup (download, scripts, debugging
  them) was most of it. A new enemy now takes about 5-10 minutes to find and decompile, plus the reading.
- **Done (2026-11-26, approved "Yes, do all 8"):** Gemini, the Blighted Ovum, Sloth, Pin, Monstro, Attack Fly, Trite and
  Charger are in `RE_ENEMIES.md`.
- **GO for the other 8.** The same steps cover Gemini (79.0, also the Blighted Ovum 79.2), Sloth (46.0), Pin (62.0),
  Monstro (20.0), Attack Fly (18.0), Trite (29.1) and Charger (23.0): look up the case byte at
  `0x6cbe5c + (Type - 10)`, decompile that call, then write a table like Dingle's. Each one is still a hypothesis
  until one recording confirms it.
- **Costs and risks:**
  - Every game update moves the addresses. Keep the method, not the addresses, and re-run it.
  - About 40% of REPENTOGON's signatures didn't match this new build. The AI functions themselves don't need them;
    the names just make the code easier to read.
  - Some fields stay unnamed (`field_0x14`, `field_0x36c`, which acts like friction). Mark those as unknown, not
    guessed.

## Sources

- Our own decompile of the build above (local only, not committed).
- REPENTOGON `libzhl/functions` (signatures and field offsets; GPL-2.0, used locally, nothing copied into the repo).
- [Isaac.LuaDecomps `Haunt.lua`](https://github.com/Guantol-Lemat/Isaac.LuaDecomps/blob/main/_Legacy/Actor/Boss/Haunt.lua)
  (Unlicense), for the calibration.
- `knowledge/bestiary_game.json` (animation lengths and event frames) and `knowledge/boss_tactics.json` (champion
  descriptions).
