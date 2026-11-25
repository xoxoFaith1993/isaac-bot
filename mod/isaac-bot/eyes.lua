-- Isaac Bot eyes (Stage 1): everything the bot can see in the current room, as plain data.
-- snapshot() -> table sent to the helper 10x a second; grid() -> the room's tiles, sent when they change.
-- Compact on purpose: positions are whole pixels, velocities one decimal, lists are arrays.

local Eyes = {}

local function r0(x) return math.floor(x + 0.5) end
local function r1(x) return math.floor(x * 10 + 0.5) / 10 end
local function r2(x) return math.floor(x * 100 + 0.5) / 100 end

-- Tile letters for the room map (one per grid square):
--  . floor   # rock/block/pillar/statue   ~ pit   ^ spikes   w cobweb   p poop   T tnt
--  L lock block   W wall   D door   v trapdoor   = stairs   _ pressure plate   ? other
local TILE = {}
for name, ch in pairs({
  GRID_ROCK = "#", GRID_ROCKB = "#", GRID_ROCKT = "#", GRID_ROCK_BOMB = "#", GRID_ROCK_ALT = "#", GRID_ROCK_SS = "#",
  GRID_PILLAR = "#", GRID_STATUE = "#", GRID_ROCK_SPIKED = "#", GRID_ROCK_ALT2 = "#", GRID_ROCK_GOLD = "#",
  GRID_PIT = "~", GRID_SPIKES = "^", GRID_SPIKES_ONOFF = "^", GRID_SPIDERWEB = "w", GRID_POOP = "p", GRID_TNT = "T",
  GRID_LOCK = "L", GRID_WALL = "W", GRID_DOOR = "D", GRID_TRAPDOOR = "v", GRID_STAIRS = "=",
  GRID_PRESSURE_PLATE = "_", GRID_DECORATION = ".",
}) do
  local id = GridEntityType[name]
  if id then TILE[id] = ch end -- skip names this game version doesn't have
end
-- These still matter when you can walk over them (they hurt, slow, or are exits).
local KEEP_WHEN_PASSABLE = { ["^"] = true, ["w"] = true, ["v"] = true, ["="] = true, ["_"] = true, ["D"] = true, ["W"] = true }

