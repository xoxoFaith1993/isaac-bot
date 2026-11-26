-- Fake Isaac for offline logic tests of the bot (2026-11-25; pattern from an earlier Isaac mod's
-- offline tests). Runs the bot's REAL nav/reflex/mover/danger code against scripted
-- rooms inside Isaac's own Lua engine (Lua5.3.3r.dll, see run.ps1). Movement is simplified: this catches logic
-- mistakes and crashes, not real dodging quality (that's the in-game room bench).
--
-- Room geometry matches the game: 40 px tiles, a 1x1 room is 15x9 tiles, tile (x, y) centre = (40 + 40x, 120 + 40y).

------------------------------------------------------------------ vectors
local V = {}
V.__index = V
local function vec(x, y) return setmetatable({ X = x, Y = y }, V) end
V.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y) end
V.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y) end
V.__mul = function(a, b)
  if type(a) == "number" then return vec(b.X * a, b.Y * a) end
  if type(b) == "number" then return vec(a.X * b, a.Y * b) end
  return vec(a.X * b.X, a.Y * b.Y)
end
V.__div = function(a, b) return vec(a.X / b, a.Y / b) end
V.__unm = function(a) return vec(-a.X, -a.Y) end
V.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
V.__tostring = function(a) return string.format("(%.0f,%.0f)", a.X, a.Y) end
function V:Length() return math.sqrt(self.X * self.X + self.Y * self.Y) end
function V:LengthSquared() return self.X * self.X + self.Y * self.Y end
function V:Dot(o) return self.X * o.X + self.Y * o.Y end
function V:Distance(o) return (self - o):Length() end
function V:Normalized() local l = self:Length() if l == 0 then return vec(0, 0) end return vec(self.X / l, self.Y / l) end
function V:Resized(n) return self:Normalized() * n end
function V:Rotated(deg)
  local r = math.rad(deg)
  local c, s = math.cos(r), math.sin(r)
  return vec(self.X * c - self.Y * s, self.X * s + self.Y * c)
end
Vector = setmetatable({ Zero = vec(0, 0) }, { __call = function(_, x, y) return vec(x, y) end })
Vector.FromAngle = function(d) return vec(math.cos(math.rad(d)), math.sin(math.rad(d))) end

------------------------------------------------------------------ enums (real numbers; unknown names get a number too)
local nextId = 5000
local function enum(t)
  return setmetatable(t, { __index = function(tbl, k)
    nextId = nextId + 1
    rawset(tbl, k, nextId)
    return nextId
  end })
end
EntityType = enum({ ENTITY_PLAYER = 1, ENTITY_TEAR = 2, ENTITY_FAMILIAR = 3, ENTITY_BOMB = 4, ENTITY_PICKUP = 5,
  ENTITY_LASER = 7, ENTITY_PROJECTILE = 9, ENTITY_GAPER = 10, ENTITY_FLY = 13, ENTITY_FIREPLACE = 33,
  ENTITY_HOST = 27, ENTITY_SPIDER = 85, ENTITY_CONSTANT_STONE_SHOOTER = 202, ENTITY_MOVABLE_TNT = 292,
  ENTITY_EFFECT = 1000 })
GridEntityType = enum({ GRID_NULL = 0, GRID_DECORATION = 1, GRID_ROCK = 2, GRID_ROCKB = 3, GRID_ROCKT = 4,
  GRID_ROCK_BOMB = 5, GRID_ROCK_ALT = 6, GRID_PIT = 7, GRID_SPIKES = 8, GRID_SPIKES_ONOFF = 9, GRID_SPIDERWEB = 10,
  GRID_LOCK = 11, GRID_TNT = 12, GRID_FIREPLACE = 13, GRID_POOP = 14, GRID_WALL = 15, GRID_DOOR = 16,
  GRID_TRAPDOOR = 17, GRID_STAIRS = 18, GRID_GRAVITY = 19, GRID_PRESSURE_PLATE = 20, GRID_STATUE = 21,
  GRID_ROCK_SS = 22, GRID_TELEPORTER = 23, GRID_PILLAR = 24, GRID_ROCK_SPIKED = 25, GRID_ROCK_ALT2 = 26,
  GRID_ROCK_GOLD = 27 })
