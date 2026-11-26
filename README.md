# Isaac Bot

[![CI](https://github.com/xoxoFaith1993/isaac-bot/actions/workflows/ci.yml/badge.svg)](https://github.com/xoxoFaith1993/isaac-bot/actions/workflows/ci.yml)

A bot that plays **The Binding of Isaac: Repentance+** by itself. It is a REPENTOGON Lua mod (eyes, reflexes,
movement and floor autopilot) plus a small Python helper on the PC, with an optional local AI model (through
[Ollama](https://ollama.com)) that steps in when the bot gets stuck. It presses the same buttons a controller would.

**Status: work in progress.** It has beaten Mom, but it still takes hits it shouldn't, and many items and characters
aren't handled yet. The goal right now: **no damage on floors 1-2**. See the [roadmap](ROADMAP.md).

> **Save slots:** the bot only ever plays on **save slot 2**. It never loads, continues or starts a run on slot 1,
> so your own save stays untouched. Its deaths and unlocks land on slot 2.

## Find your way around

| | |
|---|---|
| **[docs/START_HERE.md](docs/START_HERE.md)** | **One-page map: the pieces, how they talk, how to test, how a change gets in** |
| [docs/HOW_WE_WORK.md](docs/HOW_WE_WORK.md) | The method used to improve the bot, and game modding in ten minutes |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Rules for changes |
| [ROADMAP.md](ROADMAP.md) | Goals and the current plan |
| [CHANGELOG.md](CHANGELOG.md) | What changed, version by version |
| [docs/BACKLOG.md](docs/BACKLOG.md) | Known work that is waiting |

## Try the tests (no game needed)

With Python 3 and Lua 5.3 or 5.4 installed:

```bash
python3 test/run.py
```

## Requirements to run the bot

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
plain Python, so most of it works unchanged. The Linux pieces are `start-bot.sh`, `test/run.py` and `tools/check.sh`.

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

## Measuring and debugging with the game running

- **Benchmark:** `tools\bench.py` plays a locked set of rooms before and after a change and gives a pass/fail gate.
- **Real-room bench:** `tools\rooms.py collect` saves every room where the bot took a hit; `tools\rooms.py run` replays
  them, worst first.
- **Gauntlet and A/B:** `tools\gauntlet.py` (common Basement enemies plus bosses), `tools\ab_test.py`, `tools\tune.py`.
- **See the game:** `tools\look.py` grabs frames from Steam's background recording; the helper saves a few after every
  hit in `runs\hitframes\`.

## Contributing

Ideas, bug reports and pull requests are welcome, from players and programmers alike. Start with
[docs/START_HERE.md](docs/START_HERE.md), then [CONTRIBUTING.md](CONTRIBUTING.md).

Thinking of reading the game's code to answer a question the bot can't? Read
[docs/REVERSE_ENGINEERING_LESSONS.md](docs/REVERSE_ENGINEERING_LESSONS.md) first: the method we ended up with and the
mistakes we made getting there (not an endorsement, and no tools or links).

**Never commit the game's files.** Unpacked game resources (sprites, `.anm2`, sounds, XML data) belong to the game's
publisher and must stay out of this repository, and so does `knowledge\gamedata.json`.

## License

MIT, see [LICENSE](LICENSE). The Binding of Isaac is a trademark of its owners; this project is not affiliated with
them.
