-- Isaac Bot rulebook: the game's mechanics and the bot's judgement, as DATA (not code).
-- Change the bot's mind here, not in nav.lua / reflex.lua. The human-readable version with the reasoning is
-- knowledge\RULES.md (the Stage 4 brain reads that one).

local R = {}

---------------------------------------------------------------- rooms
-- Room type ids (RoomType enum). visit = order to explore in (lower = sooner); nil = don't walk in.
R.room = {
  [1]  = { name = "normal",       visit = 2 },
  [2]  = { name = "shop",         visit = 1 },  -- nothing to buy until Stage 4, but cheap to peek
  [4]  = { name = "treasure",     visit = 0 },
  [5]  = { name = "boss",         visit = nil, boss = true },  -- always last
  [6]  = { name = "miniboss",     visit = 2 },
  [7]  = { name = "secret",       visit = 0 },
  [8]  = { name = "super secret", visit = 0 },
  [9]  = { name = "arcade",       visit = 3 },
  -- Level 3 (2026-11-25): risky rooms open up when the risk layer says we can afford them (`when` = risk.lua test)
  [10] = { name = "curse",        visit = 3, when = "curse" },      -- door hurts going in: soul hearts first or nothing at stake
  [11] = { name = "challenge",    visit = 3, when = "challenge" },  -- ambush waves: strong, healthy, deal not at stake
  [12] = { name = "library",      visit = 1 },
  [13] = { name = "sacrifice",    visit = nil },
  [14] = { name = "devil",        visit = 0, deal = true },         -- strategy.lua buyValue decides what to take
  [15] = { name = "angel",        visit = 0, deal = true },         -- angel items are free
  [20] = { name = "chest",        visit = 2 },
  [21] = { name = "dice",         visit = nil },
  [24] = { name = "planetarium",  visit = 0 },
  [29] = { name = "ultra secret", visit = nil },
}

---------------------------------------------------------------- secret rooms (no seed reading)
-- Known placement rules, used to guess from the map the bot has explored itself:
--  * a secret room sits in an empty map square next to existing rooms, usually 3+ of them (needs 2+)
--  * never next to the boss room
--  * hidden doors aren't shown to the bot until a bomb (or similar) reveals them
R.secret = {
  min_neighbours = 2,      -- below this, not a candidate
  strong_neighbours = 3,   -- "very likely"
  bombs_if_strong = 3,     -- bombs needed to try a very-likely spot
  bombs_if_weak = 6,       -- ...a 2-neighbour spot
  tries_per_floor = 2,
}

