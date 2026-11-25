# Isaac Bot: item knowledge

Items are outliers. One strong item makes a run look good and can hide bugs. One bad item can kill the bot early.
This file and `item_ratings.json` tell the bot two things about each of the game's 772 collectibles:
- how good the item is **for this bot**;
- how much it inflates a run's results (its **carry**).

- **Machine-readable half:** `item_ratings.json` (next to this file). Read it; don't hard-code lists in Lua.
- **Made:** 2026-11-25, from `gamedata.json` (the EID descriptions the bot's data mod dumped from the game) plus
  Isaac knowledge, judged against `RULES.md` and `rules.lua`.
- **Not rated yet:** trinkets (195) and cards (112). They're in `gamedata.json` and could get the same treatment
  later.

## How the ratings were made

Every item was judged for **this** bot, not for a human player. The bot:
- plays carefully and wants to take no damage at all (a hit also lowers the floor's deal chance);
- fights from a distance, lined up on the enemy's row or column;
- holds the fire button down most of the time;
- doesn't yet do charge-and-release attacks, double-taps, aiming a crosshair, or two-step actives.

So the scores differ from the game's own `quality` (0-4) on purpose:
- **Rated down:** "works after you get hit" items (dead weight for a no-hit bot); close-range and contact items;
  items that change how aiming works; items that can hurt Isaac.
- **Rated up:** defensive items (Holy Mantle, The Wafer, Stop Watch, shot blockers) and anything that rewards
  never being hit (Crown of Light, Paschal Candle).

How each of the 772 items was handled:
- **741 rated by hand.** Each has a rating, a carry score, tags, a one-line reason, and for actives, when it's
  safe to press.
- **Stat changes read from the EID text.** These are parsed into `stats` (for example
  `{"damage": 0.5, "damage_mult": 1.5}`). Stat-up and stat-down tags are added from that text automatically.
  Changes that only last for a room are left out.
- **31 rated from game quality only** (`source: "quality-fallback"`). These items (ids 733-783) have no description
  in the dump. They're probably from an installed mod. Their rating is capped at 2, and their actives are never
  auto-used.
- **59 items marked `unsure: true`.** That's those 31, plus items whose mechanics I wasn't sure of: Kamikaze! (does
  it hurt Isaac?), Dead Sea Scrolls, Chocolate Milk, Mega Blast, Sulfur, Birthright and Delirious. An unsure
  active is never marked safe to auto-use. Test these before trusting them.

### Scales
| Field | Meaning |
|---|---|
| `rating` 0-4 | 0 = avoid (hurts this bot), 1 = weak or mixed, 2 = fine, 3 = good, 4 = take it whenever it's offered |
| `carry` 0-5 | How much the item inflates results: 0 = none, 1 = small, 2 = noticeable, 3 = big, 4 = huge, 5 = carries the run alone |
| `tags` | Readable tags such as "damage up", "flight", "risky: costs health", "bad: confusing controls", "active: two-step" (`tag_glossary` lists them all; `tag_codes` has the short forms) |
| `active.auto_use` | `fight` / `boss` / `hurt` / `clear` / `close` / `any` = safe in that situation; `manual` = needs new code; `never` = a decision or harmful |
| `active.safe_to_auto_use` | true only for the situations above that are safe, and never when the item is unsure |

**Rating and carry are different things.** Brimstone, Mom's Knife, Tech X, Epic Fetus and Ipecac have carry 4-5,
because they're run-winning damage. Their rating is low (1-2) because the bot can't use them properly yet:
- Brimstone and Tech X need charge-and-release.
- Mom's Knife needs a hold-and-throw.
- Epic Fetus needs a crosshair steered onto enemies.
- Ipecac's explosions can hurt Isaac.

When the bot learns those attacks, raise their ratings. Leave their carry as it is.

## The 30 best items for this bot
| # | Item (id) | Rating | Carry | Game quality | Why |
|---|---|---|---|---|---|
| 1 | Sacred Heart (182) | 4 | 5 | 4 | Homing and a big damage multiplier: carries any run. |
| 2 | Godhead (331) | 4 | 5 | 4 | Homing tears with a damage aura: carries any run. |
| 3 | Cricket's Head (4) | 4 | 4 | 4 | Huge damage multiplier, no downside. |
| 4 | Magic Mushroom (12) | 4 | 4 | 4 | Big all-round stat boost. |
| 5 | Polyphemus (169) | 4 | 4 | 4 | Massive damage per tear, slower fire. |
| 6 | The Wafer (108) | 4 | 3 | 4 | Most hits cost only half a heart. |
| 7 | Stop Watch (232) | 4 | 3 | 4 | Slows every enemy and their shots, permanently. |
| 8 | Holy Mantle (313) | 4 | 3 | 4 | Blocks the first hit in every room: made for a no-damage bot. |
| 9 | Incubus (360) | 4 | 3 | 4 | Second shooter copying Isaac's tears. |
| 10 | Crown of Light (415) | 4 | 3 | 4 | Double damage while health is full, and a no-hit bot keeps it full. |
| 11 | Twisted Pair (698) | 4 | 3 | 4 | Two shooters copying Isaac. |
| 12 | Psy Fly (581) | 4 | 2 | 4 | Chases and blocks enemy shots. |
| 13 | Revelation (643) | 3 | 3 | 4 | Flight and soul hearts; the beam doesn't replace tears. |
| 14 | Pyromaniac (223) | 3 | 2 | 4 | Immune to explosions and fire; explosions heal. |
| 15 | 20/20 (245) | 3 | 2 | 4 | Double shot. |
| 16 | Binge Eater (664) | 3 | 2 | 4 | Food pedestals that heal and boost. |
| 17 | Spoon Bender (3) | 3 | 2 | 3 | Homing tears forgive bad aim. |
| 18 | Pentagram (51) | 3 | 2 | 3 | Damage up plus deal chance. |
| 19 | Technology (68) | 3 | 2 | 3 | Laser tears: instant hits, no travel time. |
| 20 | Death's Touch (237) | 3 | 2 | 3 | Damage, bigger piercing tears. |
| 21 | Eve's Mascara (310) | 3 | 2 | 3 | Double damage, fewer tears. |
| 22 | Toxic Shock (350) | 3 | 2 | 3 | Poisons every enemy when Isaac enters a room. |
| 23 | Seraphim (390) | 3 | 2 | 3 | Familiar with Sacred Heart tears. |
| 24 | Lusty Blood (411) | 3 | 2 | 3 | Damage up for each kill in the room. |
| 25 | Eye of Belial (462) | 3 | 2 | 3 | Piercing tears that home after a hit. |
| 26 | Technology Zero (524) | 3 | 2 | 3 | Electric links between tears; extra damage with no change to aiming. |
| 27 | Paschal Candle (567) | 3 | 2 | 3 | Fire rate grows with every room cleared without a hit: rewards careful play. |
| 28 | Immaculate Heart (573) | 3 | 2 | 3 | Health and damage multiplier. |
| 29 | Dogma (633) | 3 | 2 | 3 | Damage, flight, a shield. |
| 30 | 1up! (11) | 3 | 2 | 2 | Extra life. It inflates survival, not skill. |

## The 30 worst items for this bot
These items actively harm this bot, or make its results meaningless. The "weak because it only works after a hit"
items aren't listed here: they're dead weight, not dangers.

| # | Item (id) | Rating | Carry | Game quality | Why |
|---|---|---|---|---|---|
| 1 | Anti-Gravity (222) | 0 | 0 | 1 | Tears hover while fire is held, and the bot holds fire, so they hardly ever fly. |
| 2 | Tiny Planet (233) | 0 | 0 | 0 | Tears orbit Isaac, so aiming stops working. |
| 3 | The Ludovico Technique (329) | 0 | 0 | 1 | One giant tear you steer: completely different aiming. |
| 4 | Marked (394) | 0 | 0 | 0 | Auto-fires at a target you move: the bot's aim stops working. |
| 5 | No. 2 (378) | 0 | 0 | 2 | Holding fire drops lit bombs at Isaac's feet. |
| 6 | Rocket in a Jar (583) | 0 | 0 | 1 | Bombs dropped while shooting become rockets: breaks the bomb rules. |
| 7 | Remote Detonator (137) | 0 | 0 | 0 | While held, bombs never explode unless pressed: breaks the bomb rules. |
| 8 | Proptosis (261) | 0 | 1 | 3 | Tears weaken with distance: wrong for a long-range bot. |
| 9 | Number One (6) | 1 | 0 | 2 | Range down forces close fighting. |
| 10 | Dead Cat (81) | 1 | 2 | 3 | Sets health to one heart: every hit is a death (9 lives inflate survival). |
| 11 | Curse of the Tower (371) | 0 | 0 | 0 | Every hit spawns 6 troll bombs. |
| 12 | Cursed Eye (316) | 0 | 0 | 0 | Charge shot; getting hit while charging teleports Isaac. |
| 13 | Strange Attractor (315) | 0 | 0 | 0 | Tears pull enemies toward Isaac. |
| 14 | Isaac's Heart (276) | 0 | 0 | 0 | A heart familiar takes the hits, so the bot dodges for the wrong thing. |
| 15 | Damocles (577 active, 656 familiar) | 0 | 0 | 3/2 | Doubles items, but after any hit the sword can fall and kill Isaac. |
| 16 | Blood Oath (569) | 0 | 0 | 1 | Drains red hearts every floor. |
| 17 | Blood Puppy (565) | 0 | 0 | 1 | Later starts attacking Isaac. |
| 18 | BBF (272) / Bob's Brain (273) | 0 | 0 | 0 | Exploding familiars whose blasts hurt Isaac. |
| 19 | Mom's Knife (114) | 1 | 5 | 4 | Needs hold-and-throw the bot doesn't do. Huge carry once supported. |
| 20 | Tech X (395) | 1 | 5 | 4 | A ring that must be charged and released. Huge carry once supported. |
| 21 | Epic Fetus (168) | 1 | 4 | 4 | Crosshair missiles: needs steering, and the blasts can hurt Isaac. |
| 22 | Missing No. (258) | 1 | 0 | 0 | Rerolls every item each floor: the run can't be compared with others. |
| 23 | TMTRAINER (721) | 0 | 0 | 0 | Every later item is glitched: random effects. |
| 24 | Chaos (402) | 1 | 0 | 3 | Items come from random pools: noisy runs. |
| 25 | Whore of Babylon (122) | 0 | 0 | 2 | Only works at half a heart: the opposite of careful play. |
| 26 | Brittle Bones (549) | 1 | 1 | 3 | Turns red health into empty bone hearts; strong only when hit. |
| 27 | Lachryphagy (532) | 1 | 1 | 3 | Tears slow down and stop, so long shots stall. |
| 28 | Kidney Stone (440) | 1 | 0 | 2 | Isaac sometimes stops firing on his own. |
| 29 | Spirit Sword (579) | 1 | 2 | 3 | A sword instead of tears: melee only. |
| 30 | A Pound of Flesh (672) | 0 | 0 | 0 | Shop items cost hearts; shop pickups are ringed by spikes. |

## Active items: what is safe to press
The bot currently presses a charged active in a fight (a boss, or 3+ enemies), unless the item is on
`R.active.never` in `rules.lua`. `item_ratings.json` makes that finer: each active has an `auto_use` value.
`safe_auto_use_actives` lists the 68 ids that are safe in some situation.

- **In fights (`fight`, 48 items):** The Bible*, Book of Belial, Necronomicon, The Poop, Tammy's Head, Mom's Bra,
  Mom's Pad, Shoop da Whoop!, Lemon Mishap, The Hourglass, My Little Unicorn, The Nail, Monstro's Tooth,
  The Gamekid, Pinking Shears, Monster Manual, Best Friend, Guppy's Head, Crack the Sky, The Candle, Spider Butt,
  Telepathy for Dummies, D10, Box of Spiders, Red Candle, Flush!, Head of Krampus, Unicorn Stump, Isaac's Tears,
  Mega Bean, Glass Cannon, Box of Friends, Jar of Flies, Wait What?, Metronome, Brown Nugget, Sharp Straw,
  Sprinkler, Telekinesis, Book of the Dead, Free Lemonade, The Scooper, Larynx, Eraser, Friend Finder, Lemegeton,
  Anima Sola, Gello.
  - \*The Bible must **never** be used against Satan: it kills Isaac there (`active.not_against: ["Satan"]`).
- **Bosses only (`boss`):** Book of Shadows, Satanic Bible (makes the boss reward a devil deal: a Stage 4
  decision), Mama Mega! (one use), Mega Mush.
- **Only when hurt (`hurt`):** Yum Heart, Yuck Heart.
- **After the room is clear (`clear`):** Book of Revelations, Deck of Cards, Book of Sin, Mom's Bottle of Pills,
  Dad's Key, Book of Secrets, Wooden Nickel, Mom's Box, D1, Fortune Cookie.
  - These spawn pickups, so the pocket and trinket slot rules from `RULES.md` apply: no pressing with a full
    pocket.
- **Only when enemies are close (`close`):** The Bean, Butter Bean.
- **Any time it's charged (`any`):** Prayer Card, Crystal Ball.

**Items with no charge bar** (`charges: 0`) can be pressed every frame, so the "is it charged?" check is always true.
Jar of Flies is in the safe list and must be rate-limited. Kamikaze!, Portable Slot, How to Jump, Magic Fingers and
Golden Razor would be spammed, and they're all rated `never`.

### Fixes for `rules.lua` (I didn't edit it; another session owns that file)
- **Bug:** `R.active.never` has `530` labelled Potato Peeler. 530 is **Death's List** (a passive). Potato Peeler is
  **487**, so it isn't blocked yet. It removes a heart container on every use.
- **Should be added:** these actives are rated `never` or `manual` but aren't on the list. The full list is
  `suggest_add_to_never_list` in the JSON. The ones that matter most:
  - **Hurts Isaac or costs health:** Mr. Boom 37, Anarchist Cookbook 65, Mine Crafter 427, Sumptorium 713,
    Magic Skin 642, Converter 296, Damocles 577, Broken Shovel 550.
  - **Skips the floor:** We Need To Go Deeper! 84, Mom's Shovel 552.
  - **Moves Isaac unpredictably:** A Pony 130, White Pony 181, How to Jump 282, Stitches 635, Berserk! 704,
    Dark Arts 705, Suplex! 709.
  - **Spends coins:** Portable Slot 177, Magic Fingers 295, Golden Razor 555.
  - **One-use decisions or room changes:** Pandora's Box 297, Diplopia 347, D7 437, Mystery Gift 515,
    Eternal D6 609, Meat Cleaver 631.
  - **Two-step or aimed (need their own code):** Bob's Rotten Head 42, Doctor's Remote 47, Notched Axe 147,
    The Boomerang 338, Black Hole 512, Sharp Key 623, Urn of Souls 640.
  - **Remote Detonator 137:** holding it breaks the bomb rules, not only pressing it.
  - **Modded actives with no description:** ids 733-770.
- **Better:** let the Lua read `active.auto_use` from the JSON (or a generated Lua table) instead of keeping a
  separate never-list.

## How the bot should use the file

### 1. Picking up items (treasure rooms, boss rewards, choices)
- `rules.lua` values an item at `30 + 15 x quality`. Use the bot's **`rating`** in place of `quality`. A
  quality-3 Proptosis is worth less to this bot than a quality-1 health up.
- **Rating 0:** don't walk onto it automatically. Leave it, or let the Stage 4 brain decide.
  - Exception: quest items like Key Pieces, Knife Pieces and Broken Shovel are rated 1, so they're harmless to
    pick up.
- **Choices** (There's Options, More Options, Glitched Crown cycling, Binge Eater): take the highest rating. On a
  tie, take the higher carry.
- **`unsure: true`:** use the game's quality instead, and log the pick so the rating can be fixed after watching
  it.

### 2. Devil and angel deals (Stage 4)
- **Price in health:** use the existing `R.risk` health cost. Paying hearts costs `half_heart` points per half
  heart, and more when health is low.
- **Devil deal:** take it only if `30 + 15 x rating` is more than that heart cost, and only if at least 2 full
  hearts (red or soul) are left afterwards. In practice: rating 3-4 yes when health allows; rating 2 only with lots
  of spare health; rating 0-1 never.
- **Angel room items are free:** take anything rated 1 or more.
- **Deal chance:** items tagged "devil/angel deals" (Goat Head, Pentagram, Book of Belial, Black Candle, Eucharist,
  Act of Contrition…) make this matter more. Taking a devil deal stops future angel rooms (Act of Contrition
  undoes that).

### 3. Flagging carried runs
The bot logs a `power` line per floor with the item ids it's holding. For each run, or each floor:
- **`carry_max`** = the highest `carry` among held items. **`carry_sum`** = the sum of their `carry`.
- **Carried:** `carry_max >= 4` or `carry_sum >= 8` (`carried_run_rule` in the JSON). Mark the run "carried" in
  run scores and keep it out of bug-hunting comparisons. A carried run that still dies is the interesting kind.
- **Dragged:** the bot holds any item with rating 0 and a harmful tag ("bad: confusing controls",
  "risky: can hurt Isaac", "risky: costs health", "changes the attack"). Mark the run "dragged". A death there may
  be the item's fault, not a bug.
- **Chaos:** the bot holds an item tagged "random / chaotic" (Missing No., TMTRAINER, Chaos, D4/D100 effects).
  Leave the run out of comparisons entirely.
- **Fair comparisons:** compare runs whose `carry_sum` is in the same range (0-3 / 4-7 / 8+). Report results for
  each range rather than one average.

### 4. Keeping the file right
- `item_ratings.json` is now the source of truth. Edit an item's entry directly, keep `reason` to one line, and
  set `unsure` to false once a mechanic is confirmed in the game.
- When the bot gains a skill, raise the ratings it unlocks. Search the tags:
  - charge-and-release → "charge attack";
  - two-step actives → "active: two-step";
  - aiming → "active: needs aiming";
  - double-taps → "bad: confusing controls".