function Eyes.grid()
  local room = Game():GetRoom()
  local w, h = room:GetGridWidth(), room:GetGridHeight()
  local chars = {}
  for i = 0, room:GetGridSize() - 1 do
    local ch = "."
    local ge = room:GetGridEntity(i)
    if ge then
      ch = TILE[ge:GetType()] or "?"
      if ge.CollisionClass == GridCollisionClass.COLLISION_NONE and not KEEP_WHEN_PASSABLE[ch] then
        ch = "." -- broken rock, bridged pit, destroyed poop
      end
      if ch == "^" and ge:GetType() == GridEntityType.GRID_SPIKES_ONOFF and ge.State ~= 0 then
        ch = "," -- retracted on/off spikes
      end
    end
    chars[#chars + 1] = ch
  end
  local p0 = room:GetGridPosition(0)
  local level = Game():GetLevel()
  return table.concat({ level:GetCurrentRoomIndex(), w, h, r0(p0.X), r0(p0.Y), table.concat(chars) }, "|")
end

local function doors(room)
  local list = {}
  for slot = 0, 7 do
    local d = room:GetDoor(slot)
    if d then
      local p = room:GetDoorSlotPosition(slot)
      list[#list + 1] = { slot, d.TargetRoomType, d:IsOpen() and 1 or 0, d:IsLocked() and 1 or 0, r0(p.X), r0(p.Y) }
    end
  end
  return list
end

local function player_info(p)
  return {
    x = r0(p.Position.X), y = r0(p.Position.Y), vx = r1(p.Velocity.X), vy = r1(p.Velocity.Y),
    size = r1(p.Size), type = p:GetPlayerType(),
    red = p:GetHearts(), max = p:GetMaxHearts(), soul = p:GetSoulHearts(), bone = p:GetBoneHearts(),
    eternal = p:GetEternalHearts(),
    speed = r2(p.MoveSpeed), dmg = r2(p.Damage), delay = r2(p.MaxFireDelay), range = r0(p.TearRange),
    shot = r2(p.ShotSpeed), luck = r2(p.Luck), fly = p.CanFly and 1 or 0,
    coins = p:GetNumCoins(), bombs = p:GetNumBombs(), keys = p:GetNumKeys(),
    items = p:GetCollectibleCount(), active = p:GetActiveItem(ActiveSlot.SLOT_PRIMARY),
    charge = p:GetActiveCharge(ActiveSlot.SLOT_PRIMARY),
    hurt = p:GetDamageCooldown(),
  }
end

local function from_player(e)
  return e.SpawnerType == EntityType.ENTITY_PLAYER or e.SpawnerType == EntityType.ENTITY_FAMILIAR
    or (e.Parent and e.Parent.Type == EntityType.ENTITY_PLAYER)
end

function Eyes.snapshot()
  local game = Game()
  local room, level = game:GetRoom(), game:GetLevel()
  local p = Isaac.GetPlayer(0)
  local s = {
    f = game:GetFrameCount(),
    room = { level:GetCurrentRoomIndex(), room:GetType(), room:GetRoomShape(), room:IsClear() and 1 or 0 },
    floor = { level:GetStage(), level:GetStageType() },
    p = player_info(p),
    e = {},   -- enemies:     type, variant, x, y, vx, vy, hp, maxhp, boss, size
    t = {},   -- projectiles: x, y, vx, vy, height
    l = {},   -- enemy lasers: x, y, angle, length, timeout
    b = {},   -- enemy bombs: x, y
    k = {},   -- pickups:     variant, subtype, x, y, price
    fp = {},  -- fireplaces:  variant, x, y, hp
    doors = doors(room),
  }
  for _, e in ipairs(Isaac.GetRoomEntities()) do
    local ty = e.Type
    if ty == EntityType.ENTITY_PROJECTILE then
      local pr = e:ToProjectile()
      s.t[#s.t + 1] = { r0(e.Position.X), r0(e.Position.Y), r1(e.Velocity.X), r1(e.Velocity.Y), r0(pr and pr.Height or 0) }
    elseif ty == EntityType.ENTITY_LASER then
      local lz = e:ToLaser()
      if lz and not from_player(e) then
        s.l[#s.l + 1] = { r0(e.Position.X), r0(e.Position.Y), r0(lz.Angle), r0(lz.MaxDistance), lz.Timeout }
      end
    elseif ty == EntityType.ENTITY_BOMB then
      if not from_player(e) then s.b[#s.b + 1] = { r0(e.Position.X), r0(e.Position.Y) } end
    elseif ty == EntityType.ENTITY_PICKUP then
      local pk = e:ToPickup()
      s.k[#s.k + 1] = { e.Variant, e.SubType, r0(e.Position.X), r0(e.Position.Y), pk and pk.Price or 0 }
    elseif ty == EntityType.ENTITY_FIREPLACE then
      if e.HitPoints > 1 then s.fp[#s.fp + 1] = { e.Variant, r0(e.Position.X), r0(e.Position.Y), r0(e.HitPoints) } end
    elseif e:IsActiveEnemy(false) and not e:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
           and (not IsaacBotSolid or IsaacBotSolid(e)) then -- cords/chains aren't enemies; mid-jump bosses are
      s.e[#s.e + 1] = { ty, e.Variant, r0(e.Position.X), r0(e.Position.Y), r1(e.Velocity.X), r1(e.Velocity.Y),
                        r0(e.HitPoints), r0(e.MaxHitPoints), e:IsBoss() and 1 or 0, r0(e.Size), r1(e.Mass) }
    end
  end
  return s
end

return Eyes
