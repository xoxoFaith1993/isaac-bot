-- Enemy behaviour recorder (2026-11-26). The author: "there's got to be something laid out in the game files so it
-- doesn't make it an absolute surprise every single time". The game's files hold stats and animation timings, but
-- the behaviour itself is compiled into the game. So we watch it from the INSIDE instead: while recording, every
-- second update logs each enemy's animation and frame, its AI state (NpcState) and state timer, position and speed,
-- its AI scratch values (V1, V2, I1, I2) and the spot it steers for (TargetPosition), and every projectile, creep
-- puddle, bomb and enemy it creates, tied to the spawner's animation, frame and state at that moment.
-- tools/recorder.py turns the lines into a behaviour profile per enemy (knowledge/behaviour_profiles.json).
-- Off unless the helper sends "record|1". Read-only: it never changes anything in the game.

local Recorder = { on = false, every = 2, maxEnemies = 12 }
local fmt = string.format

local function keyOf(e) return e.Type .. "." .. e.Variant end

local function spriteOf(e)
  local ok, a, fr = pcall(function()
    local sp = e:GetSprite()
    return sp:GetAnimation(), sp:GetFrame()
  end)
  if ok then return a or "", fr or -1 end
  return "", -1
end

-- one enemy: key,anim,frame,state,stateFrame,x,y,vx,vy,v1x,v1y,v2x,v2y,tx,ty,i1,i2,collision,hp,projCooldown,projDelay
-- (ProjectileCooldown / ProjectileDelay: the countdown to its next shot; suggested by a second opinion, 2026-11-26)
local function npcLine(e)
  local n = e.ToNPC and e:ToNPC()
  local a, fr = spriteOf(e)
  local p, v = e.Position, e.Velocity
  if not n then
    return fmt("%s,%s,%d,-1,-1,%.0f,%.0f,%.1f,%.1f,0,0,0,0,0,0,0,0,%d,%.0f,0,0", keyOf(e), a, fr, p.X, p.Y, v.X, v.Y,
               e.EntityCollisionClass, e.HitPoints)
  end
  local v1, v2, tp = n.V1, n.V2, n.TargetPosition
  return fmt("%s,%s,%d,%d,%d,%.0f,%.0f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.0f,%.0f,%d,%d,%d,%.0f,%d,%d", keyOf(e), a, fr,
             n.State, n.StateFrame, p.X, p.Y, v.X, v.Y, v1.X, v1.Y, v2.X, v2.Y, tp.X, tp.Y, n.I1, n.I2,
             e.EntityCollisionClass, e.HitPoints, n.ProjectileCooldown or 0, n.ProjectileDelay or 0)
end

-- what each enemy was doing last update (by entity), to log every animation/state change on the update it happens
local lastSeen = {}

-- who made it, and what that spawner was doing: key,anim,frame,state,stateFrame (or "-")
local function spawnerOf(e)
  local s = e.SpawnerEntity
  if not s then return "-" end
  local a, fr = spriteOf(s)
  local n = s.ToNPC and s:ToNPC()
  return fmt("%s,%s,%d,%d,%d", keyOf(s), a, fr, n and n.State or -1, n and n.StateFrame or -1)
end

local CREEP = {}
for _, name in ipairs({ "CREEP_RED", "CREEP_GREEN", "CREEP_YELLOW", "CREEP_WHITE", "CREEP_BLACK", "CREEP_BROWN",
                        "CREEP_SLIPPERY_BROWN", "CREEP_STATIC", "CREEP_LIQUID_POOP" }) do
  if EffectVariant[name] then CREEP[EffectVariant[name]] = name end
end

