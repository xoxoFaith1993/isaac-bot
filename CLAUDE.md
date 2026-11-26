# Isaac Bot: rules for AI assistants (Claude Code and others)

Read `docs/HOW_WE_WORK.md` first: it's the method this repo is built with. Short version:

## The loop
1. **Diagnose before fixing.** Use evidence: `runs/live.log` (`room`, `hit`, `why`, `stuck`, `risk`, `aim`, `run`
   lines), frames from `tools/look.py` / `runs/hitframes/`, the `map` command. Say what you found.
2. **Fix the category, not the room.** No one-off patches for a single layout. Comment *why* (with the date and what
   happened) next to the rule.
3. **Add an offline test** in `test/tests.lua` that fails without the fix (and a `test/mutants.lua` entry if you can).
4. **Reload safely:** `tools/reload.ps1` (Windows, run with 32-bit PowerShell) or `bash tools/check.sh --reload`
   (Linux). Never reload with failing tests.
5. **Measure, then gate:** `tools/bench.py run` on a locked suite (`quick` or `v1`), learning frozen, A/B paired;
   `tools/bench.py gate <baseline> <candidate>` must pass before a behaviour change ships. "Can't tell" means more
   reps, not "fine". Name the compared labels in the commit. One run proves nothing.
6. **Write it down:** `PLAN.md`, `test/FOUND_BUGS.md`, `knowledge/*.md`.

## Hard rules
- The bot plays on **save slot 2 only**. Never start or continue a run on slot 1.
- **Never commit game files** (unpacked resources, `knowledge/gamedata.json`), `config.json`, `runs/`, or
  `privacy_words.txt`.
- **No personal details** in committed files (names, home folders, Steam ids, e-mails, IPs). The pre-commit hook
  (`python tools/install_hooks.py`) checks this. Write "the author" when crediting the project owner.
- **No hard-coded paths:** use `config.json` via `brain/botconfig.py` / `tools/config.ps1`.
- **Lua files: no byte-order mark** (the game's Lua can't read it).
- **Knowledge goes in data files** (`knowledge/*.json`, `rules.lua`), not hard-coded lists in code.
- **One writer per file:** if several AI sessions work in parallel, only one edits a given file.
- Long jobs (overnight batches) run detached; don't reload the mod while one is running.
