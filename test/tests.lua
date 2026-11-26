-- Offline logic tests: real bugs as scripted situations, so they can't quietly come back.
-- Each test builds a fake room or floor (mock.lua), runs the bot's real code, and checks one behaviour.
-- `run.ps1 -Prove` undoes each fix in memory (test\mutants.lua) and checks its test then FAILS. Every test
-- has a proof entry except 3-5 (broad behaviour checks: the fake's rough movement hides their single fixes).
-- 28-29 = bugs these tests found (test\FOUND_BUGS.md), fixed in 1.1.41. A new found bug goes in as a KNOWN test
-- (see FOUND_BUGS.md) so it doesn't block reloads until it's fixed.
--
-- What each test covers (PLAN.md Stage 3 log):
--  1  walks to the button in a cleared trap room ......... pressure plates: no enemies + unpressed plate = walk on it
--  2  collects pennies across the room ................... distance used to make every far penny "not worth it"
--  3  dodges a shot coming straight at it ................ basic dodge
--  4  doesn't run into a corner from a chaser ............ corners / ways-out (1.1.x)
--  5  walks up to bait a closed Host ..................... no aim reward on a closed target: bait it (1.1.2-13)
--  6  moves toward a still target it can't hit yet ....... beam search trimmed by the FULL score (tied plans froze)
--  7  no two-room bounce over a locked door .............. 1.0.8: failed doors remembered for the whole floor (deadEdge)
--  8  loop breaker refuses to step straight back ......... 1.0.8: 8+ entries in 25 s, none new -> another way on
--  9  tries a locked door again after finding a key ...... 1.0.8: a dead door is forgiven when keys go up
-- 10  shoots open a door walled off by poop .............. 1.0.8: poop in front of a door gets shot, not given up on
-- 11  secret-wall guess with pits in front is dropped .... 1.0.11: needs a walkable spot in front (secretBlocked)
-- 12  steps off a trapdoor that opened under it .......... 1.1.2-13: closed trapdoor under Isaac
-- 13  goes back to the cleared boss room for the trapdoor  1.1.2-13: "nothing to do" in a cleared floor
-- 14  floor map survives a code reload ................... 1.1.2-13: IsaacBotNavState (reload wiped the map)
-- 15  hidden secret door isn't treated as a door ......... "Fixed bugs": secret doors report open while still wall
-- 16  breaks the poop gate of a boxed-in enemy ........... 1.1.14-23: poop gates (no firing spot -> shoot the poop)
-- 17  targets the spawner before its spiders ............. 1.1.14-23: spawners first (SpawnerEntity, the Sack)
-- 18  never plans a firing spot next to a fire ........... 1.0.16-22: fires never lose their gap
-- 19  closed Host doesn't make it go for a far fire ...... 1.1.2-13: a shield must be within 70 px of the enemy
-- 20  never siege-bombs a fire or a poop ................. 1.1.2-13: never bomb toward a fire/poop
-- 21  sprays at a target that's roughly in line .......... 1.1.14-23: loose_aim (it never fired at spiders)
-- 22  fights an enemy that has no collision yet (Boils) .. 1.0.9: never-solid filter hid free-standing enemies
-- 23  doesn't cross spikes for a penny ................... worth-it rule (died walking over spikes for a coin)
-- 24  doesn't swap its card for a pill ................... pills/cards share one slot (the old pick-up loop)
-- 25  cleared room with an unkillable shooter ............ 1.1.35: dodge-only (stone shooter kept it fighting)
-- 26  weak door write-offs expire after a minute ......... 1.1.36: "walking there failed" etc. expire after 60 s
-- 26b locked door write-off doesn't expire ............... 1.1.36: ...but "locked, no key" doesn't
-- 27  only exit written off: still takes it .............. 1.1.36: nothing left -> forgive written-off doors
-- 30  doesn't settle in a corner (enemies circle middle) . 1.1.46: wall ways count x2, centre pull, edge cost
-- 31  keeps moving while an enemy is underground ......... 1.1.47: burrowers (m_burrow on standing still)
-- 32  leaves a secret room the way it came in ............ 1.1.48: inside a secret room only open doors count
-- 33  gets clear of a bomb it just placed ................. 1.1.49: v2 bomb danger = bomb_r + Isaac's size, full cost
-- 34  doesn't shoot poop next to a moving enemy in the open 1.1.50: poop gates only for walled-in enemies
-- 35  leaves a crowded corner of a big room .............. 1.1.53 crowd pressure (behaviour check, no proof entry)
-- K3  steps off the line between two chasers ............. 1.1.51/54 sandwich cost: OPEN (FOUND_BUGS.md #3)
-- 28  no bounce between two rooms with a locked door each  1.1.41 (found here): forgive weak write-offs only, once
-- 29  sprays down a corridor at a target roughly in line . 1.1.41 (found here): loose aim tries all 4 directions

local Rules = include("rules")
local Nav = include("nav")
local Reflex = include("reflex")
Reflex.status.mode = "full"
-- the behaviour tests below were written for the fixed, careful settings: risk pinned there (risk tests unpin it)
Reflex.risk.pin = 0.25

local results = {}
local function check(name, ok, detail)
  results[#results + 1] = (ok and "PASS " or "FAIL ") .. name .. (detail and ("  (" .. detail .. ")") or "")
end
-- a real bug found but not fixed yet (written up in FOUND_BUGS.md): prints KNOWN, or FIXED? once it passes;
-- doesn't count as a failure, so it doesn't block reloads. When fixed: switch it to check() + a mutants.lua entry.
local function known(name, ok, detail)
  results[#results + 1] = (ok and "FIXED? " or "KNOWN ") .. name .. (detail and ("  (" .. detail .. ")") or "")
end
local function run(name, fn)
  if ONLY and ONLY ~= "" and not name:find(ONLY, 1, true) then return end
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then results[#results + 1] = "FAIL " .. name .. "  (crashed: " .. tostring(err) .. ")" end
end
local function fmt(...) return string.format(...) end
local function rooms(seq) return #seq == 0 and "none" or table.concat(seq, ">") end

-- 1. Button room: no enemies, room not clear, a pressure plate -> walk to it (it used to wait forever)
run("walks to the button in a cleared trap room", function()
  Mock.room({
    "WWWWWWWDWWWWWWW",
    "W........_....W",
    "W.............W",
    "W.............W",
    "D.............W",
    "W.............W",
    "W.............W",
    "W.............W",
    "WWWWWWWDWWWWWWW",
  }, { clear = false, player = Mock.tile(7, 4) })
  Nav.newRoom()
  local move = Nav.update(Isaac.GetPlayer())
  local toPlate = Mock.tile(9, 1) - Isaac.GetPlayer().Position
  check("walks to the button in a cleared trap room", move and move:Dot(toPlate) > 0,
        "goal: " .. tostring(Nav.status.goal))
end)

-- 2. Coins far away in a cleared room -> go get them (distance used to make every penny "not worth it")
run("collects pennies across the room", function()
  Mock.room(nil, { player = Mock.tile(2, 4) })
  Mock.pickup(PickupVariant.PICKUP_COIN, 1, Mock.tile(12, 2))
  Mock.pickup(PickupVariant.PICKUP_COIN, 1, Mock.tile(12, 6))
  Nav.newRoom()
  Nav.update(Isaac.GetPlayer())
  check("collects pennies across the room", tostring(Nav.status.goal):find("pickup") ~= nil,
        "goal: " .. tostring(Nav.status.goal))
end)

-- 3. A shot heading straight at a standing Isaac -> it must not be standing in its way when it arrives
run("dodges a shot coming straight at it", function()
  Mock.room(nil, { player = Mock.tile(8, 4), clear = false })
  local p = Isaac.GetPlayer()
  Mock.enemy(EntityType.ENTITY_HOST, 0, Mock.tile(2, 1), { vulnerable = false }) -- something to make it a fight
  Mock.shot(p.Position + Mock.vec(-150, 0), Mock.vec(8, 0))
  local hit = nil
  for _ = 1, 30 do
    local move = Reflex.update(p)
    Mock.step(move)
    local t = Mock.touching()
    if t and t.Type == EntityType.ENTITY_PROJECTILE then hit = t; break end
  end
  check("dodges a shot coming straight at it", not hit, "ended at " .. tostring(p.Position))
end)

-- 4. A chaser coming at Isaac near a corner -> don't run into the corner and get pinned
run("doesn't run into a corner from a chaser", function()
  Mock.room(nil, { player = Mock.tile(10, 5), clear = false })
  local p = Isaac.GetPlayer()
  Mock.enemy(EntityType.ENTITY_GAPER, 0, Mock.tile(4, 3), { chase = 2.6, hp = 999 })
  local corner = Mock.vec(560, 400)
  local minCorner, touched = math.huge, 0
  for _ = 1, 150 do
    local move = Reflex.update(p)
    Mock.step(move)
    minCorner = math.min(minCorner, (p.Position - corner):Length())
    if Mock.touching() then touched = touched + 1 end
  end
  check("doesn't run into a corner from a chaser", minCorner > 70 and touched == 0,
        fmt("closest to corner %.0f px, touched %d updates", minCorner, touched))
end)

-- 5. A closed Host (can't be hurt until it opens) -> walk up to bait it, don't stand across the room
run("walks up to bait a closed Host", function()
  Mock.room(nil, { player = Mock.tile(2, 4), clear = false })
  local p = Isaac.GetPlayer()
  local host = Mock.enemy(EntityType.ENTITY_HOST, 0, Mock.tile(11, 4), { vulnerable = false })
  local d0 = (host.Position - p.Position):Length()
  for _ = 1, 90 do
    local move = Reflex.update(p)
    Mock.step(move)
  end
  local d1 = (host.Position - p.Position):Length()
  check("walks up to bait a closed Host", d1 < d0 - 80, fmt("distance %.0f -> %.0f px", d0, d1))
end)

-- 6. Standing still with nothing to do in a fight must not freeze (tied plans picked at random used to)
run("moves toward a still target it can't hit yet", function()
  Mock.room(nil, { player = Mock.tile(2, 2), clear = false })
  local p = Isaac.GetPlayer()
  Mock.enemy(EntityType.ENTITY_GAPER, 0, Mock.tile(11, 6), { hp = 999 })
  local start = p.Position
  for _ = 1, 60 do local move = Reflex.update(p); Mock.step(move) end
  check("moves toward a still target it can't hit yet", (p.Position - start):Length() > 40,
        "moved " .. fmt("%.0f", (p.Position - start):Length()) .. " px")
end)

------------------------------------------------------------------------ walking the floor (nav.lua)
-- Map used by 7-9: start room 84, room B (85) to its right, a locked treasure room (86) behind B, and an
-- unexplored normal room W (83) on the left. From 84 the treasure room looks best (it goes via B).
local function bounceFloor()
  Mock.floor({
    [84] = { visited = true, doors = { [0] = 83, [2] = 85 } },
    [85] = { visited = true, doors = { [0] = 84, [2] = { to = 86, locked = true } } },
    [86] = { type = 4, doors = { [0] = { to = 85, locked = true } } },
    [83] = { doors = { [2] = 84 } },
  })
  Mock.enter(84); Nav.newRoom()      -- been in both rooms already: the bot knows their doors
  Mock.enter(85, 0); Nav.newRoom()   -- ...and is now in B, next to the door it came in by
end

-- 7. 1.0.8: floor 2, 25 minutes bouncing between two rooms. B's door was locked; B gave up and went back to A,
-- A (having forgotten) routed via B again. Now a failed door stays failed for the floor.
run("no two-room bounce over a locked door", function()
  bounceFloor()
  local seq = Mock.walk(Nav, 30 * 40)
  local firstW = nil
  for k, r in ipairs(seq) do if r == 83 then firstW = k; break end end
  check("no two-room bounce over a locked door", firstW ~= nil and firstW <= 2,
        "rooms entered: " .. rooms(seq) .. " | " .. tostring(Nav.status.detail))
end)

-- 8. 1.0.8 loop breaker (the safety net for bounces with any other cause): 8 quick re-entries between two
-- known rooms -> don't step straight back into the room we just came from; take another way on.
run("loop breaker refuses to step straight back", function()
  Mock.floor({
    [84] = { visited = true, doors = { [0] = 83, [2] = 85 } },
    [85] = { visited = true, doors = { [0] = 84, [2] = 86 } },
    [86] = { type = 4, doors = { [0] = 85 } },   -- open treasure room behind B: the "best" target via B
    [83] = { doors = { [2] = 84 } },
  })
  Mock.enter(84); Nav.newRoom()
  for _ = 1, 5 do
    Mock.enter(85, 0); Nav.newRoom()
    Mock.enter(84, 2); Nav.newRoom()
  end
  local move = Nav.update(Isaac.GetPlayer())
  check("loop breaker refuses to step straight back", move ~= nil and move.X < -0.5,
        fmt("move %s, goal %s | %s", tostring(move), tostring(Nav.status.goal), tostring(Nav.status.detail)))
end)

-- 9. ...but a door given up on for lack of a key is tried again once we have one.
run("tries a locked door again after finding a key", function()
  bounceFloor()
  local m1 = Nav.update(Isaac.GetPlayer()) -- locked, no key: written off, heads back left
  Isaac.GetPlayer()._keys = 1
  Mock.enter(85, 0); Nav.newRoom()
  local m2 = Nav.update(Isaac.GetPlayer())
  check("tries a locked door again after finding a key", m1 and m1.X < 0 and m2 and m2.X > 0.5,
        fmt("before key %s, after key %s (%s)", tostring(m1), tostring(m2), tostring(Nav.status.goal)))
end)

-- 10. 1.0.8: the only way to the next room is behind a line of poop -> shoot it open and go through.
run("shoots open a door walled off by poop", function()
  Mock.floor({
    [84] = { visited = true, doors = { [2] = 85 }, rows = {
      "WWWWWWWWWWWWWWW",
      "W............pW",
      "W............pW",
      "W............pW",
      "W............pD",
      "W............pW",
      "W............pW",
      "W............pW",
      "WWWWWWWWWWWWWWW",
    } },
    [85] = { doors = { [0] = 84 } },
  })
  Mock.enter(84); Nav.newRoom()
  local goals = {}
  local seq = Mock.walk(Nav, 30 * 30, function(k) if k <= 3 then goals[#goals + 1] = Nav.status.goal end end)
  check("shoots open a door walled off by poop", seq[1] == 85,
        "rooms entered: " .. rooms(seq) .. " | first goal: " .. tostring(goals[1]))
end)

-- 40. 1.2.16 (2026-11-25): the level's data for some unvisited rooms came back as garbage types (1065353216...), and
-- the game itself crashed loading one (corrupted by a data-dump mod mid-run). The door's sane type is used; with
-- no sane type anywhere, the room is never entered.
run("garbage room type: door type used, corrupt room never entered", function()
  Mock.floor({
    [84] = { visited = true, doors = { [2] = { to = 85, type = 1 }, [0] = { to = 83, type = -404104361 } } },
    [85] = { type = 1065353216, doors = { [0] = 84 } },
    [83] = { type = -404104361, doors = { [2] = 84 } },
  })
  Mock.enter(84); Nav.newRoom()
  local seq = Mock.walk(Nav, 30 * 20)
  local into83 = false
  for _, r in ipairs(seq) do if r == 83 then into83 = true end end
  check("garbage room type: door type used, corrupt room never entered", seq[1] == 85 and not into83,
        "rooms entered: " .. rooms(seq))
end)

-- 11. 1.0.11: 15 minutes stuck. The secret-room guess was a wall with pits in front: it couldn't get there and
-- re-picked the same guess every update. Now that wall is crossed off from this room, and it tries the same
-- spot from a neighbour room instead.
run("secret-wall guess with pits in front is dropped", function()
  -- explored: 70-71 above, 84 (here), 96-97 below. Empty square 83 has 3 rooms around it: the best guess.
  -- From 84 that wall (left) has a pit right in front of it.
  Mock.floor({
    [70] = { visited = true, doors = { [2] = 71 } },
    [71] = { visited = true, doors = { [0] = 70, [3] = 84 } },
    [84] = { visited = true, doors = { [1] = 71, [3] = 97 }, rows = {
      "WWWWWWWDWWWWWWW",
      "W.............W",
      "W.............W",
      "W.............W",
      "W~............W",
      "W.............W",
      "W.............W",
      "W.............W",
      "WWWWWWWDWWWWWWW",
    } },
    [97] = { visited = true, doors = { [1] = 84, [0] = 96 } },
    [96] = { visited = true, doors = { [2] = 97 } },
  })
  for _, r in ipairs({ 70, 71, 84, 97, 96 }) do Mock.enter(r); Nav.newRoom() end
  Mock.enter(84, 3); Nav.newRoom()
  local p = Isaac.GetPlayer()
  p._bombs = 3
  local goals, bombWall, otherRoom = {}, false, false
  for _ = 1, 8 do
    local move = Nav.update(p)
    Mock.step(move)
    local g = tostring(Nav.status.goal)
    goals[#goals + 1] = g
    if g:find("bomb wall") then bombWall = true end
    if g:find("secret%-room spot") then otherRoom = true end
  end
  check("secret-wall guess with pits in front is dropped", not bombWall and otherRoom,
        "goals: " .. table.concat(goals, " / ", 1, 3))
end)

-- 12. 1.1.2-13: a trapdoor that opens UNDER Isaac stays shut until he steps off. He stood on it forever.
run("steps off a trapdoor that opened under it", function()
  Mock.room({
    "WWWWWWWDWWWWWWW",
    "W.............W",
    "W.............W",
    "W.............W",
    "D......T......D",
    "W.............W",
    "W.............W",
    "W.............W",
    "WWWWWWWDWWWWWWW",
  }, { type = 5, player = Mock.tile(7, 4) })
  Nav.newRoom()
  local p = Isaac.GetPlayer()
  local trap = Mock.tile(7, 4)
  local maxAway, backAfter = 0, false
  for _ = 1, 150 do
    local move = Nav.update(p)
    Mock.step(move)
    local d = (p.Position - trap):Length()
    if d > maxAway then maxAway = d end
    if maxAway > 30 and d < 24 then backAfter = true end
  end
  check("steps off a trapdoor that opened under it", maxAway > 30 and backAfter,
        fmt("farthest %.0f px off it, came back: %s, goal %s", maxAway, tostring(backAfter), tostring(Nav.status.goal)))
end)

-- 13. 1.1.2-13: boss beaten, but it walked out before taking the trapdoor -> "nothing to do" in a cleared
-- floor. Now it goes back to the cleared boss room.
run("goes back to the cleared boss room for the trapdoor", function()
  Mock.floor({
    [84] = { visited = true, doors = { [2] = 85 } },
    [85] = { type = 5, visited = true, clear = true, doors = { [0] = 84 } },
  })
  Mock.enter(85); Nav.newRoom()
  Mock.enter(84, 2); Nav.newRoom()
  local seq = Mock.walk(Nav, 30 * 5)
  check("goes back to the cleared boss room for the trapdoor", seq[1] == 85,
        "rooms entered: " .. rooms(seq) .. ", goal " .. tostring(Nav.status.goal))
end)

-- 14. 1.1.2-13: the "reload" command (luamod) re-runs nav.lua mid-floor. Its map lived in a local and was
-- wiped: "nothing to do" in a cleared room. Now it's kept in the global IsaacBotNavState.
run("floor map survives a code reload", function()
  Mock.floor({
    [84] = { visited = true, doors = { [2] = 85 } },
    [85] = { visited = true, doors = { [0] = 84, [2] = 86 } },
    [86] = { doors = { [0] = 85 } },               -- unexplored, only known from B's doors
  })
  Mock.enter(85); Nav.newRoom()
  Mock.enter(84, 2); Nav.newRoom()
  local Nav2 = Mock.reload("nav")
  Nav2.update(Isaac.GetPlayer())
  check("floor map survives a code reload", tostring(Nav2.status.goal):find("next room") ~= nil,
        "goal after reload: " .. tostring(Nav2.status.goal))
end)

-- 15. "Fixed bugs" list: the game reports a hidden secret-room door as OPEN; only the solid wall gives it
-- away. The bot must not see it (no peeking) until it's blown open.
run("hidden secret door isn't treated as a door", function()
  local room = Mock.room({
    "WWWWWWWWWWWWWWW",
    "W.............W",
    "W.............W",
    "W.............W",
    "D.............D",
    "W.............W",
    "W.............W",
    "W.............W",
    "WWWWWWWDWWWWWWW",
  }, { doors = { [1] = { to = 71, type = 7 } } })
  local d = room:GetDoor(1)
  local hidden = not Nav.visibleDoor(d)
  room.cells[d:GetGridIndex()] = GridCollisionClass.COLLISION_NONE -- bombed open
  local shown = Nav.visibleDoor(d)
  check("hidden secret door isn't treated as a door", hidden and shown,
        fmt("while wall: visible=%s, blown open: visible=%s", tostring(not hidden), tostring(shown)))
end)

------------------------------------------------------------------------ fighting (reflex.lua)
-- 16. 1.1.14-23: an enemy in a rock pocket whose only opening is a poop. No firing spot on the enemy at all
-- -> the poop next to it is the gate: plan a shot at the poop. (the author: "all it needs to do is shoot the poop")
run("breaks the poop gate of a boxed-in enemy", function()
  Mock.room({
    "WWWWWWWDWWWWWWW",
    "W.............W",
    "W....###......W",
    "W....#..#.....W",
    "D....##p#.....D",
    "W.............W",
    "W.............W",
    "W.............W",
    "WWWWWWWDWWWWWWW",
  }, { clear = false, player = Mock.tile(3, 6) })
  Mock.enemy(EntityType.ENTITY_GAPER, 0, Mock.tile(6, 3), { hp = 999 })
  Reflex.update(Isaac.GetPlayer())
  local t = Reflex.plan.target
  check("breaks the poop gate of a boxed-in enemy", t ~= nil and t.kind == "poop",
        "planned target: " .. (t and (t.kind or ("enemy " .. tostring(t.Type))) or "none"))
end)

-- 17. 1.1.14-23: a Sack making spiders. Killing spiders first is pointless: the spawner (found by asking the
-- game who spawned each enemy) is the target, even with 6 of its spiders closer.
run("targets the spawner before its spiders", function()
  Mock.room(nil, { clear = false, player = Mock.tile(2, 6) })
  local sack = Mock.enemy(EntityType.ENTITY_SACK, 0, Mock.tile(12, 2), { hp = 30 })
  for _, xy in ipairs({ { 4, 5 }, { 5, 7 }, { 6, 5 }, { 4, 3 }, { 7, 7 }, { 6, 3 } }) do
    Mock.enemy(EntityType.ENTITY_SPIDER, 0, Mock.tile(xy[1], xy[2]), { hp = 5, spawner = sack })
  end
  Reflex.update(Isaac.GetPlayer())
  local t = Reflex.plan.target
  check("targets the spawner before its spiders", t == sack,
        "planned target: " .. (t and (t == sack and "the Sack" or ("type " .. tostring(t.Type))) or "none"))
end)

-- 17b. 1.2.7 (mirror chat + the author's rule): Mega Fatty's small adds scored better than the boss (low HP), and the
-- boss got ~0.8 damage a second for 4 minutes. With a boss alive: the boss first; harmless adds don't steal the aim.
run("boss first over harmless adds", function()
  Mock.room(nil, { clear = false, player = Mock.tile(2, 6) })
  local boss = Mock.enemy(EntityType.ENTITY_GAPER, 0, Mock.tile(11, 2), { hp = 500, boss = true })
  Mock.enemy(EntityType.ENTITY_SPIDER, 0, Mock.tile(7, 6), { hp = 4 })
  Mock.enemy(EntityType.ENTITY_SPIDER, 0, Mock.tile(7, 3), { hp = 4 })
  Reflex.plan.at = -999
  Reflex.update(Isaac.GetPlayer())
  local t = Reflex.plan.target
  check("boss first over harmless adds", t == boss,
        "planned target: " .. (t and (t == boss and "the boss" or ("type " .. tostring(t.Type))) or "none"))
end)

-- 36. 1.2.7 (the author: "it still parks itself in the corner when coming close to flies"; bench d.1109, 7 Dart Flies):
-- chasers home in on wherever Isaac goes, and corners cost more the more movers are about. Behaviour check.
run("doesn't park in a corner against chasing flies", function()
  Reflex.loadPlaybook("18.0=flies,chases,k3,d3")
  Mock.room(nil, { clear = false, player = Mock.tile(1, 1) })
  for _, xy in ipairs({ { 6, 3 }, { 9, 2 }, { 8, 6 }, { 11, 5 } }) do
    Mock.enemy(18, 0, Mock.tile(xy[1], xy[2]), { hp = 5, chase = 1.2, size = 8 })
  end
  local cornerFrames = 0
  for _ = 1, 150 do
    local move = Reflex.update(Isaac.GetPlayer())
    Mock.step(move)
    local p = Isaac.GetPlayer().Position
    local nearX = p.X < Mock.tile(0, 0).X + 50 or p.X > Mock.tile(13, 0).X - 50
    local nearY = p.Y < Mock.tile(0, 0).Y + 50 or p.Y > Mock.tile(0, 7).Y - 50
    if nearX and nearY then cornerFrames = cornerFrames + 1 end
  end
  Reflex.playbook = {}
  check("doesn't park in a corner against chasing flies", cornerFrames < 40, cornerFrames .. " of 150 updates in a corner")
end)

-- 38. 1.2.9 invincible windows (the author: Unicorn Stump "makes you invincible, but you can walk into enemies whilst
-- it's active"): during the effect, no hit cost, no gaps, point-blank; back to normal when it ends
run("invincible window: drops dodging, then back to normal", function()
  local Risk = Reflex.risk
  local S = Reflex.S
  Mock.room(nil, { clear = false, player = Mock.tile(7, 4) })
  local p = Isaac.GetPlayer()
  local fxOn = true
  p.GetEffects = function()
    return { HasCollectibleEffect = function(_, id) return fxOn and id == 298 end,
             GetCollectibleEffect = function() return { Cooldown = 150 } end }
  end
  Mock.enemy(EntityType.ENTITY_GAPER, 0, Mock.tile(9, 4), { hp = 20 })
  Reflex.update(p)
  local onHit, onDist = S.m_hit, S.pref_dist
  fxOn = false
  Reflex.update(p)
  local offHit = S.m_hit
  p.GetEffects = nil
  check("invincible window: drops dodging, then back to normal", onHit < 50 and onDist <= 60 and offHit >= 900,
        fmt("m_hit %.0f while invincible (pref %.0f), %.0f after", onHit, onDist, offHit))
end)

-- 39. 1.2.12 boss attack windows (the author: "there are windows where he can lay damage and windows where he focuses
-- on dodging; he sits in the predicted safe spot and it limits the damage"): in a window, aim counts more, closer
run("boss attack window: aim harder while the boss is tired", function()
  local S, Risk = Reflex.S, Reflex.risk
  Reflex.loadBossTactics("261.0=200,k,kill_close,Dance,Idle|Tired")
  Mock.room(nil, { clear = false, player = Mock.tile(2, 6) })
  local dingle = Mock.enemy(261, 0, Mock.tile(11, 3), { hp = 300, boss = true, anim = "Tired" })
  local p = Isaac.GetPlayer()
  Reflex.update(p); Reflex.update(p)
  local inWin, aimIn = Risk.window, S.m_aim
  dingle._anim = "Slide"
  Reflex.update(p); Reflex.update(p)
  local outWin, aimOut = Risk.window, S.m_aim
  Reflex.bossTactics = {}; IsaacBotBossTactics = Reflex.bossTactics
  check("boss attack window: aim harder while the boss is tired", inWin == "Tired" and outWin == nil and aimIn > aimOut,
        fmt("window %s -> %s, m_aim %.0f -> %.0f", tostring(inWin), tostring(outWin), aimIn, aimOut))
end)

-- 41. 1.2.17 (the author: "make it so it hits the red fire if it's a threat. You can shoot the red fire to prevent it
-- from shooting you"): a lit red fire is a target, even in a cleared room; a plain (orange) fire stays a hazard only
run("puts out a red fire, leaves a plain fire alone", function()
  Mock.room(nil, { clear = true, player = Mock.tile(2, 4) })
  local red = Mock.enemy(EntityType.ENTITY_FIREPLACE, 1, Mock.tile(9, 4), { hp = 5, size = 13 })
  red._enemy = false
  local p = Isaac.GetPlayer()
  Reflex.plan.at = -999
  Reflex.update(p)
  local redTarget = Reflex.status.active and (Reflex.status.target == red or Reflex.plan.target == red)
  Mock.room(nil, { clear = true, player = Mock.tile(2, 4) })
  Mock.fire(Mock.tile(9, 4))
  Reflex.plan.at = -999
  Reflex.update(Isaac.GetPlayer())
  local plainFight = Reflex.status.active
  check("puts out a red fire, leaves a plain fire alone", redTarget and not plainFight,
        fmt("red fire targeted: %s, plain fire made a fight: %s", tostring(redTarget), tostring(plainFight)))
end)

-- 37. 1.2.7 boss tactics (knowledge/boss_tactics.json via the helper): loads, finds the boss, adds policy decides
run("boss tactics: loaded and used", function()
  Reflex.loadBossTactics("261.0=200,k,kill_close,BeforeSlide|Dance|Whistle;260.0=160,c,kill_first,")
  Mock.room(nil, { clear = false, player = Mock.tile(2, 6) })
  local dingle = Mock.enemy(261, 0, Mock.tile(11, 2), { hp = 300, boss = true })
  local tac = Reflex.tacticsOf(dingle)
  check("boss tactics: Dingle's distance and tells load", tac and tac.pd == 200 and tac.tells.Dance and tac.corners,
        tac and ("pd " .. tostring(tac.pd)) or "no tactic")
  -- a "kill_first" boss (the Haunt): its adds come first even when they're harmless and far
  Mock.room(nil, { clear = false, player = Mock.tile(2, 6) })
  Mock.enemy(260, 0, Mock.tile(11, 2), { hp = 300, boss = true })
  local lil = Mock.enemy(260, 10, Mock.tile(9, 6), { hp = 13 })
  Reflex.plan.at = -999
  Reflex.update(Isaac.GetPlayer())
  local t = Reflex.plan.target
  check("boss tactics: 'kill the adds first' boss -> adds first", t == lil,
        "planned target: " .. (t and (t == lil and "the add" or ("type " .. tostring(t.Type) .. "." .. tostring(t.Variant))) or "none"))
  Reflex.bossTactics = {}; IsaacBotBossTactics = Reflex.bossTactics
end)

-- 18. 1.0.16-22: the relax ladder had dropped the gap around fires to 0; it planned a firing spot next to a
-- fire and walked into it. Fires burn on touch: no firing spot may be next to one (diagonals included).
run("never plans a firing spot next to a fire", function()
  Mock.room(nil, { clear = false, player = Mock.tile(3, 2) })
  local fire = Mock.fire(Mock.tile(4, 3))
  Mock.enemy(EntityType.ENTITY_GAPER, 0, Mock.tile(7, 4), { hp = 999 })
  local p = Isaac.GetPlayer()
  local closest, planned = math.huge, 0
  for _ = 1, 45 do
    local move = Reflex.update(p)
    if Reflex.plan.cellPos then
      planned = planned + 1
      closest = math.min(closest, (Reflex.plan.cellPos - fire.Position):Length())
    end
    Mock.step(move)
  end
  check("never plans a firing spot next to a fire", planned > 0 and closest > 60,
        fmt("closest planned spot %.0f px from the fire (%d plans)", closest, planned))
end)

-- 19. 1.1.2-13: a closed Host (can't be hurt) made the bot "break" a fire across the room as if it shielded
-- the Host, then bomb it. A poop/fire only counts as a shield if it's within 70 px of the enemy.
run("closed Host doesn't make it go for a far fire", function()
  Mock.room(nil, { clear = false, player = Mock.tile(2, 6) })
  Mock.enemy(EntityType.ENTITY_HOST, 0, Mock.tile(11, 4), { vulnerable = false })
  Mock.fire(Mock.tile(3, 2))
  local p = Isaac.GetPlayer()
  local wentForFire = false
  for _ = 1, 30 do
    local move = Reflex.update(p)
    local t1, t2 = Reflex.plan.target, Reflex.status.target
    if (t1 and t1.kind == "fire") or (t2 and t2.kind == "fire") then wentForFire = true end
    Mock.step(move)
  end
  check("closed Host doesn't make it go for a far fire", not wentForFire, "targeted the fire: " .. tostring(wentForFire))
end)

-- 20. 1.1.2-13: never bomb toward a fire or a poop (tears put those out), even when rocks are in the way.
run("never siege-bombs a fire or a poop", function()
  local room = Mock.room({
    "WWWWWWWDWWWWWWW",
    "W.............W",
    "W........###..W",
    "W........#p#..W",
    "D........###..D",
    "W.............W",
    "W........###..W",
    "W........#.#..W",
    "WWWWWWWDW###WWW",
  }, { clear = false, player = Mock.tile(3, 4) })
  local p = Isaac.GetPlayer()
  p._bombs = 5
  local fire = Mock.fire(Mock.tile(10, 7))
  local poop = { Position = Mock.tile(10, 3), Velocity = Mock.vec(0, 0), kind = "poop" }
  local m1 = Nav.siege(p, fire)
  local m2 = Nav.siege(p, poop)
  check("never siege-bombs a fire or a poop", m1 == nil and m2 == nil and not Nav.siegeActive(),
        fmt("fire: %s, poop: %s", tostring(m1), tostring(m2)))
  -- (a real walled-in enemy still gets sieged: the test above would pass trivially if siege never worked)
  local gaper = Mock.enemy(EntityType.ENTITY_GAPER, 0, Mock.tile(10, 7), { hp = 999 })
  local m3 = Nav.siege(p, gaper)
  check("never siege-bombs a fire or a poop (enemy still sieged)", m3 ~= nil, "enemy: " .. tostring(m3))
  room = nil
end)

-- 21. 1.1.14-23: it only fired when the shot was SURE to land, and jumpy spiders never are: it never shot at
-- them ("way too carefully"). Roughly in line (within loose_aim px) with an open lane -> fire.
-- (A hopping spider, 30 px off our row: the led shot can't be sure to land. A STILL target off the row
-- doesn't test this: walking sideways curves the tear onto it, so it fires anyway.)
run("sprays at a target that's roughly in line", function()
  Mock.room(nil, { clear = false, player = Mock.tile(2, 4) })
  Mock.enemy(EntityType.ENTITY_SPIDER, 0, Mock.tile(7, 4) + Mock.vec(0, 30), { hp = 5, vel = Mock.vec(0, 5) })
  Reflex.update(Isaac.GetPlayer())
  check("sprays at a target that's roughly in line", Reflex.status.shoot ~= "",
        "shoot: '" .. tostring(Reflex.status.shoot) .. "'")
end)

-- 22. 1.0.9: Boils spawn small with NO collision; the "never solid = cord piece" filter hid them (0/3 cleared,
-- not even in the enemy list). A free-standing hurtable enemy is real; a cord piece hanging off a parent isn't.
run("fights an enemy that has no collision yet (Boils)", function()
  Mock.room(nil, { clear = false, player = Mock.tile(2, 4) })
  local boil = Mock.enemy(EntityType.ENTITY_BOIL, 0, Mock.tile(10, 4),
                          { hp = 20, coll = EntityCollisionClass.ENTCOLL_NONE })
  Reflex.update(Isaac.GetPlayer())
  local st = Reflex.status
  local ok1 = st.active and (st.target == boil or Reflex.plan.target == boil)
  -- a cord piece: no collision, hangs off a parent -> not an enemy to fight or dodge
  Mock.room(nil, { clear = false, player = Mock.tile(2, 4) })
  local boss = Mock.enemy(EntityType.ENTITY_GEMINI, 0, Mock.tile(12, 6), { hp = 300, boss = true })
  local cord = Mock.enemy(EntityType.ENTITY_GEMINI, 20, Mock.tile(5, 4),
                          { hp = 300, coll = EntityCollisionClass.ENTCOLL_NONE, parent = boss })
  Reflex.update(Isaac.GetPlayer())
  local ok2 = Reflex.plan.target ~= cord and Reflex.status.target ~= cord
  check("fights an enemy that has no collision yet (Boils)", ok1 and ok2,
        fmt("boil fought: %s, cord ignored: %s", tostring(ok1), tostring(ok2)))
end)

------------------------------------------------------------------------ pickups (nav.lua, rules.lua)
-- 23. the author, 2026-11-25: it died walking over spikes for a coin. Value vs damage at this health decides.
run("doesn't cross spikes for a penny", function()
  Mock.room({
    "WWWWWWWDWWWWWWW",
    "W.............W",
    "W.........^^^.W",
    "W.........^.^.W",
    "D.........^^^.D",
    "W.............W",
    "W.............W",
    "W.............W",
    "WWWWWWWDWWWWWWW",
  }, { player = Mock.tile(3, 4) })
  Isaac.GetPlayer()._hearts = 2
  Mock.pickup(PickupVariant.PICKUP_COIN, 1, Mock.tile(11, 3))
  Nav.newRoom()
  Nav.update(Isaac.GetPlayer())
  check("doesn't cross spikes for a penny", not tostring(Nav.status.goal):find("pickup"),
        "goal: " .. tostring(Nav.status.goal))
end)

-- 24. Pills and cards share one pocket slot: with a card held, walking over a pill swaps them, and the bot
-- then wanted the card back (the old pick-up loop).
run("doesn't swap its card for a pill", function()
  Mock.room(nil, { player = Mock.tile(3, 4) })
  Isaac.GetPlayer()._card = 1
  Mock.pickup(PickupVariant.PICKUP_PILL, 1, Mock.tile(9, 4))
  Nav.newRoom()
  Nav.update(Isaac.GetPlayer())
  check("doesn't swap its card for a pill", not tostring(Nav.status.goal):find("pickup"),
        "goal: " .. tostring(Nav.status.goal))
end)

------------------------------------------------------------------------ 1.1.35-1.1.36
-- 25. 1.1.35: a Constant Stone Shooter (built into the room, can't be hurt) in a CLEARED room. Its shots in the
-- air kept the bot in fight mode: it aimed at the statue and the stuck ladder ended up bombing it. Now: not a
-- fight (walk on) unless a shot within dodge_only_r is coming at Isaac; then dodge, but don't aim at anything.
run("cleared room with an unkillable shooter: walks on, only dodges", function()
  Mock.room(nil, { clear = true, player = Mock.tile(7, 4) })
  local p = Isaac.GetPlayer()
  Mock.enemy(EntityType.ENTITY_CONSTANT_STONE_SHOOTER, 0, Mock.tile(1, 1), { vulnerable = false })
  Mock.shot(p.Position + Mock.vec(-240, 0), Mock.vec(8, 0)) -- far away, coming at us
  Mock.shot(p.Position + Mock.vec(60, 0), Mock.vec(8, 0))   -- close, but flying away
  local m1 = Reflex.update(p)
  local walksOn = (m1 == nil) and not Reflex.status.active
  Mock.shot(p.Position + Mock.vec(0, -80), Mock.vec(0, 8))  -- 80 px away, heading straight at us
  local m2 = Reflex.update(p)
  local dodges = (m2 ~= nil) and Reflex.status.active and Reflex.status.target == nil
  check("cleared room with an unkillable shooter: walks on, only dodges", walksOn and dodges,
        fmt("far/away shots: move %s; close shot: move %s, target %s", tostring(m1), tostring(m2),
            tostring(Reflex.status.target and Reflex.status.target.Type)))
end)

-- 26. 1.1.36: a door written off for a WEAK reason ("walking there failed", "rescue had to leave": it was busy
-- with that statue) is tried again after a minute. A locked door with no new key stays written off.
run("weak door write-offs expire after a minute, locked ones don't", function()
  Mock.floor({
    [84] = { visited = true, doors = { [0] = 83, [2] = 85, [1] = { to = 71, locked = true } } },
    [85] = { doors = { [0] = 84 } },               -- normal room on the right: the first pick
    [83] = { type = 9, doors = { [2] = 84 } },     -- arcade on the left: explored later (keeps something to do)
    [71] = { type = 4, doors = { [3] = { to = 84, locked = true } } }, -- locked treasure room above
  })
  Mock.enter(84); Nav.newRoom()
  local p = Isaac.GetPlayer()
  Nav.update(p)                 -- treasure room is locked (written off), heads for 85
  Nav.replan()                  -- ...and "walking there failed": 85 written off too
  Mock.enter(84); Nav.newRoom()
  local before = Nav.update(p)  -- both written off: the arcade (left)
  MockWorld.frame = MockWorld.frame + 30 * 61
  Mock.enter(84); Nav.newRoom()
  local after = Nav.update(p)   -- a minute later: 85 again (right); the locked door still not (not up)
  check("weak door write-offs expire after a minute, locked ones don't",
        before and before.X < -0.5 and after and after.X > 0.5,
        fmt("right after: move %s; a minute later: move %s (%s)", tostring(before), tostring(after),
            tostring(Nav.status.goal)))
end)

-- 26b. ...and the locked door must really stay written off when it's in ANOTHER room: after a minute it must
-- not walk back through B to retry the locked treasure door (in-room it re-checks the lock, so 26 can't see it).
run("locked door write-off doesn't expire after a minute", function()
  Mock.floor({
    [84] = { visited = true, doors = { [1] = 71, [2] = 85 } },
    [85] = { visited = true, doors = { [0] = 84, [2] = { to = 86, locked = true } } },
    [86] = { type = 4, doors = { [0] = { to = 85, locked = true } } },
    [71] = { type = 9, doors = { [3] = 84 } },     -- an arcade above A: something else left to do
  })
  Mock.enter(84); Nav.newRoom()
  Mock.enter(85, 0); Nav.newRoom()
  local p = Isaac.GetPlayer()
  Nav.update(p)                 -- in B: treasure door locked, no key -> written off
  MockWorld.frame = MockWorld.frame + 30 * 61
  Mock.enter(84, 2); Nav.newRoom()
  local move = Nav.update(p)    -- a minute later in A: the arcade (up), not back to B (right)
  check("locked door write-off doesn't expire after a minute", move ~= nil and move.Y < -0.5,
        fmt("move %s, goal %s", tostring(move), tostring(Nav.status.goal)))
end)

-- 27. 1.1.36: both doors of a room had been written off while it fought that statue, then "nothing to do".
-- With nothing left and doors written off, it forgives them and searches again: the only exit gets picked.
-- (Careful: forgiving EVERYTHING is also what brings back the bounce in K1 below. A fix for K1 must keep this
-- passing: this door was written off for a weak reason, K1's for "locked, no key".)
run("only exit written off: still takes it", function()
  Mock.floor({
    [84] = { visited = true, doors = { [2] = 85 } },
    [85] = { doors = { [0] = 84 } },
  })
  Mock.enter(84); Nav.newRoom()
  local p = Isaac.GetPlayer()
  Nav.update(p)
  Nav.replan()                  -- "walking there failed": the only exit is written off for the floor
  Mock.enter(84); Nav.newRoom()
  local move = Nav.update(p)
  check("only exit written off: still takes it", move ~= nil and move.X > 0.5,
        fmt("move %s, goal %s", tostring(move), tostring(Nav.status.goal)))
end)

------------------------------------------------------------------------ 1.1.46-1.1.47
-- 30. 1.1.46: corners. With wide-moving enemies around the middle, enemy circles closed as many ways out
-- everywhere as a corner's walls did, so corners stopped looking bad. Now a wall-blocked way counts double, plus a
-- steady pull to the middle and a cost near walls. Checked over 8 runs (2 layouts of enemies circling the middle,
-- Isaac starting by each corner): share of updates 60-150 spent within 80 px of a corner.
-- (Measured 2026-11-25: fixed 8%; wall ways counted once 32%; that + no centre/edge pull 52%; the centre/edge pull
-- alone only 8% -> 16%, too small for the fake to prove on its own.)
run("doesn't settle in a corner when enemies circle the middle", function()
  local function cornerDist(p)
    local best = math.huge
    for _, c in ipairs({ Mock.vec(60, 140), Mock.vec(580, 140), Mock.vec(60, 420), Mock.vec(580, 420) }) do
      best = math.min(best, (p - c):Length())
    end
    return best
  end
  local inCorner, samples, per = 0, 0, {}
  for _, cfg in ipairs({ { 4, 130, 0.06 }, { 5, 150, 0.05 } }) do
    for _, start in ipairs({ { 12, 7 }, { 1, 1 }, { 13, 1 }, { 1, 7 } }) do
      Mock.room(nil, { clear = false, player = Mock.tile(start[1], start[2]) })
      for k = 0, cfg[1] - 1 do
        Mock.orbiter(EntityType.ENTITY_GAPER, Mock.vec(320, 280), cfg[2], cfg[3], k * 6.283 / cfg[1], { hp = 999 })
      end
      local p = Isaac.GetPlayer()
      local n = 0
      for i = 1, 150 do
        local move = Reflex.update(p)
        Mock.step(move)
        if i > 60 then
          samples = samples + 1
          if cornerDist(p.Position) < 80 then n = n + 1 end
        end
      end
      inCorner = inCorner + n
      per[#per + 1] = n
    end
  end
  check("doesn't settle in a corner when enemies circle the middle", inCorner / samples < 0.2,
        fmt("%.0f%% of the time in a corner (per run, of 90: %s)", 100 * inCorner / samples, table.concat(per, ",")))
end)

-- 31. 1.1.47: burrowers. Something underground (a worm, Pin, a mid-jump boss) has no collision and surfaces
-- where Isaac stands; it stood still and got hit. One enemy that dives underground -> keep moving.
run("keeps moving while an enemy is underground", function()
  Mock.room(nil, { clear = false, player = Mock.tile(4, 4) })
  local worm = Mock.enemy(EntityType.ENTITY_ROUND_WORM, 0, Mock.tile(10, 6), { hp = 20 })
  local p = Isaac.GetPlayer()
  Reflex.update(p)        -- seen above ground (solid) once...
  Mock.step(nil)
  worm.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE -- ...then it burrows
  local still, longest, streak = 0, 0, 0
  for _ = 1, 90 do
    local move = Reflex.update(p)
    Mock.step(move)
    if not move or move:Length() < 0.01 then
      still, streak = still + 1, streak + 1
      longest = math.max(longest, streak)
    else
      streak = 0
    end
  end
  check("keeps moving while an enemy is underground", longest <= 5,
        fmt("stood still %d of 90 updates, longest %d in a row", still, longest))
end)

------------------------------------------------------------------------ 1.1.48-1.1.50
-- 32. 1.1.48: inside a secret room, the walls toward its neighbours are "doors" in the game's data but solid until
-- bombed. It kept walking into them (the author: "just leave the way you came in"). Only open, non-solid doors count.
run("leaves a secret room the way it came in", function()
  Mock.floor({
    [84] = { type = 7, visited = true, doors = { [0] = 83, [2] = 85 }, rows = {
      "WWWWWWWWWWWWWWW",
      "W.............W",
      "W.............W",
      "W.............W",
      "W.............D", -- left: solid wall (a "door" to 83 in the data); right: the way we came in
      "W.............W",
      "W.............W",
      "W.............W",
      "WWWWWWWWWWWWWWW",
    } },
    [85] = { visited = true, doors = { [0] = 84, [2] = 86 } }, -- the room we bombed our way in from
    [86] = { doors = { [0] = 85 } },  -- unexplored, past it
    [83] = { doors = { [2] = 84 } },  -- unexplored, behind the secret room's solid wall
  })
  Mock.enter(85); Nav.newRoom()
  Mock.enter(84, 2); Nav.newRoom()
  local move = Nav.update(Isaac.GetPlayer())
  check("leaves a secret room the way it came in", move ~= nil and move.X > 0.5,
        fmt("move %s, goal %s", tostring(move), tostring(Nav.status.goal)))
end)

-- 33. 1.1.49: its own bomb. Bomb danger in the v2 core is now bomb_r + Isaac's size from the bomb at the full hit
-- cost. A live bomb right next to Isaac (just placed) in a cleared room -> get clear and stay clear.
run("gets clear of a bomb it just placed", function()
  Mock.room(nil, { clear = true, player = Mock.tile(7, 4) })
  local p = Isaac.GetPlayer()
  local bomb = Mock.entity(EntityType.ENTITY_BOMB, 0, p.Position + Mock.vec(12, 6), { size = 10 })
  local clearAt, minAfter = nil, math.huge
  for i = 1, 40 do
    local move = Reflex.update(p)
    Mock.step(move)
    local d = (p.Position - bomb.Position):Length()
    if not clearAt and d >= Reflex.S.bomb_r + p.Size then clearAt = i end
    if clearAt then minAfter = math.min(minAfter, d) end
  end
  local need = Reflex.S.bomb_r + p.Size
  check("gets clear of a bomb it just placed", clearAt ~= nil and clearAt <= 30 and minAfter >= need,
        fmt("clear (%d px) after %s updates, closest after that %.0f px", need, tostring(clearAt), minAfter))
end)

-- 34. 1.1.50: poop "gates" only for an enemy that's really walled in. In the Dingle fight the planner had no
-- firing spot only because Dingle MOVES, and the bot shot a nearby poop instead of the boss.
run("doesn't shoot poop next to a moving enemy in the open", function()
  Mock.room({
    "WWWWWWWDWWWWWWW",
    "W.............W",
    "W.............W",
    "W.........p...W",
    "D.............D",
    "W.............W",
    "W.............W",
    "W.............W",
    "WWWWWWWDWWWWWWW",
  }, { clear = false, player = Mock.tile(2, 6) })
  local mover = Mock.orbiter(EntityType.ENTITY_GAPER, Mock.tile(10, 4), 50, 0.12, 0, { hp = 999 })
  local p = Isaac.GetPlayer()
  local poopTarget, enemyTarget = 0, 0
  for _ = 1, 30 do
    local move = Reflex.update(p)
    local t1, t2 = Reflex.plan.target, Reflex.status.target
    if (t1 and t1.kind == "poop") or (t2 and t2.kind == "poop") then poopTarget = poopTarget + 1 end
    if t2 == mover then enemyTarget = enemyTarget + 1 end
    Mock.step(move)
  end
  check("doesn't shoot poop next to a moving enemy in the open", poopTarget == 0 and enemyTarget > 0,
        fmt("updates aimed at the poop %d, at the enemy %d", poopTarget, enemyTarget))
end)

-- 35. 1.1.53 crowd pressure (big rooms: 18 enemies, it never went for the empty half and got pinned in a corner).
-- A 2x2-sized room (28x16), Isaac in the top-left corner, 10 enemies along the top-left (one run circling, one
-- run slowly chasing); open floor below and to the right -> over seconds 2-4 he's on average 120+ px from the
-- corner and never touched. NOT a proof of m_crowd itself: with m_crowd 0 he leaves the corner too (measured
-- 2026-11-25: 158/362 px with it, 191/340 without), so there's no mutants.lua entry. See FOUND_BUGS.md #4.
run("leaves a crowded corner of a big room for the open side", function()
  local rows = { string.rep("W", 28) }
  for _ = 1, 14 do rows[#rows + 1] = "W" .. string.rep(".", 26) .. "W" end
  rows[#rows + 1] = string.rep("W", 28)
  local spots = {}
  for y = 1, 5, 2 do for x = 5, 13, 2 do spots[#spots + 1] = { x + ((y // 2) % 2), y } end end
  local res, ok = {}, true
  for _, kind in ipairs({ "circling", "chasing" }) do
    Mock.room(rows, { clear = false, player = Mock.tile(2, 2) })
    local p = Isaac.GetPlayer()
    for k = 1, 10 do
      local c = Mock.tile(spots[k][1], spots[k][2])
      if kind == "circling" then Mock.orbiter(EntityType.ENTITY_TEST_CROWD, c, 30, 0.08, k, { hp = 999 })
      else Mock.enemy(EntityType.ENTITY_TEST_CROWD, 0, c, { chase = 1.2, hp = 999 }) end
    end
    local corner = Mock.vec(60, 140)
    local sum, touched = 0, 0
    for i = 1, 120 do
      local move = Reflex.update(p)
      Mock.step(move)
      if i > 60 then sum = sum + (p.Position - corner):Length() end
      if Mock.touching() then touched = touched + 1 end
    end
    if sum / 60 < 120 or touched > 0 then ok = false end
    res[#res + 1] = fmt("%s: %.0f px from the corner, touched %d", kind, sum / 60, touched)
  end
  check("leaves a crowded corner of a big room for the open side", ok, table.concat(res, "; "))
end)

-- K3. FOUND_BUGS.md #3 (1.1.51 sandwich cost, open): two chasers closing from opposite sides along Isaac's row.
-- Fair version over 9 cases (gap 170/200/230 px each side x speed 2.0/2.6/3.2): within ~1.2 s he should be 30+ px
-- off the line between them in at least 7 of 9. With m_pincer 200 / pincer_r 160 it's 0-2 of 9; m_pincer 0 gives 1 of 9
-- (rule off) (the rule fires, but nearly every reachable plan end counts as "between them", so it doesn't steer).
-- When it shows FIXED?: switch to check() and add a mutants.lua entry (m_pincer = 0).
run("K3 steps off the line between two chasers within ~1 s", function()
  local function lineDist(p, a, b)
    local ab = b - a
    local l = ab:Length()
    if l < 1 then return (p - a):Length() end
    return math.abs((p - a).X * ab.Y - (p - a).Y * ab.X) / l
  end
  -- its own enemy type: the mover learns reach PER TYPE, so Gapers taught by earlier tests (the fast circling
  -- ones in test 30) would change this result (9/9 inside the suite vs 0-2/9 alone). One warm-up chase first.
  local CHASER = EntityType.ENTITY_TEST_PINCER_CHASER
  local good, per = 0, {}
  local cases = { { 200, 2.6, true } }
  for _, gap in ipairs({ 170, 200, 230 }) do
    for _, sp in ipairs({ 2.0, 2.6, 3.2 }) do cases[#cases + 1] = { gap, sp } end
  end
  for _, cs in ipairs(cases) do
    local gap, sp, warm = cs[1], cs[2], cs[3]
    do
      Mock.room(nil, { clear = false, player = Mock.tile(7, 4) })
      local p = Isaac.GetPlayer()
      local a = Mock.enemy(CHASER, 0, p.Position + Mock.vec(-gap, 0), { chase = sp, hp = 999 })
      local b = Mock.enemy(CHASER, 0, p.Position + Mock.vec(gap, 0), { chase = sp, hp = 999 })
      local best = 0
      for _ = 1, warm and 75 or 36 do
        local move = Reflex.update(p)
        Mock.step(move)
        best = math.max(best, lineDist(p.Position, a.Position, b.Position))
      end
      if not warm then
        if best >= 30 then good = good + 1 end
        per[#per + 1] = fmt("%.0f", best)
      end
    end
  end
  known("K3 steps off the line between two chasers within ~1 s", good >= 7,
        fmt("%d of 9 cases got 30+ px off the line in 1.2 s (max px per case: %s)", good, table.concat(per, ",")))
end)

------------------------------------------------------------------------ found by these tests (FOUND_BUGS.md, fixed 1.1.41)

-- 28. FOUND_BUGS.md #1 (fixed 1.1.41): a locked door in EACH of two rooms, nothing else left on the floor.
-- "Nothing to do: forgave all written-off doors" un-wrote both, so it walked back and forth again (the 1.0.8
-- bounce: 22 room changes and 5,000 log lines a minute). Now only weak write-offs are forgiven, once per situation.
run("no bounce between two rooms with a locked door each", function()
  Mock.floor({
    [84] = { visited = true, doors = { [0] = { to = 83, locked = true }, [2] = 85 } },
    [85] = { visited = true, doors = { [0] = 84, [2] = { to = 86, locked = true } } },
    [86] = { type = 4, doors = { [0] = { to = 85, locked = true } } },
    [83] = { type = 4, doors = { [2] = { to = 84, locked = true } } },
  })
  Mock.enter(84); Nav.newRoom()
  Mock.enter(85, 0); Nav.newRoom()
  local notes = 0
  local before = Nav.onNote
  Nav.onNote = function() notes = notes + 1 end
  local seq = Mock.walk(Nav, 30 * 60)
  Nav.onNote = before
  check("no bounce between two rooms with a locked door each", #seq <= 1 and notes <= 10, -- B -> A once, then it stays put
        fmt("%d room changes in 60 s, %d nav notes logged", #seq, notes))
end)

-- 29. FOUND_BUGS.md #2 (fixed 1.1.41): in a one-tile corridor, a hopping spider 30 px off our row to the right. The shot axis
-- comes from the positioning lane (the row at the SPIDER's height is rock from our column, so it picks
-- "down"); the spray rule then checked only "down": no shot at all. Now it tries all 4 directions.
run("sprays down a corridor at a target roughly in line", function()
  Mock.room({
    "WWWWWWWDWWWWWWW",
    "W.............W",
    "W.............W",
    "W######.......W",
    "D.............D",
    "W######.......W",
    "W.............W",
    "W.............W",
    "WWWWWWWDWWWWWWW",
  }, { clear = false, player = Mock.tile(2, 4) })
  local spider = Mock.enemy(EntityType.ENTITY_SPIDER, 0, Mock.tile(7, 4) + Mock.vec(0, 30), { hp = 5 })
  local shots = 0
  for _ = 1, 6 do
    spider.Position = Mock.tile(7, 4) + Mock.vec(0, 30) -- it hops about but stays just off our row
    local move = Reflex.update(Isaac.GetPlayer())
    if Reflex.status.shoot ~= "" then shots = shots + 1 end
    Mock.step(move)
  end
  check("sprays down a corridor at a target roughly in line", shots >= 3, shots .. " of 6 updates fired")
end)

-- R. Risk layer (1.2.6, the author: "if you are above a certain threshold on hearts, is it worth playing risky? Do I
-- have soul hearts so I don't lose my devil deal chance? Will playing risky kill me?")
run("risk: careful only when it matters", function()
  local Risk = Reflex.risk
  local Danger = include("danger")
  local lvl = Game():GetLevel()
  Mock.room(nil, { player = Mock.tile(7, 4) })
  local p = Isaac.GetPlayer()
  Risk.pin = nil
  local oldStage = lvl.stage
  local function at(stage, red, soul)
    lvl.stage, p._hearts, p._soul = stage, red, soul
    Risk.update(p, {})
    return Risk.level
  end
  local stake = at(2, 6, 0)          -- floor 2, red hearts next: the deal is at stake
  local stakeCost = Danger.cost(p, 1)
  local soul = at(2, 6, 4)           -- same floor, two soul hearts in front
  local soulCost = Danger.cost(p, 1)
  local floor1 = at(1, 6, 0)         -- floor 1: no deal to lose
  local dying = at(1, 1, 0)          -- half a heart left
  local twoLeft = at(1, 2, 0)        -- two hits left
  check("risk: deal at stake stays careful (0.25)", math.abs(stake - 0.25) < 0.01, fmt("%.2f", stake))
  check("risk: soul hearts in front -> bolder", soul >= 0.45 and soul > stake, fmt("%.2f vs %.2f", soul, stake))
  check("risk: floor 1 has no deal -> bolder", floor1 >= 0.45, fmt("%.2f", floor1))
  check("risk: one hit from death -> fully careful", dying == 0, fmt("%.2f", dying))
  check("risk: two hits left -> careful", twoLeft <= 0.15, fmt("%.2f", twoLeft))
  check("risk: a hit is cheaper with soul hearts in front", soulCost < stakeCost, fmt("%.1f vs %.1f", soulCost, stakeCost))
  -- the settings follow the level: bold = smaller hit cost and gaps, 0.25 = exactly the old values
  local S = Reflex.S
  Risk.level = 0.25; Risk.apply(S)
  local baseHit, baseGap = S.m_hit, S.plan_clearance
  Risk.level = 0.9; Risk.apply(S)
  check("risk: bold play shrinks hit cost and gaps", S.m_hit < baseHit and S.plan_clearance < baseGap,
        fmt("m_hit %.0f->%.0f, gap %.0f->%.0f", baseHit, S.m_hit, baseGap, S.plan_clearance))
  Risk.level = 0.25; Risk.apply(S)
  check("risk: 0.25 gives back the old settings", S.m_hit == baseHit, fmt("%.0f", S.m_hit))
  -- Level 2, pace: a tough enemy for far longer than our damage says it should take -> push
  lvl.stage, p._hearts, p._soul = 2, 6, 0
  local e = Mock.enemy(10, 0, Mock.tile(12, 4), { hp = 200 })
  Risk.update(p, { e })
  local before = Risk.level
  for _ = 1, 30 * 120 do Mock.step(nil) end
  Risk.update(p, { e })
  check("risk: a slow room pushes harder (but the deal cap holds)", Risk.level > before and Risk.level <= 0.45,
        fmt("%.2f -> %.2f (%s)", before, Risk.level, Risk.why))
  lvl.stage, p._hearts, p._soul = oldStage, 6, 0
  Risk.pin = 0.25
  Risk.update(p, {}); Risk.apply(S)
end)

-- S. Level 3 run strategy (1.2.7): items valued for THIS bot and THIS run; rating 0 = never; choice pedestals = best one
run("strategy: run-aware item value", function()
  local St = Reflex.strategy
  local V = Rules.value
  St.ratings = {}
  St.loadRatings("1=3,1,tear;2=0,0;3=4,2,def;4=2,0,rng;5=2,0,dmg")
  Mock.room(nil, { player = Mock.tile(2, 4) })
  local p = Isaac.GetPlayer()
  St.lastProfile = -999; St.update(p)
  check("strategy: rated items get a value, unrated fall back", (St.itemValue(p, 1, V) or 0) > 0 and St.itemValue(p, 99, V) == nil)
  check("strategy: an item rated 0 (hurts this bot) is worth nothing", St.itemValue(p, 2, V) == 0)
  -- the same rating is worth more when it fixes the build's weakness: short range -> a range item beats a dmg item
  p.TearRange = 160; St.lastProfile = -999; St.update(p)
  local rngV, dmgV = St.itemValue(p, 4, V), St.itemValue(p, 5, V)
  p.TearRange = 260; St.lastProfile = -999; St.update(p)
  check("strategy: an item that fixes a weakness is worth more", rngV > dmgV, fmt("range item %d vs damage item %d", rngV, dmgV))
  -- never walks to a rating-0 item
  Mock.pickup(PickupVariant.PICKUP_COLLECTIBLE, 2, Mock.tile(10, 4))
  Nav.newRoom()
  Nav.update(p)
  check("strategy: doesn't walk to an item rated 0", not tostring(Nav.status.goal):find("item"), "goal: " .. tostring(Nav.status.goal))
  -- choice pedestals: two in one group -> walks toward the better one (id 3, rating 4), not the nearer id 1
  Mock.room(nil, { player = Mock.tile(7, 4) })
  local a = Mock.pickup(PickupVariant.PICKUP_COLLECTIBLE, 1, Mock.tile(4, 4))
  local b = Mock.pickup(PickupVariant.PICKUP_COLLECTIBLE, 3, Mock.tile(12, 4))
  a.OptionsPickupIndex, b.OptionsPickupIndex = 1, 1
  Nav.newRoom()
  local move = Nav.update(Isaac.GetPlayer())
  check("strategy: choice pedestals -> goes for the better item", move and move.X > 0,
        "goal: " .. tostring(Nav.status.goal) .. (move and fmt(", move x %.2f", move.X) or ""))
  St.ratings = {}
end)

-- S2. Level 3 buying: devil deals only for strong items and never below 2 containers; shop by need; risky rooms
run("strategy: deals, shop and risky rooms", function()
  local St, Risk = Reflex.strategy, Reflex.risk
  local V = Rules.value
  St.ratings = {}
  St.loadRatings("10=4,3,dmg;11=1,0,spd")
  Mock.room(nil, { player = Mock.tile(7, 4) })
  local p = Isaac.GetPlayer()
  St.lastProfile = -999; St.update(p)
  local function priced(id, price, variant)
    return { Price = price, Variant = variant or PickupVariant.PICKUP_COLLECTIBLE, SubType = id }
  end
  p.GetMaxHearts = function() return 6 end
  check("deal: a strong item for 1 heart container (3 -> 2 left) is taken", St.buyValue(p, priced(10, -1), V, Rules) > 0)
  check("deal: a weak item is never worth hearts", St.buyValue(p, priced(11, -1), V, Rules) == 0)
  p.GetMaxHearts = function() return 4 end
  check("deal: never below 2 heart containers", St.buyValue(p, priced(10, -1), V, Rules) == 0)
  p.GetMaxHearts = nil
  p.GetNumCoins = function() return 20 end
  check("shop: a good item it can afford is bought", St.buyValue(p, priced(10, 15), V, Rules) > 0)
  p._keys = 0
  check("shop: a key when it has none", St.buyValue(p, priced(1, 5, PickupVariant.PICKUP_KEY), V, Rules) > 0)
  p._keys = 3
  check("shop: no key when it has some", St.buyValue(p, priced(1, 5, PickupVariant.PICKUP_KEY), V, Rules) == 0)
  p.GetNumCoins = nil
  check("shop: nothing without the coins", St.buyValue(p, priced(10, 15), V, Rules) == 0)
  -- risky rooms: curse room with the deal at stake and red hearts only = no; with soul hearts in front = yes
  local lvl = Game():GetLevel()
  local oldStage = lvl.stage
  Risk.pin = nil
  lvl.stage, p._hearts, p._soul = 2, 6, 0
  Risk.update(p, {})
  local curseStake = Risk.allows("curse", p)
  p._soul = 4
  Risk.update(p, {})
  local curseSoul = Risk.allows("curse", p)
  check("risky rooms: curse room only with soul hearts in front when the deal is at stake", not curseStake and curseSoul)
  lvl.stage, p._hearts, p._soul = oldStage, 6, 0
  Risk.pin = 0.25
  Risk.update(p, {})
  St.ratings = {}
end)

return table.concat(results, "\n")
