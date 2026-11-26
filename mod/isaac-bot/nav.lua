-- Isaac Bot navigation (Stage 3): walking when there's no fight. All judgement comes from rules.lua.
--   1. pick up what's worth having in the room (pathfinding around rocks, pits, spikes)
--   2. explore the floor like a player: only visible doors and the room type each door shows; every
--      reachable room, boss last; keys for locked doors; curse rooms only as a last resort
--   3. bombs, weighed: blast through rocks to walled-in loot; secret rooms guessed from the bot's own map
--      (hidden doors are NOT shown to it); siege when enemies are fully walled in by stone
--   4. after the boss: grab the item, then the trapdoor
-- Also gives the rescue ladder (rescue.lua) its tools: replan, bombNearest, leaveAny, lastResort.
-- Nav.update(player) returns move vector (or nil), shoot direction, and "place a bomb now".

local R = include("rules")
local Danger = include("danger")
local Nav = {}
local DANGER_STEP = 30 -- path cost per half heart a square would cost: routes go around hazards when they can

Nav.status = { goal = "", detail = "" }
Nav.lastResort = false -- set by the rescue ladder: allows rooms marked last_resort (curse rooms)

local graph = {}        -- room safe-index -> { [target safe-index] = true }  (visible doors we've seen)
local skip = {}         -- per room visit: things we gave up on (key -> true)
local deadHop = {}      -- per room visit: neighbouring rooms whose door didn't work out
-- Per FLOOR: doors (room a -> room b) that didn't work out, with what we had then. Without this the bot
-- forgot a locked/blocked door the moment it left the room and walked back to it forever (2026-11-25:
-- 25 minutes bouncing between two rooms on floor 2). Forgiven once keys, bombs or health go up.
local deadEdge = {}
local cameFrom, entries = nil, {} -- loop breaker: recent room entries {frame, new room?}
local goal = nil
local lastPos, stillFrames = nil, 0
local secretTried, secretCount = {}, 0
local secretBlocked = {} -- "cell:room": that wall can't be reached from inside that room (pits/rocks in front)

local function ids(enum, names)
  local t = {}
  for _, n in ipairs(names) do if enum[n] then t[enum[n]] = true end end
  return t
end
local BREAKABLE = ids(GridEntityType, R.bombs.breakable)
local SHOOTABLE = ids(GridEntityType, R.bombs.shoot_not_bomb)
local P = {}
for k, names in pairs(R.pickups) do if type(names) == "table" then P[k] = ids(PickupVariant, names) end end

local SECRET_TYPES = { [7] = true, [8] = true, [29] = true }

local function level() return Game():GetLevel() end

local function safeIndex(idx)
  local d = level():GetRoomByIdx(idx)
  return d and d.SafeGridIndex or idx
end

-- Room type as the DOOR into it reported it (doors always know where they lead). For rooms we haven't been in, the
-- level's room data sometimes comes back as garbage (2026-11-25: types like 1065353216 and -404104361 for three
-- unvisited rooms): no rule matched them, they were never explored, the boss room stayed off the map, and the bot
-- bounced between two rooms every 21 s with "nothing to do".
local doorType = {}
local function sane(t) return type(t) == "number" and t >= 1 and t <= 40 and t == math.floor(t) end
local function roomInfo(idx)
  local d = level():GetRoomByIdx(idx)
  if not d or not d.Data then return nil end
  local t, shape = d.Data.Type, d.Data.Shape
  if not sane(t) then
    -- the door's type if it had a sane one; otherwise the room's data is CORRUPT (2026-11-25: the game itself crashed
    -- loading such a room, "Room -404104361.-1945855990((null))", after a data-dump mod read every floor's room list
    -- mid-run). Never walk into it: no type = not explored. Logged once so the watcher/log shows it.
    t = doorType[d.SafeGridIndex] or doorType[idx]
    if not t then
      if Nav.onNote and not Nav.corruptSeen then Nav.corruptSeen = {} end
      if Nav.onNote and not Nav.corruptSeen[idx] then
        Nav.corruptSeen[idx] = true
        Nav.onNote("room " .. idx .. " has corrupt room data: not going in (the game crashes loading it)")
      end
      return { type = -1, shape = 1, visited = d.VisitedCount, clear = d.Clear, grid = d.GridIndex,
               safe = d.SafeGridIndex }
    end
  end
  if not (type(shape) == "number" and shape >= 1 and shape <= 12) then shape = 1 end
  return { type = t, shape = shape, visited = d.VisitedCount, clear = d.Clear,
           grid = d.GridIndex, safe = d.SafeGridIndex }
end

local function visitWeight(t)
  local r = R.room[t]
  if not r then return nil end
  -- Level 3: risky rooms only when the risk layer says we can afford them (risk.lua Risk.allows)
  if r.when then
    local Risk = IsaacBotRisk
    if not (Risk and Risk.allows and Risk.allows(r.when, Isaac.GetPlayer(0))) then return nil end
  end
  if r.visit then return r.visit end
  if r.last_resort and Nav.lastResort then return 5 end
  return nil
end

---------------------------------------------------------------- floor graph
-- The game fires "new room" BEFORE "new level", so the map is reset here when the floor changes.
local graphFloor = nil
local forgaveSig = nil -- the situation in which written-off doors were last forgiven (once per situation)
local function floorKeyNow()
  local lv = Game():GetLevel()
  return lv:GetStage() .. ":" .. lv:GetStageType() .. ":" .. Game():GetSeeds():GetStartSeed()
end

function Nav.newLevel()
  Nav.newRoom()
end

local lastHere = nil
-- The floor map survives a code reload ("reload" command): kept in a global (all mods share one Lua state).
-- Without this a reload wiped it and the bot stood in a cleared room saying "nothing to do" (2026-11-25).
if IsaacBotNavState then
  graph, graphFloor = IsaacBotNavState.graph or {}, IsaacBotNavState.floor
  deadEdge = IsaacBotNavState.dead or {}
  secretTried, secretBlocked = IsaacBotNavState.secret or {}, IsaacBotNavState.blocked or {}
  secretCount = IsaacBotNavState.secretCount or 0
end
local function keepState()
  IsaacBotNavState = { graph = graph, floor = graphFloor, dead = deadEdge, secret = secretTried,
                       blocked = secretBlocked, secretCount = secretCount }
end