---------------------------------------------------------------- bombs: ONE budget every part of the bot asks
-- The author, 2026-11-25: "It should really conserve them. Not every opportunity." Each reason has a minimum
-- bomb count; below it, that reason may not spend a bomb. Poop is never bombed (tears break it).
R.bombs = {
  loot_major = 1,    -- an item on a pedestal walled in by rocks: worth it even with the last bomb
  loot_key_chest = 2, -- a golden chest we have a key for
  loot_minor = 5,    -- coins, keys, hearts, plain chests behind rocks
  door_boss = 1,     -- rocks between us and the only way on to the boss: worth the last bomb
  door_explore = 3,  -- rocks between us and an unexplored room's door
  siege_min = 2,     -- bombing into enemies walled in by stone...
  siege_after_s = 6, -- ...only after this long with no lane at all
  watchdog_min = 4,  -- the stuck-watchdog's "bomb" step
  brain_min = 3,     -- the brain saying "bomb" (else it's turned into "switch target"/"replan")
  blast_radius = 95, -- px; stay out of it (own bombs too)
  breakable = { "GRID_ROCK", "GRID_ROCKT", "GRID_ROCK_BOMB", "GRID_ROCK_ALT", "GRID_ROCK_SS",
                "GRID_ROCK_SPIKED", "GRID_ROCK_ALT2", "GRID_ROCK_GOLD", "GRID_POOP" },
  -- metal blocks (GRID_ROCKB), pillars and statues never break.
  -- POOP is never bombed: tears break it. Poop in the way = walk up and shoot it (the author's rule).
  shoot_not_bomb = { "GRID_POOP" },
}

---------------------------------------------------------------- pickups
-- Which pickups are worth walking to. "major" also justifies a bomb (see R.bombs).
R.pickups = {
  always = { "PICKUP_COIN", "PICKUP_KEY", "PICKUP_BOMB", "PICKUP_LIL_BATTERY", "PICKUP_GRAB_BAG" },
  pocket_if_empty = { "PICKUP_PILL", "PICKUP_TAROTCARD" }, -- one shared slot; full slot = swap loop
  trinket_if_empty = { "PICKUP_TRINKET" },
  chests = { "PICKUP_CHEST", "PICKUP_WOODENCHEST" },        -- subtype 0 = already opened
  key_chests = { "PICKUP_LOCKEDCHEST" },                   -- only with a key
  never = { "PICKUP_SPIKEDCHEST", "PICKUP_MIMICCHEST", "PICKUP_REDCHEST", "PICKUP_HAUNTEDCHEST" },
  -- worth a bomb: items, and golden chests (only wanted with a key anyway). A plain brown/wooden chest is a
  -- couple of coins or hearts, NOT worth a bomb (the author, 2026-11-25: it bombed one "when it was not needed").
  major = { "PICKUP_COLLECTIBLE", "PICKUP_LOCKEDCHEST" },
  buy = false, -- shop items and devil deals: Stage 4
}

---------------------------------------------------------------- danger map: what hurts, in half hearts
-- One map of the room that walking, fighting and the brain all read (danger.lua). A new hazard goes here once.
R.danger = {
  spikes = 1,   -- stepping on active floor spikes
  creep = 1,    -- standing in an enemy's creep puddle
  fire = 1,     -- touching a lit fireplace
  touch = 1,    -- touching an enemy body
  bomb = 2,     -- inside a live bomb's blast (a full heart)
  bomb_radius = 95,
  tnt = 1,      -- next to TNT (fixed or pushable): it explodes like a bomb when any tear or shot hits it
  tnt_radius = 85,
}

---------------------------------------------------------------- worth it? reward vs risk, scaled by health
-- The author, 2026-11-25 (after it died walking over spikes for a coin): every choice asks "is this worth the
-- damage at my health?" Cost of taking `d` half hearts with `hp` half hearts total:
--     never if d >= hp (it would kill), else  d * half_heart * full_hp / (hp - d)
-- So half a heart costs ~6 points at full health and ~70 on the last heart. Do it only if value > cost.
-- Plus a fixed price per HIT, whatever the health: taking damage lowers the floor's devil/angel deal chance
-- (the author, 2026-11-25: "the goal is to just not get hit at all"). A curse room (hit in + hit out) now costs ~50+.
R.risk = { half_heart = 6, full_hp = 12, per_hit = 25 }

---------------------------------------------------------------- Level 3: buying (strategy.lua buyValue)
-- Devil deals: pay hearts only for a strong item for THIS run, and never below 2 heart containers / 2 hearts after.
-- (Taking a devil deal stops angel rooms later in the run; that's accepted for a strong item.)
R.buy = true
R.deals = { take = true, min_value = 75, keep_containers = 2, keep_hp = 4 }
-- Shop: an item when its run value beats its price; keys/bombs/hearts only when short; keep a few coins otherwise.
R.shop = { reserve = 5, key_if_none = 12, bomb_if_none = 10, heart_if_missing = 12 }

-- Value of things, in points (a penny = 1). Items use the game's own quality rating (0-4).
R.value = {
  coin = { [1] = 1, [2] = 5, [3] = 10, [4] = 2, [5] = 2, [6] = 2, [7] = 4 },  -- penny, nickel, dime, double, lucky, sticky, golden
  key = { [1] = 4, [2] = 10, [3] = 8, [4] = 5 },                               -- key, golden key, key ring, charged key
  bomb = { [1] = 3, [2] = 6, [4] = 10, [7] = 8 },                              -- bomb, double, golden, giga; troll bombs (3,5,6) = never
  heart = { red_full = 5, red_half = 3, soul = 8, half_soul = 4, black = 10, eternal = 8, gold = 6, bone = 9, rotten = 3 },
  chest = 4, locked_chest = 10, pill_card = 3, trinket = 5, battery = 5, grab_bag = 4,
  item_base = 30, item_per_quality = 15,   -- an item = 30 + 15 x quality (quality 4 = 90)
}

---------------------------------------------------------------- stuck rescue ladder
-- "Stuck" = no progress (new room, damage dealt to enemies, something collected) for this long.
-- Each step of the ladder gets `step_s` seconds before the next one kicks in.
-- Active items (the author, 2026-11-25: "does it know how to use active items yet?"). Charged + a fight worth it
-- (a boss, or this many enemies) -> press the item button. Never the ones in `never`: they hurt Isaac, teleport,
-- reroll, restart, swap the character or eat things - a player picks the moment for those, so the bot leaves them.
R.active = {
  min_enemies = 3,   -- or any boss
  never = {
    44, 419, 324,            -- Teleport!, Teleport 2.0, Undefined
    126, 135, 186, 530, 486, -- Razor Blade, IV Bag, Blood Rights, Potato Peeler, Dull Razor (self-damage)
    133, 475,                -- Guppy's Paw (eats red hearts), Plan C (kills you)
    105, 283, 284, 406, 485, 489, 723, -- D6, D100, D4, D8, Crooked Penny, D Infinity, Spindown Dice (rerolls)
    127, 422, 636, 622,      -- Forget Me Now, Glowing Hourglass, R Key, Genesis (room/floor/run resets)
    482, 703,                -- Clicker, Esau Jr. (change the character)
    479, 536, 628,           -- Smelter, Sacrificial Altar, Death Certificate
    290, 263,                -- The Jar, Clear Rune (situational)
  },
}

R.stuck = {
  walk_s = 8,
  fight_s = 10,
  step_s = 4,
  ladder = {
    "replan",   -- drop the current goal, pick another
    "shake",    -- move to open ground, shoot all around (breaks poop, fires, reveals things)
    "bomb",     -- bomb the nearest breakable obstacle (if any bombs)
    "leave",    -- walk out through any open door (not in a fight)
    "report",   -- log the situation for a developer to fix the whole category, allow last-resort rooms, start over
  },
}

return R
