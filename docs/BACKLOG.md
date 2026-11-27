# Backlog

Work that is known but not being done yet. One heading per item, so each can later become a GitHub issue. The quotes
are the author's: they explain why the item matters. When an item is done, remove it here and add a line to
[CHANGELOG.md](../CHANGELOG.md).

Open bugs with tests already written live in [test/FOUND_BUGS.md](../test/FOUND_BUGS.md), and the notes the author
sends while watching in [LIVE_NOTES.md](LIVE_NOTES.md).

## Core (toward no damage on floors 1-2)

### Judge a spot by the space left after the next attack ("future space")
Judge a spot by the space you'll have AFTER the next attack, not the space you have now (the author, 2026-11-26): "When
you aggro those gurglings, they will chase after you in a straight or sideways line... the creep effectively cuts you
off. If you're in a bad position when the gurgling goes off, it's inevitable you will take damage."
- **Predicted creep:** enemies tagged charges_on_line/dashes + leaves_creep (Gurglings first) project creep along the
  row/column they'll charge down; that strip counts as soon-to-be floor danger, and `waysOut` counts it too, so a spot
  that will be boxed in scores like a corner.
- **Aggro on our terms:** only line up with a Gurgling when the sidestep after its charge still leaves open floor.
- **Knockback** ("you can also affect the gurglings' sideways and straight lines... by shooting it because of the
  knockback"): never lock a predicted line in; re-predict from its real position and speed every update. And use it:
  shooting a charge head-on slows it, from the side bends it, so aim so the creep lands away from the open side of the
  room and our escape route.
- **Dead-end pockets** ("stuck in the pot... going right into the bottom pot in this gurgling fight"): it hugged the
  bottom wall, sliding right while shooting left, with the Gurglings chasing along the wall, into the pocket between the
  bottom-right pot and the corner, and was hit there. The 1.2 s look-ahead can't see that a wall run ends in a pocket;
  count a pocket (wall + obstacle + corner) ahead on the current run as a closed way.
- The same principle covers Gemini (where you'll be when he wakes), Gluttony's laser and Dingle's dash. Measured with
  the benchmark like everything else.

### Indecision in big rooms with many fast enemies
"These bigger rooms, especially the 4x4s with many mobs, especially fast moving ones like spiders... how indecisive he
is from the risk factors. He could be a mile away and be scared... and if you bring a shitty terrain, it is a perfect
storm for him to just do nothing." (2026-11-26)
- Likely cause: the learned "could be here" circles of hop-and-stop movers (spiders) grow large over the 1.2 s
  look-ahead, so many of them cover most of a big room and every option looks equally bad.
- Fix with data, not tuning: the recorder's measured hop range and timing per enemy to size those circles, and danger
  from far enemies that can't reach us within the look-ahead counting less.
- Measure on big-room benchmark rooms (time spent not shooting, hits).

## Later (not core)

"Some of them are not priority and can be added at a later date to not mess with the true priority of the core
fundamentals." (2026-11-25) Core = no damage on floors 1-2, natural movement, no loops. These wait.

### Bomb purple fires
They shoot homing tears and tears don't put them out (a bomb does, the author thinks). Bomb one when it's a threat and
the bomb budget allows (a new `R.bombs.fire_purple`).

### Bomb blue fires for soul hearts
A small chance of soul hearts when put out (bomb only). "Always worth bombing if you have enough bombs": a cleared-room
goal with its own bomb minimum (`R.bombs.fire_blue`, about 3).

### Aim at burrowers' last hole
Plan the firing spot on the hole where a burrowed enemy last surfaced (Round Worms).

### Play style per item
Like the invincible window: homing tears = spray freely; flight = ignore pits.

### Flying items: rocks and pits are open floor
"When he gets flying items, he can walk over the terrain, just not fire." (2026-11-26) Today `blocked()` only lets a
flier over pits; with flight, rocks (and spikes) are passable too, but lit fires still burn.

### Two-input active items: check them live
Bob's Rotten Head and similar need two presses and a direction. A two-step version went in on 2026-11-25; it still
needs a live check.

### Mom's Hand in deal rooms
"Took damage in the devil deal room because of Mom's hands... Mom's hand grabs you and pulls you out of the devil room"
(2026-11-26; hit by 213.0). Once the deal decision is made (nothing worth buying), leave right away instead of
lingering; and dodge the hand's shadow (it marks where the hand lands). A card for 213.0 from the research queue gives
the timing.

### Use the "manual" cards
"I haven't seen him use one... those cards really do change the game... he dropped a Joker card for a different card,
and now he has a Moon card that he won't use." (2026-11-26) 23 cards are `use: manual` in
`knowledge/consumable_ratings.json`, so they are never used: mostly the teleports (Emperor = boss room, Hermit = shop,
Stars = treasure room, Moon = secret room, Joker = devil/angel room) plus Perthro, Chaos Card, Credit Card, ? Card,
Dice Shard, Cracked Key, Wild Card, some reversed tarots and Souls. Needs:
1. each card's "when it pays" rule (Joker when a deal is affordable and still live; Stars on a floor whose treasure room
   is far or locked; Emperor to skip a long floor when the bot is strong...);
2. the walker handling a teleport (new room, then carry on);
3. a swap rule: Joker and Moon have the same rating (2), so the bot saw an even swap. Rate them by what they're worth on
   THIS floor, and never drop a card for an equal one.

### Curse rooms: open the red chest
"Skipped the red chest, which is typically a reason why you go into the curse room to begin with." Seen again
2026-11-26: "When entering cursed rooms, he still doesn't grab the chest." The entry/exit spike hit is the price; the
chest is the reward (the risk layer already decides whether to go in at all). Cause: `PICKUP_REDCHEST` is in
`R.pickups.never` (`rules.lua`) for every room. Fix: allow it inside curse rooms only, with its own small value, and
dodge what comes out (troll bombs, spiders).

### Shoot chargers from just outside their trigger range
Seen by the watcher 2026-11-26: a minute with no damage dealt against Chargers at one heart. They only charge within
200 px of their row or column (`R.charge_reach`), so a firing spot in their line at 210-250 px is safe; the planner
skips moving dashers, so it never plans one.

### Teach attack timings from the game's animation events
Pre-seed "tells" from the animation events (for example Dingle Spit Shoot@3, Haunt LaserNoSkin Shoot@17) so the bot
knows when each attack fires before it ever gets hit; kept in a gitignored file.

### Check the draft enemy-playbook entries
201 entries were drafted by a local AI from wiki text. Check them before the helper sends them.

### Lead shots on the Haunt better
Still not strong (2026-11-25: "doesn't have to change immediately"). It slides and turns at the walls; the lead uses a
settled average velocity clamped to the room.

### Delirium as a dodging stress test
The hardest boss ("the unfair": it shifts into almost every boss, not quite as the real ones, projectiles everywhere).
Not a cheat sheet for single bosses and not core (floor 11+), but a good later benchmark drill for pure dodging: a
`bench_suite_delirium` once floors 1-2 pass the gate, scored on hits per minute survived.

### Ideas from outside sources, once the recorder has profiles
(Checked in `docs/research/OUTSIDE_SOURCES.md`.) Dash lines from `V1`/`TargetPosition` during wind-ups, only where a
profile shows they predict the dash; tells on `NpcState` changes; the exact fall of lobbed shots (checked against
`recshot` lines first); chasers blocked by rocks (`Room:CheckLine`), measured before changing anything.

### Bomb out of a secret room when it pays
The bot leaves a secret room the way it came in. Bombing out can be worth a bomb when the wall leads to a curse room (no
door damage) or a treasure room (no key needed, or few keys left).

### A laptop as a second test machine
Parked (usage cost).

### Isaac's own creep trail from an active item looks harmful to the bot
Live note 26 (2026-11-26): the bot treats the trail its own item leaves as something to avoid. Parked by the author
(one specific item, not a priority). To check first: which item it is and which creep variant it spawns, since the
hurting-creep list (`danger.lua`, `reflex.lua`) only names enemy variants.

## Situations to watch

### Surprise bombs
"In that TNT room... I don't know what spawns the random troll bomb and how often, if it's RNG or a scripted room in a
seed. But it's something to make note of. Things like that can happen." (2026-11-25)
- **What happened:** floor 1, a trap room (layout 765): 3 s after walking in, a hit for a full heart with no enemy as
  the source, most likely a troll bomb.
- **Where they come from:** the game's room files list each layout's spawns (some entries have weighted random
  alternatives, so a layout can have a bomb only sometimes). Troll bombs also drop from chests, beggars and some
  pickups, and certain enemies and plates can spawn them.
- **Collecting the answer:** from 1.2.8 every bomb the player didn't drop is logged as a `bomb` line (variant, what
  spawned it, updates since entering the room, room layout).
- **To check:** troll bombs are live bombs, so the movement core already avoids their blast. One that appears as Isaac
  walks in gives about 1.5 s to react, so the first update after entering a room must already count it.
