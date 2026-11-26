# Contributing

Thanks for helping! **New here? Start with [docs/HOW_WE_WORK.md](docs/HOW_WE_WORK.md)**: the big picture, game
modding in ten minutes, the improvement loop (watch, diagnose, fix the category, test, reload, measure), and where to
start depending on whether you know the game, code, or both. You don't need to write code to help: game knowledge
in `knowledge/` (enemy playbook, item ratings, boss tactics) makes the bot smarter too.

Using an AI coding assistant? `CLAUDE.md` gives it this repo's rules and method.

A few rules keep the bot safe to run and the repo clean.

- **Run the offline tests before a pull request:**
  `C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File test\run.ps1`
  (32-bit PowerShell, because Isaac's Lua DLL is 32-bit). All tests must pass.
- **Fixing a bug?** Add a scenario to `test\tests.lua` that fails without your fix, and if you can, an entry in
  `test\mutants.lua` so `run.ps1 -Prove` keeps checking it.
- **Lua files must not start with a byte-order mark** (Isaac's Lua can't read it). `tools\luacheck.ps1` catches it.
- **Save slot 1 is sacred:** the bot only ever plays on slot 2. Don't change that.
- **No game files:** never commit the game's unpacked resources, `knowledge\gamedata.json`, your `config.json`, or
  anything from `runs\`.
- **No hard-coded paths:** read them from `config.json` (`brain\botconfig.py`, `tools\config.ps1`).
- Gameplay changes are best judged by numbers: the gauntlet (`tools\gauntlet.py`) or the real-room bench
  (`tools\rooms.py run`), before and after.

Ideas are welcome too: open an issue and describe what the bot did and what it should have done.
