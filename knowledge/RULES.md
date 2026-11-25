# Isaac Bot rulebook

These are game mechanics and the bot's judgement, written once so the bot follows logic instead of being patched
case by case.

- **Machine-readable half:** `mod\isaac-bot\rules.lua` (room priorities, pickups, bombs, secret rooms, the stuck
  ladder). Change the bot's behaviour there.
- **This file:** the reasoning behind those rules. The Stage 4 brain (local LLM) reads it before deciding anything.
- **Confidence:** ✅ = well-known mechanic; ⚠️ = rule of thumb, may have exceptions.

## The first rule: don't get hit
The author, 2026-11-25: "Really, the goal is to just not get hit at all."
- ✅ Any damage on a floor lowers that floor's devil/angel deal chance. A hit costs the deal, not just health.
- So every hit has a fixed price on top of the health it costs (rules.lua `R.risk.per_hit`). Damage is accepted
  only for something big: an item, and only when health allows.
- A curse room costs a hit going in and one going out: only when nothing else is left and health is high.
- Never spend your last soul heart on anything optional.

## Exploring a floor
- ✅ Explore every reachable room before the boss. More rooms mean more pickups, items and chances at secrets.
- ✅ Treasure rooms first: one free item each. Planetariums too (astrology items).
- ✅ The shop is worth a look even when broke (prices, what's on offer). Buying is the brain's call.
- ✅ Curse room doors deal damage on the way in and out. Only use them when no other route is left (last resort).
- ✅ Challenge rooms are an optional ambush for a reward: the brain decides.
- ✅ After the boss: take the boss item, then the trapdoor to the next floor.
- ⚠️ Arcades need coins to be useful. Low priority.

## Secret rooms (guessed, never read from the seed)
- ✅ Hidden doors aren't visible until a bomb (or an item) blows the wall open.
- ✅ A secret room sits in an empty map square next to existing rooms.
- ⚠️ It's usually touching 3+ rooms. 2 is possible but weaker.
- ✅ It's never next to the boss room.
- ✅ A super secret room touches exactly one room, often off a dead end, so it's harder to guess.
- **Policy:** try a 3+ square with 2+ bombs, a 2-square with 4+ bombs, at most 2 tries per floor. Bomb the wall from
  a normal 1x1 room you've already cleared.

## Bombs
- ✅ A bomb's blast is about 95 px. Your own bomb hurts you, so step out after dropping it.
- ✅ Bombs break rocks, poop, tinted rocks (which hide loot), and secret walls. Metal blocks, pillars and statues
  never break.
- **Conserve bombs** (the author, 2026-11-25: "It should really conserve them. Not every opportunity."). There's one
  budget, and every part of the bot asks it first:
  - item on a pedestal behind rocks: 1+ bomb
  - golden chest you have a key for: 2+
  - coins, keys, hearts or a plain chest behind rocks: 5+
  - secret room: 3+ for a strong guess (3+ rooms around), 6+ for a weak one
  - siege (enemies walled in by stone, no other lane for 6 s): 2+
  - the watchdog's bomb step: 4+
  - the brain choosing "bomb": 3+ (otherwise it's turned into "try something else")
- **Poop is never bombed:** shoot it (the author: "you can just shoot the poops"). If poop blocks the way to loot,
  walk up to it and shoot it.

## TNT and puzzle rooms
- ✅ TNT (fixed barrels and the pushable kind) explodes like a bomb when any tear or enemy shot hits it.
  Don't stand next to it; a TNT barrel next to enemies is a free bomb if you shoot it from a distance.
- Some rooms are puzzles (push the TNT or blocks into the right place). When stuck there, the brain decides.
  The author accepts taking a hit to get through such a room rather than getting stuck.

## Fighting
- ✅ Tears fly over pits but are stopped by rocks and blocks. Poop and fires break when shot.
- ✅ Shielded or invulnerable enemies are often tied to something breakable (e.g. a fly linked to a poop). Break the
  thing.
- **Exit plan (the author's rule):** never get cornered. Prefer spots with several open directions to escape through.
- Fight from a distance, lined up on the enemy's row or column, with an open line of fire.

## Pickups
- Always: coins, keys, bombs, batteries, grab bags, soul and black hearts (if there's room).
- Red hearts only when hurt.
- Pills and cards share one pocket slot: pick one up only if the slot is empty. Walking over one with a full slot
  swaps them, and the bot would go back for the dropped one forever.
- Trinkets: only if the trinket slot is empty.
- Chests: normal and wooden yes; golden only with a key; spiked, mimic, red and haunted never (they hurt or ambush).
- Shop items and devil deals: never by walking into them. The brain decides.

## When stuck (the watchdog)
"Progress" means a new room, damage dealt to enemies, or something collected. Without it for 8 s (walking) or
10 s (fighting), climb the ladder, one step every 4 s:
1. **Replan:** drop the current goal and pick another.
2. **Shake:** walk to open ground and shoot in all directions. In a fight it only changes aim; dodging keeps
   steering.
3. **Bomb:** bomb the nearest breakable obstacle.
4. **Leave:** walk out through any open door.
5. **Report:** save the situation (snapshot + room map) to `runs\stuck.jsonl` for batch fixing, allow last-resort
   rooms, and start the ladder again.
   - Later (Stage 4): before reporting, ask the brain with a short description and a menu of actions.
