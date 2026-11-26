# Changelog

What changed in the bot, newest first. The version is `VERSION` in `mod/isaac-bot/main.lua` (the log's `start` line
shows it). Dates are 2026. Details and measurements: the commit messages, and [docs/HISTORY.md](docs/HISTORY.md) for
the first versions.

## Unreleased (project upkeep, no change to how the bot plays)
- Continuous integration on GitHub: Lua tests and mutant check, Python tests, privacy check, card check.
- `test/run.py`: one test runner for Linux, macOS and Windows.
- Docs reorganised: [START_HERE](docs/START_HERE.md) map, [ROADMAP](ROADMAP.md), this changelog,
  [BACKLOG](docs/BACKLOG.md), [HISTORY](docs/HISTORY.md). They replace the single `PLAN.md`.

## 1.2.x: measure everything (11-25 and 11-26)

### 11-26
- **1.2.52** Card attacks: a boss's known laser lines are avoided (`card_attacks`, off until its A/B passes).
- **1.2.51** Horsemen cards; every boss fight is recorded.
- **1.2.50** Never bombs where the blast could kill him.
- **1.2.49** Devil and angel deals: sees the deal doors (they were invisible to the walker) and weighs each offer.
- **1.2.48** Ignores a red fire that can't hit him.
- **1.2.47** Baits a closed Host from close by; walks around pits. Positioning brain started (`position`, off).
- **1.2.45** Skips a pressure plate with no way in.
- **1.2.44** A locked door seen with no key is written off at once.
- **1.2.43** An unpressed plate outranks red fires.
- **1.2.42** Plans Isaac at his real speed (he moves twice per update). Benchmark: **better**, about 0.9 fewer hits
  per room.
- **1.2.41** Enemy-card forecasts can feed the planner (`forecast`, off: can't tell yet if better).
- **1.2.31 – 1.2.40** Lag fix (Gemini fight 65 → 11 ms); Gemini, Gluttony, Host, Horf, Haunt, Sloth and Gurgling
  fixes; behaviour recorder; item-free benchmark. Gate: passed (not worse).
- **1.2.30** Timers survive a new run's frame counter (the planner could freeze).

### 11-25
- **1.2.29** Gemini's cord balls no longer counted as enemies (lag fix).
- **1.2.28** The benchmark: locked room suites, frozen learning, paired A/B, error bars, a pass/fail gate.
- **1.2.27** "Stand for a sure shot" works on the new movement core.
- **1.2.26** Dashing enemies with known tells get a firing spot between dashes.
- **1.2.25** A/B switches for `plant_feet` and `tell_timing`; two-step active items.
- **1.2.23 – 1.2.24** Better aim (plants his feet, learns tear speed and reach); never plants into a coming attack.
- **1.2.22** Aim report per shot kind; hurtful animations treated as attack lines.
- **1.2.21** Charge windows keep wall sense; dashes predicted straight; bombs rocks instead of crossing spikes.
- **1.2.19** Finishes damaged enemies first and sticks with a target.
- **1.2.18** Circles ahead of chasing bosses ("ring-kite"); aim counts more in boss fights.
- **1.2.16 – 1.2.17** Never enters a room with garbage data; red fires are shot out.
- **1.2.13 – 1.2.14** The live watcher: spots loops, sorts hits by cause, learns small lessons, queues code problems.
- **1.2.9 – 1.2.12** Uses invincibility and boss attack windows; better shot leading.
- **1.2.5 – 1.2.8** Risk layer (bold when it's safe), run strategy, boss tactics, surprise-bomb logging.
- **1.2.4** Linux support (Steam + Proton).
- **1.2.3** Enemy playbook sent to the mod; overnight batch; privacy guard.

## 1.1.x: movement core rebuilt (11-25)
- **1.1.54** First public version on GitHub.
- **1.1.35 – 1.1.50** Learned Isaac's real top speed and acceleration; bounce, corner, burrower, secret-room and
  own-bomb fixes.
- **1.1.14 – 1.1.34** Shoots open poop "gates"; spawners first; real-room bench; offline logic tests; lag fix
  (about 20 ms → 3.5 ms per update); offline compile check before every reload.
- **1.1.0 – 1.1.13** New movement core: learned reach per enemy type and a search several moves ahead, replacing
  about 40 hand-tuned weights. Learned movement is saved between sessions; code reloads in the running game.

## 1.0.x: first full floors (11-25)
- **1.0.0 – 1.0.22** Persistent learning (tells, respect, tuning); gauntlet and A/B tools; creep, leap and homing
  handling; floor-wide memory of doors that don't work; curved shots. Reached floor 4.

## 0.x: from nothing to Basement II (11-25)
- Pipe between game and PC, eyes, reflexes, floor autopilot, rescue ladder, local AI model for when it's stuck.
