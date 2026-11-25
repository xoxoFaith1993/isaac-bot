-- Isaac Bot danger map: ONE map of what hurts in this room, read by walking (nav.lua), fighting (reflex.lua)
-- and the brain's options. Values are half hearts of damage for being on that square (rules.lua: R.danger).
--   static  = spikes, creep, lit fires, unkillable leftovers (things that stay put)
--   dynamic = live bombs and enemy bodies (the reflexes also predict these frame by frame)
-- Plus the "worth it?" rule: Danger.cost(player, damage) = how many points that damage is worth right now.

local R = include("rules")
local Danger = { static = {}, dynamic = {}, builtAt = -1 }

local CREEP = {}
for _, n in ipairs({ "CREEP_RED", "CREEP_GREEN", "CREEP_YELLOW", "CREEP_WHITE", "CREEP_BLACK",
                     "CREEP_SLIPPERY_BROWN", "CREEP_STATIC", "CREEP_LIQUID_POOP" }) do
  if EffectVariant[n] then CREEP[EffectVariant[n]] = true end
end

local function mark(map, i, size, d)
  if i >= 0 and i < size and d > (map[i] or 0) then map[i] = d end
end

-- every square whose centre is within r (+ slack) of pos
local function around(room, map, pos, r, d, slack)
  slack = slack or 20
  local w, size = room:GetGridWidth(), room:GetGridSize()
  local c = room:GetGridIndex(pos)
  if c < 0 then return end
  local k = math.ceil(r / 40)
  local cx, cy = c % w, math.floor(c / w)
  for dy = -k, k do
    for dx = -k, k do
      local x, y = cx + dx, cy + dy
      if x >= 0 and x < w then
        local i = x + y * w
        if i >= 0 and i < size and (room:GetGridPosition(i) - pos):Length() <= r + slack then mark(map, i, size, d) end
      end
    end
  end
end

-- Rebuilt at most once per game update.
function Danger.build(player)
  local f = Game():GetFrameCount()
  if f == Danger.builtAt then return end
  Danger.builtAt = f
  local room = Game():GetRoom()
  local size = room:GetGridSize()
  local fly = player.CanFly
  -- the tile part (spikes, TNT) hardly changes: rescanned every 10 updates or in a new room, not every update
  -- (walking all 448 tiles of a big room every update was part of the half-speed lag)
  local roomKey = Game():GetLevel():GetCurrentRoomIndex()
  if not Danger.tiles or Danger.tiles.room ~= roomKey or f - Danger.tiles.at >= 10 or Danger.tiles.fly ~= fly then
    local tst, tca = {}, {}
    for i = 0, size - 1 do
      local ge = room:GetGridEntity(i)
      if ge then
        local t = ge:GetType()
        if not fly and (t == GridEntityType.GRID_SPIKES or (t == GridEntityType.GRID_SPIKES_ONOFF and ge.State == 0)) then
          mark(tst, i, size, R.danger.spikes)
        end
        -- TNT goes off like a bomb when HIT, not when walked past: it's "caution", never counted as damage.
        -- (As damage, a TNT-filled room made every route "cost hearts" and the bot wouldn't cross it.)
        if t == GridEntityType.GRID_TNT and ge.CollisionClass ~= GridCollisionClass.COLLISION_NONE then
          around(room, tca, room:GetGridPosition(i), R.danger.tnt_radius, R.danger.tnt, 0)
        end
      end
    end
    Danger.tiles = { room = roomKey, at = f, fly = fly, st = tst, ca = tca }
  end
  local st, dy, ca = {}, {}, {}
  for i, v in pairs(Danger.tiles.st) do st[i] = v end
  for i, v in pairs(Danger.tiles.ca) do ca[i] = v end
  for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_MOVABLE_TNT or 292)) do
    if e.HitPoints > 0 then around(room, ca, e.Position, R.danger.tnt_radius, R.danger.tnt, 0) end
  end
  local cleared = room:IsClear()
  for _, e in ipairs(Isaac.GetRoomEntities()) do
    local ty = e.Type
    if ty == EntityType.ENTITY_EFFECT then
      if CREEP[e.Variant] and not fly then
        -- real size only, no padding: padded creep turned a Clotty's whole row into a no-go zone, so the bot
        -- stood off its line shooting at nothing (the author's screenshot, 2026-11-25)
        around(room, st, e.Position, e.Size * math.max(1, e.SpriteScale.X) * 0.8, R.danger.creep, 0)
      end
    elseif ty == EntityType.ENTITY_FIREPLACE then
      if e.HitPoints > 1 then mark(st, room:GetGridIndex(e.Position), size, R.danger.fire) end
    elseif ty == EntityType.ENTITY_BOMB then
      around(room, dy, e.Position, R.danger.bomb_radius, R.danger.bomb)
    elseif e:IsActiveEnemy(false) and not e:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
           and (not IsaacBotSolid or IsaacBotSolid(e)) then -- cords/chains never hurt; a mid-jump boss still does
      if cleared then
        around(room, st, e.Position, e.Size + 20, R.danger.touch) -- leftover unkillable thing: a fixed hazard
      else
        around(room, dy, e.Position, e.Size, R.danger.touch)
      end
    end
  end
  Danger.static, Danger.dynamic, Danger.caution = st, dy, ca
end

-- "Caution" squares (next to TNT): not damage, just places not to linger, especially in a fight.
function Danger.cautionCell(i) return (Danger.caution or {})[i] or 0 end
function Danger.cautionAt(pos) return Danger.cautionCell(Game():GetRoom():GetGridIndex(pos)) end

function Danger.cell(i) return math.max(Danger.static[i] or 0, Danger.dynamic[i] or 0) end
function Danger.staticCell(i) return Danger.static[i] or 0 end
function Danger.at(pos) return Danger.cell(Game():GetRoom():GetGridIndex(pos)) end
function Danger.staticAt(pos) return Danger.staticCell(Game():GetRoom():GetGridIndex(pos)) end

-- Health in half hearts (red + soul/black + bone hearts).
function Danger.hp(p)
  return p:GetHearts() + p:GetSoulHearts() + p:GetBoneHearts() * 2
end

-- Points that `dmg` half hearts are worth right now: infinite if it would kill.
function Danger.cost(p, dmg)
  if not dmg or dmg <= 0 then return 0 end
  local hp = Danger.hp(p)
  if dmg >= hp then return math.huge end
  -- every hit also costs the floor's deal chance (each hurting square = one hit here)
  return dmg * R.risk.half_heart * R.risk.full_hp / (hp - dmg) + dmg * (R.risk.per_hit or 0)
end

-- Damage taken walking a path (list of squares): each hurting square counts once.
function Danger.pathDamage(path)
  local dmg = 0
  for _, i in ipairs(path or {}) do dmg = dmg + Danger.staticCell(i) end
  return dmg
end

return Danger
