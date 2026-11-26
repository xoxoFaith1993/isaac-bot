# How we work on the Isaac Bot

This is the guide to *how* the bot gets better, not just what the code does. It's written for someone new: maybe a
software engineer who has never modded a game, or an Isaac player who has never written code. Most of this
project was built by one person who knows the game very well, directing an AI coding assistant (Claude Code). The
method below is what came out of that. It isn't the only way, and if you know a better one, say so (see the end).

## 1. The big picture

The bot is a mod that runs **inside the game** plus a small program that runs **next to it**:

```
 The game (30 updates a second)                          Your PC
 ┌──────────────────────────────────────────┐           ┌───────────────────────────────┐
 │ mod/isaac-bot (Lua, runs every update)   │  files    │ brain/helper.py (Python)      │
 │  eyes.lua     what's on screen           │ ───────►  │  live log, dashboard          │
 │  danger.lua   spikes, creep, fires, TNT  │           │  saves what the bot learned   │
 │  mover.lua    where to move (dodging)    │ ◄───────  │  sends knowledge + commands   │
 │  reflex.lua   who to shoot, firing spots │  files    │ brain/rescue_brain.py         │
 │  nav.lua      rooms, doors, pickups      │           │  local AI model (optional)    │
 │  risk.lua     how bold to play right now │           └───────────────────────────────┘
 │  strategy.lua the whole run: items, deals│
 │  rescue.lua   unstuck ladder             │           knowledge/ (data, not code):
 │  main.lua     wires it together, inputs  │           enemy playbook, item ratings,
 └──────────────────────────────────────────┘           card/pill ratings, rules, boss tactics
```

Every update the bot looks at the room, decides a move direction and a shoot direction, and "presses" them through
the game's input hook, exactly like a controller would. Nothing reads or writes the game's memory.

## 2. Game modding in ten minutes (for software engineers)

- **The loop.** The game runs at 30 logic updates a second. A mod registers *callbacks* (`MC_POST_UPDATE` every
  update, `MC_ENTITY_TAKE_DMG` when something gets hurt, `MC_POST_NEW_ROOM`, and so on). Every callback must be fast:
  a slow update slows the whole game. A perf line in the log shows how long the bot's thinking takes.
- **The world.** Rooms are grids of 40 px tiles (rocks, pits, spikes, poop, doors). Everything that moves is an
  *entity* with a type, variant, position, velocity and size. Enemies, tears, enemy shots, pickups and bombs are all
  entities.
- **Inputs.** The bot never "teleports" or cheats: `MC_INPUT_ACTION` answers "is the move-left button pressed?" and
  so on, the same questions a controller answers.
- **REPENTOGON** is a community extension of the game's Lua API (more functions, better callbacks). The bot needs it.
- **Talking to Python.** Mods can't open sockets, but they can save small data files. The mod writes its messages
  into one mod's save file, and the helper writes commands into another. That's the pipe.
- **Reloading.** `luamod isaac-bot` in the game's console reloads the mod without restarting the game. The bot keeps
  its floor map and learned data across reloads.
- **Debugging is mostly logs and video.** There's no debugger stepping through a frame. Instead the bot explains
  itself in the log, and Steam's background recording shows what really happened (see 3b).

## 3. The improvement loop

This is the heart of the method. Every fix in the code went through some version of it.

### 3a. Watch, and say what's wrong in plain words
Someone watches the bot play and describes what looks wrong as a player would: "it parks itself in the corner when
flies come close", "it's shooting the boss's little adds instead of the boss", "it's playing way too carefully". That
description is valuable even with no code knowledge. Game sense is what tells you *what* is wrong.

### 3b. Diagnose with evidence, not guesses
Before changing anything, find out *why*:
- **`runs/live.log`** (and the `logview` window) has a line for everything: `room` (which room and layout), `hit` (what
  hit us, from how far, what the bot was doing, the risk level), `why` (every second: the chosen move and what its cost
  was made of: danger, closed ways out, aim), `stuck`, `risk`, `aim` (real accuracy), `run` (the build's strength
  and needs), `power` (stats and items each floor).
- **Frames:** `tools/look.py` pulls frames from Steam's background recording (a few seconds behind), and the helper
  saves frames of the moments before every hit in `runs/hitframes/`. Looking at the actual frame settles most
  arguments.
