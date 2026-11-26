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