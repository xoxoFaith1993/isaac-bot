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
6. **Write it down:** `CHANGELOG.md` (what changed), `docs/BACKLOG.md` (what's parked), `ROADMAP.md` (goals),
   `test/FOUND_BUGS.md`, `knowledge/*.md`. (`docs/START_HERE.md` is the map of the project.)

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
- **Commit only your own files** (2026-11-26: the sessions share one checkout and one staging area, and a plain
  `git commit` swept another session's staged CI files into a decompile commit): `git commit -m "..." -- <your files>`,
  never a bare `git commit` or `git commit -a`. Check `git show --stat HEAD` before pushing.
- Long jobs (overnight batches) run detached; don't reload the mod while one is running.

## GitHub issues (jobs for helpers)
- **Before starting work** that an open issue covers (`gh issue list`), read its comments and assignee. If someone has
  claimed it, don't start: tell the author.
- **When a commit finishes the job**, put `Fixes #N` in its message so GitHub closes the issue on push. If only part is
  done, write `Part of #N` and comment what is left.
- **Refill when low** (fewer than 3 open): draft a few from `docs/BACKLOG.md` and `test/FOUND_BUGS.md`, give the
  author a one-line summary of each, and post only the numbers they approve. Never post issues automatically.

## Usage: the right model for the job (the author, 2026-11-26: "make everything as efficient as possible... so I don't burn through the rest of my usage before the week ends")
| Job | Model | Effort |
|---|---|---|
| Design decisions, tricky debugging, judging A/B results, settling reader disagreements | Opus | high |
| Building from a clear spec: features, docs, CI, test-guarded refactors, decompile write-ups | Sonnet | medium |
| Mechanical work: second readers on simple enemy code, facts -> cards, log scans, checks | Haiku | low |
| Lookups and status checks | Haiku | low |

- **Scripts read, models think:** a repeated check becomes a tool (`tools/deals.py`, `tools/queue.py`, the card check), not
  a model reading a long log.
- **Fresh sessions for new phases:** a long session re-reads its whole history every turn. Start a new phase in a new
  session with a short brief; facts live in files, not in the conversation.
- **Wait in the background, never poll:** background waits, the watcher queue and session notes wake you.
- **Subagents:** pass a cheaper `model` for searches and mechanical pieces.
- **Between sessions:** short messages; the facts go in files, the message carries a pointer.