- **`map`** (send it through `runs/send.txt`) dumps the bot's floor map: which rooms it knows, visited, cleared,
  written off.

### 3c. Fix the category, not the room
The question is never "how do we get past *this* room" but "what kind of situation is this, and what's the general
rule?" Examples from the history:
- A trap-room button walled in by TNT didn't get a special case. Instead: "a goal square with no path: shoot poop, or
  a TNT barrel next to the rocks, else bomb."
- Corners against flies didn't get "avoid this room's corners". Instead: "chasers home in on wherever you go, so a far
  corner isn't safe from them, and corners cost more the more movers are around."
Comments in the code say *why* a rule exists and when it was found (`-- (2026-11-25: ...)`), so nobody undoes a fix
without knowing what it fixed.

### 3d. Lock the fix in with an offline test
`test/tests.lua` runs the bot's real Lua code against scripted rooms (`test/mock.lua` is a fake game). A good test
recreates the bug in miniature and fails without the fix. `test/mutants.lua` + `run.ps1 -Prove` check that each test
still guards its fix. A real bug found but not fixed yet goes in as a `known(...)` test and in `test/FOUND_BUGS.md`.

### 3e. Reload safely
`tools/reload.ps1` (Windows) or `bash tools/check.sh --reload` (Linux) compiles every Lua file and runs the tests
first. A failing test blocks the reload, so a broken mod never reaches the running game.

### 3f. Measure, and beware of outliers
One run proves nothing: a strong item can make a bad bot look good. So:
- **The real-room bench** (`tools/rooms.py collect` then `run`) replays rooms where the bot got hit, **item-free**,
  worst first, and reports clear time and hits.
- **The gauntlet** (`tools/gauntlet.py`) runs common enemies and bosses one by one.
- **A/B tests** run the same thing with a setting on and off. For example, `risk|0.25` pins the old careful play.
- `knowledge/ITEMS.md` gives every item a "carry" score, so results can say what the bot was holding.

### 3g. Write it down
`PLAN.md` holds the plan and the history of what was tried, `test/FOUND_BUGS.md` the open bugs, `knowledge/*.md`
the game knowledge. The next person (or the next AI session) starts from there.

### 3h. The live watcher: the loop, automated
`brain/watcher.py` runs inside the helper and does a first pass of this loop by itself while the bot plays:
- **Loops:** a two-room bounce (it writes that door off), standing still while walking (it asks for a re-plan), a
  fight where no enemy loses health for a minute, the same room entered 6+ times.
- **Hits by cause:** every hit is sorted (`body:<enemy>`, `shot:<shooter type>`, creep, bomb, laser) and counted
  against *encounters* (rooms where that enemy was present), so each cause has a rate.
- **Lessons:** a cause that keeps hurting (3+ hits, 0.5+ per encounter) gets one small, capped change for just that
  enemy: more berth from its body, more margin around its shots, more distance from a boss. After 4 more encounters
  the change stays only if that cause's rate fell by a quarter. Otherwise it's undone. `knowledge/lessons.json`.
- **The code-fix queue:** what a setting can't fix (a loop that repeats, a lesson that didn't help, causes like
  creep or bombs) goes into `runs/watch/queue.jsonl` with the evidence. `python tools/queue.py wait` blocks until a
  new problem arrives; an AI session (or you) then works it with the steps above and closes it with
  `tools/queue.py done <id> "what changed"`. At most 3 new problems an hour.
- Everything is summed up in `runs/watch/REPORT.md`; offline tests in `test/test_watcher.py`.

## 4. Knowledge beats learning on the spot

Early on the bot learned everything by getting hit: how far each enemy reaches, which animations come before a shot.
That works, but it's slow and it costs the hits we're trying to avoid. So whatever can be *known* is written into data:

| File | What | Who can improve it |
|---|---|---|
| `knowledge/enemy_playbook.json` + `ENEMIES.md` | every enemy's movement, attacks, danger, kill priority | Isaac players |
| `knowledge/item_ratings.json` + `ITEMS.md` | every item's value **for this bot**, its "carry", tags | Isaac players |
| `knowledge/consumable_ratings.json` | when to use each card and pill | Isaac players |
| `knowledge/boss_tactics.json` + `BOSSES.md` | how good players beat each boss | Isaac players |
| `mod/isaac-bot/rules.lua` + `knowledge/RULES.md` | the bot's judgement as numbers: what's worth a bomb or a hit, which rooms to enter | anyone |

