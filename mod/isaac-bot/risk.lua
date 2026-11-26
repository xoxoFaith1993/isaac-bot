-- Isaac Bot risk layer: how much can we afford to risk RIGHT NOW? (the author, 2026-11-25: "it is taking such a
-- safe route that it's unbearable to watch. We need to be able to play risky... is it worth playing risky? Do I have
-- soul hearts so I don't lose my devil deal chance? Will playing risky kill me? Risky does not mean reckless.")
--
-- One number, Risk.level, 0 (careful) .. 1 (bold), worked out from the whole run, not the room:
--   * would a hit kill us / leave us one hit from death?    -> careful, always (the death guard caps everything)
--   * would a hit cost the floor's devil/angel deal chance? -> only RED-heart damage does (Repentance). Soul and
--     black hearts are lost first, Holy Mantle blocks a hit, floor 1 has no deal, a floor already red-damaged has
--     nothing left to lose. Deal at stake -> stay as careful as before.
--   * how many hits of buffer do we have?                    -> more buffer = bolder
--   * how strong are we against this room?                   -> quick kills = go and end it
--   * Level 2, pace: a room taking much longer than our damage says it should -> push harder (within the caps)
-- Risk.level then scales the movement core's safety settings between "careful" and "bold" (Risk.KNOBS). 0.25 is
-- exactly the old behaviour, so tuned values keep their meaning.
local Risk = { level = 0.25, why = "start", base = nil, lastSent = -1, room = nil }

-- knob = how its multiplier moves per unit of risk away from 0.25 (negative = smaller when bold)
Risk.KNOBS = {
  m_hit = -0.8,          -- cost of being inside a 'could be here' circle
  m_soft = -0.9,         -- margin wanted outside the circles
  m_edge_hit = -0.6,     -- uncertain (graded) circles count less
  m_crowd = -1.0,        -- drifting away from enemies
  m_pincer = -0.7,       -- the sandwich rule
  m_trap = -0.6,         -- closed ways out
  m_edge = -0.6,         -- ending near a wall
  m_center = -0.6,       -- pull to the middle
  plan_clearance = -0.6, -- gap from moving enemies at firing spots
  still_clearance = -0.7,
  stand_safe_r = -0.6,   -- stand still to shoot unless a mover is this close
  calm_r = -0.6,
  relax_s = -0.9,        -- seconds without a firing spot before loosening up
  pref_dist = -0.4,      -- fight closer (more tears land)
  m_aim = 0.9,           -- lining up a shot is worth more
  loose_aim = 0.9,       -- spray at things roughly in line
  -- not scaled by risk (slope 0), but switched off during an invincible window (below)
  m_corner = 0, m_charge_line = 0, boss_dist = 0, kite_r = 0,
}
local NEUTRAL = 0.25

-- Invincible window (Unicorn Stump, Book of Shadows, My Little Unicorn, Gamekid: rules.lua R.invincible): nothing can
-- hurt us for a few seconds, so dodging is wasted time. These settings go to (almost) zero; "ram" items also fight
-- at point-blank range on purpose (contact hurts the enemy). The last few updates it plays normal again.
local INVINCIBLE = { m_hit = 0.02, m_soft = 0, m_edge_hit = 0, m_crowd = 0, m_pincer = 0, m_trap = 0, m_edge = 0,
                     m_corner = 0, m_charge_line = 0, plan_clearance = 0, still_clearance = 0, stand_safe_r = 0,
                     calm_r = 0, relax_s = 0.2, kite_r = 0 }
local WINDOW = { m_aim = 2.5, loose_aim = 1.5, pref_dist = 0.65, boss_dist = 0.65, m_soft = 0.5, m_crowd = 0.3,
                 m_trap = 0.5, m_corner = 0.5, m_edge = 0.5, m_center = 0.5, plan_clearance = 0.6, relax_s = 0.3 }
local R = include("rules")
function Risk.invincibleNow(p)
  local kind, left = nil, 0
  pcall(function()
    local fx = p:GetEffects()
    for id, k in pairs(R.invincible or {}) do
      if fx:HasCollectibleEffect(id) then
        local e = fx:GetCollectibleEffect(id)
        local cd = (e and e.Cooldown) or 999
        if cd > (R.invincible_stop or 20) then kind, left = k, cd end
      end
    end
  end)
  return kind, left
end

-- settings that are not in Reflex.S get skipped; base values come from S the first time (and Reflex.set updates them)
function Risk.apply(S)
  if not Risk.base then
    Risk.base = {}
    for k in pairs(Risk.KNOBS) do if S[k] ~= nil then Risk.base[k] = S[k] end end
  end
  local r = Risk.level
  for k, slope in pairs(Risk.KNOBS) do
    local b = Risk.base[k]
    if b then S[k] = b * math.max(0.2, 1 + slope * (r - NEUTRAL)) end
  end
  -- a boss attack window (boss tactics): line up and close in. Hits still cost in full (real shots still hurt), but
  -- aiming is worth much more and the comfort costs (crowd, corners, ways out, margins) mostly drop.
  if Risk.window and not Risk.invincible then
    for k, mult in pairs(WINDOW) do
      if Risk.base[k] then S[k] = S[k] * mult end
    end
  end
  if Risk.invincible then
    for k, mult in pairs(INVINCIBLE) do
      if Risk.base[k] then S[k] = Risk.base[k] * mult end
    end
    if Risk.base.pref_dist then S.pref_dist = (Risk.invincible == "ram") and 10 or 60 end -- point-blank
    if Risk.base.boss_dist then S.boss_dist = 60 end
  end
end

-- a live "set" of a scaled setting changes its BASE (the scaled value follows)
function Risk.setBase(key, value)
  if Risk.base and Risk.base[key] ~= nil then Risk.base[key] = value end
end

local function stageNow()
  local ok, s = pcall(function() return Game():GetLevel():GetStage() end)
  return ok and s or 1
end

-- red-heart damage on this floor so far (the game's own flag when the API has it, else our own record)
local redHitFloor = {}
local function floorKey()
  local ok, k = pcall(function()
    local l = Game():GetLevel()
    return l:GetStage() .. "." .. l:GetStageType() .. "." .. Game():GetSeeds():GetStartSeed()
  end)
  return ok and k or "?"
end
local function redDamagedThisFloor()
  local ok, yes = pcall(function()
    return Game():GetLevel():GetStateFlag(LevelStateFlag.STATE_REDHEART_DAMAGED)
  end)
  if ok and yes ~= nil then return yes or redHitFloor[floorKey()] == true end
  return redHitFloor[floorKey()] == true
end

local function hasMantle(p)
  local ok, yes = pcall(function()
    return p:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_HOLY_MANTLE)
  end)
  return ok and yes or false
end

-- Hearts as the game spends them: soul/black (and bone) hearts go before red ones.
function Risk.hearts(p)
  local h = { red = 0, soul = 0, bone = 0, mantle = false }
  pcall(function()
    h.red = p:GetHearts()
    h.soul = p:GetSoulHearts()
    h.bone = p:GetBoneHearts()
  end)
  h.mantle = hasMantle(p)
  return h
end

-- Called when Isaac is about to take damage: remember if it lands on a red heart.
function Risk.onHit(p)
  local h = Risk.hearts(p)
  if not h.mantle and h.soul == 0 and h.bone == 0 then redHitFloor[floorKey()] = true end
end

-- What a hit costs in half hearts on this floor (later floors hit for a full heart).
-- (log 2026-11-25: a floor-3 boss hit took a full heart) Counted on the safe side.
local function hitSize(stage, isBoss) return (stage >= 5 or (isBoss and stage >= 3)) and 2 or 1 end

-- Level 2: pace. Expected clear time from our damage against the room's enemy HP (counting a 50% hit rate).
local pace = { room = nil, start = 0, maxHp = 0 }
local function paceBoost(p, enemies, f)
  local roomIdx = Game():GetLevel():GetCurrentRoomIndex()
  if pace.room ~= roomIdx then pace.room, pace.start, pace.maxHp = roomIdx, f, 0 end
  local hp = 0
  for _, e in ipairs(enemies or {}) do
    if e.HitPoints and e.Type ~= EntityType.ENTITY_FIREPLACE and e:IsVulnerableEnemy() then hp = hp + e.HitPoints end
  end
  if hp <= 0 then pace.start = f; pace.maxHp = 0; return 0, 0 end -- nothing to fight: the clock restarts
  pace.maxHp = math.max(pace.maxHp, hp)
  local dps = math.max(0.5, p.Damage * 30 / (p.MaxFireDelay + 1))
  local expected = 5 + 2 * pace.maxHp / dps
  local elapsed = (f - pace.start) / 30
  local quick = (hp / dps < 3) and 0.1 or 0 -- a few tears end it: go and end it
  if elapsed <= expected then return quick, expected end
  return quick + math.min(0.3, 0.3 * (elapsed - expected) / expected), expected
end

-- Work out Risk.level for this moment. `enemies` = the room's live enemies (for pace and strength).
function Risk.update(p, enemies)
  local f = Game():GetFrameCount()
  local stage = stageNow()
  local h = Risk.hearts(p)
  local isBoss = false
  pcall(function() isBoss = Game():GetRoom():GetType() == RoomType.ROOM_BOSS end)
  local hit = hitSize(stage, isBoss)
  local hp = h.red + h.soul + h.bone * 2
  local hitsLeft = hp / hit + (h.mantle and 1 or 0)
  local dealFloor = stage >= 2 and stage <= 8
  local redNext = not h.mantle and h.soul == 0 and h.bone == 0 and h.red > 0
  local atStake = dealFloor and redNext and not redDamagedThisFloor()

  local r, why
  if atStake then
    r, why = 0.25, "deal at stake (red hearts next)"
  else
    -- the buffer: 3 hits left = 0.35 (barely bolder than before), 8+ hits = 0.85
    r = 0.25 + 0.1 * math.min(6, math.max(0, hitsLeft - 2))
    why = (not dealFloor) and "no deal on this floor" or (h.mantle and "mantle up") or
          (h.soul > 0 or h.bone > 0) and "soul/bone hearts first" or "deal already lost"
    if h.mantle then r = r + 0.15 end
    if isBoss then r = r - 0.1 end
  end
  -- Level 3: the build's strength for this floor (strategy.lua): strong ends fights fast, weak stays careful
  local St = IsaacBotStrategy
  if St then
    pcall(St.update, p)
    local nudge = St.riskNudge()
    if atStake and nudge > 0 then nudge = 0 end -- the deal outranks a strong build
    if nudge ~= 0 then r = r + nudge; why = why .. string.format(", build %+.1f", nudge) end
  end
  local push, expected = paceBoost(p, enemies, f)
  if push > 0 then r = r + push; why = why .. string.format(", pace +%.2f (expect %.0fs)", push, expected) end
  -- caps: the deal and death always win over pace
  if atStake then r = math.min(r, 0.45) end
  if hitsLeft <= 1 then r, why = 0, "one hit from death"
  elseif hitsLeft <= 2 then r = math.min(r, 0.15); why = why .. ", two hits left: careful" end
  Risk.level = math.max(0, math.min(1, r))
  Risk.why = why
  -- pinned (offline tests, A/B on the bench: "risk 0.25" = the old fixed behaviour); the death guard still wins
  if Risk.pin then
    Risk.level = (hitsLeft <= 1) and 0 or Risk.pin
    Risk.why = "pinned " .. Risk.pin
  end
  Risk.atStake = atStake
  return Risk.level
end

-- Level 3, step 5: optional risky rooms (rules.lua `when`). Can we afford it right now?
--   curse: the door takes a hit going in (and out). OK with soul/bone hearts or mantle in front, or no deal at stake,
--          and 3+ hearts of health so the two hits never get close to death.
--   challenge: waves of enemies. OK when the deal isn't at stake, health is 3+ hearts and the build is at least
--          average for this floor.
function Risk.allows(kind, p)
  if not p then return false end
  local h = Risk.hearts(p)
  local hp = h.red + h.soul + h.bone * 2
  local shielded = h.mantle or h.soul > 0 or h.bone > 0
  if kind == "curse" then
    return hp >= 6 and (shielded or not Risk.atStake)
  end
  if kind == "challenge" then
    local St = IsaacBotStrategy
    local strong = St and St.profile and St.profile.strength >= 1.0
    return hp >= 6 and not Risk.atStake and strong and true or false
  end
  return false
end

return Risk
