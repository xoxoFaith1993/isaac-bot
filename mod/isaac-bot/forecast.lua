-- Forecast (forecast plan step 1, 2026-11-26; docs/FORECAST_PLAN.md, docs/CARDS.md). Where an enemy's BODY will be
-- over the next ~35 updates, from its card (knowledge/enemy_cards.json -> cards.lua): game facts read from the game's
-- code and checked against recordings, instead of a circle learned from watching. The author, 2026-11-26: "Imagine
-- having 60 behaviors and 5 of those conflict each other... Now multiply that by 5" - so facts go into PREDICTION
-- (each card on its own; two enemies' forecasts just add up), and the decisions stay a few fixed goals.
--
-- Plain numbers only (no game Vectors inside): it runs for every enemy, every sample time, every update, and the
-- offline card check (test/card_check.lua) runs it on thousands of recorded samples.
--
--   Forecast.body(card, s, t, isaac, bounds) -> x, y, sure
--     card   = a card's machine part (cards.lua), or nil
--     s      = the enemy now: { x, y, vx, vy, size, state, tx, ty } (tx/ty = TargetPosition)
--     t      = updates ahead
--     isaac  = { x, y, vx, vy } now
--     bounds = { x0, y0, x1, y1 } the room's floor (optional)
--   "sure" is how much to trust it: 1 = the card's rule applies, 0 = no rule, plain coasting.

local Forecast = { cards = {} }

function Forecast.setCards(c) Forecast.cards = c or {} end

function Forecast.cardFor(key) return Forecast.cards[key] end

local sqrt, min, max, abs = math.sqrt, math.min, math.max, math.abs

local function clampIn(x, y, b, pad)
  if not b then return x, y, false end
  local hit = false
  if x < b.x0 + pad then x, hit = b.x0 + pad, true elseif x > b.x1 - pad then x, hit = b.x1 - pad, true end
  if y < b.y0 + pad then y, hit = b.y0 + pad, true elseif y > b.y1 - pad then y, hit = b.y1 - pad, true end
  return x, y, hit
end

-- coast with friction (no rule): the enemy keeps its velocity, slowing by `f` each update
local function coast(s, t, f, b)
  local x, y, vx, vy = s.x, s.y, s.vx, s.vy
  for _ = 1, t do
    x, y = x + vx, y + vy
    vx, vy = vx * f, vy * f
  end
  x, y = clampIn(x, y, b, s.size or 10)
  return x, y
end

-- steer toward a fixed point: v <- v*f + a*dir, with a = speed*(1-f) so the steady speed is `speed`
-- (the game's one-step physics, decoded in Batch D and confirmed on 5,920 recorded pairs)
local function steer(s, t, gx, gy, speed, f, b, stopAt)
  local x, y, vx, vy = s.x, s.y, s.vx, s.vy
  local a = speed * (1 - f)
  for _ = 1, t do
    local dx, dy = gx - x, gy - y
    local d = sqrt(dx * dx + dy * dy)
    if d <= (stopAt or 0) then break end
    if d > 0.001 then dx, dy = dx / d, dy / d end
    vx, vy = vx * f + a * dx, vy * f + a * dy
    x, y = x + vx, y + vy
  end
  x, y = clampIn(x, y, b, s.size or 10)
  return x, y
end

-- straight line at constant speed, bouncing off the room's walls
local function bounce(s, t, b)
  local x, y, vx, vy = s.x, s.y, s.vx, s.vy
  local pad = s.size or 10
  for _ = 1, t do
    x, y = x + vx, y + vy
    if b then
      if x < b.x0 + pad then x, vx = 2 * (b.x0 + pad) - x, -vx elseif x > b.x1 - pad then x, vx = 2 * (b.x1 - pad) - x, -vx end
      if y < b.y0 + pad then y, vy = 2 * (b.y0 + pad) - y, -vy elseif y > b.y1 - pad then y, vy = 2 * (b.y1 - pad) - y, -vy end
    end
  end
  return x, y
end

local KIND = {}

KIND.pinned = function(m, s) return s.x, s.y, 1 end

KIND.chase = function(m, s, t, isaac, b)
  if not m.speed then return nil end
  local x, y = steer(s, t, isaac.x, isaac.y, m.speed, m.friction or 0.9, b, (s.size or 10) + 8)
  return x, y, 1
end
-- (the grid path isn't followed yet: within 70 px with a clear line it's the same straight chase)
KIND.path_chase = KIND.chase

KIND.lead_chase = function(m, s, t, isaac, b)
  if not m.speed then return nil end
  local k = m.lead or 0
  local x, y = steer(s, t, isaac.x + (isaac.vx or 0) * k, isaac.y + (isaac.vy or 0) * k, m.speed, m.friction or 0.9, b,
                     (s.size or 10) + 8)
  return x, y, 1
end

KIND.bounce = function(m, s, t, isaac, b)
  local x, y = bounce(s, t, b)
  return x, y, 1
end

-- straight runs along an axis that stop at walls; the run's end isn't known, so trust fades after ~10 updates
KIND.axis_walk = function(m, s, t, isaac, b)
  local x, y = coast(s, t, 1, b)
  return x, y, t <= 10 and 1 or 0.5
end
KIND.wander = function(m, s, t, isaac, b)
  local x, y = coast(s, t, m.friction or 0.9, b)
  return x, y, 0.5
end

-- hop: lands on its TargetPosition (the decoded rule; the recorder logs it as tx, ty)
KIND.hop = function(m, s, t, isaac, b)
  local tx, ty = s.tx or 0, s.ty or 0
  if tx == 0 and ty == 0 then return s.x, s.y, 0.5 end
  local air = m.air or 20
  local k = min(1, t / air)
  return s.x + (tx - s.x) * k, s.y + (ty - s.y) * k, 1
end

-- dart (spiders): picks a point (Isaac + 10 x his velocity, or a random spot) and darts there without re-aiming,
-- then idles. The point is in its TargetPosition while it darts and zero while it idles (recordings, 2026-11-26: the
-- card check found "lead_chase" 3x worse than coasting for the Big Spider, which re-aimed every update)
KIND.dart = function(m, s, t, isaac, b)
  local tx, ty = s.tx or 0, s.ty or 0
  if tx == 0 and ty == 0 then return s.x, s.y, 0.5 end
  local x, y = steer(s, t, tx, ty, m.dart_speed or 9, m.dart_friction or 0.8, b, m.stop or 14)
  return x, y, 1
end

-- charge along its row/column: charging now = keep going to the wall; idle with Isaac in its band and range = it
-- will charge at him along that axis; otherwise it idles (the band/range rule is decoded and recording-confirmed)
KIND.charge_line = function(m, s, t, isaac, b)
  local sp2 = s.vx * s.vx + s.vy * s.vy
  local idle = m.idle_speed or 1.5
  if sp2 > (idle * 2) ^ 2 then
    local x, y = coast(s, t, 1, b)
    return x, y, 1
  end
  local band, range = m.band or 20, m.range or 200
  local dx, dy = isaac.x - s.x, isaac.y - s.y
  local speed = m.speed or 10
  if abs(dy) < band and abs(dx) < range then
    local x = s.x + (dx > 0 and 1 or -1) * speed * t
    local y = s.y
    x, y = clampIn(x, y, b, s.size or 10)
    return x, y, 1
  elseif abs(dx) < band and abs(dy) < range then
    local y = s.y + (dy > 0 and 1 or -1) * speed * t
    local x = s.x
    x, y = clampIn(x, y, b, s.size or 10)
    return x, y, 1
  end
  local x, y = coast(s, t, m.friction or 0.9, b)
  return x, y, 1
end

function Forecast.body(card, s, t, isaac, bounds)
  local m = card and card.move
  local f = m and KIND[m.kind]
  if f then
    local x, y, sure = f(m, s, t, isaac, bounds)
    if x then return x, y, sure end
  end
  -- no rule: keep the current velocity (the card check, 2026-11-26: coasting with friction 0.9 was 2-4x worse than
  -- plain constant velocity on every recorded enemy without a card)
  local x, y = coast(s, t, 1, bounds)
  return x, y, 0
end

-- no damage right now (the card's no_damage_states): don't waste tears, and it's still dangerous to touch
function Forecast.immune(card, state)
  local nd = card and card.body and card.body.no_damage_states
  if not nd then return false end
  for _, st in ipairs(nd) do if st == state then return true end end
  return false
end

return Forecast