GridCollisionClass = enum({ COLLISION_NONE = 0, COLLISION_PIT = 1, COLLISION_OBJECT = 2, COLLISION_SOLID = 3,
  COLLISION_WALL = 4, COLLISION_WALL_EXCEPT_PLAYER = 5 })
EntityCollisionClass = enum({ ENTCOLL_NONE = 0, ENTCOLL_PLAYEROBJECTS = 1, ENTCOLL_PLAYERONLY = 2,
  ENTCOLL_ENEMIES = 3, ENTCOLL_ALL = 4 })
EffectVariant = enum({ CREEP_RED = 22, CREEP_GREEN = 23, CREEP_YELLOW = 24, CREEP_WHITE = 25, CREEP_BLACK = 26 })
PickupVariant = enum({ PICKUP_NULL = 0, PICKUP_HEART = 10, PICKUP_COIN = 20, PICKUP_KEY = 30, PICKUP_BOMB = 40,
  PICKUP_CHEST = 50, PICKUP_LOCKEDCHEST = 60, PICKUP_COLLECTIBLE = 100 })
HeartSubType = enum({ HEART_FULL = 1, HEART_HALF = 2, HEART_SOUL = 3 })
EntityFlag = enum({ FLAG_FRIENDLY = 1 << 29 })
RoomType = enum({ ROOM_DEFAULT = 1, ROOM_BOSS = 5 })

------------------------------------------------------------------ world
local W = { frame = 0, time = 0, entities = {}, nextHash = 1 }
MockWorld = W
function GetPtrHash(e) return e._hash end

