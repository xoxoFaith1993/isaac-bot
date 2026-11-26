# Reading the game's code: what we learned

**This is not an endorsement.** Reading a game's compiled code may be restricted by its licence and by the law where
you live; that call is yours. This page gives no tools, downloads or links. It only describes the method we ended up
with and the mistakes we made getting there, so that if you go down this road you don't repeat them.

**Never contribute decompiled code or game files to this repository.** What goes in is game *facts* in plain words and
numbers (a speed, a range, a timing), each checked against how the game really plays.

## Why we ended up here

The bot started with rules of thumb tuned by watching it play: "stay out of this boss's row", "keep away from corners".
Each fix helped one fight and quietly moved others, because every rule was a weight in one shared score. The game's
behaviour is compiled into the program, not written in its data files, so for exact answers (how far a slide goes, when
an attack can come, how strong a pull is) there was no other source than the code itself.

## Try the cheap sources first

In order of cost:
1. **Watch it from inside the game.** A recorder that logs each enemy's state, timers, speed and every shot it fires
   answers many questions for free while the bot plays (`mod/isaac-bot/recorder.lua`).
2. **What others already wrote.** Community re-implementations and modding API docs often cover common enemies. Use them
   to check your own readings, not as truth.
3. **The code**, only for what 1 and 2 can't answer.

## The method that worked

1. **Calibrate on something you already know.** Our first reading was an enemy whose behaviour we had already measured.
   Only after it matched did we trust readings of unknown ones. Later, a boss with a public community re-implementation
   gave a third independent check.
2. **Decode the shared building blocks first.** Most enemies are built from a few shared parts: chase, charge along a
   line, hop, aimed shot, ring shot, laser line, creep trail, spawn, and so on. We found 16. Once those are understood,
   a plain enemy is mostly "these parts, these numbers", which is quick to read.
3. **Decode what hurts you most.** We ordered the queue by the bot's own hit log. The top hazard turned out to be spikes
   (43 hits), not any enemy.
4. **A fact needs two sources.** A reading becomes something the bot relies on only when the code and a recording agree.
5. **Blind readers, spent where they matter.** A reader who hasn't seen anyone else's interpretation reads the same
   code independently. Two of them for the shared parts, the player's own rules and bosses; one plus the recording for
   plain enemies. It costs real usage and time, so don't spend it everywhere.
6. **Label every fact** with what it describes (move / attack / timing / body / terrain), where it came from, and how
   it was checked (one reader, two readers, recording, contradicted). When the bot later gets hit by something its
   forecast called safe, the label points at the one piece to re-read, instead of starting a guessing game.
7. **Facts are forecasts, not rules.** This was our biggest lesson. A decoded fact says where danger *will be* (where a
   slide ends, where a lob lands). Feed it into prediction, and keep the decisions to a few fixed goals (don't get hit,
   keep a way out, deal damage). Two enemies' forecasts simply add up; two hand-tuned rules fight each other.
   See [FORECAST_PLAN.md](FORECAST_PLAN.md).

## Mistakes we made (so you don't have to)

- **Patching per encounter for too long.** Every new fight got its own weight. By the time we had a few dozen, fixing
  one boss broke another. Should have moved to forecasts much earlier.
- **Two readers on everything.** Accurate, but it burned through usage on simple enemies that a single reading plus a
  recording would have settled.
- **Letting the analysis eat the computer.** Decompiling one very large function took over 13 GB of memory and nearly
  froze the PC. Cap memory and time per function, skip the giants (read their raw instructions instead), and run a
  watchdog.
- **Trusting a reading before checking it.** Some first readings were right in shape but wrong in a detail (a timing,
  a range). Only the recording check caught those.
- **Logging hits without a source.** 28 hits came from "unknown". They turned out to be the curse-room door. Make sure
  every hit records what caused it before you go looking in the code.

## Keeping it private and legal

- Decompiled code stays on your own machine, never in a commit.
- Facts go into the repository as plain words and numbers, with the checking label.
- Never commit game resources (sprites, sounds, data files).
