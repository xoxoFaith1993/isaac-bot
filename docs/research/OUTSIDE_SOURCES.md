# Outside sources: what we checked and what we took

The author keeps finding outside material about Isaac bots and game AI: videos, other people's repos, articles,
and "second opinions" from other AI assistants (mostly Gemini). Each one gets checked here before any of it goes
into the bot. One dated section per source.

## How a source is checked

1. **Get it in full.** Transcripts and comments for videos, the whole repo or article, the whole handoff. Copies
   stay in the local `runs/research/` folder (never committed: third-party text).
2. **Check every concrete claim** (IDs, numbers, API fields, file and function names, timelines) against:
   - our code (`mod/isaac-bot/*.lua`, `brain/`, `tools/`);
   - our data (`runs/live.log`, `runs/logs/`, `runs/hits.jsonl`, `runs/bench/`, `knowledge/*.json`);
   - the game's own files (`knowledge/bestiary_game.json`: every entity's type.variant and animation events);
   - the web (official docs, the author's code if there is any).
   Each section lists what was checked and how.
3. **Sort it into four buckets:**
   - **Usable now:** true, fits the architecture, cheap. The exact change goes to the main session, which owns
     the code (one writer per file).
   - **Worth learning from:** a principle or lesson, even when the project itself isn't usable.
   - **Apply later:** true, but it needs recorder data or a bigger change first. Also added to `PLAN.md`
     "To do later (not core)".
   - **Strongly avoid:** unproven, contradicted by our data, entertainment rather than a goal, or a direction that
     fights how the bot works (it reads the game's real state, then measures every change on the benchmark).

## Cross-checking with Gemini

When a source is another AI's answer, the check runs both ways:
- The answer is saved word for word in `runs/research/gemini/` (`<date>_<nn>_gemini_<topic>.md`).
- Its section here has a **claim table**: what the AI said, what we checked it against, and the verdict
  (confirmed / partly / wrong / unverified).
- A short **reply packet** (`<date>_<nn>_claude_reply.md`, same folder) lists the corrections, with evidence, plus
  the questions still open. The author pastes it back into Gemini, so each model checks the other. Whatever comes
  back is a new source and gets checked the same way.
- An AI answer is a lead, not evidence. A claim counts only when our code, our data, the game's files or the
  official docs back it.

---

## 2026-11-26: "I Trapped an AI in the Binding of Isaac" (YouTube video)

**What it is:** a roughly 11-minute video by a YouTuber (SINA). It says a reinforcement-learning agent (PPO, seeing
the screen as pixels) learned to clear rooms and then beat a boss. Most of the runtime explains reinforcement
learning, starting from Thorndike's puzzle-box cats.

**Verdict:** the teaching is accurate. The project is **unverified, with red flags**. Treat it as entertainment,
not a target to match.

**What we checked:**
- The full auto-transcript (kept locally). The RL explanation matches the standard description of PPO:
  - the law of effect as the root idea;
  - reward hacking (when it was rewarded for firing, it shot walls; for surviving, it hid in a corner);
  - the policy;
  - the critic and "better than expected" (the advantage);
  - clipped updates (the "proximal" part);
  - on-policy learning, which throws old data away and so needs thousands of runs.
- The project claims don't hold together:
  - The timeline doesn't add up. It says the agent "couldn't walk through a door" 3 days earlier, also that it
    sat in one corner for two whole days, and also that it needed thousands of runs.
  - There is no code, repo or training log.
  - The main session found an image reused from Reddit.
  - Cube Baby, a strong familiar, appears to be used on purpose. That hides how much the agent itself does.

**Usable now:** nothing.

**Worth learning from:**
- **Reward hacking applies to our own measuring.** Any single number the bot is judged on can be "won" the wrong
  way. For example, fewer hits per room can come from stalling or skipping rooms. That's why the gate reports hits,
  clear rate and seconds together, and the watcher checks that a lesson helped before keeping it. Keep it that way.
- **Why we don't use pixel RL:** on-policy RL needs thousands of runs, and Isaac only runs in real time at
  30 updates a second, with no fast simulator. Reading the real game state and measuring each change on a locked
  benchmark gets further for the same playing time.

**Apply later:** nothing.

**Strongly avoid:**
- Switching to pixel-based PPO.
- Using the video's results as a goal or a comparison. They can't be checked.

**Sources:** [the video](https://www.youtube.com/watch?v=xoDi4OeZ0LU).

---

## 2026-11-26: Gemini handoff, "Replacing statistical guesswork with live REPENTOGON engine state"

**What it is:** a design note from Gemini that the author pasted in. It says the bot guesses enemy and projectile
behaviour from motion, when REPENTOGON already gives Lua the enemy's AI state (`State`, `StateFrame`, `V1`/`V2`,
`TargetPosition`) and the projectile's height and fall (`Height`, `FallingSpeed`, `FallingAccel`). It proposes
three code changes: projectile arc maths, dash lines during wind-ups, and tells keyed by type.variant.

**Verdict:** the core idea is right, and it matches what the new recorder (`recorder.lua`, 2026-11-26) logs. Several
details are wrong, and one rule is contradicted by our own hit data.

**Claim table:**

| Gemini said | Checked against | Verdict |
|---|---|---|
| Decision code doesn't read `State`/`V1`/`TargetPosition` | grep of `mod/isaac-bot/*.lua`: only `recorder.lua` (record-only) reads them | confirmed |
| `mover.lua` treats an enemy as dashing only when its speed is over 5 | `mover.lua` (`dashing = ... sp > (Mover.dashSpeed or 5)`) | confirmed |
| Shots are learned as circles keyed `9.<variant>@<spawner>` | `mover.lua` key function | confirmed |
| `tells.lua` keys animations by `e.Type` alone | `tells.lua` `book[etype]` / `trans[e.Type]` | confirmed |
| Tells only learn an animation is dangerous after hits | `Tells.onHit` counts hits per animation; reflex asks `Tells.hurtRateOf` | confirmed |
| Dingle is `217.0`, Dangle `217.1` | `bestiary_game.json`: 217 is Dip/Corn; **Dingle is 261.0, Dangle 261.1** | wrong ID; the point still holds, since Dingle and Dangle share type 261 |
| Haunt `260.0`, Lil' Haunt `260.10`; Gurgling `237.0`; Sloth `46.0` | `bestiary_game.json` | confirmed |
| A projectile higher than Height -18 can't hit Isaac, so the bot can walk under it | hit lines in `runs/live.log` + `runs/logs/` that name the nearest shot, and the community decompilation (see the next section) | **wrong** (details below) |
| Most charging bosses write their dash velocity or target into `V1`/`V2` during the wind-up | docs: `V1`/`V2`/`I1`/`I2` mean something different for each enemy and are undocumented; the recorder logs them | unverified |
| `TargetPosition` is an `EntityNPC` field | REPENTOGON `libzhl`: it lives on the base `Entity` | minor slip (still readable from an NPC) |
| `NpcState` has `STATE_CHARGE` | IsaacDocs NpcState enum: 0 INIT to 18 DEATH; no CHARGE | wrong |
| Landing spot from `h(t) = Height + FallingSpeed*t + 0.5*FallingAccel*t^2` | community decompilation: the speed is damped each update, so constant-acceleration maths is the wrong shape | wrong formula (right idea) |
| Attack `NpcState`s flag danger without taking a hit | only if enemies use `NpcState` consistently; undocumented, unknown until recorded | unverified |

**About the height:** our hit lines log the nearest shot within 120 px.
- Of the 117 hits where that shot was within 30 px (almost certainly the one that hit), **102 were higher than
  -18**.
- 258 of all 262 were at -50 or lower. That matches the decompiled rule in the next section: a shot can hit while
  its Height is -50 or lower, and lands at -5.
- Normal enemy shots fly at -23 by default, which is above Gemini's line and still hits.

**Usable now** (for the main session):
- **Key tells by `type.variant`:** in `tells.lua`, use `e.Type .. "." .. e.Variant` wherever `e.Type` is the key
  (`entry`, `update`, `onHit`, `windingUp`). Change the `tells.dat` line format and its `load` pattern from
  `^(%d+),` to `^([%d%.]+),`. Old type-only entries load as `<type>.0` or get dropped. Dingle/Dangle (261) and
  Haunt/Lil' Haunt (260) stop sharing data. Add a test where two variants of one type keep separate tells.
- The suggested "diagnostic probe" is already covered: `recorder.lua` logs more than it asked for.

**Worth learning from:**
- Read the enemy's intent from the game instead of guessing it from motion. This is the recorder's whole reason
  to exist.
- Check every "rule" from another AI against logged data before coding it. The height rule looked neat and was
  wrong for about half of our real hits.

**Apply later** (needs recorder profiles first):
- Dash or leap lines drawn from `V1`/`TargetPosition` from the first wind-up update, per enemy, only where the
  profile shows the value really predicts the dash.
- Tells keyed by `NpcState` changes as well as animations.
- The landing spot and time for lobbed shots, from the decompiled fall rule in the next section, checked against
  recorded landings. Keep the learned circles as a fallback.

**Strongly avoid:**
- The Height -18 "can't hit" rule, or any rule that makes airborne shots harmless. Our hit data contradicts it.
- Copying IDs from an AI answer. Look them up in `bestiary_game.json`.
- Swapping out the learned shot circles wholesale for formulas before they're checked against recordings.

**Sources:** the handoff (local copy only);
[REPENTOGON EntityNPC docs](https://repentogon.com/EntityNPC.html);
[Isaac API docs, EntityNPC](https://wofsauge.github.io/IsaacDocs/rep/EntityNPC.html).

---

## 2026-11-26: Gemini, "repos and engine fields you're missing"

**What it is:** a second Gemini answer the author pasted in. It lists five references (four GitHub repos and the
API docs) and three "things you're missing": projectile maths from the shot's first frame, the game's own
pathfinder for chasers, and adding AI state to the eyes snapshot.

**Verdict:** every repo is real, but each one is oversold. The field names are right. Two of the three code
claims are half-right, and one rests on a wrong picture of our tools. The useful part came from checking it: an
exact fall rule for shots, and a REPENTOGON call that gives the exact frame an attack fires.

**How it was checked:** two parallel research agents, one on GitHub (`gh` API, file trees, READMEs), one on the
REPENTOGON and IsaacDocs pages, plus REPENTOGON's `libzhl` files and a community decompilation of the game's
entity code. Then grep of our Lua and tools, and our hit logs.

**Claim table:**

| Gemini said | Checked against | Verdict |
|---|---|---|
| REPENTOGON's `libzhl/functions/` has `.zhl` files with structs, offsets and signatures, including EntityNPC, EntityProjectile and AI routines | the repo: 246 files. `EntityNPC.zhl` has the State/V1/V2/I1/I2 offsets; `EntityProjectile.zhl` has no data fields (Height etc. are in `EntityTear.zhl`); **no per-enemy AI functions** | partly: real, but it won't tell us what an enemy's State or V1 means |
| `TeamREPENTOGON/TestMod` is an official test suite of the extended callbacks | the repo: 147 scripts, mostly auto-generated "call it and see nothing crashes" checks; the README warns they can touch save data | partly |
| `caos-obliquo/tboi-recomp` is a clean-room C++ reimplementation mapping 64 classes, 1,003 methods, 461 properties against the `.zhl` files | the repo exists (7 weeks old, GPL-3) and the numbers are in its README, but they come from decompiling the game; it says nothing plays yet | numbers right; "clean-room" wrong; not usable |
| `2-X/binding-of-isaac-ai` has a modular room_search / level_search / navigator / on_input_request design | the repo: those files exist, but it's 5 commits from one day in 2019, for Afterbirth+, no licence, and it **does nothing when enemies are present** | names right, value oversold |
| The docs cover State, StateFrame, V1, V2, I1, I2, ProjectileDelay and PathFinder | IsaacDocs + REPENTOGON docs | confirmed (`TargetPosition` is on `Entity`) |
| Read `Acceleration`, `HomingStrength`, `CurvingStrength`, `FallingSpeed`, `FallingAccel` at `MC_POST_PROJECTILE_INIT`, and predict with `v = v * Acceleration` | IsaacDocs ModCallbacks: at INIT only position, velocity and spawner are set; flags aren't. The `Acceleration` formula isn't documented anywhere, and mods only set it together with the ACCELERATE/DECELERATE flags | **wrong timing; formula unproven** |
| `mover.lua` learns shot circles keyed `9.<variant>@<spawner>` | `mover.lua` key function | confirmed |
| Chasers drift straight at `player.Position` through rocks | `mover.lua`: the drift is aimed at each plan's own position, and it ignores obstacles | partly (the obstacle part is true) |
| `npc:GetPathfinder():HasDirectPath()` says whether a ground chaser can go straight at us | REPENTOGON docs + `NPCAI_Pathfinder.zhl`: it takes no target and returns a flag cached by the enemy's own last path search | **wrong use**: not a line-of-sight test |
| `eyes.lua` snapshot enemies have 11 fields (type, variant, x, y, vx, vy, HP, max HP, boss, size, mass) | `eyes.lua` | confirmed |
| Adding AI state to the snapshot lets `tools/rooms.py` replay and analyse rooms offline without the game | `tools/rooms.py` replays rooms **in the live game** (`goroom` commands); nothing replays offline | **wrong**; `recorder.lua` already logs this state |

**What checking it turned up:**
- **How shots fall** (from a community decompilation of the game's projectile code, unofficial): each update,
  `FallingSpeed = FallingAccel + 0.1 + 0.9 * FallingSpeed`, then `Height += FallingSpeed`. A shot can hit while its
  Height is -50 or lower (unless it has the ANY_HEIGHT_ENTITY_HIT flag) and lands at -5. Our hits agree: 258 of 262
  logged were at -50 or lower.
- **Exact attack frames:** REPENTOGON's `Sprite:GetEventTriggerFrames(anim, event)` lists the frames where an
  animation fires an event such as "Shoot". With `GetAnimation()` and `GetFrame()` that gives frames until the
  attack, live, for every enemy.
- `Room:CheckLine` and `PathFinder:HasPathToPos(pos, ignorePoop)` are the real "can it get there" checks.

**Usable now** (for the main session):
- **Frames until the shot:** in `tells.lua`, when an enemy plays an animation, ask
  `e:GetSprite():GetEventTriggerFrames(anim, "Shoot")` once per type.variant and animation, and cache it. Then
  `Tells.windingUp(e)` can say "fires in N updates" before the bot has ever been hit by it. This replaces the
  to-do-later idea of pre-seeding tells from a gitignored animation-events file. Wrap it in `pcall` (the docs
  mislabel its signature) and add an offline test with a mocked sprite. It changes behaviour, so it goes through
  the gate.
- Already right, so leave it alone: `recorder.lua` reads each shot on its first update (`FrameCount == 1`), not at
  INIT.

**Worth learning from:**
- A list of real-looking repos can still be weak. Check the commit history and what the code actually does, not
  just whether the names exist.
- The game's own `libzhl` names its generic movement routines (EvadeTarget, HasPathToPos, MoveRandomly). Enemies
  are built from shared pieces, so a few generic behaviours may cover many enemies once the recorder shows which
  ones each uses.
- Small navigation ideas from `2-X`: webs and poop cost more on the path but stay passable, and pressure plates come
  before pickups. Check `nav.lua` already does these before borrowing.

**Apply later** (needs recorder data first):
- **Exact fall for lobbed shots** (Sloth, Monstro) using the rule above, checked against recorded `recshot` lines
  before replacing anything.
- **Chasers and obstacles:** first measure how often a ground chaser that hits us had rocks or pits in the way.
  If it matters, shrink the drift when `Room:CheckLine` from the enemy to the plan's spot is blocked.
- **Shots too high to hit** (above -50 without ANY_HEIGHT_ENTITY_HIT): safe to skip, but they're rare in our data
  (4 of 262), so it's low value.

**Strongly avoid:**
- `HasDirectPath()` as a line-of-sight test.
- Predicting with `v = v * Acceleration` without the flags and a recording that shows it.
- Reading projectile flags or fall values at INIT.
- Adding AI state to the eyes snapshot "for offline replay". There is no offline replay, and the recorder already
  logs that state.
- `tboi-recomp` as a reference for game behaviour while nothing in it runs.
- `Wuxie233/isaac-dodge-assist` (found while checking): it reads game memory, which this bot doesn't do.

**Sources:**
[REPENTOGON](https://github.com/TeamREPENTOGON/REPENTOGON) (`libzhl/functions/EntityNPC.zhl`,
`NPCAI_Pathfinder.zhl`, `docs/docs/Pathfinder.md`); [TestMod](https://github.com/TeamREPENTOGON/TestMod);
[tboi-recomp](https://github.com/caos-obliquo/tboi-recomp);
[binding-of-isaac-ai](https://github.com/2-X/binding-of-isaac-ai);
[IsaacDocs EntityProjectile](https://wofsauge.github.io/IsaacDocs/rep/EntityProjectile.html),
[ModCallbacks](https://wofsauge.github.io/IsaacDocs/rep/enums/ModCallbacks.html),
[NpcState](https://wofsauge.github.io/IsaacDocs/rep/enums/NpcState.html);
[REPENTOGON docs](https://repentogon.com/); the community decompilation
[Isaac.LuaDecomps](https://github.com/Guantol-Lemat/Isaac.LuaDecomps) (`EntityProjectile.lua`).

**Other Isaac bot repos found while checking** (all new, 0-1 stars; none looked at in depth yet):
netlesha/isaac-bot, 404-Wont-Fix/GhostStep (auto-dodge), jcmno/AI-Isaac (RL interface), ly4aznik/isaac-bot,
dmosley2/TBOI_AI (design docs only), Monster7704/isaac-rl-agent (stub). GhostStep is the only one worth comparing
our dodging against.
---

## 2026-11-26: ChatGPT research pass (first reply to our handoff)

**What it is:** ChatGPT's answer to the source-finding handoff, written back as a handoff for Claude. It found three
pages about Dingle and two research papers on bullet-hell bots, then listed seven gaps it couldn't fill. It said
plainly that it could see only search-engine snippets of the Dingle pages, not the pages themselves.

**Verdict:** honest about how sure it was, but thin. The Dingle facts were already in our `boss_tactics.json`
(made 2026-11-25 from the same wiki and the same guide). One fact was wrong (the champions are swapped). One gap
it reported was already filled, by the decompiled projectile rule found earlier today. It didn't read the repo's
guide files.

**How it was checked:** a research agent opened each link. Then `knowledge/boss_tactics.json`, `BOSSES.md`,
`ENEMIES.md` and the Dingle animations in `knowledge/bestiary_game.json`.

**Claim table:**

| ChatGPT said | Checked against | Verdict |
|---|---|---|
| Dingle dashes 3 times (wiki.gg) | the wiki page; `boss_tactics.json` already has "dash x3" | confirmed, already known |
| The **Black** champion does 4 shorter, slower dashes | the wiki page and our `boss_tactics.json`: that's the **Red** champion; Black does one very fast dash, an 8-shot ring and Spiders | **wrong** (swapped) |
| StrategyWiki: 3 dashes, and "use Monstro's shadow to avoid a landing" | the page was blocked (403); Dingle doesn't jump, so the Monstro line likely merges two bosses' sections | unverified, probably a merge |
| Bamboo Gaming: 3 dashes, a pause, a stationary triple shot | blocked for the agent (429); our `BOSSES.md` already used this guide, read in a real browser on 2026-11-25 | already known |
| A bachelor thesis abstract: influence map + Q-learning (DCI/ICI) for a bullet-hell game | the PDF: real, a 4-page Japanese abstract; a home-made Touhou-style clone; ICI won 76%/62% against two bosses and about 0-6% against two others; no code | confirmed, weak evidence |
| PIFE (IEEE CoG 2022): order-insensitive features for danmaku games, environment via game memory | DOI record + the lab page: real (Waseda); Touhou 9; the environment *reads* game memory; no code listed | mostly confirmed |
| Gap: no source for the numerical projectile update rules | the community decompilation (previous section) has the fall and hit-height rule | already filled |
| Gap: no frame data or internal state for the hit-heavy bosses | the game files give animation lengths and event frames (Dingle: Spit 16 f, shot at frame 3; BeforeSlide 21 f; Slide 22 f); for the Haunt, see below | partly filled |

**Found while checking: per-enemy AI in the decompilation.**
- The community decompilation ([Isaac.LuaDecomps](https://github.com/Guantol-Lemat/Isaac.LuaDecomps), Unlicense)
  recreates some enemies' AI in Lua:
  - **the Haunt** (`_Legacy/Actor/Boss/Haunt.lua`, about 600 lines; on our hit list);
  - Gurdy, Widow and Wormwood;
  - Gaper, Lust and Cultist;
  - the shared AI helpers (`NpcAi.lua`, `AiUtils.lua`, `Pathfinder.lua`).
- For the Haunt it names what the fields hold:
  - `I1` is the Lil' Haunt count;
  - `TargetPosition` is reused as its wall-slide velocity;
  - `V2.X` is the pink champion's shot angle;
  - it stays invulnerable in MOVE and SPECIAL, and goes IDLE (where it side-dashes and attacks) after the
    Lil' Haunts die.
- It's unofficial, so it's a hypothesis until the recorder confirms it. But it's the first per-enemy source for
  `State`/`I1`/`V2`.
- **Apply later:** use it to label the Haunt's recorder profile and check it against the recording. Dingle, Gemini,
  Sloth, Monstro and Pin aren't in it yet.

**Usable now:** nothing new. Dingle's entry already holds this.

**Worth learning from:**
- **Its method advice is right and matches ours:** treat wiki and video behaviour as hypotheses, measure them with
  the recorder (`State`, `StateFrame`, animation and frame, hits), and ask every claim for a file, line, section or
  timestamp.
- **Influence maps** (a danger value per cell around the player) are the same family as our danger costs in
  `mover.lua`. The thesis's weak results against two of four bosses back what we found: the learning part isn't
  where the gains are.
- **Order-insensitive handling of shots** (PIFE): our mover already sums costs over all shots, so their order
  doesn't matter. Nothing to change.

**Apply later:** nothing new. The `PLAN.md` line for recorder-dependent work covers measuring Dingle's dashes and
wind-ups.

**Strongly avoid:**
- Champion facts from search snippets. Our `boss_tactics.json` (from the full wiki page) is the record.
- Both papers' learning setups (Q-learning, learned features from memory-read environments). They don't fit a bot
  that reads the real state and has no fast simulator.

**Sources:** [Dingle, wiki.gg](https://bindingofisaacrebirth.wiki.gg/wiki/Dingle);
[StrategyWiki bosses](https://strategywiki.org/wiki/The_Binding_of_Isaac:_Repentance/Bosses) (blocked);
[Bamboo Gaming, Dingle](https://www.bamboogaming.net/the-binding-of-isaac/bosses/dingle);
[the thesis abstract](https://hosobe.cis.k.hosei.ac.jp/lab/wp-content/uploads/2019/05/t_suga-bthesis-abstract.pdf);
[PIFE](https://doi.org/10.1109/COG51982.2022.9893649).
---

## 2026-11-26: ChatGPT research pass, round 2, and the decompiled Haunt AI

**What it is:** ChatGPT's second reply, plus our own reading of the decompiled Haunt AI file it couldn't open.

**Verdict on ChatGPT's round 2:** honest, but almost nothing new.
- Most of it repeats our own round-2 handoff back, including the champion correction and the decompilation's Haunt
  details. Those aren't independent confirmations.
- New and checked:
  - **The repo numbers:** 163 commits, Unlicense. Confirmed with the GitHub API.
  - **The shared helper file:** `AiUtils.lua` holds only function signatures with empty bodies. Confirmed by
    reading it.
  - **StrategyWiki:** the Monstro-shadow advice sits under Monstro's section, not Dingle's. This came from a search
    snippet; the page itself was 403 again. Probably right, and it matches our guess.
- **Patch notes:** it says the Repentance+ notes it opened changed none of our target enemies. **Confirmed, and
  widened:**
  - Its three examples are in the official Steam posts:
    - 1.9.7.8 moved Needles' minimum spawn distance farther from the player and lowered Wizoob and Red Ghost health;
    - 1.9.7.6 fixed Mother's intro.
  - Across every Repentance+ patch up to 1.9.7.20 (2026-11-25), our 17 target enemies and bosses got no change to
    behaviour, speed, health or attacks. The only mentions were a rare themed drop on death (1.9.7.11), new sounds
    (1.9.7.13), and fixes to friendly versions summoned by an item.
  - So Repentance-era guides and data still apply to these enemies. The 2026 patches were checked on the wiki's
    pages only. ([1.9.7.8](https://store.steampowered.com/news/app/250900/view/520825731534554234),
    [1.9.7.6](https://store.steampowered.com/news/app/250900/view/4470480602670303857),
    [version history](https://bindingofisaacrebirth.wiki.gg/wiki/Version_History))
- **The lesson:** a search-only assistant hits the same blocked pages we do. It's more useful for a *blind second
  reading* of a file we've both opened than for more searching.

**The decompiled Haunt AI** ([`_Legacy/Actor/Boss/Haunt.lua`](https://github.com/Guantol-Lemat/Isaac.LuaDecomps/blob/main/_Legacy/Actor/Boss/Haunt.lua),
read in full, about 600 lines). In our own words:

| Part | What the code does | Bot meaning |
|---|---|---|
| Start | Spawns 3 Lil' Haunts (Black champion 2, Pink 1) orbiting 50 px out. `I1` = Lil' Haunts still alive (recounted every 4 updates). `TargetPosition` = its wall-slide push, starting at 0.3 px/update sideways | read `I1` for the phase |
| Phase 1, `STATE_MOVE` (4) | wanders, can't be damaged, not a target | don't shoot it; shots are wasted |
| Last Lil' Haunt dead | plays AngrySkin and drifts up to the top wall, then Peel (`STATE_SPECIAL`, 16, still invulnerable), then `STATE_IDLE` (3) | the phase change is readable as a state, not just an animation |
| Phase 2, `STATE_IDLE` | pinned to the top wall (top bound + 30); slides left/right, picking up speed, and bounces at the side walls | the laser column moves (we already knew this) |
| Side dash | only when Isaac is within **40 px vertically** of its line, with a 1-in-40 chance each update: a burst of 10-15 px/update toward him | staying more than 40 px below its line means it never dashes |
| Attack timing | `StateFrame` counts up in IDLE; **no attack before 60 updates (2 s)**, then a 1-in-60 chance each update, half spit and half laser; every attack resets the count to 0 | **a guaranteed 2 s safe window after every attack**, readable from `StateFrame` |
| Spit (`STATE_ATTACK`, 8) | at the "Shoot" event: a 5-shot spread fired **straight down**, speed 10. Pink: a sweeping stream aimed at Isaac every 2 updates, ±60° | normal spit isn't aimed: get out from under it |
| Laser (`STATE_ATTACK2`, 9) | at the "Shoot" event: a thick laser **straight down**. Pink: two bouncing diagonal lasers (down-left, down-right). Black: throws 1-2 spiders toward the midpoint between it and Isaac | it keeps sliding while it lasers |
| Lil' Haunt, orbiting (`STATE_IDLE`) | circles the Haunt at 50 px, takes no damage, touches only the player, flies over rocks | **never shoot orbiting Lil' Haunts** |
| Lil' Haunt, chasing (`STATE_MOVE`) | the first one detaches after about 90 updates (3 s), the rest once one has died. It accelerates toward **where Isaac is heading** (his position plus his velocity scaled by the distance) | it cuts Isaac off; running straight lets it catch him |
| Lil' Haunt shot | only after 90 updates of chasing, **only within about 63 px** (**corrected: 200 px**; see the Ghidra pilot below), with a 1-in-50 chance each update: one shot at speed 10, aimed at Isaac's position plus 5 updates of his velocity | it shoots from across most of the room, so change direction instead of strafing straight |

**Matches our data:**
- Our Haunt hits are 81 Lil' Haunt body contacts and 50 shots from type 260.
- Body contact by a chaser that leads its target fits the cut-off behaviour.
- `boss_tactics.json` (from guides and logs) already had the column laser, the downward fan, the side dash near the
  top wall, and Lil' Haunts first.
- So the guides, our logs and the decomp agree independently. The decomp adds the numbers.

**Caution:** the decomp is a hand translation with slips. One Lil' Haunt detach check compares the controller index
with 1 where -1 looks meant. The aim line subtracts a position from an entity. So treat every number as a
hypothesis, and confirm it with one recorded Haunt fight (`record|1`): `State` values, the `StateFrame` gap between
attacks, `I1`, and the side-dash trigger.

**Usable once one recording confirms it** (knowledge edits for the main session, in `boss_tactics.json`):
- `260.10`: orbiting Lil' Haunts (`State` 3, animation Float) are invulnerable, so add them to `never_aim`.
  Chasing ones (`State` 4) are the targets. Add `how: change_direction` for their led shot. (A
  "70 px berth" was suggested here first; the real range is 200 px, so a berth doesn't stop the shot.)
- `260.0`: invulnerable in `State` 4 and 16 (IdleSkin, AngrySkin, Peel), so add those to `invulnerable_while`.
  Add a safe window of `StateFrame < 60` after each attack, the time to step under it and shoot. Add the side-dash
  rule: more than 40 px below its line.

**Worth learning from:** a single decompiled enemy file settled more than two rounds of web searching. For enemies
the decompilation covers, read the file first, then confirm with the recorder.

**Apply later:** the same reading for the other floor 1-2 bosses in the decompilation (Gurdy, Widow). Dingle,
Gemini, Sloth, Pin and Monstro aren't covered yet.

**Strongly avoid:** copying the decomp's numbers into code without a recording. It has known translation slips.

**Sources:** [Isaac.LuaDecomps](https://github.com/Guantol-Lemat/Isaac.LuaDecomps) (Unlicense; `Haunt.lua`,
`AiUtils.lua`); [StrategyWiki bosses](https://strategywiki.org/wiki/The_Binding_of_Isaac:_Repentance/Bosses)
(snippet only).
---

## 2026-11-26: ChatGPT round 3, a blind read of the decompiled enemy AI (Gurdy, Widow, Haunt, Gaper)

**What it is:**
- ChatGPT (working in its own read-only clone of Isaac.LuaDecomps at commit `30b09e2`, the same commit the GitHub
  API shows) read the files without seeing our notes.
- It gave line numbers for each claim and flagged code that looks mistranslated.
- We then did the second read of the same files: every line reference below was checked by hand.

**Verdict:** a good, honest reading.
- **Gurdy:** every number checked is right. It missed two useful facts (below).
- **Widow:** right about what's in the files. It missed that the raw state numbers are standard (6 = `STATE_JUMP`,
  4 = `STATE_MOVE`).
- **The Haunt:** its reading and ours agree on every number. Each side caught a slip the other missed. This round
  shows two independent readers working.

**Gurdy** (`Isaac/Content/Actor/Boss/Gurdy.lua`, 332 lines; a floor 1-2 boss):

| What | Checked | Bot meaning |
|---|---|---|
| **It never moves.** Each update its speed is set to pull it back to its starting spot (spawn + 25 px down) | lines 76-77, 305 | a fixed target: plan the firing spot once |
| **At the start of the fight it teleports Isaac** to y = 400 below it (1x1 rooms, room spawn) | lines 52-74 (missed by GPT) | the bot's opening position is known |
| `I1` = the chosen attack (1 = flies, 2 = shot down, 3 = Pooter, 4/5 = shot left/right, 6 = Boils); `V1.X` = a "hit the player" flag that picks the Idle2 animation | lines 26-47, 107-113, 155-159, 317-320 | read `I1` to know the attack |
| It attacks when its idle animation ends. It **spawns** (Pooter, 2 Attack Flies or Boils) on a 1-in-3 chance, **or whenever Isaac stands at y ≤ 200, or there are more than 7 enemies, or it's the green champion**. Nothing spawns at 14+ enemies | lines 122-137 | **don't stand high in the room**: that forces adds |
| Otherwise it **shoots**: a 5-shot spread **down** (speed 10) if Isaac is below it, **sideways** (left or right) if he's off to the side or above it | lines 138-147, 197-206, 221-239 | the spread isn't aimed: be off its line, not just moving |
| Its adds are pushed away from it when within 80 px | lines 83-102 (missed by GPT) | adds spread out from it |
| Slips (GPT): line 76 adds a number to a vector; line 68 uses cos twice (co-op teleport only); the sideways spread's spray is lopsided (-0.5 to +2.5) | confirmed | check against a recording |

**Widow** (`_Legacy/Actor/Boss/Widow/Common.lua` + `Sprite.lua`; a Cellar boss, floors 1-2; only the jump is
covered):
- The jump sets state 6 (`STATE_JUMP`) and stores a leap velocity in `V1`: a 7 px/update push toward the target point,
  added every update.
- Between the "Jump" and "Land" sprite events it **can't touch anything**, so there's no contact damage mid-air.
- The animation ending sets state 4 (`STATE_MOVE`).
- The file is unfinished: its module exports nothing, and the jump's trigger and its landing aren't in it (GPT spotted
  this).
- **Bot meaning:** Widow's mid-air flight is harmless. The danger is where it lands, toward the target point it
  stored in `V1` at take-off.

**The Haunt, two blind readings compared:** all numbers match (60-update gap, 1 in 60, 40 px side-dash band, 10-15
dash, the Lil' Haunt range, 5-update lead, orbit 50 px). But both readings copied the same mistake: the community
file's "63 px" range is really 200 px in the game's code (Ghidra pilot, below). Two readers of one source can't catch
an error in the source itself. On slips:
- **GPT caught two that we missed:**
  - the Pink champion's angle multiplies the whole `V2` vector instead of `V2.X` (line 197);
  - the Lil' Haunt's parent subtype is overwritten by its own (line 439; GPT cited 442-443, a small line slip).
- **We caught one GPT missed:** the Lil' Haunt detach check `controllerIdx ~= 1` (line 488) would make every Lil'
  Haunt detach at once. That contradicts the real fight, where they orbit and detach one by one, so it's surely a
  slip for -1.
- **Gaper** (optional): a plain pathfinding chaser, speed 0.6 (0.72 or 0.55 for some variants), no attack. Nothing
  for the bot.

**Usable once one recording confirms it** (knowledge edits for the main session):
- **Gurdy** (it has no entry in `boss_tactics.json` yet): stay below y = 200 so it doesn't keep spawning adds; when it's shooting, stand off its down or side
  spread lines; it's a fixed target.
- **Widow:** no contact danger between its Jump and Land events; watch the landing point.

**Worth learning from:** two independent readings plus a hand check are worth it. Each reader missed things the
other caught.

**Apply later:** the Ghidra pilot (its own session, 2026-11-26) is trying to decompile Dingle and the others from the
game itself. When it has output, the same blind second read applies.

**Sources:** [Gurdy.lua](https://github.com/Guantol-Lemat/Isaac.LuaDecomps/blob/main/Isaac/Content/Actor/Boss/Gurdy.lua),
[Widow/Common.lua](https://github.com/Guantol-Lemat/Isaac.LuaDecomps/blob/main/_Legacy/Actor/Boss/Widow/Common.lua),
[Haunt.lua](https://github.com/Guantol-Lemat/Isaac.LuaDecomps/blob/main/_Legacy/Actor/Boss/Haunt.lua),
[Gaper.lua](https://github.com/Guantol-Lemat/Isaac.LuaDecomps/blob/main/Isaac/Content/Actor/Enemy/Gaper.lua).
---

## 2026-11-26: Ghidra pilot, the game's own code (our own work, cross-checked)

**What it is:** our own decompile of a copy of `isaac-ng.exe` (Ghidra, plus REPENTOGON's signatures), done in a
separate session. Full method and results: [`RE_PILOT.md`](RE_PILOT.md); scripts in `tools/re/`.

**Verdict:** works. **GO** for the other worst enemies.
- **The Haunt:** the decompiled AI matches the community `Haunt.lua` on every number but one. The Lil' Haunt's shot
  range is **200 px** (`dist² < 40000`), not 63 px. The hand translation dropped a zero, and both of our blind
  readings copied it. The real code also settles the `controllerIdx` slip: it's -1, as we guessed.
- **Dingle:** the full behaviour table is in `RE_PILOT.md`. In short:
  - **no attack in the first 30 updates of each Idle** (15 for Dangle);
  - **3 dashes** (Red 4, Black 1), each aimed at Isaac's position at that moment, no lead, with a 12-15 update pause
    between them;
  - Tired lasts about 2-3 s, with no attacks;
  - the triple Spit is aimed at Isaac's position with no lead, at ±16°;
  - the Black champion fires an 8-way ring instead.
  - Champions are `SubType` 1 (Red) and 2 (Black).
  - Nothing in the code makes the Red champion's dashes slower or shorter, which contradicts the wiki (check it in a
    recording).

**How it was checked:**
- From this session, three spots read in the decompiled C:
  - the Lil' Haunt `40000.0` check (with the 90-update delay);
  - Dingle's IDLE threshold (30, or 15 for Dangle), its 1 in 20 (or 10) roll, then 1/3 Whistle and 1/2 BeforeSlide,
    else Dance;
  - the 12-15 update pause (`(rand & 3) + 12`) and the first-dash poop roll (1 in 5).
- All match `RE_PILOT.md`.
- ChatGPT's blind read of the same C (round 4) is still to come.

**Usable now:** nothing directly. The `boss_tactics.json` suggestions in `RE_PILOT.md` wait for one recorded Dingle
fight and one Haunt fight (the checklist is there).

**Worth learning from:**
- The original code beats every secondary source, including a careful hand translation that two readers agreed on.
- Keep the method, not the addresses: every game update moves them.