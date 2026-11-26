# Live notes: what the author sees while the bot plays

Every note the author sends while watching goes here, in order, with the time, the version that was playing, the
author's own words, the category it belongs to, and what happened with it. Nothing is dropped: each note ends up
**fixed** (with the version and test), **in a fix** (linked to the work that covers it), or **parked** (in `PLAN.md`
"To do later", with the reason).

Categories: `space` (corners, tunnels, escape room), `boss` (one boss's pattern), `hazard` (spikes, creep, bombs,
fires), `aim`, `items`, `nav` (routes, doors, pickups), `lag`, `logging`.

| # | When | Playing | The author's words | Category | Status |
|---|------|---------|--------------------|----------|--------|
| 1 | 2026-11-26 06:30 | 1.2.30 (gate baseline) | "Isaac just going into the corner of a 4x4 room... When are we gonna fix this?" | space | in a fix: escape-room scoring (below) |
| 2 | 2026-11-26 06:31 | 1.2.30 (gate baseline) | "It's also a little laggy in this room too." | lag | in a fix: the log shows 32 ms per update on average, 124 ms at worst, in a 28x16 room with 7-8 enemies; moves 2-3 of the planner take 45 of the 60 ms. Escape-room scoring replaces the per-plan corner and ways-out checks with one map per update |
| 3 | 2026-11-26 06:33 | 1.2.30 (gate baseline) | "Gluttony is not fixed. It is standing in a area where it has no escape route from the brimstone... You can stand close to him within the gap that allows you to move vertical rather than horizontal. But he decides to stand in the one place where he can't go vertical." | space + boss | in a fix: escape-room scoring measures the room to dodge in each direction, so standing in a line attack's row needs open floor above or below. Offline test: Gluttony case |

| 4 | 2026-11-26 06:40 | 1.2.30 (gate baseline) | "whenever Isaac has multiple enemies in one room, his target selecting is very all over the place, especially for fast-moving enemies... Envy... what we can do to prevent lag from happening from tracking many enemies... as Envy splits, the more he does, the choppier the game will be... I hope it's not going to be in the same way where it skews data." | aim + lag | open: target switching with many fast enemies, and the bot's cost per enemy. Next after the escape-room fix; the new map's cost is checked against enemy count |
| 5 | 2026-11-26 06:45 | 1.2.30 (gate baseline) | "it's hard for him to lay on damage [Larry Jr.]... the terrain is really having a part in it... when he lays poops down, it can block you... if Larry Jr. were to be close to you and a poop is laid down that's not broken, that limits your mobility and increases a risk factor... If you have an escape plan that you know for certain that you won't get hurt in, then focus on laying damage down and getting a good angle... no hits, which is good. The only thing is they timed out... The terrain really hinders his thought process... That leads to stutters, which makes it look indecisive, which is, in my view, an AI bot's own panic." | space + boss | in a fix: the escape-room map counts his poops as terrain; then use it the other way too - with plenty of sure room, push in and shoot (timeouts count as failures, not wins). Breaking a poop that boxes Isaac in while Larry is near: after the map is in |

| 6 | 2026-11-26 06:55 | 1.2.30 (gate baseline) | "Similar thing with the gurglings. Isaac is capable of putting so much damage into these guys if he were to just learn the terrain, the environment, like the creep from the gurglings better, and position himself better. This game is solely made on positioning properly... I think positioning in this game is probably priority at this point." | space | **priority decided**: positioning first. In a fix: the escape-room map (creep tiles count as not-ours too, next step) |
| 7 | 2026-11-26 06:56 | - | "Usually a person who is good at a game is good at positioning themselves... Go play Call of Duty. The best people on the top of the leaderboard know the map. They know how to react to the environment. They know where to go when things fall shy. They have a game plan ready at any situation." | space | the design rule: a map of the room (escape room), a plan kept while positioning (commitment), and instant reaction when an attack starts (commitment off while a tell, wind-up or aimed shot is live) |

| 8 | 2026-11-26 07:05 | 1.2.30 (gate baseline) | "it's like borderline impulse reaction. We have nothing coded set up for this type of thorough thinking when it comes to positioning, but we need to figure out how we can make it impulsive to fast critical thinking. That is smart and intelligent... if done correctly and positioned properly, it also lays a lot of damage down... this game teaches people how to open up their third eye, because it teaches you how to read the environment" | space | design proposal: two layers, a positioning brain (slow, a plan for the room) over the reflexes (fast dodges). See below |

## Escape-room scoring (the fix for notes 1-3)

The old checks only look a few steps around where a plan ends (8 short rays, a "wall on two sides" test), so a corner
or a one-tile gap can pass them. The new map is made once per update over the room's tiles:
- when Isaac can reach each tile, and when the nearest enemy can (by its speed);
- a tile is "ours" if Isaac gets there clearly first, and is open floor with no spikes or creep;
- for every tile: how much of "our" floor is connected to it, and how far it can be walked up/down and left/right
  without hitting a wall, rock or pit.

A plan then pays for ending where there's little of our floor around it (corners, tunnels, dead-end pockets) and, inside
a line attack's row or column, for having no room to step out of that line.

| 9 | 2026-11-26 13:40 | 1.2.45 | "right now Isaac is stuck on the host. He is sitting super far away and won't aggro him for him to open." | nav + aim | **fixed** 1.2.47: a shielded target's firing spot within bait distance; the spot pull follows the walking path past pits (test 5b + 2 mutants) |
| 10 | 2026-11-26 13:58 | 1.2.47 | "Stuck on a red fire that's not in killing distance. It should overall just ignore anything that's not gonna hurt it... it's behind two rocks." | hazard | **fixed** 1.2.48: a lit red fire is a fight only within 200 px with a clear line (it shoots within ~160); test 41b + mutant |
| 11 | 2026-11-26 14:05 | 1.2.48 | "make a note on making Isaac use the tarot cards he picks up. So far, I haven't seen him use one... he dropped a Joker card for a different card, and now he has a Moon card that he won't use." | items | **parked** (PLAN.md To do later: 23 cards are 'manual' = never used; teleport handling, when-it-pays rules, swap rule) |
