# Isaac Bot

A bot that plays **The Binding of Isaac: Repentance+** by itself. It is a REPENTOGON Lua mod (eyes, reflexes,
movement and floor autopilot) plus a small Python helper on the PC, with an optional local LLM (through
[Ollama](https://ollama.com)) that steps in when the bot gets stuck.

**Status: work in progress.** It has played through to floor 4 on its own and fights most regular Basement
enemies without being hit, but bosses still hurt it and many items and characters aren't handled yet. The author's goal
for now: no damage on floors 1-2. See [PLAN.md](PLAN.md) for the full technical history and what's next.

> **Save slots:** the bot only ever plays on **save slot 2**. It never loads, continues or starts a run on slot 1,
> so your own save stays untouched. Its deaths and unlocks land on slot 2.

## Requirements

- Windows, or Linux with Steam + Proton (see [Linux](#linux))
- The Binding of Isaac: Repentance+ (Steam)
- [REPENTOGON](https://repentogon.com) and its launcher
- Python 3 (standard library only)
- Optional: Ollama with a local model (the stuck-rescue brain and `tools\exam.py`)
- Optional: ffmpeg and Steam's background game recording (for `tools\look.py`, frames of the moments before a hit)

## Install

1. Copy the three mod folders from `mod\` into the game's `mods` folder
   (`...\steamapps\common\The Binding of Isaac Rebirth\mods\`):
   - `isaac-bot` (the bot itself)
   - `isaac-bot-out` (carries the bot's messages to the helper)
   - `isaac-bot-data` (dumps the game's item, trinket and card data once per launch)

   A directory junction (`mklink /J`) instead of a copy keeps the game in sync with your checkout.
2. Copy `config.example.json` to `config.json` and fill it in:
   | Key | What |
   |---|---|
   | `game_dir` | the game folder (holds `isaac-ng.exe` and `Lua5.3.3r.dll`) |
   | `repentogon_launcher` | full path of `REPENTOGONLauncher.exe` |
   | `repentogon_ini` | the launcher's settings file; empty = `Documents\My Games\repentogon_launcher.ini` |
   | `python` | Python to run the helper with; default `python` on PATH |
   | `ffmpeg` | ffmpeg for `look.py`; default `ffmpeg` on PATH |
   | `steam_userdata` | `<Steam>\userdata\<your id>` for Steam's recordings; empty = found automatically |
   | `bot_dir` | where `runs\` and `knowledge\` live; empty = this folder |
3. Run `start-bot.cmd`. It opens the helper and log windows, starts the game through the REPENTOGON launcher, and the
   mod loads slot 2 and starts a run as Isaac. `restart-bot.cmd` closes the game first (use it after changing the
   mod).

`knowledge\gamedata.json` is not in the repo: the `isaac-bot-data` mod writes the game's own item data on the first
launch and the helper saves it there.

## Linux

The game runs through Steam's Proton; the bot's mod runs inside the game the same as on Windows, and the helper is
plain Python, so most of it works unchanged. The Linux pieces are `start-bot.sh`, `test/run.sh` and `tools/check.sh`.

1. **The game with REPENTOGON under Proton.** Install the game in Steam (Proton is picked automatically) and start
   it once. Then install REPENTOGON following [its own instructions](https://repentogon.com) for Linux/Steam Deck,
   and check that the title screen shows REPENTOGON when you start the game from Steam. This is the one step that
   hasn't been tested on Linux by us yet; everything below only needs the game to start with REPENTOGON.
2. **Packages** (Debian/Ubuntu/Mint names):
   ```
   sudo apt install python3 xdotool lua5.3 ffmpeg
   ```
   `xdotool` presses Enter on the title and save screens (X11, or XWayland, which Proton games use). Without it,
   press Enter on those two screens yourself. `lua5.3` is only for the offline tests, `ffmpeg` only for `look.py`.
   Ollama is optional, as on Windows (`curl -fsSL https://ollama.com/install.sh | sh`).
3. **Mods:** link the three mod folders into the game's `mods` folder (default Steam library path shown):
   ```
   GAME=~/.local/share/Steam/steamapps/common/"The Binding of Isaac Rebirth"
   for m in isaac-bot isaac-bot-out isaac-bot-data; do ln -s "$PWD/mod/$m" "$GAME/mods/$m"; done
   ```
4. **config.json:** only needed if the game is in another Steam library. `game_dir` defaults to the path above and
   `python` to `python3`; the `repentogon_*` keys are Windows-only.
5. **Start:** `bash start-bot.sh` (opens the helper and log in terminal windows, starts Ollama if installed, then the
   game through Steam). `bash start-bot.sh --restart` closes the game first.
6. **After changing the mod:** `bash tools/check.sh --reload` (every Lua file compiles + offline tests, then the
   running bot reloads the mod).

`tools/overnight.py` works on Linux too (run it as `systemd-inhibit python3 tools/overnight.py` to keep the PC awake).

## How it works

- **Eyes** (`eyes.lua`): ten snapshots a second of Isaac, enemies, shots, lasers, pickups, doors and the room grid.
- **Reflexes and movement core** (`reflex.lua`, `mover.lua`): learns how far each enemy type can reach in 0.2-1.5 s
  from what it sees (saved to `knowledge\motion.dat`), then runs a short beam search over move sequences (~1.2 s
  ahead) with one safety cost; lining up a shot is a reward inside the same search. Learned attack wind-ups
  (`tells.lua`) and a danger map of spikes, creep, fires and bombs (`danger.lua`) feed into it.
- **Navigation** (`nav.lua`): pathfinding around rocks, pits and spikes, a floor map, door choice, pickups weighed by
  value against the risk of getting hit (`rules.lua`), bombs used sparingly.
- **Risk layer** (`risk.lua`): one number, careful (0) to bold (1), from the whole run: would a hit kill us, would it
  cost the floor's devil/angel deal (only red-heart damage does; soul hearts and Holy Mantle go first), how many hits
  of buffer we have, and whether a room is taking far longer than our damage says it should. It scales the movement
  core's safety settings, makes a hit cheaper for good loot when nothing is at stake, and opens curse and challenge
  rooms only when we can afford them. `risk|0.25` pins the old careful play, `risk|auto` lets it decide.
- **Run strategy** (`strategy.lua`): a profile of the build (strength for this floor, weaknesses), items valued for
  this run (`knowledge\item_ratings.json` plus what fixes the build's weaknesses), choice pedestals, devil deals (only
  strong items, never below 2 heart containers), shop buys by need, and cards/pills
  (`knowledge\consumable_ratings.json`).
- **Live watcher** (`brain\watcher.py`, inside the helper): spots loops as they happen and nudges the bot, sorts every
  hit by cause, learns small capped per-enemy adjustments (kept only if they cut that cause's hits), and queues what
  needs a code fix with the evidence (`runs\watch\`, `tools\queue.py`).
- **Rescue watchdog** (`rescue.lua`): no progress for a while climbs a ladder: replan, shake, bomb, leave, report.
- **Brain** (`brain\rescue_brain.py`, optional): when the watchdog runs out of ideas, the mod lists the real options
  and a local model picks one (`options.lua`, `knowledge\RULES.md`).
- **Helper** (`brain\helper.py`): the pipe between the game and the PC (through the mods' save files), the live
  dashboard and log, run logs in `runs\`, and saving what the bot learned (`knowledge\*.dat`, `tuned.json`).

## Testing

- **Offline logic tests:** `test\run.ps1` runs the bot's real Lua code against scripted rooms (`test\mock.lua`,
  `test\tests.lua`) inside Isaac's own Lua DLL, no game needed. The DLL is 32-bit, so use 32-bit PowerShell:
  ```
  C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File test\run.ps1
  ```
  `-Prove` checks that every fix's test fails without the fix (`test\mutants.lua`). `tools\luacheck.ps1` compiles
  every Lua file the same way; `tools\reload.ps1` runs both, then reloads the mod in the running game.
  On Linux: `bash test/run.sh` (system Lua 5.3) and `bash tools/check.sh`.
- **Real-room bench:** `tools\rooms.py collect` saves every room where the bot took a hit (by layout ID);
  `tools\rooms.py run` replays them in the game, worst first.
- **Gauntlet and A/B:** `tools\gauntlet.py` (every common Basement enemy plus bosses), `tools\ab_test.py`,
  `tools\tune.py`.
- **See the game:** `tools\look.py` grabs frames from Steam's background recording; the helper saves a few after
  every hit in `runs\hitframes\`.

## Contributing

Ideas, bug reports and pull requests are welcome, from players and programmers alike. **Start with
[docs/HOW_WE_WORK.md](docs/HOW_WE_WORK.md)**: how the bot is built and the method used to improve it (watch, diagnose
from logs and frames, fix the category, add a test, reload safely, measure on the bench). Then
[CONTRIBUTING.md](CONTRIBUTING.md) for the rules. Run the offline tests (`test\run.ps1`) before opening a PR, and add
a test for any bug you fix.

**Never commit the game's files.** Unpacked game resources (sprites, `.anm2`, sounds, XML data) belong to the game's
publisher and must stay out of this repository, and so does `knowledge\gamedata.json`.

## License

MIT, see [LICENSE](LICENSE). The Binding of Isaac is a trademark of its owners; this project is not affiliated with
them.
