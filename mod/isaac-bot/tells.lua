-- Isaac Bot "tells": learning enemy attack telegraphs from their animations, the way Elden Ring's summons
-- read a boss's animation instead of waiting for the hit (the author's idea, 2026-11-25).
--
-- Every enemy plays named animations from the game's own files ("Attack", "Shoot", "Jump"...). We watch:
--   * which animation an enemy was in when one of ITS shots appeared, and how many frames into it
--   * which animation it was in when it hurt us
-- and build a table per enemy type. Then, when an enemy starts an animation that usually ends in a shot
-- aimed at us, the reflexes move off the spot BEFORE the shot exists ("wind-up" = step aside).
-- Nothing per enemy is hand-written: the table fills itself from experience.

local Tells = { book = {}, cur = {}, lastReport = 0, trans = {} }
-- trans[type][from][to] = count: which animation follows which. An animation usually followed by one that
-- HURTS is a warning (Dingle: "BeforeSlide" -> "Slide", and Slide was 64 hits).

local function entry(etype, anim)
  local t = Tells.book[etype]
  if not t then t = {}; Tells.book[etype] = t end
  local r = t[anim]
  if not r then r = { seen = 0, shots = 0, hits = 0, lead = 0 }; t[anim] = r end
  return r
end

-- Call every update with the room's enemies.
function Tells.update(enemies)
  local f = Game():GetFrameCount()
  local alive = {}
  for _, e in ipairs(enemies) do
    if e.Type ~= EntityType.ENTITY_FIREPLACE then
      local h = GetPtrHash(e)
      alive[h] = true
      local ok, anim = pcall(function() return e:GetSprite():GetAnimation() end)
      if ok and anim and anim ~= "" then
        local c = Tells.cur[h]
        if not c or c.anim ~= anim then
          if c then -- remember the transition from the previous animation to this one
            local tt = Tells.trans[e.Type] or {}
            Tells.trans[e.Type] = tt
            tt[c.anim] = tt[c.anim] or {}
            tt[c.anim][anim] = (tt[c.anim][anim] or 0) + 1
          end
          Tells.cur[h] = { anim = anim, start = f, shot = false, type = e.Type }
          entry(e.Type, anim).seen = entry(e.Type, anim).seen + 1
        end
      end
    end
  end
  for h in pairs(Tells.cur) do if not alive[h] then Tells.cur[h] = nil end end
  -- fresh enemy shots: credit the animation their shooter was in
  for _, s in ipairs(Isaac.FindByType(EntityType.ENTITY_PROJECTILE)) do
    if s.FrameCount <= 1 and s.SpawnerEntity then
      local c = Tells.cur[GetPtrHash(s.SpawnerEntity)]
      if c and not c.shot then
        c.shot = true
        local r = entry(c.type, c.anim)
        r.shots = r.shots + 1
        r.lead = r.lead + (f - c.start)
      end
    end
  end
end

-- We got hurt by `src` (an entity): credit the animation it was in.
function Tells.onHit(src)
  if not src then return end
  local c = Tells.cur[GetPtrHash(src)]
  if c then entry(c.type, c.anim).hits = entry(c.type, c.anim).hits + 1 end
end

-- Is this enemy winding up an attack right now? (its current animation usually ends in a shot and we're
-- still before the usual moment). Returns frames until the shot is expected, or nil.
function Tells.windingUp(e)
  local c = Tells.cur[GetPtrHash(e)]
  if not c then return nil end
  local r = (Tells.book[c.type] or {})[c.anim]
  if not r or r.seen < 2 or r.shots / r.seen < 0.4 then return nil end
  local avgLead = r.lead / math.max(1, r.shots)
  local into = Game():GetFrameCount() - c.start
  if into > avgLead + 4 then return nil end
  return math.max(0, avgLead - into)
end

-- Save / load what's been learned, so it carries over between game launches (the helper keeps the file).
-- Format: "type,anim,seen,shots,hits,lead;..."  (anim names have no commas or semicolons)
function Tells.dump()
  local parts = {}
  for etype, anims in pairs(Tells.book) do
    for anim, r in pairs(anims) do
      if r.seen > 0 then
        parts[#parts + 1] = table.concat({ etype, anim, r.seen, r.shots, r.hits, r.lead }, ",")
      end
    end
  end
  for etype, froms in pairs(Tells.trans) do -- transitions: "T,type,from,to,count"
    for from, tos in pairs(froms) do
      for to, n in pairs(tos) do parts[#parts + 1] = table.concat({ "T", etype, from, to, n }, ",") end
    end
  end
  return table.concat(parts, ";")
end

function Tells.load(text)
  local n = 0
  for item in tostring(text):gmatch("[^;]+") do
    local tt, from, to, cnt = item:match("^T,(%d+),([^,]+),([^,]+),(%d+)$")
    if tt then
      local ty = tonumber(tt)
      Tells.trans[ty] = Tells.trans[ty] or {}
      Tells.trans[ty][from] = Tells.trans[ty][from] or {}
      Tells.trans[ty][from][to] = tonumber(cnt)
    end
    local t, anim, seen, shots, hits, lead = item:match("^(%d+),([^,]+),(%d+),(%d+),(%d+),(%d+)$")
    if t then
      local r = entry(tonumber(t), anim)
      r.seen, r.shots, r.hits, r.lead = tonumber(seen), tonumber(shots), tonumber(hits), tonumber(lead)
      n = n + 1
    end
  end
  return n
end

-- Is this enemy in an animation that has HURT us before (a charge, a slide, a body slam)?
-- Returns how often (hits), or nil. Gemini's walk and Dingle's slide killed it; Monstro's jump never did.
function Tells.hurtful(e)
  local c = Tells.cur[GetPtrHash(e)]
  if not c then return nil end
  local r = (Tells.book[c.type] or {})[c.anim]
  if r and r.hits > 0 then return r.hits end
  return nil
end

-- Is this enemy playing a WARNING animation: one that's usually followed by an animation that hurts us?
-- (learned from transitions; e.g. Dingle's "BeforeSlide" before its dash)
local function hurtRate(etype, anim)
  local r = (Tells.book[etype] or {})[anim]
  if not r or r.seen < 3 then return 0 end
  return r.hits / r.seen
end
function Tells.warning(e)
  local c = Tells.cur[GetPtrHash(e)]
  if not c then return false end
  if hurtRate(c.type, c.anim) > 0.1 then return false end -- it's the hurting animation itself, not a warning
  local nexts = (Tells.trans[c.type] or {})[c.anim]
  if not nexts then return false end
  local total, bad = 0, 0
  for to, n in pairs(nexts) do
    total = total + n
    if hurtRate(c.type, to) > 0.15 then bad = bad + n end
  end
  return total >= 3 and bad / total >= 0.5
end

-- Has this enemy TYPE been seen shooting at all? (any animation that produced a shot)
function Tells.isShooter(etype)
  for _, r in pairs(Tells.book[etype] or {}) do
    if r.shots > 0 then return true end
  end
  return false
end

-- Short text of what's been learned (for the log / knowledge file).
function Tells.report()
  local parts = {}
  for etype, anims in pairs(Tells.book) do
    for anim, r in pairs(anims) do
      if r.shots > 0 or r.hits > 0 then
        parts[#parts + 1] = string.format("%d:%s=%d/%d shots@%df,%d hits", etype, anim, r.shots, r.seen,
          math.floor(r.lead / math.max(1, r.shots)), r.hits)
      end
    end
  end
  return table.concat(parts, "; ")
end

return Tells