function Recorder.init(mod, send)
  Recorder.send = send

  mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not Recorder.on then return end
    local f = Game():GetFrameCount()
    local sample = (f % Recorder.every == 0)
    local parts, seen = {}, {}
    for _, e in ipairs(Isaac.GetRoomEntities()) do
      if e:IsActiveEnemy(false) and not e:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
         and not (e.Parent ~= nil and not e:IsVulnerableEnemy() and e.EntityCollisionClass == 0) then -- not cord balls
        -- every update: an animation or AI-state change is logged on the exact update it happens
        -- (from>to anim | from>to state | frame in the new anim | stateFrame | x,y)
        local h = GetPtrHash(e)
        seen[h] = true
        local a, fr = spriteOf(e)
        local n = e.ToNPC and e:ToNPC()
        local st = n and n.State or -1
        local was = lastSeen[h]
        if was and (was.a ~= a or was.s ~= st) then
          send("rectrans", fmt("%d|%s|%s>%s|%d>%d|%d|%d|%.0f,%.0f", f, keyOf(e), was.a, a, was.s, st, fr,
                                n and n.StateFrame or -1, e.Position.X, e.Position.Y))
        end
        lastSeen[h] = { a = a, s = st }
        if sample and #parts < Recorder.maxEnemies then parts[#parts + 1] = npcLine(e) end
      end
    end
    for h in pairs(lastSeen) do if not seen[h] then lastSeen[h] = nil end end
    if #parts == 0 then return end
    -- Isaac: position and velocity (velocity added 2026-11-26: the game code says his speed tops out ~4.4 x k, but he
    -- moves 7.7-11 px per update in our data - two movement steps per update, or a missed term? this settles it)
    local pl = Isaac.GetPlayer(0)
    local p, pv = pl.Position, pl.Velocity
    send("rec", fmt("%d|%.0f,%.0f,%.2f,%.2f|%s", f, p.X, p.Y, pv.X, pv.Y, table.concat(parts, ";")))
  end)

  -- projectiles on their first update (their arc values are set by then):
  -- variant|x,y|vx,vy|height,fallingSpeed,fallingAccel|scale|flags|spawner
  mod:AddCallback(ModCallbacks.MC_POST_PROJECTILE_UPDATE, function(_, pr)
    if not Recorder.on or pr.FrameCount ~= 1 then return end
    local p, v = pr.Position, pr.Velocity
    send("recshot", fmt("%d|%d|%.0f,%.0f|%.1f,%.1f|%.1f,%.2f,%.3f|%.2f|%s|%s", Game():GetFrameCount(), pr.Variant,
      p.X, p.Y, v.X, v.Y, pr.Height, pr.FallingSpeed, pr.FallingAccel, pr.Scale, tostring(pr.ProjectileFlags),
      spawnerOf(pr)))
  end)

  -- creep puddles: name|x,y|size|spawner
  mod:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, function(_, fx)
    if not Recorder.on or fx.FrameCount ~= 1 or not CREEP[fx.Variant] then return end
    local p = fx.Position
    send("reccreep", fmt("%d|%s|%.0f,%.0f|%.1f|%s", Game():GetFrameCount(), CREEP[fx.Variant], p.X, p.Y,
      fx.Size * math.max(1, fx.SpriteScale.X), spawnerOf(fx)))
  end)

  -- enemies made by other enemies: key|x,y|spawner
  mod:AddCallback(ModCallbacks.MC_POST_NPC_INIT, function(_, npc)
    if not Recorder.on or not npc.SpawnerEntity then return end
    local p = npc.Position
    send("recnpc", fmt("%d|%s|%.0f,%.0f|%s", Game():GetFrameCount(), keyOf(npc), p.X, p.Y, spawnerOf(npc)))
  end)

  -- bombs (troll bombs from enemies and the like): variant|x,y|spawner
  mod:AddCallback(ModCallbacks.MC_POST_BOMB_INIT, function(_, b)
    if not Recorder.on then return end
    local p = b.Position
    send("recbomb", fmt("%d|%d|%.0f,%.0f|%s", Game():GetFrameCount(), b.Variant, p.X, p.Y, spawnerOf(b)))
  end)
end

return Recorder