function Nav.newRoom()
  local lv = level()
  local floorKey = lv:GetStage() .. ":" .. lv:GetStageType() .. ":" .. Game():GetSeeds():GetStartSeed()
  if floorKey ~= graphFloor then
    graph, graphFloor, secretTried, secretCount, Nav.lastResort = {}, floorKey, {}, 0, false
    secretBlocked = {}
    deadEdge, entries, lastHere = {}, {}, nil
    doorType = {}
  end
  local desc = lv:GetCurrentRoomDesc()
  cameFrom, lastHere = lastHere, desc.SafeGridIndex
  entries[#entries + 1] = { f = Game():GetFrameCount(), new = desc.VisitedCount <= 1 }
  while #entries > 16 do table.remove(entries, 1) end
  skip, deadHop, goal = {}, {}, nil
  Nav.recordDoors()
  keepState()
end

-- Bouncing: 8+ room entries inside 25 s, none of them into a room we hadn't seen.
local function looping()
  if #entries < 8 then return false end
  local now = Game():GetFrameCount()
  local n = 0
  for k = #entries, 1, -1 do
    local e = entries[k]
    if now - e.f > 30 * 25 then break end
    if e.new then return false end
    n = n + 1
  end
  return n >= 8
end

local function markDead(here, hop, why)
  local p = Isaac.GetPlayer(0)
  deadHop[hop] = true
  deadEdge[here .. ">" .. hop] = { keys = p:GetNumKeys(), bombs = p:GetNumBombs(),
                                   hp = p:GetHearts() + p:GetSoulHearts(), why = why, f = Game():GetFrameCount() }
  Nav.status.detail = "door " .. here .. ">" .. hop .. " no good: " .. (why or "?")
  if Nav.onNote then Nav.onNote(Nav.status.detail) end
end

local function edgeDead(a, b)
  local d = deadEdge[a .. ">" .. b]
  if not d then return false end
  local p = Isaac.GetPlayer(0)
  -- weak evidence (it was busy, e.g. fighting an unkillable statue) expires after a minute; a locked door doesn't
  local soft = d.why ~= "locked, no key" and not tostring(d.why):find("rocks in the way")
  if p:GetNumKeys() > d.keys or p:GetNumBombs() > d.bombs or p:GetHearts() + p:GetSoulHearts() > d.hp
     or (soft and d.f and Game():GetFrameCount() - d.f > 30 * 60) then
    deadEdge[a .. ">" .. b] = nil
    return false
  end
  return true
end

-- A door the player can actually see. Secret-room doors stay hidden until something blows them open;
-- the game tells mods where they are anyway, so we ignore them while they're shut (no peeking).
local function visibleDoor(d)
  if not d or not d.TargetRoomIndex or d.TargetRoomIndex < 0 then return false end
  if SECRET_TYPES[d.TargetRoomType] then
    -- a hidden secret door still reports "open"; what gives it away is that it's still solid wall
    if not d:IsOpen() then return false end
    local col = Game():GetRoom():GetGridCollision(d:GetGridIndex())
    if col == GridCollisionClass.COLLISION_WALL or col == GridCollisionClass.COLLISION_SOLID then return false end
  end
  -- From INSIDE a secret room, walls toward the neighbours still count as doors in the game's data though they're
  -- solid until bombed. Only the open ones are real (the author, 2026-11-25: "just leave the way you came in"; it kept
  -- walking into unbombed walls until the stuck ladder threw it out).
  local here = level():GetCurrentRoomDesc()
  if here and here.Data and SECRET_TYPES[here.Data.Type] then
    if not d:IsOpen() then return false end
    local col = Game():GetRoom():GetGridCollision(d:GetGridIndex())
    if col == GridCollisionClass.COLLISION_WALL or col == GridCollisionClass.COLLISION_SOLID then return false end
  end
  return true
end

function Nav.recordDoors()
  local room = Game():GetRoom()
  local here = level():GetCurrentRoomDesc().SafeGridIndex
  graph[here] = graph[here] or {}
  for slot = 0, 7 do
    local d = room:GetDoor(slot)
    if visibleDoor(d) then
      local there = safeIndex(d.TargetRoomIndex)
      if sane(d.TargetRoomType) then doorType[there] = d.TargetRoomType end
      graph[here][there] = true
      graph[there] = graph[there] or {}
      graph[there][here] = true
    end
  end
end

-- Breadth-first over doors we've seen, only walking THROUGH rooms we've been in.
-- `want(room, info, dist)` -> score or nil (lowest wins). Returns the first hop and the destination.
local function search(here, want)
  local queue, from, dist = { here }, { [here] = here }, { [here] = 0 }
  local best, bestScore = nil, math.huge
  local head = 1
  while queue[head] do
    local cur = queue[head]; head = head + 1
    for nb in pairs(graph[cur] or {}) do
      if not from[nb] and not (cur == here and deadHop[nb]) and not edgeDead(cur, nb) then
        local info = roomInfo(nb)
        if info then
          from[nb], dist[nb] = cur, dist[cur] + 1
          local s = want(nb, info, dist[nb])
          if s and s < bestScore then best, bestScore = nb, s end
          if info.visited > 0 then queue[#queue + 1] = nb end
        end
      end
    end
  end
  if not best then return nil end
  local hop = best
  while from[hop] ~= here do hop = from[hop] end
  return hop, best
end

local function nextHop(here)
  local hop = search(here, function(_, info, d)
    local w = visitWeight(info.type)
    if info.visited == 0 and not (R.room[info.type] or {}).boss and w then return w * 2 + d end
  end)
  if hop then return hop, "explore" end
  hop = search(here, function(_, info, d)
    if (R.room[info.type] or {}).boss and (info.visited == 0 or not info.clear) then return d end
  end)
  if hop then return hop, "boss" end
  -- boss beaten but we walked out before the trapdoor (2026-11-25: "nothing to do" in a cleared floor): go back
  if level():GetCurrentRoomDesc().Data and not (R.room[level():GetCurrentRoomDesc().Data.Type] or {}).boss then
    hop = search(here, function(_, info, d)
      if (R.room[info.type] or {}).boss and info.clear then return d end
    end)
    if hop then return hop, "boss" end
  end
  return nil
end

local function routeTo(here, target)
  return search(here, function(nb, _, d) if nb == target then return d end end)
end

---------------------------------------------------------------- secret rooms (the bot's own guess)
local SHAPE_CELLS = { [1] = { 0 }, [2] = { 0 }, [3] = { 0 }, [4] = { 0, 13 }, [5] = { 0, 13 }, [6] = { 0, 1 },
                      [7] = { 0, 1 }, [8] = { 0, 1, 13, 14 }, [9] = { 1, 13, 14 }, [10] = { 0, 13, 14 },
                      [11] = { 0, 1, 14 }, [12] = { 0, 1, 13 } }

local function secretGuess()
  local occupied, bossCells, known = {}, {}, {}
  for s in pairs(graph) do
    local info = roomInfo(s)
    if info then
      known[s] = info
      for _, off in ipairs(SHAPE_CELLS[info.shape] or { 0 }) do
        occupied[info.grid + off] = s
        if (R.room[info.type] or {}).boss then bossCells[info.grid + off] = true end
      end
    end
  end
  local best = nil
  for c = 0, 168 do
    if not occupied[c] and not secretTried[c] then
      local x = c % 13
      local around, nearBoss, from = {}, false, nil
      for _, nb in ipairs({ { -1, 2 }, { 1, 0 }, { -13, 3 }, { 13, 1 } }) do -- neighbour, wall slot facing c
        local n = c + nb[1]
        if n >= 0 and n <= 168 and math.abs(n % 13 - x) <= 1 and occupied[n] then
          local s = occupied[n]
          around[s] = true
          if bossCells[n] then nearBoss = true end
          local info = known[s]
          if info and info.shape == 1 and info.visited > 0 and not (R.room[info.type] or {}).boss
             and not SECRET_TYPES[info.type] and not secretBlocked[c .. ":" .. s] then
            from = from or { room = s, slot = nb[2] }
          end
        end
      end
      local score = 0
      for _ in pairs(around) do score = score + 1 end
      if not nearBoss and from and score >= R.secret.min_neighbours and (not best or score > best.score) then
        best = { cell = c, score = score, room = from.room, slot = from.slot }
      end
    end
  end
  return best
end

local function secretWorthIt(p, guess)
  if not guess or secretCount >= R.secret.tries_per_floor then return false end
  local bombs = p:GetNumBombs()
  if guess.score >= R.secret.strong_neighbours then return bombs >= R.secret.bombs_if_strong end
  return bombs >= R.secret.bombs_if_weak
end

---------------------------------------------------------------- pathfinding inside a room
-- Square cost for paths. Hazards come from the shared danger map (spikes, creep, fires, unkillable leftovers):
-- passable but expensive, so the route goes around them whenever it can. Whether a hurting route is WORTH it
-- is decided separately (Danger.cost) once the route is known.
-- Tile costs are worked out ONCE per update and reused (asking the game about every tile for every search, many
-- searches per update, made big rooms run at half speed - the author, 2026-11-25). nil = can't walk there.
local tileCache = { frame = -1 }
local function baseCost(room, i, canFly, allowRocks)
  local f = Game():GetFrameCount()
  if tileCache.frame ~= f then tileCache = { frame = f } end
  local key = (canFly and 2 or 0) + (allowRocks and 1 or 0)
  local t = tileCache[key]
  if not t then t = {}; tileCache[key] = t end
  local v = t[i]
  if v == nil then
    local hurt = Danger.staticCell(i) * DANGER_STEP + Danger.cautionCell(i) * 3 -- TNT: mild preference only
    local ge = room:GetGridEntity(i)
    local col = room:GetGridCollision(i)
    local gt = ge and ge:GetType()
    if gt == GridEntityType.GRID_DOOR then v = false -- never brush other doors
    elseif col == GridCollisionClass.COLLISION_NONE then v = (gt == GridEntityType.GRID_SPIDERWEB and 4 or 1) + hurt
    elseif col == GridCollisionClass.COLLISION_PIT and canFly then v = 1 + hurt
    elseif allowRocks and gt and SHOOTABLE[gt] then v = 4 -- poop: just shoot it
    elseif allowRocks and gt and BREAKABLE[gt] then v = 12 -- rock: "could blow this up"
    else v = false end
    t[i] = v
  end
  return v or nil
end

local function cellCost(room, i, goalIdx, canFly, allowRocks)
  if i == goalIdx then
    return 1 + Danger.staticCell(i) * DANGER_STEP + Danger.cautionCell(i) * 3
  end
  return baseCost(room, i, canFly, allowRocks)
end

-- min-heap of { cost, cell } (the old search rescanned the whole open list for every step)
local function hpush(h, d, i)
  local n = #h + 1
  h[n] = { d, i }
  while n > 1 do
    local p = n // 2
    if h[p][1] <= h[n][1] then break end
    h[p], h[n] = h[n], h[p]
    n = p
  end
end
local function hpop(h)
  local top = h[1]
  local last = h[#h]
  h[#h] = nil
  if #h > 0 then
    h[1] = last
    local n, size = 1, #h
    while true do
      local l, r, m = n * 2, n * 2 + 1, n
      if l <= size and h[l][1] < h[m][1] then m = l end
      if r <= size and h[r][1] < h[m][1] then m = r end
      if m == n then break end
      h[m], h[n] = h[n], h[m]
      n = m
    end
  end
  return top
end

local pathMemo = { frame = -1 }
local function findPath(room, startIdx, goalIdx, canFly, allowRocks)
  local f = Game():GetFrameCount()
  if pathMemo.frame ~= f then pathMemo = { frame = f } end
  local key = startIdx .. ">" .. goalIdx .. (canFly and "f" or "") .. (allowRocks and "r" or "")
  local memo = pathMemo[key]
  if memo ~= nil then return memo or nil end
  Danger.build(Isaac.GetPlayer(0)) -- once per update; spikes, creep, fires, leftovers
  local w, size = room:GetGridWidth(), room:GetGridSize()
  local dist, prev, done = { [startIdx] = 0 }, {}, {}
  local heap = {}
  hpush(heap, 0, startIdx)
  while #heap > 0 do
    local top = hpop(heap)
    local bd, cur = top[1], top[2]
    if not done[cur] then
      if cur == goalIdx then break end
      done[cur] = true
      local cx, cy = cur % w, cur // w
      for dy = -1, 1 do
        for dx = -1, 1 do
          if dx ~= 0 or dy ~= 0 then
            local nx, ny = cx + dx, cy + dy
            local ni = nx + ny * w
            if nx >= 0 and nx < w and ni >= 0 and ni < size and not done[ni] then
              local c = cellCost(room, ni, goalIdx, canFly, allowRocks)
              if c and dx ~= 0 and dy ~= 0 then -- no cutting rock corners
                if not cellCost(room, cx + dx + cy * w, goalIdx, canFly, false)
                   or not cellCost(room, cx + (cy + dy) * w, goalIdx, canFly, false) then c = nil end
                if c then c = c * 1.41 end
              end
              if c then
                local nd = bd + c
                if not dist[ni] or nd < dist[ni] then
                  dist[ni], prev[ni] = nd, cur
                  hpush(heap, nd, ni)
                end
              end
            end
          end
        end
      end
    end
  end
  if not dist[goalIdx] then pathMemo[key] = false; return nil end
  local path, cur = {}, goalIdx
  while cur and cur ~= startIdx do table.insert(path, 1, cur); cur = prev[cur] end
  pathMemo[key] = path
  return path
end

-- Where to stand to open the way from startIdx to goalIdx: the square just before the first obstacle.
-- Returns stand square, obstacle square, and whether it's poop (shoot it) rather than rock (bomb it).
local function bombSpot(room, startIdx, goalIdx, canFly)
  local path = findPath(room, startIdx, goalIdx, canFly, true)
  if not path then return nil end
  local before = startIdx
  for _, i in ipairs(path) do
    local ge = room:GetGridEntity(i)
    if ge and BREAKABLE[ge:GetType()] and ge.CollisionClass ~= GridCollisionClass.COLLISION_NONE then
      return before, i, SHOOTABLE[ge:GetType()] or false
    end
    before = i
  end
  return nil
end

---------------------------------------------------------------- what's worth picking up (rules.lua)
-- How many points a pickup is worth to us right now (0 = don't want it). Values live in rules.lua (R.value).
local V = R.value
local function value(p, e)
  local pk = e:ToPickup()
  if not pk then return 0 end
  -- things with a price (shop coins, devil-deal hearts): Level 3 decides (strategy.lua buyValue, rules R.deals/R.shop)
  if pk.Price ~= 0 or pk:IsShopItem() then
    local St = IsaacBotStrategy
    if not (St and R.buy) then return 0 end
    local ok, val = pcall(St.buyValue, p, pk, V, R)
    return ok and val or 0
  end
  local v, s = e.Variant, e.SubType
  if P.never[v] then return 0 end
  if v == PickupVariant.PICKUP_HEART then
    if s == HeartSubType.HEART_FULL or s == HeartSubType.HEART_DOUBLEPACK or s == HeartSubType.HEART_SCARED then
      return p:CanPickRedHearts() and V.heart.red_full or 0
    end
    if s == HeartSubType.HEART_HALF then return p:CanPickRedHearts() and V.heart.red_half or 0 end
    if s == HeartSubType.HEART_SOUL then return p:CanPickSoulHearts() and V.heart.soul or 0 end
    if s == HeartSubType.HEART_HALF_SOUL then return p:CanPickSoulHearts() and V.heart.half_soul or 0 end
    if s == HeartSubType.HEART_BLACK then return p:CanPickBlackHearts() and V.heart.black or 0 end
    if s == HeartSubType.HEART_ETERNAL then return V.heart.eternal end
    if s == HeartSubType.HEART_GOLDEN then return V.heart.gold end
    if s == HeartSubType.HEART_BONE then return V.heart.bone end
    if s == HeartSubType.HEART_ROTTEN then return p:CanPickRedHearts() and V.heart.rotten or 0 end
    return 3
  end
  if v == PickupVariant.PICKUP_COIN then return V.coin[s] or 1 end
  if v == PickupVariant.PICKUP_KEY then return V.key[s] or 4 end
  if v == PickupVariant.PICKUP_BOMB then return V.bomb[s] or 0 end -- troll bombs (3,5,6) aren't listed: 0
  if v == PickupVariant.PICKUP_LIL_BATTERY then return V.battery end
  if v == PickupVariant.PICKUP_GRAB_BAG then return V.grab_bag end
  -- Pills and cards share one pocket slot: with it full, walking over one swaps it (the old loop bug)
  if P.pocket_if_empty[v] then return (p:GetPill(0) == 0 and p:GetCard(0) == 0) and V.pill_card or 0 end
  if P.trinket_if_empty[v] then return p:GetTrinket(0) == 0 and V.trinket or 0 end
  if P.chests[v] then return s ~= 0 and V.chest or 0 end
  if P.key_chests[v] then return (s ~= 0 and p:GetNumKeys() > 0) and V.locked_chest or 0 end
  if v == PickupVariant.PICKUP_COLLECTIBLE then
    if s == 0 or pk.Touched then return 0 end
    -- Level 3: worth to THIS run (rating for this bot + fixes the build's weaknesses); quality if unrated
    local St = IsaacBotStrategy
    local val = St and St.itemValue(p, s, V)
    if not val then
      local cfg = Isaac.GetItemConfig():GetCollectible(s)
      val = V.item_base + V.item_per_quality * ((cfg and cfg.Quality) or 1)
    end
    -- choice pedestals (take one, the others vanish): only the best of the group is wanted
    local okO, group = pcall(function() return pk.OptionsPickupIndex end)
    if val > 0 and okO and group and group ~= 0 then
      for _, o in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE)) do
        local op = o:ToPickup()
        if op and o.SubType ~= 0 and GetPtrHash(o) ~= GetPtrHash(e) and op.OptionsPickupIndex == group then
          local ov = (St and St.itemValue(p, o.SubType, V)) or 0
          if ov > val or (ov == val and GetPtrHash(o) < GetPtrHash(e)) then return 0 end
        end
      end
    end
    return val
  end
  return 0
end
local function wanted(p, e) return value(p, e) > 0 end

---------------------------------------------------------------- choosing a goal
local function doorGoal(room, p, hop, kind)
  local here = level():GetCurrentRoomDesc().SafeGridIndex
  local why = "no visible door"
  for slot = 0, 7 do
    local d = room:GetDoor(slot)
    if visibleDoor(d) and safeIndex(d.TargetRoomIndex) == hop and not skip["d" .. slot] then
      if d:IsLocked() and p:GetNumKeys() == 0 then
        skip["d" .. slot] = true
        why = "locked, no key"
      else
        -- the route to the door must not be lethal (spikes in front of a door at half a heart, say)
        local start = room:GetGridIndex(p.Position)
        local path = findPath(room, start, d:GetGridIndex(), p.CanFly, false)
        local dmg = Danger.pathDamage(path)
        if path and Danger.cost(p, dmg) < math.huge then
          local pos = room:GetDoorSlotPosition(slot)
          local out = (pos - room:GetCenterPos()):Normalized()
          return { kind = kind .. (dmg > 0 and (" (route costs " .. dmg .. " half hearts)") or ""), key = "d" .. slot,
                   hop = hop, idx = d:GetGridIndex(), pos = pos + out * 40, roomType = d.TargetRoomType }
        end
        if not path then
          -- walled off inside this room: poop -> shoot it; rocks -> bomb, if the trip is worth a bomb
          local stand, obstacle, isPoop = bombSpot(room, start, d:GetGridIndex(), p.CanFly)
          if stand and isPoop then
            return { kind = "shoot poop to the door (" .. kind .. ")", key = "d" .. slot .. "s" .. obstacle,
                     shootAt = true, target = obstacle, idx = stand, pos = room:GetGridPosition(stand) }
          end
          local need = kind == "to boss" and R.bombs.door_boss or R.bombs.door_explore
          if stand and p:GetNumBombs() >= need and not skip["d" .. slot .. "b"] then
            return { kind = "bomb rocks to the door (" .. kind .. ")", key = "d" .. slot .. "b", bomb = true,
                     idx = stand, pos = room:GetGridPosition(stand) }
          end
          why = stand and ("rocks in the way, " .. p:GetNumBombs() .. " bombs") or "no way to the door"
        else
          why = "route would kill (" .. dmg .. " half hearts)"
        end
        skip["d" .. slot] = true
      end
    end
  end
  markDead(here, hop, why) -- no usable door to it from here: try the next best room instead
  return nil
end

local function chooseGoal(p, room)
  local start = room:GetGridIndex(p.Position)
  -- 1. pickups, nearest first; walled in -> maybe bomb a way through
  local list = {}
  for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP)) do
    local key = "p" .. GetPtrHash(e)
    if not skip[key] and wanted(p, e) then list[#list + 1] = { e = e, d = (e.Position - p.Position):Length(), key = key } end
  end
  table.sort(list, function(a, b) return a.d < b.d end)
  while #list > 10 do table.remove(list) end
  -- Worth it? value minus the damage there AND back, priced at current health (Danger.cost; lethal = never).
  -- The author, 2026-11-25: it died walking over spikes for a coin. That can't pass this test any more.
  local best, bestWorth, unreachable = nil, 0, {}
  for _, it in ipairs(list) do
    local e = it.e
    local idx = room:GetGridIndex(e.Position)
    local name = (e.Variant == PickupVariant.PICKUP_COLLECTIBLE) and "item" or ("pickup " .. e.Variant .. "." .. e.SubType)
    local path = findPath(room, start, idx, p.CanFly, false)
    if path then
      local val = value(p, e)
      local dmg = Danger.pathDamage(path) * 2
      -- worth it = value vs. the damage risk on the way; distance only decides the ORDER (2026-11-25: with
      -- distance in the test too, every penny more than ~100 px away "wasn't worth it" - it skipped a secret
      -- room full of coins)
      local net = val - Danger.cost(p, dmg)
      -- The way there hurts (spikes), but a way through breakable rock doesn't: a bomb is cheaper than a hit. (The
      -- author, 2026-11-25: it walked over spikes for an item on the first floor with bombs in its pocket. "That
      -- would be a good use of bombs... try not to take damage the first floor.")
      if dmg > 0 then
        local need = (e.Variant == PickupVariant.PICKUP_COLLECTIBLE) and R.bombs.loot_major
                  or (e.Variant == PickupVariant.PICKUP_LOCKEDCHEST) and R.bombs.loot_key_chest or R.bombs.loot_minor
        local rockPath = findPath(room, start, idx, p.CanFly, true)
        if p:GetNumBombs() >= need and rockPath and Danger.pathDamage(rockPath) == 0
           and Danger.cost(p, dmg) > (V.bomb[1] or 3) * 2 and not skip[it.key .. "b"] then
          local stand, _, isPoop = bombSpot(room, start, idx, p.CanFly)
          if stand and not isPoop then
            return { kind = "bomb rocks to " .. name .. " (instead of " .. dmg .. " half hearts of spikes)",
                     key = it.key .. "b", bomb = true, idx = stand, pos = room:GetGridPosition(stand) }
          end
        end
      end
      local worth = net > 0 and (net + 1000 - it.d * 0.01) or net
      if worth > bestWorth then
        best = { kind = name .. (dmg > 0 and (" (worth " .. val .. ", risking " .. dmg .. " half hearts)") or ""),
                 key = it.key, entity = e, idx = idx }
        bestWorth = worth
      elseif worth <= 0 then
        skip[it.key] = true
        Nav.status.detail = "skipped " .. name .. ": worth " .. val .. ", not " .. dmg .. " half hearts at this health"
        if Nav.onNote then Nav.onNote(Nav.status.detail) end
      end
    else
      unreachable[#unreachable + 1] = it
    end
  end
  if best then return best end
  for _, it in ipairs(unreachable) do
    local e = it.e
    local idx = room:GetGridIndex(e.Position)
    local name = (e.Variant == PickupVariant.PICKUP_COLLECTIBLE) and "item" or ("pickup " .. e.Variant .. "." .. e.SubType)
    local stand, obstacle, isPoop = bombSpot(room, start, idx, p.CanFly)
    if stand and isPoop then
      -- only poop in the way: walk up and shoot it, no bomb
      return { kind = "shoot poop to " .. name, key = it.key .. "s" .. obstacle, shootAt = true, target = obstacle,
               idx = stand, pos = room:GetGridPosition(stand) }
    end
    local need = (e.Variant == PickupVariant.PICKUP_COLLECTIBLE) and R.bombs.loot_major
              or (e.Variant == PickupVariant.PICKUP_LOCKEDCHEST) and R.bombs.loot_key_chest
              or R.bombs.loot_minor
    if stand and p:GetNumBombs() >= need then
      return { kind = "bomb rocks to " .. name, key = it.key .. "b", bomb = true, idx = stand,
               pos = room:GetGridPosition(stand) }
    end
    skip[it.key] = true
    if Nav.onNote then
      Nav.onNote("skipped " .. name .. ": " .. (stand and ("walled in, " .. p:GetNumBombs() .. " bombs (needs " .. need .. ")")
        or "no way to it"))
    end
  end
  -- 2. after the boss: the trapdoor
  local desc = level():GetCurrentRoomDesc()
  if desc.Data and (R.room[desc.Data.Type] or {}).boss then
    -- Level 3: a devil/angel door opened after the fight -> look inside before the trapdoor (strategy.lua decides
    -- what to take; the bot comes back here for the trapdoor afterwards)
    for slot = 0, 7 do
      local d = room:GetDoor(slot)
      if visibleDoor(d) and d:IsOpen() and (R.room[d.TargetRoomType] or {}).deal then
        local info = roomInfo(d.TargetRoomIndex)
        if not (info and info.visited > 0) and not skip["deal" .. slot] then
          local g = doorGoal(room, p, safeIndex(d.TargetRoomIndex), "deal room")
          if g then g.key = "deal" .. slot; return g end
          skip["deal" .. slot] = true
        end
      end
    end
    for i = 0, room:GetGridSize() - 1 do
      local ge = room:GetGridEntity(i)
      if ge and ge:GetType() == GridEntityType.GRID_TRAPDOOR and not skip["trap"] then
        return { kind = "trapdoor", key = "trap", idx = i, pos = room:GetGridPosition(i) }
      end
    end
  end
  -- 3. explore (trying the next-best room when a door doesn't work out); before the boss, weigh a secret room
  local here = desc.SafeGridIndex
  for _ = 1, 6 do
    local hop, why = nextHop(here)
    if why ~= "explore" then
      local guess = secretGuess()
      if secretWorthIt(p, guess) then
        if guess.room == here then
          local slotPos = room:GetDoorSlotPosition(guess.slot)
          local inward = (room:GetCenterPos() - slotPos):Normalized()
          local stand = slotPos + inward * 38
          local standIdx = room:GetGridIndex(stand)
          -- the spot in front of that wall must be floor we can walk to (2026-11-25: pits in front of the wall,
          -- it re-picked the same unreachable guess for 15 minutes)
          if room:GetGridCollision(standIdx) == GridCollisionClass.COLLISION_NONE
             and findPath(room, start, standIdx, p.CanFly, false) then
            return { kind = "bomb wall: secret room? (" .. guess.score .. " rooms around)", key = "s" .. guess.cell,
                     bomb = true, idx = standIdx, pos = stand, secret = guess }
          end
          secretBlocked[guess.cell .. ":" .. here] = true
          if Nav.onNote then Nav.onNote("secret wall " .. guess.cell .. " can't be reached from room " .. here) end
          guess = nil
        end
        local h = guess and routeTo(here, guess.room)
        if h then
          local g = doorGoal(room, p, h, "to a secret-room spot")
          if g then return g end
        end
      end
    end
    if not hop and next(deadEdge) then
      -- nothing left to do, but doors are written off: forgive the WEAKLY written-off ones and look again (2026-11-25:
      -- both exits were written off while it fought an unkillable statue). Never a locked door while the key count is
      -- unchanged, and only once per situation (keys/bombs/health): forgiving everything every time brought the
      -- two-room bounce back (offline test K1: 22 room changes and 5,000 log lines a minute).
      local pl = Isaac.GetPlayer(0)
      local sig = floorKeyNow() .. "|" .. pl:GetNumKeys() .. "|" .. pl:GetNumBombs() .. "|" .. (pl:GetHearts() + pl:GetSoulHearts())
      if forgaveSig ~= sig then
        forgaveSig = sig
        local n = 0
        for k, d in pairs(deadEdge) do
          if d.why ~= "locked, no key" and not tostring(d.why):find("rocks in the way") then deadEdge[k] = nil; n = n + 1 end
        end
        if n > 0 then
          deadHop = {}
          keepState()
          if Nav.onNote then Nav.onNote("nothing to do: forgave " .. n .. " weakly written-off door(s)") end
          hop, why = nextHop(here)
        end
      end
    end
    if not hop then return nil end
    if why == "explore" and hop == cameFrom and looping() then
      -- bouncing between rooms we've seen: don't step straight back, find another way on
      markDead(here, hop, "bouncing back and forth")
      hop, why = nextHop(here)
      if not hop then return nil end
    end
    local g = doorGoal(room, p, hop, why == "boss" and "to boss" or "next room")
    if g then return g end
  end
  return nil
end

---------------------------------------------------------------- steering + bombs
local function steer(room, player, goalIdx, target)
  local start = room:GetGridIndex(player.Position)
  local path = findPath(room, start, goalIdx, player.CanFly, false)
  if not path then return nil end
  local aim = target
  if #path > 1 then aim = room:GetGridPosition(path[1]) end
  if #path >= 1 and (room:GetGridPosition(path[1]) - player.Position):Length() < 18 and path[2] then
    aim = room:GetGridPosition(path[2])
  end
  if #path <= 1 then aim = target end
  -- where the walker is heading, for the reflexes: when they take over to dodge something (an Eternal Fly in a
  -- cleared room) they keep walking this way instead of stopping
  IsaacBotNavAim = { pos = aim, final = target, f = Game():GetFrameCount() }
  local move = aim - player.Position
  if move:Length() < 1 then move = target - player.Position end
  return move
end

-- Walk next to a poop and shoot it until it breaks (poop is never bombed). Returns move, shoot, finished.
local function driveShoot(room, player, g)
  local ge = room:GetGridEntity(g.target)
  if not ge or ge.CollisionClass == GridCollisionClass.COLLISION_NONE then return nil, nil, true end -- broken
  local d = (g.pos - player.Position):Length()
  if d > 14 then
    local move = steer(room, player, g.idx, g.pos)
    if not move then return nil, nil, true end
    return move, nil, false
  end
  local to = room:GetGridPosition(g.target) - player.Position
  local shoot
  if math.abs(to.X) >= math.abs(to.Y) then shoot = to.X > 0 and "right" or "left"
  else shoot = to.Y > 0 and "down" or "up" end
  return Vector(0, 0), shoot, false
end

-- Walk to the bomb spot, drop the bomb, then let the reflexes run from it (bombs count as danger).
-- Returns move, bombNow, finished
local function driveBomb(room, player, g, f)
  if g.placed then
    if f - g.placed < 80 then return nil, false, false end
    if g.secret then
      secretTried[g.secret.cell] = true
      secretCount = secretCount + 1
      keepState()
      Nav.recordDoors() -- the blown-open door is visible now if we guessed right
      local d = room:GetDoor(g.secret.slot)
      Nav.status.detail = (d and d:IsOpen()) and "secret room found!" or "no secret room there"
    end
    return nil, false, true
  end
  -- bomb already asked for: hands OFF (never stand still next to it - it blew itself up doing that);
  -- the reflexes see the live bomb and run from it
  if g.asked then
    if player:GetNumBombs() < g.bombsBefore then g.placed = g.asked; return nil, false, false end
    if f - g.asked > 20 then g.asked = nil end -- didn't drop: walk back and try again
    return nil, false, false
  end
  local d = (g.pos - player.Position):Length()
  if d < 14 then
    g.asked, g.bombsBefore = f, player:GetNumBombs()
    -- the walker's heading was THIS spot: clear it, or the dodge code "keeps walking there" into its own blast
    -- (2026-11-25: it bombed itself at a secret wall)
    IsaacBotNavAim = nil
    return Vector(0, 0), true, false -- one frame: drop it
  end
  local move = steer(room, player, g.idx, g.pos)
  if not move then
    if g.secret then secretBlocked[g.secret.cell .. ":" .. g.secret.room] = true end
    return nil, false, true
  end
  return move, false, false
end

local function norm(v) return v and (v:Length() > 0 and v:Normalized() or v) end

-- A goal square we can't walk to (2026-11-25: a trap-room button boxed in by rocks and TNT barrels; the bot walked
-- into the wall for minutes). Work out how to open the way: poop in the way -> shoot it; a rock in the way with a
-- TNT barrel next to it -> shoot the barrel from a safe spot in line with it (its blast breaks the rocks, free);
-- otherwise -> bomb the first rock. Returns a shootAt/bomb goal for driveShoot/driveBomb, or nil.
local TNT_SAFE = 110 -- stand at least this far from every intact barrel (blast ~85, chains)
local function openWay(room, player, goalIdx)
  local start = room:GetGridIndex(player.Position)
  local stand, obstacle, isPoop = bombSpot(room, start, goalIdx, player.CanFly)
  if not stand then return nil end
  if isPoop then
    return { kind = "shoot poop in the way", key = "ow" .. obstacle, shootAt = true, target = obstacle,
             idx = stand, pos = room:GetGridPosition(stand) }
  end
  -- intact barrels, and the rocks on the rock-allowed path
  local w, size = room:GetGridWidth(), room:GetGridSize()
  local tnts = {}
  for i = 0, size - 1 do
    local ge = room:GetGridEntity(i)
    if ge and ge:GetType() == GridEntityType.GRID_TNT and ge.CollisionClass ~= GridCollisionClass.COLLISION_NONE then
      tnts[#tnts + 1] = i
    end
  end
  local rocks = {}
  for _, i in ipairs(findPath(room, start, goalIdx, player.CanFly, true) or {}) do
    local ge = room:GetGridEntity(i)
    if ge and BREAKABLE[ge:GetType()] and ge.CollisionClass ~= GridCollisionClass.COLLISION_NONE then rocks[#rocks + 1] = i end
  end
  local function safeFromTnt(pos)
    for _, t in ipairs(tnts) do if (room:GetGridPosition(t) - pos):Length() < TNT_SAFE then return false end end
    return true
  end
  local best, bestLen = nil, math.huge
  for _, t in ipairs(tnts) do
    local tpos = room:GetGridPosition(t)
    local nearRock = false
    for _, r in ipairs(rocks) do if (room:GetGridPosition(r) - tpos):Length() < 60 then nearRock = true; break end end
    if nearRock then
      local tx, ty = t % w, t // w
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local clear = true
        for k = 1, 7 do
          local x, y = tx + d[1] * k, ty + d[2] * k
          local ci = x + y * w
          if x < 0 or x >= w or ci < 0 or ci >= size then break end
          local col = room:GetGridCollision(ci)
          if col ~= GridCollisionClass.COLLISION_NONE and col ~= GridCollisionClass.COLLISION_PIT then clear = false end
          if not clear then break end -- tears stop at the first rock (they fly over pits)
          if k >= 3 and col == GridCollisionClass.COLLISION_NONE and safeFromTnt(room:GetGridPosition(ci)) then
            local path = (ci == start) and {} or findPath(room, start, ci, player.CanFly, false)
            if path and #path < bestLen then best, bestLen = { t = t, stand = ci }, #path end
          end
        end
      end
    end
  end
  if best then
    return { kind = "shoot TNT to open the way", key = "owt" .. best.t, shootAt = true, target = best.t,
             idx = best.stand, pos = room:GetGridPosition(best.stand) }
  end
  if player:GetNumBombs() >= 1 then
    return { kind = "bomb the rocks in the way", key = "owb" .. obstacle, bomb = true, idx = stand,
             pos = room:GetGridPosition(stand) }
  end
  return nil
end
local plateWay = nil -- the current "open the way to the button" job

---------------------------------------------------------------- per update
function Nav.update(player)
  local room = Game():GetRoom()
  local f = Game():GetFrameCount()
  -- Pressure plates (the author, 2026-11-25: a "trap room" with no enemies stays shut until the button is pressed;
  -- the bot just waited). No enemies left + an unpressed plate = walk onto it. Covers reward plates too.
  if Isaac.CountEnemies() == 0 then
    local plateIdx = nil
    for i = 0, room:GetGridSize() - 1 do
      local ge = room:GetGridEntity(i)
      if ge and ge:GetType() == GridEntityType.GRID_PRESSURE_PLATE and ge.State < 3 then plateIdx = i; break end
    end
    if plateIdx then
      Nav.status.goal = "pressing the button"
      local pos = room:GetGridPosition(plateIdx)
      local move = steer(room, player, plateIdx, pos)
      local here = level():GetCurrentRoomDesc().SafeGridIndex
      if move then
        plateWay = nil
        if move:Length() > 0.5 then return norm(move), nil, false end
        return norm(pos - player.Position), nil, false
      end
      -- walled in: open the way (shoot poop / a TNT barrel, or bomb), a few tries per room
      if plateWay and (plateWay.room ~= here or plateWay.done) then plateWay = nil end
      if not plateWay or not plateWay.job then
        local tries = (plateWay and plateWay.room == here) and plateWay.tries or 0
        local job = (tries < 4) and openWay(room, player, plateIdx) or nil
        if job then job.started = f end
        plateWay = { room = here, job = job, tries = tries + 1 }
        if job and Nav.onNote then Nav.onNote("button walled in: " .. job.kind) end
      end
      local job = plateWay.job
      if job then
        Nav.status.goal = "button walled in: " .. job.kind
        if f - job.started > 30 * 15 then plateWay.job = nil; return nil end -- took too long: think again
        if job.bomb then
          local m, bombNow, finished = driveBomb(room, player, job, f)
          if finished then plateWay.job = nil end
          return norm(m), nil, bombNow
        end
        local m, shoot, finished = driveShoot(room, player, job)
        if finished then plateWay.job = nil; return nil end
        return norm(m), shoot, false
      end
      return norm(pos - player.Position), nil, false
    end
  end
  if not room:IsClear() then Nav.status.goal = "waiting (room not clear)"; return nil end

  if goal and goal.entity and (not goal.entity:Exists() or not wanted(player, goal.entity)) then goal = nil end
  if player:IsHoldingItem() then Nav.status.goal = "holding up an item"; return nil end
  if not goal then
    goal = chooseGoal(player, room)
    if goal then goal.started = f end
  end
  if not goal then Nav.status.goal = "nothing to do"; return nil end

  if f - goal.started > 30 * (goal.bomb and 15 or 12) then
    skip[goal.key] = true
    if goal.hop then markDead(level():GetCurrentRoomDesc().SafeGridIndex, goal.hop, "walking there failed") end
    goal = nil
    return nil
  end

  Nav.status.goal = goal.kind .. ((goal.roomType and (" (type " .. goal.roomType .. ")")) or "")

  -- A trapdoor that opened UNDER Isaac stays shut until he steps off it (2026-11-25: the bot stood on one
  -- forever). On it for a second without falling: walk off for a moment, then come back.
  if goal.key == "trap" then
    if goal.offUntil and f < goal.offUntil then
      local away = player.Position - goal.pos
      if away:Length() < 1 then away = Vector(1, 0) end
      return away:Normalized(), nil, false
    end
    if (goal.pos - player.Position):Length() < 24 then goal.onFor = (goal.onFor or 0) + 1 else goal.onFor = 0 end
    if goal.onFor > 30 then goal.offUntil, goal.onFor, goal.started = f + 25, 0, f end
  end
  if goal.bomb then
    local move, bombNow, finished = driveBomb(room, player, goal, f)
    if finished then skip[goal.key] = true; goal = nil end
    return norm(move), nil, bombNow
  end
  if goal.shootAt then
    local move, shoot, finished = driveShoot(room, player, goal)
    if finished then goal = nil; return nil end -- path is open now: next update picks the loot again
    return norm(move), shoot, false
  end

  local target = goal.pos or (goal.entity and goal.entity.Position)
  local goalIdx = goal.entity and room:GetGridIndex(goal.entity.Position) or goal.idx
  local move = steer(room, player, goalIdx, target)
  if not move then
    skip[goal.key] = true
    if goal.hop then markDead(level():GetCurrentRoomDesc().SafeGridIndex, goal.hop, "walking there failed") end
    goal = nil
    Nav.status.goal = "no path, skipping"
    return nil
  end

  local shoot = nil
  if lastPos and (player.Position - lastPos):Length() < 0.5 then stillFrames = stillFrames + 1 else stillFrames = 0 end
  lastPos = player.Position
  if stillFrames > 45 then
    if math.abs(move.X) >= math.abs(move.Y) then shoot = move.X > 0 and "right" or "left"
    else shoot = move.Y > 0 and "down" or "up" end
  end
  return move:Normalized(), shoot, false
end

---------------------------------------------------------------- tools for the rescue ladder
function Nav.replan()
  if goal then
    skip[goal.key] = true
    if goal.hop then markDead(level():GetCurrentRoomDesc().SafeGridIndex, goal.hop, "walking there failed") end
  end
  goal = nil
end

-- Walk out through the nearest open door into a room we've been in (any visible, open door if none).
function Nav.leaveAny(player)
  local room = Game():GetRoom()
  -- whatever we were stuck on here stays failed for this floor: don't come straight back to retry it
  if goal then
    local here = level():GetCurrentRoomDesc().SafeGridIndex
    if goal.secret then secretBlocked[goal.secret.cell .. ":" .. here] = true end
    if goal.hop then markDead(here, goal.hop, "rescue had to leave") end
  end
  local best, bestD = nil, math.huge
  for slot = 0, 7 do
    local d = room:GetDoor(slot)
    if visibleDoor(d) and d:IsOpen() and not skip["leave" .. slot] then
      local info = roomInfo(d.TargetRoomIndex)
      local pos = room:GetDoorSlotPosition(slot)
      local dist = (pos - player.Position):Length() + ((info and info.visited > 0) and 0 or 400)
      if dist < bestD then best, bestD = slot, dist end
    end
  end
  if not best then return false end
  local d = room:GetDoor(best)
  local pos = room:GetDoorSlotPosition(best)
  local out = (pos - room:GetCenterPos()):Normalized()
  goal = { kind = "rescue: leaving the room", key = "leave" .. best, idx = d:GetGridIndex(), pos = pos + out * 40,
           started = Game():GetFrameCount() }
  return true
end

-- Bomb the nearest breakable rock within reach (never poop). Only within the bomb budget (rules.lua).
function Nav.bombNearest(player, minBombs)
  if player:GetNumBombs() < (minBombs or R.bombs.watchdog_min) then return false end
  local room = Game():GetRoom()
  local start = room:GetGridIndex(player.Position)
  local bestIdx, bestD = nil, 260
  for i = 0, room:GetGridSize() - 1 do
    local ge = room:GetGridEntity(i)
    if ge and BREAKABLE[ge:GetType()] and not SHOOTABLE[ge:GetType()] -- poop is shot, never bombed
       and ge.CollisionClass ~= GridCollisionClass.COLLISION_NONE then
      local d = (room:GetGridPosition(i) - player.Position):Length()
      if d < bestD then bestIdx, bestD = i, d end
    end
  end
  if not bestIdx then return false end
  local stand = bombSpot(room, start, bestIdx, player.CanFly) or start
  goal = { kind = "rescue: bombing an obstacle", key = "rb" .. bestIdx, bomb = true, idx = stand,
           pos = room:GetGridPosition(stand), started = Game():GetFrameCount() }
  return true
end

-- Brain's choices (Stage 4 "ask the brain when stuck"):
function Nav.useDoor(player, slot)
  local room = Game():GetRoom()
  local d = room:GetDoor(slot)
  if not visibleDoor(d) then return false end
  local pos = room:GetDoorSlotPosition(slot)
  local out = (pos - room:GetCenterPos()):Normalized()
  goal = { kind = "brain: door " .. slot, key = "bd" .. slot, idx = d:GetGridIndex(), pos = pos + out * 40,
           started = Game():GetFrameCount() }
  return true
end

function Nav.gotoCell(player, col, row)
  local room = Game():GetRoom()
  local idx = col + row * room:GetGridWidth()
  if idx < 0 or idx >= room:GetGridSize() then return false end
  goal = { kind = "brain: go to " .. col .. "," .. row, key = "bg" .. idx, idx = idx, pos = room:GetGridPosition(idx),
           started = Game():GetFrameCount() }
  return true
end

-- More tools for the brain's options (options.lua builds them, the brain picks one).
function Nav.shootPoop(player, poopIdx)
  local room = Game():GetRoom()
  local stand = bombSpot(room, room:GetGridIndex(player.Position), poopIdx, player.CanFly)
  if not stand then return false end
  goal = { kind = "brain: shoot poop", key = "bp" .. poopIdx, shootAt = true, target = poopIdx, idx = stand,
           pos = room:GetGridPosition(stand), started = Game():GetFrameCount() }
  return true
end

function Nav.bombFrom(player, standIdx)
  local room = Game():GetRoom()
  goal = { kind = "brain: bomb", key = "bb" .. standIdx, bomb = true, idx = standIdx,
           pos = room:GetGridPosition(standIdx), started = Game():GetFrameCount() }
  return true
end

function Nav.fetch(player, e)
  local room = Game():GetRoom()
  goal = { kind = "brain: fetch", key = "bf" .. GetPtrHash(e), entity = e, idx = room:GetGridIndex(e.Position),
           started = Game():GetFrameCount() }
  return true
end

Nav.value = value
Nav.findPath = findPath
Nav.bombSpot = bombSpot
Nav.visibleDoor = visibleDoor
Nav.roomInfo = roomInfo

---------------------------------------------------------------- siege (fight, enemies walled in by stone)
local siege = nil

function Nav.siege(player, target)
  local room = Game():GetRoom()
  local f = Game():GetFrameCount()
  if player:GetNumBombs() < R.bombs.siege_min or not target then siege = nil; return nil end
  -- never bomb toward a fire or poop: tears put those out (2026-11-25: it bombed a fire "for no reason")
  if target.kind or target.Type == EntityType.ENTITY_FIREPLACE then siege = nil; return nil end
  if not siege then
    local stand, _, isPoop = bombSpot(room, room:GetGridIndex(player.Position), room:GetGridIndex(target.Position), player.CanFly)
    if not stand or isPoop then return nil end -- poop in the way: the reflexes shoot through poop lanes instead
    siege = { idx = stand, pos = room:GetGridPosition(stand), started = f }
  end
  if f - siege.started > 30 * 12 then siege = nil; return nil end
  local move, bombNow, finished = driveBomb(room, player, siege, f)
  if finished then siege = nil end
  Nav.status.goal = "siege: bombing a way in"
  return norm(move), nil, bombNow
end

function Nav.siegeActive() return siege ~= nil end

-- The watcher (brain\watcher.py) saw the bot bounce between two rooms: write the door off like a failed one. The room
-- indexes are the ones the "room" lines show (GetCurrentRoomIndex); written off as a weak reason, so it expires.
function Nav.blockDoor(fromIdx, toIdx, why)
  local here = safeIndex(fromIdx)
  local hop = safeIndex(toIdx)
  if not here or not hop then return false end
  markDead(here, hop, why or "watcher")
  keepState()
  return true
end

-- What the bot thinks the floor looks like (the "map" command): room, type, visited?, cleared?, doors seen
-- (x = written off). For diagnosing "nothing to do".
function Nav.mapReport()
  local out = {}
  for s, nbs in pairs(graph) do
    local info = roomInfo(s)
    local list = {}
    for nb in pairs(nbs) do list[#list + 1] = tostring(nb) .. (edgeDead(s, nb) and "x" or "") end
    out[#out + 1] = string.format("%d[t%s %s%s]->%s", s, info and info.type or "?",
      info and (info.visited > 0 and "v" or "-") or "?", info and (info.clear and "c" or "-") or "?",
      table.concat(list, ","))
  end
  table.sort(out)
  return "here " .. level():GetCurrentRoomDesc().SafeGridIndex .. " | " .. table.concat(out, " ")
end

-- reloaded mid-run: at least put the room we're standing in back on the map
if Isaac.IsInGame() then pcall(Nav.recordDoors) end

return Nav
