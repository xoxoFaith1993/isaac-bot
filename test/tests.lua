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
  Reflex.v2err = nil
  -- every test starts from the same state: the lap direction, last move and plan carried over between tests and
  -- made results depend on which tests ran before (2026-11-26: an unrelated setting moved the ring-kite result)
  Reflex.ringDir = 1
  Reflex.mover.lastDir, Reflex.mover.lastMove, Reflex.mover.lastFrame = nil, nil, nil
  Reflex.plan.at, Reflex.plan.target, Reflex.plan.cell, Reflex.plan.cellPos, Reflex.plan.path = -999, nil, nil, nil, nil
  Reflex.plan.banned, Reflex.plan.forced, Reflex.plan.forcedTarget = {}, nil, nil
  Reflex.lastFrameSeen = nil
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then results[#results + 1] = "FAIL " .. name .. "  (crashed: " .. tostring(err) .. ")" end
  -- the movement core errored (it's run under pcall and silently falls back to the old core): a test can then pass or
  -- fail for the wrong reason (2026-11-25: a missing field made every update fall back, and 3 tests failed for it)
  if Reflex.v2err then
    results[#results + 1] = "FAIL " .. name .. "  (movement core errored, fell back: " .. tostring(Reflex.v2err) .. ")"
  end
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

-- 5b. 1.2.46 (the author, 2026-11-26, room 56: "Isaac is stuck on the host. He is sitting super far away and won't
-- aggro him for him to open"). A pit between them: tears fly over pits, so the firing-spot planner picked a square in
-- the Host's row 7 tiles away and stood there. A shielded target's firing spot must be within bait distance.
run("baits a closed Host across a pit instead of waiting far away", function()
  Mock.room({
    "WWWWWWWDWWWWWWW",
    "W.............W",
    "W.............W",
    "W......~......W",
    "D.....~~~.....D",
    "W......~......W",
    "W.............W",
    "W.............W",
    "WWWWWWWDWWWWWWW",
  }, { player = Mock.tile(5, 4), clear = false }) -- (right at the pit's edge, as live)
  local p = Isaac.GetPlayer()
  p.TearRange = 420 -- (range items: live, the planned spot was 280 px out; with the short default range it never is)
  local oldTop, oldAcc = Reflex.mover.top, Reflex.mover.acc -- (learned while it walks: later tests must not inherit it)
  local host = Mock.enemy(EntityType.ENTITY_HOST, 0, Mock.tile(12, 4), { vulnerable = false })
  local closest = math.huge
  for _ = 1, 150 do
    local move = Reflex.update(p)
    Mock.step(move)
    closest = math.min(closest, (host.Position - p.Position):Length())
  end
  p.TearRange = 260 -- (the mock player is shared by later tests: back to its default)
  Reflex.mover.top, Reflex.mover.acc = oldTop, oldAcc
  check("baits a closed Host across a pit instead of waiting far away", closest <= Reflex.S.bait_dist + 20,
        fmt("closest %.0f px (bait distance %d)", closest, Reflex.S.bait_dist))
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
  -- (seen while it still had a key, spent since: since 1.2.43 a locked door SEEN with no key is written off on sight,
  -- so these tests cover the other case - one it only finds out about at the door)
  Mock.enter(84)
  Isaac.GetPlayer()._keys = 1
  Nav.newRoom()                      -- been in both rooms already: the bot knows their doors
  Mock.enter(85, 0); Nav.newRoom()   -- ...and is now in B, next to the door it came in by
  Isaac.GetPlayer()._keys = 0
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
  -- (160 px with a clear line: in its firing range. Since 1.2.48 one that can't hit Isaac is ignored, test 41b)
  local red = Mock.enemy(EntityType.ENTITY_FIREPLACE, 1, Mock.tile(6, 4), { hp = 5, size = 13 })
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

-- 41b. 1.2.48 (the author, 2026-11-26, Depths I: "Stuck on a red fire that's not in killing distance. It should overall
-- just ignore anything that's not gonna hurt it... it's behind two rocks"): a red fire with rocks between it and
-- Isaac, in a cleared room, is no fight; the same fire in the open next to him still is.
run("ignores a red fire behind rocks", function()
  Mock.room({
    "WWWWWWWDWWWWWWW",
    "W.............W",
    "W.............W",
    "W.##..........W",
    "D.##..........D",
    "W.##..........W",
    "W.............W",
    "W.............W",
    "WWWWWWWDWWWWWWW",
  }, { clear = true, player = Mock.tile(6, 4) })
  local red = Mock.enemy(EntityType.ENTITY_FIREPLACE, 1, Mock.tile(1, 4), { hp = 5, size = 13 })
  red._enemy = false
  Reflex.plan.at = -999
  Reflex.update(Isaac.GetPlayer())
  local walledFight = Reflex.status.active
  Mock.room(nil, { clear = true, player = Mock.tile(6, 4) })
  local red2 = Mock.enemy(EntityType.ENTITY_FIREPLACE, 1, Mock.tile(3, 4), { hp = 5, size = 13 })
  red2._enemy = false
  Reflex.plan.at = -999
  Reflex.update(Isaac.GetPlayer())
  local openFight = Reflex.status.active
  check("ignores a red fire behind rocks", not walledFight and openFight,
        fmt("behind rocks made a fight: %s, in the open made a fight: %s", tostring(walledFight), tostring(openFight)))
end)

-- 42. 1.2.18 ring-kite (the author's Gemini rule: "slowly let him chase you, circle the outside of the room so you
-- always have a clear line of sight"): against a chasing boss it runs the lane round the room in one direction,
-- keeps its distance, never parks in a corner, and keeps lining up shots
run("ring-kites a chasing boss round the room", function()
  local S = Reflex.S
  local function fight(ringOn)
    -- (a clean start: the lap direction and last move carried over from earlier tests changed this result - 2026-11-26
    -- the Host bait distance, an unrelated setting, moved it from 1.5 to 1.4 rad)
    Reflex.ringDir = 1
    Reflex.mover.lastDir, Reflex.mover.lastMove = nil, nil
    Reflex.loadPlaybook("46.0=chases,k2,d3")
    local oldW, oldF = S.ring_w, S.ring_flow
    if not ringOn then S.ring_w, S.ring_flow = 0, 0 end
    Mock.room(nil, { clear = false, player = Mock.tile(11, 4) })
    local boss = Mock.enemy(46, 0, Mock.tile(3, 4), { hp = 300, boss = true, chase = 1.6, size = 20 })
    local c = Game():GetRoom():GetCenterPos()
    local p = Isaac.GetPlayer()
    local swept, prevA, corner, closest, aimed = 0, nil, 0, math.huge, 0
    for _ = 1, 240 do
      local move, shoot = Reflex.update(p)
      Mock.step(move)
      local a = math.atan(p.Position.Y - c.Y, p.Position.X - c.X)
      if prevA then
        local da = a - prevA
        if da > math.pi then da = da - 2 * math.pi elseif da < -math.pi then da = da + 2 * math.pi end
        swept = swept + da
      end
      prevA = a
      local nearX = p.Position.X < Mock.tile(0, 0).X + 50 or p.Position.X > Mock.tile(13, 0).X - 50
      local nearY = p.Position.Y < Mock.tile(0, 0).Y + 50 or p.Position.Y > Mock.tile(0, 7).Y - 50
      if nearX and nearY then corner = corner + 1 end
      closest = math.min(closest, (boss.Position - p.Position):Length())
      if shoot then aimed = aimed + 1 end
    end
    S.ring_w, S.ring_flow = oldW, oldF
    Reflex.playbook = {}
    return math.abs(swept), corner, closest, aimed
  end
  local sw, corner, closest, aimed = fight(true)
  local sw0 = fight(false)
  check("ring-kites a chasing boss round the room", sw > sw0 + 0.8 and sw > 1.5 and corner < 20 and closest > 45
        and aimed > 40,
        fmt("swept %.1f rad (%.1f without the ring), %d updates in a corner, closest %.0f px, shooting %d of 240",
            sw, sw0, corner, closest, aimed))
end)

-- 43. 1.2.19 (the author, Gurglings: it switched away from one that was nearly dead just because another was
-- closer): finish the nearly dead one, stick with the one we've been damaging
run("finishes a nearly dead enemy instead of the nearest one", function()
  Mock.room(nil, { clear = false, player = Mock.tile(2, 4) })
  Mock.enemy(EntityType.ENTITY_GAPER, 0, Mock.tile(5, 4), { hp = 20 })          -- near, full health
  local weak = Mock.enemy(EntityType.ENTITY_GAPER, 0, Mock.tile(9, 2), { hp = 4 }) -- farther, one tear from dead
  weak.MaxHitPoints = 20
  Reflex.plan.at = -999
  Reflex.update(Isaac.GetPlayer())
  -- the CHOSEN target (plan.target): status.target also names a free shot at whatever is lined up this update ("run
  -- and shoot"), and since 1.2.42 (isaac_steps 2) the near Gaper is in line on the first update
  local t = Reflex.plan.target or Reflex.status.target
  check("finishes a nearly dead enemy instead of the nearest one", t == weak,
        "target: " .. (t and (t == weak and "the nearly dead one" or ("hp " .. tostring(t.HitPoints))) or "none"))
end)

-- 44. 1.2.21 the author's rule of thumb (Dingle): "take advantage of the time windows, and position yourself so it
-- won't be hard to get out of harm's way when he does attack" - it pre-positioned off Dingle's lines long before any
-- tell and never hit him. Now: lined up and shooting while it idles, off the line once the tell plays.
run("uses the window, steps off the line when the tell plays", function()
  Reflex.loadPlaybook("261.0=charges_on_line,k2,d4")
  Reflex.loadBossTactics("261.0=200,k,kill_close,BeforeSlide|Dance|Whistle,Idle|Tired")
  Mock.room(nil, { clear = false, player = Mock.tile(3, 2) })
  local dingle = Mock.enemy(261, 0, Mock.tile(10, 4), { hp = 300, boss = true, anim = "Idle", size = 20 })
  local p = Isaac.GetPlayer()
  local shots = 0
  for _ = 1, 90 do
    local move, shoot = Reflex.update(p)
    Mock.step(move)
    if shoot then shots = shots + 1 end
  end
  dingle._anim = "BeforeSlide"
  local inLine = 0
  for i = 1, 30 do
    local move = Reflex.update(p)
    Mock.step(move)
    local rel = p.Position - dingle.Position
    if i > 10 and (math.abs(rel.X) < 36 or math.abs(rel.Y) < 36) then inLine = inLine + 1 end
  end
  Reflex.playbook = {}
  Reflex.bossTactics = {}; IsaacBotBossTactics = Reflex.bossTactics
  check("uses the window, steps off the line when the tell plays", shots >= 30 and inLine <= 6,
        fmt("shooting %d of 90 updates while it idled; in its line %d of the last 20 after the tell", shots, inLine))
end)

-- 45. 1.2.21 (the author: "it gets hit deliberately every single time when he dashes"): Dingle stands still most of
-- the fight, so the learned model said "stays put" even mid-dash. A fast mover is now predicted as a straight dash.
run("gets out of the way of a dash", function()
  -- teach the movement model that this type usually stands still (as Dingle does between dashes)
  Mock.room(nil, { clear = false, player = Mock.tile(11, 6) })
  local d0 = Mock.enemy(261, 0, Mock.tile(3, 4), { hp = 300, boss = true, size = 20 })
  for _ = 1, 240 do Reflex.update(Isaac.GetPlayer()) end
  d0._alive = false
  -- now a dash straight at Isaac
  Mock.room(nil, { clear = false, player = Mock.tile(10, 4) })
  local dingle = Mock.enemy(261, 0, Mock.tile(3, 4), { hp = 300, boss = true, size = 20, vel = Mock.vec(9, 0) })
  local p = Isaac.GetPlayer()
  local closest = math.huge
  for _ = 1, 30 do
    local move = Reflex.update(p)
    Mock.step(move)
    dingle.Velocity = Mock.vec(9, 0) -- keeps dashing (the mock doesn't run Dingle's AI)
    closest = math.min(closest, (dingle.Position - p.Position):Length())
  end
  check("gets out of the way of a dash", closest > dingle.Size + p.Size, fmt("closest %.0f px (touch at %.0f)", closest,
        dingle.Size + p.Size))
end)

-- 46. 1.2.21 (the author: it walked over spikes for an item with bombs in its pocket; "that would be a good use of
-- bombs... try not to take damage the first floor"): a rock way that doesn't hurt -> bomb it instead
run("bombs rocks instead of walking over spikes to an item", function()
  Mock.room({
    "WWWWWWWDWWWWWWW",
    "W.............W",
    "W.......#^#...W",
    "W.......#.#...W",
    "D.......###...D",
    "W.............W",
    "W.............W",
    "W.............W",
    "WWWWWWWDWWWWWWW",
  }, { player = Mock.tile(3, 5) })
  local p = Isaac.GetPlayer()
  p._bombs = 2
  Mock.pickup(PickupVariant.PICKUP_COLLECTIBLE, 1, Mock.tile(9, 3))
  Nav.newRoom()
  Nav.update(p)
  local goal = tostring(Nav.status.goal)
  check("bombs rocks instead of walking over spikes to an item", goal:find("bomb rocks") ~= nil, "goal: " .. goal)
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
-- 47. 1.2.29 (the author: "it's the Gemini's little balls that he has attached to him"): the cord balls (79.20: no
-- collision, a parent, unhurtable) are never enemies, even when their reused memory address was "seen solid" before
run("Gemini's cord balls aren't enemies, even at a reused address", function()
  Mock.room(nil, { clear = false, player = Mock.tile(11, 4) })
  local boss = Mock.enemy(79, 0, Mock.tile(3, 4), { hp = 300, boss = true })
  local balls = {}
  for i = 1, 6 do
    local b = Mock.enemy(79, 20, Mock.tile(4 + i, 4), { parent = boss, vulnerable = false,
                                                         coll = EntityCollisionClass.ENTCOLL_NONE })
    IsaacBotSolidSeen[GetPtrHash(b)] = 0 -- as if an earlier room's solid enemy lived at this address
    balls[#balls + 1] = b
  end
  local counted = 0
  for _, b in ipairs(balls) do if IsaacBotSolid(b) then counted = counted + 1 end end
  Reflex.update(Isaac.GetPlayer())
  check("Gemini's cord balls aren't enemies, even at a reused address", counted == 0 and Reflex.nEnemies == 1,
        fmt("%d balls counted, bot sees %s enemies", counted, tostring(Reflex.nEnemies)))
end)

-- 48. 1.2.30 (the author: Monstro "always shoots at the bottom right... when really it could be aiming at Monstro"):
-- a new run restarts the game's frame counter; the planner must not freeze on a plan from the old run
run("re-plans after a new run restarts the frame counter", function()
  Mock.room(nil, { clear = false, player = Mock.tile(2, 4) })
  local old = Mock.enemy(EntityType.ENTITY_GAPER, 0, Mock.tile(12, 6), { hp = 20 })
  Reflex.plan.at = -999
  Reflex.update(Isaac.GetPlayer())
  local hadPlan = Reflex.plan.target == old
  -- died: a new run, frame counter back near 0, a boss somewhere else
  Mock.room(nil, { clear = false, player = Mock.tile(11, 4) })
  Mock.setFrame(40)
  local boss = Mock.enemy(20, 0, Mock.tile(4, 2), { hp = 250, boss = true })
  for _ = 1, 20 do
    local move = Reflex.update(Isaac.GetPlayer())
    Mock.step(move)
  end
  local t = Reflex.plan.target
  check("re-plans after a new run restarts the frame counter", hadPlan and t == boss,
        fmt("first plan on the old enemy: %s, now planning on: %s", tostring(hadPlan),
            t == boss and "the boss" or (t == old and "the OLD room's enemy" or tostring(t))))
end)

-- 49. 1.2.31 (the author: "sloth's tears have an explosion radius"): a Sloth shot lying 45 px away bursts; the bot
-- must get out of the blast, while a plain shot that close but moving away is no reason to run
run("steps out of a Sloth shot's blast", function()
  -- the danger the movement core sees where Isaac stands, from shots (the "danger here" breakdown)
  local function shotDanger(spawner)
    Mock.room(nil, { clear = false, player = Mock.tile(7, 4) })
    Mock.enemy(46, 0, Mock.tile(1, 1), { hp = 300 })
    local s = Mock.shot(Mock.tile(7, 4) + Vector(50, 0), Vector(0, 0))
    s.SpawnerType = spawner
    Reflex.update(Isaac.GetPlayer())
    return tonumber(tostring(Reflex.mover.debug):match("shots (%d+)") or "0")
  end
  local sloth, plain = shotDanger(46), shotDanger(0)
  check("steps out of a Sloth shot's blast", sloth > 0 and plain == 0,
        fmt("shot danger where Isaac stands: Sloth shot 50 px away %d, plain shot %d", sloth, plain))
end)

-- 50. 1.2.31 (the author, Haunt room: "had no idea what to do and killed itself walking over the spikes trying to kill
-- the mini haunts"; 3 of 4 hits were spikes, a FULL heart each). Spikes are sure damage, an enemy's circle only a
-- maybe: inside a ring of spikes with a chaser, it dodges inside the ring instead of crossing the spikes.
run("doesn't walk over spikes to dodge a chaser", function()
  local rows = {
    "WWWWWWWDWWWWWWW",
    "W.............W",
    "W..^^^^^^^^^..W",
    "W..^.......^..W",
    "D..^.......^..D",
    "W..^.......^..W",
    "W..^^^^^^^^^..W",
    "W.............W",
    "WWWWWWWDWWWWWWW",
  }
  Mock.room(rows, { clear = false, player = Mock.tile(8, 4) })
  -- fast flyers like Lil' Haunts (260.10), two of them
  Mock.enemy(260, 10, Mock.tile(4, 3), { hp = 300, chase = 2.2 })
  Mock.enemy(260, 10, Mock.tile(4, 5), { hp = 300, chase = 2.2 })
  local p = Isaac.GetPlayer()
  local onSpikes = 0
  for _ = 1, 150 do
    local move = Reflex.update(p)
    Mock.step(move)
    local col = math.floor((p.Position.X - 20) / 40) + 1
    local row = math.floor((p.Position.Y - 100) / 40) + 1
    local line = rows[row]
    if line and line:sub(col, col) == "^" then onSpikes = onSpikes + 1 end
  end
  check("doesn't walk over spikes to dodge a chaser", onSpikes == 0,
        fmt("%d of 150 updates on spikes", onSpikes))
end)

-- 51. 1.2.31 (the author: the Squirt "should be dead within the first few seconds of the room, but he is
-- struggling"): a stop-and-go dasher is led by what it does NOW: not at all once it stops, at full speed mid-dash
run("leads a Squirt by what it does now, not its average", function()
  Reflex.loadPlaybook("220.0=dashes_at_isaac,wanders,k2,d3")
  Mock.room(nil, { clear = false, player = Mock.tile(11, 4) })
  local sq = Mock.enemy(220, 0, Mock.tile(3, 4), { hp = 20 })
  local p = Isaac.GetPlayer()
  sq.Velocity = Vector(9, 0)
  for _ = 1, 12 do Reflex.trackSpeeds({ sq }, p) end
  local midDash = Reflex.leadVel(sq)
  sq.Velocity = Vector(0, 0) -- the dash ends
  Reflex.trackSpeeds({ sq }, p)
  local stopped = Reflex.leadVel(sq)
  Reflex.playbook = {}
  check("leads a Squirt by what it does now, not its average", stopped:Length() < 0.1 and midDash.X > 8.5,
        fmt("lead mid-dash %.1f px/update (moving 9), just stopped %.1f", midDash.X, stopped:Length()))
end)

-- 52. 1.2.31 (the author, Widow: "gets a little too carried away... no regard for his surroundings"): a spider sitting
-- still between hops is no "stands still" enemy: firing spots keep the full gap from it
run("keeps the full gap from a spider between hops", function()
  Reflex.loadPlaybook("85.0=bursts,k1,d2")
  Mock.room(nil, { clear = false, player = Mock.tile(6, 2) })
  Mock.enemy(EntityType.ENTITY_GAPER, 0, Mock.tile(11, 4), { hp = 30 })
  local spider = Mock.enemy(85, 0, Mock.tile(6, 4), { hp = 10 })
  Reflex.plan.at = -999
  Reflex.update(Isaac.GetPlayer())
  local cp = Reflex.plan.cellPos
  local d = cp and (cp - spider.Position):Length() or -1
  Reflex.playbook = {}
  check("keeps the full gap from a spider between hops", cp ~= nil and d >= Reflex.S.plan_clearance + spider.Size,
        fmt("firing spot %.0f px from the spider (wanted %d+)", d, Reflex.S.plan_clearance + spider.Size))
end)

-- 53. 1.2.31 (the author: "the spider creep, the white creep, does not hurt you"): red creep is danger, white isn't
run("white creep isn't danger, red creep is", function()
  local function floorDanger(variant)
    Mock.room(nil, { clear = false, player = Mock.tile(7, 4) })
    Mock.enemy(EntityType.ENTITY_GAPER, 0, Mock.tile(1, 1), { hp = 30 })
    Mock.creep(variant, Mock.tile(7, 4), 30)
    Reflex.update(Isaac.GetPlayer())
    return tonumber(tostring(Reflex.mover.debug):match("floor (%d+)") or "0")
  end
  local red, white = floorDanger(EffectVariant.CREEP_RED), floorDanger(EffectVariant.CREEP_WHITE)
  check("white creep isn't danger, red creep is", red > 0 and white == 0,
        fmt("floor danger standing in red creep %d, in white creep %d", red, white))
end)

-- 54. 1.2.31 (the author, Gluttony: "it gets too scared of standing in front of him... take advantage of the windows
-- that you got"): a laser shooter with KNOWN wind-ups makes its row/column cost nothing between attacks, and a lot
-- while a wind-up plays
run("Gluttony's line is free between attacks, costly during the wind-up", function()
  Reflex.loadPlaybook("49.0=laser,chases,k2,d4")
  Reflex.loadBossTactics("49.0=170,,ignore,Attack01Horiz|Attack01Up|Attack01Down,")
  local function lineCost(anim)
    Mock.room(nil, { clear = false, player = Mock.tile(10, 4) })
    Mock.enemy(49, 0, Mock.tile(3, 4), { hp = 200, boss = true, anim = anim })
    Reflex.update(Isaac.GetPlayer())
    return tonumber(tostring(Reflex.mover.debug):match("row/col lines (%d+)") or "0")
  end
  local calm, winding = lineCost("WalkHori"), lineCost("Attack01Horiz")
  Reflex.playbook = {}
  Reflex.loadBossTactics("")
  check("Gluttony's line is free between attacks, costly during the wind-up", calm == 0 and winding > 0,
        fmt("standing in his row: line cost %d while he walks, %d during Attack01Horiz", calm, winding))
end)

-- 55. 1.2.31 (the author, Gemini: "gets tired, starts panting. That's your ticket to put as much damage in him...
-- Isaac doesn't utilize that"): the lap stops while the chaser pants, and the bot closes in to shoot
run("stops kiting and closes in while the chaser pants", function()
  Reflex.loadPlaybook("79.0=chases,k2,d3")
  Reflex.loadBossTactics("79.0=180,kg,ignore,,Pant")
  local function fight(anim)
    Mock.room(nil, { clear = false, player = Mock.tile(11, 4) })
    local boss = Mock.enemy(79, 0, Mock.tile(4, 4), { hp = 300, boss = true, anim = anim })
    local p = Isaac.GetPlayer()
    local d0 = (boss.Position - p.Position):Length()
    local rings = 0
    for _ = 1, 45 do
      local move = Reflex.update(p)
      if Reflex.status.ring then rings = rings + 1 end
      Mock.step(move)
    end
    return rings, d0 - (boss.Position - p.Position):Length()
  end
  local ringsPant, closedPant = fight("Pant")
  local ringsWalk = fight("WalkHori")
  Reflex.playbook = {}
  Reflex.loadBossTactics("")
  check("stops kiting and closes in while the chaser pants", ringsPant == 0 and ringsWalk > 0 and closedPant > 60,
        fmt("lap on in %d of 45 updates while panting (%d while walking), closed in %.0f px while panting",
            ringsPant, ringsWalk, closedPant))
end)

-- 56. 1.2.31 the enemy behaviour recorder (tools/recorder.py reads these lines): off by default, one line per sample
-- with every enemy, read-only, and no cord balls
run("recorder: one compact line per sample, off by default", function()
  ModCallbacks = ModCallbacks or {}
  for _, n in ipairs({ "MC_POST_UPDATE", "MC_POST_PROJECTILE_UPDATE", "MC_POST_EFFECT_UPDATE", "MC_POST_NPC_INIT",
                       "MC_POST_BOMB_INIT" }) do ModCallbacks[n] = ModCallbacks[n] or n end
  local Recorder = include("recorder")
  local cbs, lines = {}, {}
  Recorder.init({ AddCallback = function(_, id, fn) cbs[id] = fn end }, function(k, b) lines[#lines + 1] = k .. "|" .. b end)
  Mock.room(nil, { clear = false, player = Mock.tile(7, 4) })
  local boss = Mock.enemy(79, 0, Mock.tile(3, 4), { hp = 200, boss = true, anim = "WalkHori" })
  Mock.enemy(79, 20, Mock.tile(4, 4), { parent = boss, vulnerable = false, coll = EntityCollisionClass.ENTCOLL_NONE })
  Mock.enemy(85, 0, Mock.tile(9, 2), { hp = 10 })
  Mock.setFrame(2000)
  cbs[ModCallbacks.MC_POST_UPDATE]()
  local whileOff = #lines
  Recorder.on = true
  cbs[ModCallbacks.MC_POST_UPDATE]()
  local l = lines[#lines] or ""
  check("recorder: one compact line per sample, off by default", whileOff == 0 and #lines == 1
        and l:find("79.0,WalkHori", 1, true) ~= nil and l:find(";85.0,", 1, true) ~= nil and not l:find("79.20", 1, true),
        "lines while off " .. whileOff .. ", line: " .. l:sub(1, 160))
end)

-- 57. 1.2.32 (the author: with Chocolate Milk "it won't shoot... just walking around with his mouth full"): charge
-- weapons get a hold-then-let-go rhythm; normal tears keep the button held
run("charge weapons: holds, then lets go to fire", function()
  Mock.room(nil, { clear = false, player = Mock.tile(7, 4) })
  local p = Isaac.GetPlayer()
  local function pattern(hasMilk)
    p.HasCollectible = function(_, id) return hasMilk and id == 69 end
    Reflex.chargeFire(p, nil)
    local s = ""
    for _ = 1, 40 do s = s .. (Reflex.chargeFire(p, "left") and "H" or "_") end
    return s
  end
  local milk, plain = pattern(true), pattern(false)
  p.HasCollectible = nil
  check("charge weapons: holds, then lets go to fire", milk:find("H_", 1, true) ~= nil and not plain:find("_", 1, true),
        "Chocolate Milk: " .. milk .. " | plain tears: " .. plain)
end)

-- 58. 1.2.32 (the author: a Horf, "it was dancing around it for quite a while"): a shot coming from a FAR shooter
-- draws no pre-fire line (the shot can be dodged once it's fired); a CLOSE one still does
run("no pre-fire line from a far shooter, still one up close", function()
  local T = Reflex.tells
  local old = T.shotComing
  T.shotComing = function(e) return e.Type == 12 end
  local function lineCost(dx)
    Mock.room(nil, { clear = false, player = Mock.tile(7, 4) })
    Mock.enemy(12, 0, Mock.tile(7, 4) + Vector(dx, 0), { hp = 20 })
    Reflex.update(Isaac.GetPlayer())
    return tonumber(tostring(Reflex.mover.debug):match("attack lines (%d+)") or "0")
  end
  local ok, far, near = pcall(function() return lineCost(240), lineCost(80) end)
  T.shotComing = old
  check("no pre-fire line from a far shooter, still one up close", ok and far == 0 and near > 0,
        fmt("attack-line cost with a Horf 240 px away %s, 80 px away %s", tostring(far), tostring(near)))
end)

-- 59. 1.2.33 (the author: "the host will not open up if you are attacking it or shooting near it. You have to wait for
-- the opening"): no tears at a closed Host while baiting it; fires once it opens
run("holds fire at a closed Host, fires when it opens", function()
  local function shots(vulnerable)
    Mock.room(nil, { player = Mock.tile(2, 4), clear = false })
    local p = Isaac.GetPlayer()
    Mock.enemy(EntityType.ENTITY_HOST, 0, Mock.tile(5, 4), { vulnerable = vulnerable })
    local n = 0
    for _ = 1, 45 do
      local move, shoot = Reflex.update(p)
      if shoot and shoot ~= "" then n = n + 1 end
      Mock.step(move)
    end
    return n
  end
  local closed, open = shots(false), shots(true)
  check("holds fire at a closed Host, fires when it opens", closed == 0 and open > 10,
        fmt("updates firing at a closed Host %d of 45, at an open one %d", closed, open))
end)

-- 60. 1.2.34 (recorder + decompiled AI agree: the Haunt takes no damage in state 4, orbiting Lil' Haunts none in
-- state 3): targets only the chasing Lil' Haunt, and holds fire when only unhurtable ones are left
run("Haunt phase 1: only the chasing Lil' Haunt is a target", function()
  local function npc(e, state) e.ToNPC = function(self) return self end; e.State = state; return e end
  Mock.room(nil, { player = Mock.tile(11, 4), clear = false })
  local p = Isaac.GetPlayer()
  npc(Mock.enemy(260, 0, Mock.tile(6, 2), { hp = 300, boss = true }), 4)
  npc(Mock.enemy(260, 10, Mock.tile(6, 3), { hp = 20 }), 3)
  local chaser = npc(Mock.enemy(260, 10, Mock.tile(4, 6), { hp = 20 }), 4)
  Reflex.plan.at = -999
  Reflex.update(p)
  local t = Reflex.status.target or Reflex.plan.target
  -- the chaser dies: nothing hurtable left
  chaser._alive = false
  local fired = 0
  for _ = 1, 30 do
    local move, shoot = Reflex.update(p)
    if shoot and shoot ~= "" then fired = fired + 1 end
    Mock.step(move)
  end
  check("Haunt phase 1: only the chasing Lil' Haunt is a target", t == chaser and fired == 0,
        fmt("target: %s; updates firing with only the shielded ones left: %d of 30",
            t == chaser and "the chasing Lil' Haunt" or tostring(t and (t.Type .. "." .. t.Variant)), fired))
end)

-- 61. 1.2.34 (decompiled AI + recorder: a Charger charges when Isaac is in its row/column WITHIN 200 px): its line
-- costs nothing at 300 px, and a lot at 150 px
run("Charger's row only matters within 200 px", function()
  Reflex.loadPlaybook("23.0=charges_on_line,k2,d2")
  local function lineCost(dx)
    Mock.room(nil, { clear = false, player = Mock.tile(7, 4) })
    Mock.enemy(23, 0, Mock.tile(7, 4) + Vector(dx, 0), { hp = 20 })
    Reflex.update(Isaac.GetPlayer())
    return tonumber(tostring(Reflex.mover.debug):match("row/col lines (%d+)") or "0")
  end
  local far, near = lineCost(-300), lineCost(-150)
  Reflex.playbook = {}
  check("Charger's row only matters within 200 px", far == 0 and near > 0,
        fmt("standing in its row: line cost %d at 300 px, %d at 150 px", far, near))
end)

-- 62. 1.2.34 (Sloth's lob: a known arc, harmless overhead, a blast where it lands): a lob just launched above Isaac and
-- flying away is no danger where he stands; the same shot without gravity (a plain shot) is
run("a lob high overhead is no danger; it lands farther on", function()
  local function shotDanger(accel)
    Mock.room(nil, { clear = false, player = Mock.tile(7, 4) })
    Mock.enemy(46, 0, Mock.tile(1, 1), { hp = 300 })
    local s = Mock.shot(Mock.tile(7, 4), Vector(8, 0))
    s.SpawnerType = 46
    s.Height, s.FallingSpeed, s.FallingAccel = -45, -21.9, accel
    s.ToProjectile = function(self) return self end
    Reflex.update(Isaac.GetPlayer())
    return tonumber(tostring(Reflex.mover.debug):match("shots (%d+)") or "0")
  end
  local lob, flat = shotDanger(1.02), shotDanger(0)
  check("a lob high overhead is no danger; it lands farther on", lob == 0 and flat > 0,
        fmt("shot danger where Isaac stands: lob just launched over him %d, flat shot %d", lob, flat))
end)

-- 63. 1.2.35 (the author: "even if there's a pixel peek of space in between rocks... you can't go through it"): the
-- corner where two rocks meet diagonally is no passage - Isaac's body has to fit, not just his centre
run("a diagonal gap between two rocks is no passage", function()
  Mock.room({
    "WWWWWWWDWWWWWWW",
    "W.............W",
    "W.............W",
    "W.....#.......W",
    "D......#......D",
    "W.............W",
    "W.............W",
    "W.............W",
    "WWWWWWWDWWWWWWW",
  }, { player = Mock.tile(2, 2) })
  local room = Game():GetRoom()
  -- just past the shared corner, on the open side of the grid line (the old centre-only check said "open")
  local corner = Mock.tile(6, 3) + Vector(21, 19)
  local open = Mock.tile(10, 6)
  check("a diagonal gap between two rocks is no passage",
        Reflex.blocked(room, corner, false) > 0 and Reflex.blocked(room, open, false) == 0,
        fmt("at the rocks' corner: %s, in the open: %s", Reflex.blocked(room, corner, false) > 0 and "blocked" or
            "OPEN", Reflex.blocked(room, open, false) == 0 and "open" or "blocked"))
end)

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

-- 64. 1.2.36 (the author: it blew itself up at a secret wall, "it in fact had an escape route. You can go up or
-- down"): its bomb at its feet in a one-tile strip between pits and the wall - it must run up or down the strip
run("escapes its own bomb along a narrow strip", function()
  Mock.room({
    "WWWWWWWDWWWWWWW",
    "W.............W",
    "W.............W",
    "W..........~~.W",
    "D..........~~.D",
    "W..........~~.W",
    "W.............W",
    "W.............W",
    "WWWWWWWDWWWWWWW",
  }, { clear = true, player = Mock.tile(13, 4) })
  local p = Isaac.GetPlayer()
  local bomb = Mock.entity(EntityType.ENTITY_BOMB, 0, p.Position + Mock.vec(4, 0), { size = 10 })
  local clearAt = nil
  for i = 1, 40 do
    local move = Reflex.update(p)
    Mock.step(move)
    if not clearAt and (p.Position - bomb.Position):Length() >= Reflex.S.bomb_r + p.Size then clearAt = i end
  end
  check("escapes its own bomb along a narrow strip", clearAt ~= nil and clearAt <= 30,
        fmt("clear of the blast after %s updates (ended %.0f px from it)", tostring(clearAt),
            (p.Position - bomb.Position):Length()))
end)

-- 65. 1.2.37 (the author: "it still walked over the spike!" - the last diagonal step to an item cut the corner past
-- the spike beside it): a path never cuts a corner next to a spike
run("paths don't cut corners past spikes", function()
  Mock.room({
    "WWWWWWWDWWWWWWW",
    "W.............W",
    "W.............W",
    "W.......^.....W",
    "D.............D",
    "W.............W",
    "W.............W",
    "W.............W",
    "WWWWWWWDWWWWWWW",
  }, { clear = true, player = Mock.tile(6, 2) })
  local room = Game():GetRoom()
  local w = room:GetGridWidth()
  local start, goal = room:GetGridIndex(Mock.tile(6, 2)), room:GetGridIndex(Mock.tile(8, 4))
  local path = Nav.findPath(room, start, goal, false, false) or {}
  local spike = room:GetGridIndex(Mock.tile(8, 3))
  local cut, prev = false, start
  for _, i in ipairs(path) do
    local dx, dy = i % w - prev % w, i // w - prev // w
    if dx ~= 0 and dy ~= 0 then
      local a, b = prev + dx, prev + dy * w
      if a == spike or b == spike then cut = true end
    end
    if i == spike then cut = true end
    prev = i
  end
  check("paths don't cut corners past spikes", #path > 0 and not cut,
        fmt("%d steps, cuts past or onto the spike: %s", #path, tostring(cut)))
end)

-- 66. 1.2.39 (the best run died to a Gaping Maw: "he sucks in air and it brings in Isaac" onto the spikes around it):
-- with a steady pull toward a ring of spikes, the bot measures the push and keeps off the spikes
run("measures a pull and keeps off the spikes it drags toward", function()
  local rows = {
    "WWWWWWWDWWWWWWW",
    "W.............W",
    "W.............W",
    "W.....^^^.....W",
    "D.....^.^.....D",
    "W.....^^^.....W",
    "W.............W",
    "W.............W",
    "WWWWWWWDWWWWWWW",
  }
  PULL = PULL or 2.2
  Mock.room(rows, { clear = false, player = Mock.tile(10, 4) })
  local p = Isaac.GetPlayer()
  local maw = Mock.tile(7, 4)
  Mock.enemy(235, 0, maw, { hp = 100, vulnerable = false })
  Mock.enemy(EntityType.ENTITY_GAPER, 0, Mock.tile(12, 1), { hp = 300, chase = 0.6 })
  local onSpikes = 0
  for _ = 1, 150 do
    local move = Reflex.update(p)
    Mock.step(move)
    local to = maw - p.Position
    local pull = to:Length() > 1 and to:Normalized() * PULL or Vector(0, 0)
    p.Position = p.Position + pull
    p.Velocity = p.Velocity + pull
    local col = math.floor((p.Position.X - 20) / 40) + 1
    local row = math.floor((p.Position.Y - 100) / 40) + 1
    if rows[row] and rows[row]:sub(col, col) == "^" then onSpikes = onSpikes + 1 end
  end
  check("measures a pull and keeps off the spikes it drags toward", onSpikes == 0,
        fmt("%d of 150 updates on spikes (pull %.1f px/update toward the Maw)", onSpikes, PULL))
end)

-- 67. 1.2.40 (the author: it spent "his only soul heart, the only thing that was preventing him from losing the devil
-- deal" on floor 2 for an item: "I don't think that's worth it"): a hit that uses up the last protection costs the deal
run("a hit that spends the last soul heart costs the deal", function()
  Mock.room(nil, { clear = true, player = Mock.tile(7, 4) })
  local p = Isaac.GetPlayer()
  local Risk, Danger = Reflex.risk, include("danger")
  local saved = { Risk.dealLive, Risk.atStake, Risk.buffer, Risk.level }
  Risk.dealLive, Risk.atStake, Risk.level = true, false, 0.85
  Risk.buffer = 2 -- one soul heart in front of the red ones
  local lastBuffer = Danger.cost(p, 2)
  Risk.buffer = 4 -- two soul hearts: one is left after this hit
  local spare = Danger.cost(p, 2)
  Risk.dealLive, Risk.atStake, Risk.buffer, Risk.level = saved[1], saved[2], saved[3], saved[4]
  check("a hit that spends the last soul heart costs the deal",
        lastBuffer >= Rules.risk.deal_value and spare < Rules.risk.deal_value,
        fmt("full-heart hit with 1 soul heart in front: %.0f, with 2: %.0f (deal worth %d)", lastBuffer, spare,
            Rules.risk.deal_value))
end)

-- 68. 1.2.41 Dingle predictor, Level 1 (decompiled AI + recordings; the author: "Level 1 first"): winding up for a
-- dash (BeforeSlide), the bot gets off the line before the aim locks; the learned circle alone gives no reason to
run("Dingle predictor: off his line before the aim locks", function()
  local S = Reflex.S
  local function offLine(known)
    local saved = S.predict_known
    S.predict_known = known
    Mock.room(nil, { clear = false, player = Mock.tile(11, 4) })
    local p = Isaac.GetPlayer()
    local d = Mock.enemy(261, 0, Mock.tile(7, 4), { hp = 300, boss = true, anim = "BeforeSlide" })
    d.ToNPC = function(self) return self end
    d.State, d.StateFrame = 11, 15
    local y0 = p.Position.Y
    for i = 1, 8 do
      d.StateFrame = 15 + i
      local move = Reflex.update(p)
      Mock.step(move)
    end
    S.predict_known = saved
    return math.abs(p.Position.Y - y0)
  end
  local withKnown, without = offLine(1), offLine(0)
  -- (work in progress: predict_known is off by default until this passes - KNOWN, not a failure, 2026-11-26)
  known("Dingle predictor: off his line before the aim locks", withKnown >= 25 and withKnown > without + 15,
        fmt("off Dingle's row after 8 updates: %.0f px with the predictor, %.0f px without", withKnown, without))
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
  Mock.enter(84)
  Isaac.GetPlayer()._keys = 1 -- (seen with a key, spent since: see bounceFloor)
  Nav.newRoom()
  Mock.enter(85, 0); Nav.newRoom()
  Isaac.GetPlayer()._keys = 0
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
  -- (since 2026-11-26 weighed in deals.lua: worth minus hearts minus the angel path - floor 2, no deal taken yet)
  local lv0 = Game():GetLevel()
  local stage0 = lv0.stage
  lv0.stage = 2
  p.GetMaxHearts = function() return 8 end
  check("deal: a strong item for 1 heart container (4 -> 3 left) is taken", St.buyValue(p, priced(10, -1), V, Rules) > 0,
        tostring(St.deals.why))
  p.GetMaxHearts = function() return 6 end
  check("deal: a weak item is never worth hearts", St.buyValue(p, priced(11, -1), V, Rules) == 0)
  p.GetMaxHearts = function() return 4 end
  check("deal: never below 2 heart containers", St.buyValue(p, priced(10, -1), V, Rules) == 0)
  p.GetMaxHearts = nil
  lv0.stage = stage0
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
  -- (1.2.40, the author: one soul heart is the deal's only protection - the door's hits would spend it)
  p._soul = 2
  Risk.update(p, {})
  local curseOneSoul = Risk.allows("curse", p)
  check("risky rooms: curse room only with soul hearts in front when the deal is at stake",
        not curseStake and curseSoul and not curseOneSoul,
        fmt("red only: %s, two soul hearts: %s, one soul heart: %s", tostring(curseStake), tostring(curseSoul),
            tostring(curseOneSoul)))
  lvl.stage, p._hearts, p._soul = oldStage, 6, 0
  Risk.pin = 0.25
  Risk.update(p, {})
  St.ratings = {}
end)

-- 69. 1.2.41 forecast plan step 2: a darting spider's card puts its zone where the dart ENDS (its TargetPosition), not
-- where its current velocity would carry it. The card check (2026-11-26) found the spider darts to a fixed point
-- without re-aiming: forecast 24 px off after 16 updates vs 62 for coasting.
run("a darting spider's zone is at the dart's end (card forecast)", function()
  Mock.room(nil, { clear = false, player = Mock.tile(10, 6) })
  local spider = Mock.enemy(94, 0, Mock.tile(3, 4), { hp = 20 })
  spider.Velocity = Mock.vec(8, 0)
  spider.TargetPosition = Mock.tile(7, 2)
  spider.ToNPC = function(self) return self end
  spider.State = 4
  local S, M = Reflex.S, Reflex.mover
  local ctx = { fcCache = {}, player = Isaac.GetPlayer(), room = Game():GetRoom() }
  local z = M.cardZone(spider, 20, S, ctx)
  local goal = Mock.tile(7, 2)
  local d = z and math.sqrt((z.cx - goal.X) ^ 2 + (z.cy - goal.Y) ^ 2) or 999
  check("a darting spider's zone is at the dart's end (card forecast)", z ~= nil and d < 30,
        fmt("zone centre %s px from the dart's end after 20 updates (coasting would be ~%d px off)",
            z and string.format("%.0f", d) or "none", math.floor(math.sqrt((spider.Position.X + 160 - goal.X) ^ 2 + (spider.Position.Y - goal.Y) ^ 2))))
end)

-- 70. 1.2.43 (2026-11-26, room 71: six red fires behind rock columns, two plates in the corners, doors shut): it
-- "fought" the fires it couldn't reach for over a minute. An unpressed plate with only fires left = go press it.
run("presses the button instead of fighting fires behind rocks", function()
  Mock.room({
    "WWWWWWWDWWWWWWW",
    "W_#.........#.W",
    "W.#.........#.W",
    "W.#.........#.W",
    "D.#.........#.D",
    "W.#.........#.W",
    "W.#.........#.W",
    "W.#.........#_W",
    "WWWWWWWDWWWWWWW",
  }, { clear = false, player = Mock.tile(7, 4) })
  for _, tl in ipairs({ { 1, 3 }, { 1, 5 }, { 13, 3 }, { 13, 5 } }) do
    local fire = Mock.fire(Mock.tile(tl[1], tl[2]))
    fire.Variant = 1 -- red: it shoots
  end
  -- (and one in the open, 120 px from Isaac with a clear line: one that CAN hit him - since 1.2.48 the ones behind
  -- rocks are ignored anyway, so this keeps the plate rule itself under test)
  Mock.fire(Mock.tile(10, 4)).Variant = 1
  Nav.newRoom()
  local p = Isaac.GetPlayer()
  local move = Reflex.update(p)
  local active = Reflex.status.active
  if not move then move = Nav.update(p) end
  local goal = Reflex.status.active and tostring(Reflex.status.goalText) or tostring(Nav.status.goal)
  check("presses the button instead of fighting fires behind rocks", not active and goal:find("button") ~= nil,
        fmt("reflexes %s, goal: %s", active and "FIGHTING" or "off", goal))
end)

-- 71. 1.2.43 (2026-11-26: it walked three rooms back to the start room to find the treasure door locked, then walked
-- back): a locked door it has already SEEN with no key isn't a goal. Start room 84 has a locked treasure room (83);
-- the bot was in 84 with no key and is now in 85, with an unexplored room (86) on the far side.
run("doesn't walk back to a locked door it already saw", function()
  Mock.floor({
    [84] = { visited = true, doors = { [0] = { to = 83, locked = true }, [2] = 85 } },
    [83] = { type = 4, doors = { [2] = { to = 84, locked = true } } },
    [85] = { visited = true, doors = { [0] = 84, [2] = 86 } },
    [86] = { doors = { [0] = 85 } },
  })
  Mock.enter(84)
  Isaac.GetPlayer()._keys = 0
  Nav.newRoom()
  Mock.enter(85, 0); Nav.newRoom()
  local move = Nav.update(Isaac.GetPlayer())
  check("doesn't walk back to a locked door it already saw", move ~= nil and move.X > 0.5,
        fmt("move %s (right = on to the new room), goal %s", tostring(move), tostring(Nav.status.goal)))
end)

-- 72. 1.2.45 (2026-11-26, room 82: reward plates sealed in metal blocks, one behind a poop): it walked into the metal
-- toward the nearest sealed plate for minutes. A plate with no way in is skipped; the reachable one gets pressed.
run("skips a button sealed in metal and presses the reachable one", function()
  Mock.room({
    "WWWWWWWDWWWWWWW",
    "W.............W",
    "W.............W",
    "W.............W",
    "D.............D",
    "W.............W",
    "WMMMMMMMMMM...W",
    "WMM_MMMMMMM._.W",
    "WWWWWWWDWWWWWWW",
  }, { clear = true, player = Mock.tile(3, 4) })
  Isaac.GetPlayer()._bombs = 3
  Nav.newRoom()
  local p = Isaac.GetPlayer()
  local pressedReachable = false
  for _ = 1, 30 * 12 do
    local move = Nav.update(p)
    Mock.step(move)
    local col = math.floor((p.Position.X - 20) / 40) + 1
    local row = math.floor((p.Position.Y - 100) / 40) + 1
    if col == 13 and row == 7 then pressedReachable = true; break end
  end
  check("skips a button sealed in metal and presses the reachable one", pressedReachable,
        fmt("ended at %s, goal %s", tostring(p.Position), tostring(Nav.status.goal)))
end)

-- 78. Deals, level 2 (the author, 2026-11-26, after the first Mom kill: "I'd like to work on the devil deals and angel
-- deals weighing"). deals.lua's devilNet on its own: hearts dearer the fewer are left, the first deal pays for the
-- angel rooms it gives up, and once on the devil path that cost is gone.
run("deals: weighing devil items", function()
  local Deals = Reflex.strategy.deals
  local D = Rules.deals
  local function st(containers, stage, taken, soul)
    return { containers = containers, stage = stage, dealTaken = taken, soul = soul or 0,
             hp = containers * 2 + (soul or 0) }
  end
  local one = { red = 2 }
  local q4, q2 = 90, 60
  local a = Deals.devilNet(q4, one, st(6, 2, false), D)
  local b = Deals.devilNet(q2, one, st(6, 2, false), D)
  local c = Deals.devilNet(q2, one, st(6, 2, true), D)
  local d = Deals.devilNet(q2, one, st(6, 6, false), D)
  local e = Deals.devilNet(q4, { red = 4 }, st(3, 2, true), D)
  local f = Deals.devilNet(q4, one, st(6, 2, true), D) > Deals.devilNet(q4, one, st(3, 2, true), D)
  local g = Deals.devilNet(q4, { soul = 6 }, st(3, 3, true, 4), D)
  check("deals: weighing devil items", a > 0 and b == 0 and c > 0 and d > 0 and e == 0 and f and g == 0,
        fmt("Q4 floor 2: %s | Q2 floor 2: %s | Q2 after a deal: %s | Q2 floor 6: %s | 2 hearts at 3 containers: %s | " ..
            "hearts dearer when fewer: %s | 3 soul with 2: %s", a > 0 and "buy" or "skip", b > 0 and "buy" or "skip",
            c > 0 and "buy" or "skip", d > 0 and "buy" or "skip", e > 0 and "buy" or "skip", tostring(f),
            g > 0 and "buy" or "skip"))
end)

-- 79. Deals, level 1: the walker never saw a deal door. Devil/angel rooms sit at room index -1 and doors to negative
-- indexes were all ignored, so after a boss it walked past an open deal door to the trapdoor (no deal room entered in
-- any run so far). A cleared boss room with an open devil door and a trapdoor: it heads for the devil door first.
run("deals: walks into an open devil room after the boss", function()
  local rows = {
    "WWWWWWWDWWWWWWW",
    "W.............W",
    "W.............W",
    "W.............W",
    "D......T......W",
    "W.............W",
    "W.............W",
    "W.............W",
    "WWWWWWWDWWWWWWW",
  }
  Mock.floor({
    [84] = { visited = true, type = 5, clear = true, rows = rows, doors = { [1] = { to = -1, type = 14 } } },
    [-1] = { type = 14, doors = { [3] = 84 } },
  })
  Mock.enter(84, nil, Mock.tile(7, 6)); Nav.newRoom()
  local move = Nav.update(Isaac.GetPlayer())
  local goal = tostring(Nav.status.goal)
  check("deals: walks into an open devil room after the boss", goal:find("deal room") ~= nil and move ~= nil and move.Y < -0.5,
        fmt("goal %s, move %s", goal, tostring(move)))
end)

-- 80. 1.2.50 (the author, 2026-11-26: "Why did he just bomb himself?... It's like he gave up, committed suicide... It was
-- such a good run"): the stuck-rescue dropped a bomb at one heart, from a pocket by the wall with every way out closed.
-- No bomb when the blast could kill, or when no floor outside the blast can be reached in time.
run("never bombs where the blast could kill it", function()
  local rows = {
    "WWWWWWWDWWWWWWW",
    "W.............W",
    "W###..........W",
    "W..#..........W",
    "D..#..........D",
    "W###..........W",
    "W.............W",
    "W.............W",
    "WWWWWWWDWWWWWWW",
  }
  Mock.room(rows, { clear = true, player = Mock.tile(7, 4) })
  local p = Isaac.GetPlayer()
  local room = Game():GetRoom()
  p._hearts, p._soul = 6, 0
  local openOK = Nav.bombSafe(room, p, Mock.tile(7, 4))
  p._hearts = 2
  local lowOK, lowWhy = Nav.bombSafe(room, p, Mock.tile(7, 4))
  p._hearts = 6
  local pocketOK, pocketWhy = Nav.bombSafe(room, p, Mock.tile(1, 4)) -- the pocket at the left, closed by rocks
  check("never bombs where the blast could kill it", openOK and not lowOK and not pocketOK,
        fmt("open floor, 3 hearts: %s | 1 heart: %s (%s) | rock pocket: %s (%s)", tostring(openOK), tostring(lowOK),
            tostring(lowWhy), tostring(pocketOK), tostring(pocketWhy)))
end)

------------------------------------------------------------------------ forecast plan step 3: the positioning brain
-- (position.lua over roommap.lua; docs/FORECAST_PLAN.md step 3). Each test is one of the author's live notes
-- (docs/LIVE_NOTES.md). The brain is behind S.position (A/B), so each test switches it on itself.
local Danger = include("danger")
local function withPosition(fn)
  local S = Reflex.S
  local old = S.position
  S.position = 1
  Reflex.position.reset()
  local ok, a, b, c = pcall(fn)
  S.position = old
  Reflex.position.reset()
  if not ok then error(a) end
  return a, b, c
end

-- 73. Live note 1 (the author, 2026-11-26: "Isaac just going into the corner of a 4x4 room... When are we gonna fix
-- this?"). Gate bench d.410, 1.2.30: four hits on one tile by the top wall two tiles from the corner, pinned by Gapers.
-- A big room, Isaac by the top wall near the top-left corner, five chasers closing from the right and below.
local function bigRoom()
  local rows = { string.rep("W", 28) }
  for _ = 1, 14 do rows[#rows + 1] = "W" .. string.rep(".", 26) .. "W" end
  rows[#rows + 1] = string.rep("W", 28)
  return rows
end
local function pinnedRun()
  Mock.room(bigRoom(), { clear = false, player = Mock.tile(4, 2) })
  local p = Isaac.GetPlayer()
  for _, xy in ipairs({ { 9, 2 }, { 10, 5 }, { 8, 8 }, { 5, 9 }, { 12, 3 } }) do
    Mock.enemy(EntityType.ENTITY_GAPER, 1, Mock.tile(xy[1], xy[2]), { chase = 3, hp = 999 })
  end
  local tl, br = Mock.vec(60, 140), Mock.vec(40 + 40 * 27 - 20, 120 + 40 * 15 - 20)
  local corner, touched = 0, 0
  for _ = 1, 240 do
    local move = Reflex.update(p)
    Mock.step(move)
    local x, y = p.Position.X, p.Position.Y
    if math.min(x - tl.X, br.X - x) < 80 and math.min(y - tl.Y, br.Y - y) < 80 then corner = corner + 1 end
    if Mock.touching() then touched = touched + 1 end
  end
  return corner, touched
end
run("positioning: doesn't get pinned in a corner of a big room", function()
  local c0, t0 = pinnedRun()
  local c1, t1 = withPosition(pinnedRun)
  check("positioning: doesn't get pinned in a corner of a big room", c1 < 20 and t1 <= t0 and t1 == 0,
        fmt("brain off: %d corner updates, touched %d; on: %d, touched %d (of 240)", c0, t0, c1, t1))
end)

-- 74. Live note 3 (the author, 2026-11-26, Gluttony 2012: "It is standing in a area where it has no escape route from
-- the brimstone... You can stand close to him within the gap that allows you to move vertical... But he decides to
-- stand in the one place where he can't go vertical"). Gluttony at the left; his row runs through a one-tile rock
-- corridor where Isaac starts. The home spot must not be in his row inside the corridor.
run("positioning: Gluttony - no home in his row where it can't step out", function()
  Reflex.loadPlaybook("49.0=laser,chases,k2,d4")
  Reflex.loadBossTactics("49.0=170,,ignore,Attack01Horiz|Attack01Up|Attack01Down,")
  local trapped = withPosition(function()
    Mock.room({
      "WWWWWWWWWWWWWWW",
      "W.............W",
      "W.............W",
      "W.....###.....W",
      "W.............W",
      "W.....###.....W",
      "W.............W",
      "W.............W",
      "WWWWWWWWWWWWWWW",
    }, { clear = false, player = Mock.tile(7, 4) })
    local boss = Mock.enemy(49, 0, Mock.tile(2, 4), { hp = 999, boss = true, anim = "WalkHori" })
    local p = Isaac.GetPlayer()
    local n = 0
    for i = 1, 90 do
      local move = Reflex.update(p)
      Mock.step(move)
      boss.Position = Mock.tile(2, 4)
      local x = p.Position.X
      local inRow = math.abs(p.Position.Y - boss.Position.Y) < (boss.Size or 13) + 14
      if i > 30 and inRow and x > 240 and x < 400 then n = n + 1 end
    end
    return n
  end)
  Reflex.playbook = {}
  Reflex.loadBossTactics("")
  -- KNOWN (2026-11-26, step 3 in progress): the home spot is right (the corridor's mouth) but the reflexes stop ~55 px
  -- short, in his row, even with the commit signal. FOUND_BUGS.md #4.
  known("positioning: Gluttony - no home in his row where it can't step out", trapped < 6,
        fmt("%d of the last 60 updates in his row inside the rock corridor", trapped))
end)

-- 75. Live note 6 (the author, 2026-11-26: "if he were to just learn the terrain, the environment, like the creep from
-- the gurglings better, and position himself better"). Creep puddles in the middle of the room, a slow chaser at the
-- right: the home spot is never on creep, and Isaac doesn't stand in it.
run("positioning: no home on creep", function()
  local onCreep, homeOnCreep = withPosition(function()
    Mock.room(nil, { clear = false, player = Mock.tile(4, 4) })
    for _, xy in ipairs({ { 6, 3 }, { 6, 4 }, { 6, 5 }, { 7, 4 }, { 5, 4 } }) do
      Mock.creep(EffectVariant.CREEP_RED, Mock.tile(xy[1], xy[2]), 22)
    end
    Mock.enemy(EntityType.ENTITY_GAPER, 1, Mock.tile(12, 4), { chase = 1.5, hp = 999 })
    local p = Isaac.GetPlayer()
    local n, h = 0, 0
    for _ = 1, 90 do
      local move = Reflex.update(p)
      Mock.step(move)
      local home = Reflex.position.home
      if home and Danger.staticAt(home) > 0 then h = h + 1 end
      if Danger.staticAt(p.Position) > 0 then n = n + 1 end
    end
    return n, h
  end)
  check("positioning: no home on creep", homeOnCreep == 0 and onCreep <= 3,
        fmt("home on creep %d updates, Isaac on creep %d of 90", homeOnCreep, onCreep))
end)

-- 76. Live note 5 (the author, 2026-11-26, Larry Jr.: "when he lays poops down, it can block you... a poop is laid down
-- that's not broken, that limits your mobility and increases a risk factor"). Isaac in a pocket closed by poops with
-- one gap, an enemy coming: the home spot is outside the pocket, where the room is.
run("positioning: leaves a pocket closed by poops", function()
  local col, row = withPosition(function()
    Mock.room({
      "WWWWWWWDWWWWWWW",
      "W...p.........W",
      "W...p.........W",
      "W...p.........W",
      "Dpp.p.........D",
      "W.............W",
      "W.............W",
      "W.............W",
      "WWWWWWWDWWWWWWW",
    }, { clear = false, player = Mock.tile(2, 2) })
    Mock.enemy(EntityType.ENTITY_GAPER, 1, Mock.tile(11, 6), { chase = 1.5, hp = 999 })
    Reflex.update(Isaac.GetPlayer())
    local idx = Reflex.position.idx
    local gw = Game():GetRoom():GetGridWidth()
    return idx and (idx % gw) or -1, idx and (idx // gw) or -1
  end)
  check("positioning: leaves a pocket closed by poops", col >= 5 or row >= 5,
        fmt("home column %d, row %d (the pocket is columns 1-3, rows 1-3, its gap at 3,4)", col, row))
end)

-- 77. Live note 5 again: "If you have an escape plan that you know for certain that you won't get hurt in, then focus
-- on laying damage down and getting a good angle" (Larry Jr. "timed out" with no hits). A big open room, one slow
-- enemy: plenty of room everywhere, so the home spot is in line with it, within range.
run("positioning: with a sure way out, a home in line with the target", function()
  local lane, d = withPosition(function()
    Mock.room(nil, { clear = false, player = Mock.tile(2, 7) })
    local e = Mock.enemy(EntityType.ENTITY_GAPER, 1, Mock.tile(10, 3), { chase = 0.5, hp = 999 })
    local p = Isaac.GetPlayer()
    Reflex.update(p)
    local home = Reflex.position.home
    if not home then return false, -1 end
    local rel = home - e.Position
    local inLine = math.abs(rel.X) < 21 or math.abs(rel.Y) < 21
    return inLine and rel:Length() < p.TearRange, rel:Length()
  end)
  check("positioning: with a sure way out, a home in line with the target", lane,
        fmt("home %s, %.0f px from the target", lane and "in line" or "NOT in line", d))
end)

return table.concat(results, "\n")