**You don't need to write Lua to make the bot smarter.** Correcting a playbook entry or a boss tactic is a real
contribution.

The bot still learns on top of that (`knowledge/motion.dat`, `tells.dat`, `respect.dat`), because exact reach and
timing differ in practice.

## 5. Layers of judgement

The bot thinks at several time scales, and most bugs belong to one of them:

1. **Reflexes** (every update, about a second ahead): dodge, line up, shoot. `mover.lua`, `reflex.lua`.
2. **The room:** which enemy first, where to fire from, which pickups are worth the risk, doors, buttons. `reflex.lua`,
   `nav.lua`.
3. **Risk** (twice a second, from the whole run): can we afford to be bold? Not if a hit would kill us or cost the
   floor's devil deal. Yes with soul hearts in front, Holy Mantle, or nothing at stake. `risk.lua`.
4. **The run:** how strong is this build for this floor, what does it need, which item, deal, shop buy or risky room
   is worth it. `strategy.lua`.
5. **Rescue:** when nothing works, a ladder of unstuck moves, then a local AI model picks from real options.
   `rescue.lua`, `brain/rescue_brain.py`.

## 6. Working with an AI assistant

This repo was largely written by an AI coding assistant, directed by a human player. Lessons learned:

- **The human brings game sense, the AI brings reading and typing speed.** Say what you see ("it got hit 3 times in a
  row by Dingle's spit"); let the AI dig through logs and frames.
- **Ask for the diagnosis before the fix.** "Why did it do that?" first. Then "fix the category, add a test, reload,
  measure."
- **Insist on tests and numbers.** The AI is as confident when it's wrong as when it's right; the offline tests and
  the bench are how you find out which.
- **Parallel sessions for research.** Long knowledge jobs (rating all items, the enemy playbook, boss tactics from
  guides) ran in their own AI sessions while the main session kept coding. Rule: only one session edits a given file
  at a time.
- **`CLAUDE.md`** at the repo root gives any AI assistant this repo's rules and method. Keep it up to date.
- **Privacy:** the pre-commit hook (`python tools/install_hooks.py` once) blocks commits that contain home folders,
  e-mail addresses, private IPs or Steam ids. Put your own private words in `privacy_words.txt` (never committed).

## 7. Where to start

**First, get it running** (README: Install, or the Linux section), and watch a run with `logview` open. Read a few `why`
and `hit` lines while watching. That's the fastest way to understand the bot.

**Then pick by what you know:**
- *Isaac player:* watch the bot, open an issue describing what it did wrong as a player would. Or improve a knowledge
  file: a boss tactic, a playbook entry, an item rating.
- *Software engineer:* run the bench (`tools/rooms.py run 10`), pick the worst room, and go through the loop in
  section 3: diagnose with the log and frames, find the category, write a failing test, fix, reload, re-run the bench.
  `test/FOUND_BUGS.md` lists known open bugs with tests already written.
- *Either:* test it on Linux (the Linux setup hasn't been tried on a real Linux PC yet), or improve the tools.

**Open a pull request** with: what was wrong (log lines or a frame help), the category you fixed, the test, and
before/after numbers from the bench or gauntlet.

## 8. Glossary

- **Update / frame:** one game logic step, 30 a second. "8 updates ahead" = about a quarter of a second.
- **Tile:** a 40 px grid square.
- **"Could be here" circle:** where an enemy might be at a time ahead, learned from watching it. The mover pays a cost
  for plans that end inside one.
- **Beam search:** the mover tries short sequences of 3 moves, keeps the 6 best after each, and picks the best first
  move.
- **Risk level:** 0 (careful) to 1 (bold); 0.25 is the old default. Scales the safety settings.
- **Deal at stake:** on floors 2-8, red-heart damage lowers the chance of a devil/angel room; soul/black hearts don't.
- **Bench / gauntlet:** repeatable item-free tests in real rooms / against single enemies.
- **Playbook:** the enemy knowledge file. **Carry:** how much an item inflates results.

## Doing it differently

This method is what one player and an AI found by trial and error. It's probably not optimal: experienced game-AI
people might use reinforcement learning, a proper simulator, or something else entirely. If you'd go about it
differently, open an issue and explain how. Ideas are part of contributing too.