-- grid letters (same as the bot's eyes): # rock, W wall, D door, _ pressure plate, p poop, ^ spikes, ~ pit, . floor
local GRID = {
  ["#"] = { GridEntityType.GRID_ROCK, GridCollisionClass.COLLISION_SOLID },
  ["W"] = { GridEntityType.GRID_WALL, GridCollisionClass.COLLISION_WALL },
  ["D"] = { GridEntityType.GRID_DOOR, GridCollisionClass.COLLISION_WALL_EXCEPT_PLAYER },
  ["_"] = { GridEntityType.GRID_PRESSURE_PLATE, GridCollisionClass.COLLISION_NONE },
  ["p"] = { GridEntityType.GRID_POOP, GridCollisionClass.COLLISION_SOLID },
  ["^"] = { GridEntityType.GRID_SPIKES, GridCollisionClass.COLLISION_NONE },
  ["~"] = { GridEntityType.GRID_PIT, GridCollisionClass.COLLISION_PIT },
  ["T"] = { GridEntityType.GRID_TRAPDOOR, GridCollisionClass.COLLISION_NONE },
}

local Room = {}
Room.__index = Room
local function newRoom(rows, opts)
  local r = setmetatable({ w = #rows[1], h = #rows, cells = {}, ents = {}, clear = opts.clear, doors = {},
                           type = opts.type or 1 }, Room)
  for y, row in ipairs(rows) do
    for x = 1, #row do
      local ch = row:sub(x, x)
      local i = (x - 1) + (y - 1) * r.w
      local g = GRID[ch]
      if g then
        local ge = { _type = g[1], CollisionClass = g[2], State = 0, _hp = (ch == "p") and 4 or nil }
        function ge:GetType() return self._type end
        r.ents[i] = ge
        r.cells[i] = g[2]
      else
        r.cells[i] = GridCollisionClass.COLLISION_NONE
      end
    end
  end
  return r
end
function Room:GetGridWidth() return self.w end
function Room:GetGridHeight() return self.h end
function Room:GetGridSize() return self.w * self.h end
function Room:GetGridPosition(i) return vec(40 + 40 * (i % self.w), 120 + 40 * (i // self.w)) end
function Room:GetGridIndex(p)
  local x = math.floor((p.X - 20) / 40 + 0.0001)
  local y = math.floor((p.Y - 100) / 40 + 0.0001)
  if x < 0 or y < 0 or x >= self.w or y >= self.h then return -1 end
  return x + y * self.w
end
function Room:GetGridEntity(i) return self.ents[i] end
function Room:GetGridEntityFromPos(p) return self.ents[self:GetGridIndex(p)] end
function Room:GetGridCollision(i) return self.cells[i] or GridCollisionClass.COLLISION_WALL end
function Room:GetGridCollisionAtPos(p) return self:GetGridCollision(self:GetGridIndex(p)) end
function Room:GetTopLeftPos() return vec(60, 140) end
function Room:GetBottomRightPos() return vec(40 + 40 * (self.w - 1) - 20, 120 + 40 * (self.h - 1) - 20) end
function Room:GetCenterPos() return (self:GetTopLeftPos() + self:GetBottomRightPos()) / 2 end
function Room:IsPositionInRoom(p, margin)
  local tl, br = self:GetTopLeftPos(), self:GetBottomRightPos()
  return p.X >= tl.X + margin and p.X <= br.X - margin and p.Y >= tl.Y + margin and p.Y <= br.Y - margin
end
function Room:IsClear() return self.clear end
function Room:GetType() return self.type end
function Room:GetDoor(slot) return self.doors[slot] end
-- door squares of a 1x1 room: 0 left, 1 up, 2 right, 3 down (same as the game's DoorSlot numbers)
function Room:DoorSlotIndex(slot)
  local w, h = self.w, self.h
  local xy = { [0] = { 0, h // 2 }, [1] = { w // 2, 0 }, [2] = { w - 1, h // 2 }, [3] = { w // 2, h - 1 } }
  local c = xy[slot]
  return c and (c[1] + c[2] * w) or -1
end
local Door = {}
Door.__index = Door
function Door:IsOpen() return self._open and not self._locked end
function Door:IsLocked() return self._locked end
function Door:GetGridIndex() return self._idx end
-- a hidden secret door: the game reports it "open" while its square is still solid wall
local function newDoor(room, slot, spec)
  return setmetatable({ Slot = slot, TargetRoomIndex = spec.to, TargetRoomType = spec.type or 1,
    _locked = spec.locked or false, _open = spec.open ~= false, _idx = room:DoorSlotIndex(slot) }, Door)
end
function Room:GetDoorSlotPosition(slot)
  local c = self:GetCenterPos()
  local pos = { [0] = vec(40, c.Y), [1] = vec(c.X, 120), [2] = vec(40 + 40 * (self.w - 1), c.Y),
                [3] = vec(c.X, 120 + 40 * (self.h - 1)) }
  return pos[slot] or c
end

------------------------------------------------------------------ entities
local Ent = {}
Ent.__index = Ent
local function entity(t, v, pos, opts)
  opts = opts or {}
  local e = setmetatable({ Type = t, Variant = v or 0, SubType = opts.sub or 0, Position = pos,
    Velocity = opts.vel or vec(0, 0), Size = opts.size or 13, HitPoints = opts.hp or 10, MaxHitPoints = opts.hp or 10,
    Mass = opts.mass or 10, FrameCount = 10, EntityCollisionClass = opts.coll or EntityCollisionClass.ENTCOLL_ALL,
    SpriteScale = vec(1, 1), SpawnerType = opts.spawnerType or 0, SpawnerEntity = opts.spawner, Parent = opts.parent,
    _hash = W.nextHash, _alive = true, _enemy = opts.enemy, _vuln = opts.vulnerable ~= false, _boss = opts.boss,
    _anim = opts.anim or "Idle", _chase = opts.chase or 0, _flags = 0, Price = opts.price or 0, Touched = false }, Ent)
  W.nextHash = W.nextHash + 1
  W.entities[#W.entities + 1] = e
  return e
end
function Ent:Exists() return self._alive end
function Ent:IsDead() return not self._alive end
function Ent:IsActiveEnemy() return self._enemy and self._alive or false end
function Ent:IsVulnerableEnemy() return self._enemy and self._vuln and self._alive or false end
function Ent:IsInvincible() return false end
function Ent:IsBoss() return self._boss or false end
function Ent:HasEntityFlags(f) return (self._flags & f) ~= 0 end
function Ent:ToPickup() return self.Type == EntityType.ENTITY_PICKUP and self or nil end
function Ent:ToLaser() return nil end
function Ent:IsShopItem() return false end
function Ent:GetSprite()
  local e = self
  return { GetAnimation = function() return e._anim end, GetFrame = function() return 0 end,
           IsPlaying = function(_, a) return e._anim == a end, IsFinished = function() return false end }
end

------------------------------------------------------------------ player
local P = {}
P.__index = function(t, k) return P[k] or Ent[k] end
local function newPlayer(pos)
  local p = entity(EntityType.ENTITY_PLAYER, 0, pos, { size = 10 })
  setmetatable(p, P)
  p.MoveSpeed, p.TearRange, p.ShotSpeed, p.CanFly, p.Damage, p.MaxFireDelay = 1, 260, 1, false, 3.5, 10
  p._bombs, p._keys, p._hearts, p._soul = 1, 0, 6, 0
  return p
end
function P:GetNumBombs() return self._bombs end
function P:GetNumKeys() return self._keys end
function P:GetNumCoins() return 0 end
function P:GetHearts() return self._hearts end
function P:GetMaxHearts() return 6 end
function P:GetSoulHearts() return self._soul end
function P:GetBoneHearts() return 0 end
function P:GetBlackHearts() return 0 end
function P:IsHoldingItem() return false end
function P:CanPickRedHearts() return self._hearts < 6 end
function P:CanPickSoulHearts() return true end
function P:CanPickBlackHearts() return true end
function P:GetCard() return self._card or 0 end
function P:GetPill() return self._pill or 0 end
function P:GetTrinket() return 0 end
function P:GetCollectibleCount() return 0 end
function P:HasCollectible() return false end
function P:GetActiveItem() return 0 end

------------------------------------------------------------------ level, game, Isaac
local level = { stage = 1, stageType = 0, rooms = {}, current = 84 }
function level:GetStage() return self.stage end
function level:GetStageType() return self.stageType end
function level:GetCurrentRoomIndex() return self.current end
function level:GetCurrentRoomDesc() return self.rooms[self.current] end
function level:GetRoomByIdx(i) return self.rooms[i] end

local game = { TimeCounter = 0 }
function game:GetRoom() return W.room end
function game:GetLevel() return level end
function game:GetFrameCount() return W.frame end
W.seed = 12345 -- a new seed = a new floor as far as the bot's floor map is concerned
function game:GetSeeds() return { GetStartSeed = function() return W.seed end } end
function Game() return game end

Isaac = {}
function Isaac.GetPlayer() return W.player end
function Isaac.GetRoomEntities()
  local out = {}
  for _, e in ipairs(W.entities) do if e._alive and e.Type ~= EntityType.ENTITY_PLAYER then out[#out + 1] = e end end
  return out
end
function Isaac.FindByType(t, v)
  local out = {}
  for _, e in ipairs(W.entities) do
    if e._alive and e.Type == t and (v == nil or v == -1 or e.Variant == v) then out[#out + 1] = e end
  end
  return out
end
function Isaac.CountEnemies()
  local n = 0
  for _, e in ipairs(W.entities) do if e._alive and e._enemy then n = n + 1 end end
  return n
end
function Isaac.GetTime() return W.time end
function Isaac.GetFrameCount() return W.frame end
function Isaac.IsInGame() return true end
function Isaac.DebugString() end
function Isaac.ExecuteCommand() return "" end
function Isaac.GetItemConfig() return { GetCollectible = function() return nil end } end

------------------------------------------------------------------ the bot's own modules (include = load from the mod)
-- MUTANT (set by run.ps1 -Prove): patches applied IN MEMORY to the bot's code, to show a test fails without
-- the fix it guards. The files in mod\ are never touched.
local loaded = {}
local function loadModule(name)
  local path = MOD_DIR .. "/" .. name .. ".lua"
  local patches = {}
  for _, p in ipairs((MUTANT and MUTANT.patches) or {}) do if p.file == name then patches[#patches + 1] = p end end
  if #patches == 0 then return dofile(path) end
  local fh = assert(io.open(path, "rb"))
  local src = fh:read("a"):gsub("\r\n", "\n")
  fh:close()
  for _, p in ipairs(patches) do
    local s, e = src:find(p.find, 1, true)
    if not s then error("MUTANT PATCH NOT FOUND in " .. name .. ".lua (the code changed): " .. p.find) end
    src = src:sub(1, s - 1) .. p.replace .. src:sub(e + 1)
    MUTANT.applied = (MUTANT.applied or 0) + 1
  end
  return assert(load(src, "@" .. path))()
end
function include(name)
  if loaded[name] == nil then loaded[name] = loadModule(name) end
  return loaded[name]
end

------------------------------------------------------------------ scenario helpers for the tests
Mock = {}
Mock.vec = vec
Mock.entity = entity
Mock.level = level

local DEFAULT_ROWS = {
  "WWWWWWWDWWWWWWW",
  "W.............W",
  "W.............W",
  "W.............W",
  "D.............D",
  "W.............W",
  "W.............W",
  "W.............W",
  "WWWWWWWDWWWWWWW",
}
local soloRoom = 1000 -- single-room tests each get their own room number (the bot keys state by room)

-- A fresh world: rows = grid letters (default: an empty 1x1 room), player at a tile.
-- opts: clear, player, roomIdx, type (room type), doors = { [slot] = { to = room, type = t, locked = true } },
--       keepFloor (used by Mock.enter: stay on the same floor; otherwise every call is a brand-new floor)
-- a new run: the game's frame counter starts again from 0 (tests: timers must survive it)
function Mock.setFrame(n) W.frame = n end

function Mock.room(rows, opts)
  opts = opts or {}
  -- a new test jumps 1000 updates ahead (stale timers run out); walking into the next room is just 1 update
  W.entities, W.frame, W.time = {}, (W.frame or 0) + (opts.keepFloor and 1 or 1000), 0
  rows = rows or DEFAULT_ROWS
  W.room = newRoom(rows, { clear = opts.clear ~= false, type = opts.type })
  for slot, spec in pairs(opts.doors or {}) do W.room.doors[slot] = newDoor(W.room, slot, spec) end
  if not opts.keepFloor then
    W.seed, W.floorSpec = W.seed + 1, nil
    level.rooms = {}
    soloRoom = soloRoom + 1
  end
  level.current = opts.roomIdx or soloRoom
  level.rooms[level.current] = level.rooms[level.current] or { SafeGridIndex = level.current,
    GridIndex = level.current, VisitedCount = 1, Data = { Type = opts.type or 1, Variant = 1, Shape = 1, Name = "test" } }
  level.rooms[level.current].Clear = W.room.clear
  W.player = newPlayer(opts.player or vec(320, 280))
  return W.room
end
function Mock.tile(x, y) return vec(40 + 40 * x, 120 + 40 * y) end
function Mock.enemy(t, v, pos, opts) opts = opts or {}; opts.enemy = true; return entity(t, v, pos, opts) end
-- an enemy circling `c` at radius r, w radians per update, starting at angle a (moves every Mock.step)
function Mock.orbiter(t, c, r, w, a, opts)
  local e = Mock.enemy(t, 0, c + vec(math.cos(a), math.sin(a)) * r, opts)
  e._orbit = { c = c, r = r, w = w, a = a }
  return e
end
function Mock.pickup(v, sub, pos) return entity(EntityType.ENTITY_PICKUP, v, pos, { sub = sub }) end
function Mock.shot(pos, vel) return entity(EntityType.ENTITY_PROJECTILE, 0, pos, { vel = vel, size = 7 }) end
-- a lit fireplace (an entity in the real game, type 33; HitPoints > 1 = burning)
function Mock.fire(pos) return entity(EntityType.ENTITY_FIREPLACE, 0, pos, { hp = 5, size = 13 }) end

-- A floor of several 1x1 rooms on the game's 13-wide map (84 = the start room, 85 = right of it, 71 = above...).
-- spec[idx] = { type = room type, visited = true/false, clear = bool, rows = grid letters,
--               doors = { [slot] = idx  or  { to = idx, locked = true, open = false } }, setup = function(room) }
-- Doors are listed on BOTH rooms by the test. Nothing is entered yet: call Mock.enter.
function Mock.floor(spec)
  W.seed = W.seed + 1
  W.floorSpec = spec
  W.player = nil -- a fresh Isaac (keys/bombs aren't carried over from the last test)
  level.rooms = {}
  for idx, r in pairs(spec) do
    level.rooms[idx] = { SafeGridIndex = idx, GridIndex = idx, VisitedCount = r.visited and 1 or 0,
      Clear = (r.clear == nil) and (r.visited or false) or r.clear,
      Data = { Type = r.type or 1, Variant = 1, Shape = 1, Name = "test" } }
  end
end

-- Walk into room `idx` (through its door `slot`, or at `pos`). Like the game: VisitedCount goes up, the
-- player stands just inside that door. Call the bot's Nav.newRoom() after this (Mock.walk does).
function Mock.enter(idx, slot, pos)
  local r = W.floorSpec[idx]
  local doors = {}
  for s, d in pairs(r.doors or {}) do
    local to = type(d) == "table" and d.to or d
    local target = W.floorSpec[to]
    doors[s] = { to = to, type = type(d) == "table" and d.type or (target and target.type) or 1,
                 locked = type(d) == "table" and d.locked, open = type(d) ~= "table" or d.open ~= false }
  end
  local desc = level.rooms[idx]
  local keys = W.player and W.player._keys
  local bombs = W.player and W.player._bombs
  Mock.room(r.rows, { roomIdx = idx, keepFloor = true, type = r.type, doors = doors,
                      clear = desc.Clear or r.clear ~= false })
  desc.VisitedCount = desc.VisitedCount + 1
  desc.Clear = W.room.clear
  if keys then W.player._keys, W.player._bombs = keys, bombs end
  if slot then
    local c = W.room:GetCenterPos()
    local dp = W.room:GetDoorSlotPosition(slot)
    W.player.Position = dp + (c - dp):Normalized() * 60
  elseif pos then
    W.player.Position = pos
  end
  if r.setup then r.setup(W.room) end
  return W.room
end

-- Our tear hits the first thing in a straight line: a poop loses 1 of its 4 hit points per tear.
function Mock.shootGrid(dir)
  local d = ({ left = vec(-1, 0), right = vec(1, 0), up = vec(0, -1), down = vec(0, 1) })[dir]
  if not d then return end
  W.tearCd = (W.tearCd or 0) - 1
  if W.tearCd > 0 then return end
  W.tearCd = 10
  local pos = W.player.Position
  for _ = 1, 20 do
    pos = pos + d * 20
    local i = W.room:GetGridIndex(pos)
    if i < 0 then return end
    local ge = W.room.ents[i]
    if ge and ge.CollisionClass ~= GridCollisionClass.COLLISION_NONE and ge.CollisionClass ~= GridCollisionClass.COLLISION_PIT then
      if ge._hp then
        ge._hp = ge._hp - 1
        ge.State = ge.State + 250
        if ge._hp <= 0 then
          ge.State, ge.CollisionClass, W.room.cells[i] = 1000, GridCollisionClass.COLLISION_NONE, GridCollisionClass.COLLISION_NONE
        end
      end
      return
    end
  end
end

-- The open door the player is standing in, if any (a locked one opens with a key, like the game).
function Mock.doorTouched()
  local p = W.player
  for slot, d in pairs(W.room.doors) do
    local col = W.room:GetGridCollision(d._idx)
    if d._open and col ~= GridCollisionClass.COLLISION_WALL and col ~= GridCollisionClass.COLLISION_SOLID
       and (W.room:GetDoorSlotPosition(slot) - p.Position):Length() < 28 then
      if d._locked and p._keys > 0 then p._keys, d._locked = p._keys - 1, false end
      if not d._locked then return d end
    end
  end
  return nil
end

-- Let the walking part of the bot (nav) play the floor for `n` updates: its moves, its shots at poop, and
-- going through doors. Returns the list of rooms entered, in order.
function Mock.walk(nav, n, onUpdate)
  local seq = {}
  for k = 1, n do
    local move, shoot = nav.update(W.player)
    if shoot then Mock.shootGrid(shoot) end
    Mock.step(move)
    if onUpdate then onUpdate(k) end
    local d = Mock.doorTouched()
    if d and W.floorSpec and W.floorSpec[d.TargetRoomIndex] then
      Mock.enter(d.TargetRoomIndex, (d.Slot + 2) % 4)
      nav.newRoom()
      seq[#seq + 1] = d.TargetRoomIndex
    end
  end
  return seq
end

-- A code reload in the running game ("reload" command = luamod): the module's file runs again, its local
-- state starts fresh; only globals survive.
function Mock.reload(name)
  loaded[name] = nil
  return include(name)
end

-- One game update: advance time, move chasers toward the player, move shots, move the player by `move`
-- (sliding along a wall like the game does when a diagonal move is half blocked).
local function free(np)
  return W.room:GetGridCollisionAtPos(np) == GridCollisionClass.COLLISION_NONE and W.room:IsPositionInRoom(np, 0)
end
function Mock.step(move, speed)
  W.frame = W.frame + 1
  local p = W.player
  if move then
    local dv = move * (speed or 4.6)
    local np = p.Position + dv
    if not free(np) then
      np = nil
      for _, alt in ipairs({ vec(dv.X, 0), vec(0, dv.Y) }) do
        if alt:Length() > 0.5 and free(p.Position + alt) then np = p.Position + alt; break end
      end
    end
    if np then
      p.Velocity = np - p.Position
      p.Position = np
    else
      p.Velocity = vec(0, 0)
    end
  end
  for _, e in ipairs(W.entities) do
    if e._alive and e ~= p then
      if e._chase > 0 then e.Velocity = (p.Position - e.Position):Normalized() * e._chase end
      if e._orbit then -- circles a point (a wide-moving enemy that never leaves the middle)
        local o = e._orbit
        o.a = o.a + o.w
        local np = o.c + vec(math.cos(o.a), math.sin(o.a)) * o.r
        e.Velocity = np - e.Position
      end
      e.Position = e.Position + e.Velocity
    end
  end
end

-- "hit" = something touching the player right now
function Mock.touching()
  local p = W.player
  for _, e in ipairs(W.entities) do
    if e._alive and e ~= p and (e._enemy or e.Type == EntityType.ENTITY_PROJECTILE)
       and (e.Position - p.Position):Length() < e.Size + p.Size then return e end
  end
  return nil
end
