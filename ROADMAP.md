# Roadmap

Where the project is going, and why. What's already done is in [CHANGELOG.md](CHANGELOG.md); ideas waiting their turn
are in [docs/BACKLOG.md](docs/BACKLOG.md). The quotes are the author's: they're the reasons behind the rules.

## Now: no damage on floors 1-2

No damage on floors 1-2, bosses included (so devil deals stay open), with natural, fast-but-safe play and quick boss
kills. Every behaviour change is measured on a locked benchmark and has to pass its gate (`tools/bench.py`, see
[docs/HOW_WE_WORK.md](docs/HOW_WE_WORK.md)).

**Why floors 1-2 are strict, and later floors aren't** (2026-11-26): "you don't have many resources to protect yourself
from losing the devil or angel deal... Soul hearts allow you to take damage without losing your devil deal chance... you
typically don't get a lot of those in the first 2 floors. You get a lot of resources as you progress floors. Using
abilities, checking secret rooms, the shop... So I can allow getting hit. But it can't be often." So: floors 1-2 no
damage; later floors, hits are rare and only when protection is up (soul hearts, Holy Mantle: `risk.lua` already reasons
about these).

**The measure we push to zero: avoidable hits per room** on the locked benchmark. There's no "good enough at 90%": we
keep going until the hits left are the unavoidable kind.

## The current plan: cards, goals, positioning

Forecast "cards" per enemy, a few fixed goals, and a positioning brain over the reflexes, replacing the growing pile of
hand weights. Full plan and steps: [docs/FORECAST_PLAN.md](docs/FORECAST_PLAN.md). The author's notes while watching
the bot: [docs/LIVE_NOTES.md](docs/LIVE_NOTES.md).

## The long goal: beat Delirium, with a proof video

Post a video (the game plus the bot's live log and helper on screen, repo link in the description, failed attempts
included). The road:

1. No damage on floors 1-2.
2. Beat Mom.
3. Beat Mom's Heart in real runs.
4. An early Delirium drill on the benchmark (dropped into his room with set items, measured like any other room).
5. A full run that ends with Delirium dead.

## The far goal: The Lost, the perfect run

"The Lost can only get hit once per room. Tainted Lost can only get hit once... If you get hit twice in 1 room, you're
dead... It's sort of what I want to strive for, the perfect run. Only, I want this to be superhuman... insanely fast
reflexes, faster than any human can have. The only negative caveat to this is logic... I want to make it as intelligent
as it is fast and agile." (2026-11-26)

It's the same measure with zero tolerance everywhere, so all the hit-avoidance work carries straight over. One fact for
then (from the game's code, [docs/research/RE_CORE.md](docs/research/RE_CORE.md)): after a hit Isaac is invincible for 60
updates (half heart) or 120 (full heart), and a Holy Mantle break gives 60, so for the Lost the 2 s after a mantle break
is the only grace.

## Longer term

- Whole runs on its own, played better than an average player (who beats Mom fairly often but dies a lot after that):
  first Mom, then Mom's Heart / It Lives regularly; stretch goal Satan or ??? (Blue Baby).
- A local AI model making the strategy choices (items, shops, deals, route), with the rules as a safety net.
- A learning loop that retunes settings after each run, including approved overnight sessions, and a run-history board
  (floors reached, deaths by cause, best run).
- Fully self-running: launch, play, death or win screen, next run, with total playtime counted.
- A reusable method for building bots for other games.

## Honest limits

- **Dodging is the hard part.** Bullet-hell bosses (Delirium, Hush, Mega Satan) may stay out of reach for a rule-based
  dodger, even with learning.
- **The game runs in real time,** so learning is slow.
- **Weird items** (Brimstone, Mom's Knife, Tech, homing, flight, Soy Milk) change how it has to aim; they're added as
  they show up.
- **Characters:** plain Isaac first. Others later.

## Working rules

- Fighting well comes before everything else.
- Never change the player's own save slot (slot 1) or normal mod setup without asking. The bot uses save slot 2.
  Anything switched off for bot runs gets switched back.
- Each overnight session is approved first.
