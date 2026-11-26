-- Isaac Bot movement core v2 (2026-11-25). the author: "There has to be a better way... this still comes down to
-- fixing every little bug." The old core scored 33 moves 0.4 s ahead with ~40 hand-tuned weights (corners,
-- crowds, edges, runway, kiting, per-enemy fixes) that fought each other. This one has ONE movement goal:
--
--     never be where something could reach, over the next ~1.2 s
--
-- and it LEARNS how far each enemy type can get, from watching every room the bot plays:
--   * every update, for every enemy, it checks where that enemy really went 0.2 / 0.5 / 1 / 1.5 s after an
--     earlier moment, against two simple guesses: "keeps its velocity" (dashes, leaps, shots) and "stays put"
--     (random wanderers). Per enemy type it learns which guess fits, how much it drifts toward Isaac (chasers,
--     homing bosses) and a radius that holds 95% of the time. => a "could be here by then" circle.
--   * a new enemy type starts with a cautious circle and is learned after one room. No per-enemy code.
-- Movement: a small beam search over 3 chained moves (first move = one of the old 33, then 9 each), keeping the
-- best few at each step. Cost = overlap with those circles (sooner = surer = worse), enemy shots, lasers, bombs,
-- creep, spikes. Corners lose on their own: by the 3rd move the circles fill them and every way out is blocked.
-- Shooting is part of the same plan: being lined up with an open lane to the target is a reward.

local Danger = include("danger")
-- forecast plan step 2 (2026-11-26): enemy cards (game facts read from the code, checked against recordings) predict
-- where a body goes, for the move kinds where the card check showed them beating the learned guess
local Forecast = include("forecast")
local okCards, Cards = pcall(include, "cards")
Forecast.setCards(okCards and Cards or {})
local Mover = {}

local H = { 6, 15, 30, 45 } -- learned look-ahead points (updates; 30 = 1 s)
local RING = 64
local model = {}            -- "type.variant" -> { n = samples, [hi] = { [b] = { err, drift, rad } } }, b 1 = keep velocity, 2 = stay
local hist = {}             -- ptr hash -> { [f % RING] = { f, p, v, d } }
local seen = {}

-- per type.variant; shots also per shooter (Sloth's lob isn't a Gaper's straight shot)
local function key(e)
  if e.Type == EntityType.ENTITY_PROJECTILE then return "9." .. e.Variant .. "@" .. tostring(e.SpawnerType or 0) end
  return e.Type .. "." .. e.Variant
end

local function newStats()
  local m = { n = 0 }
  for hi = 1, #H do m[hi] = { { err = 0, drift = 0, rad = 0 }, { err = 0, drift = 0, rad = 0 } } end
  return m
end

-- One learning step: what we guessed h updates ago vs where the enemy is now.
local function learn(m, hi, b, guess, now, d)
  local s = m[hi][b]
  local err = now - guess
  local along = err:Dot(d)                      -- drift toward where Isaac was
  s.drift = s.drift * 0.98 + along * 0.02
  local res = (err - d * s.drift):Length()      -- what's left after the drift
  s.err = s.err * 0.98 + res * 0.02
  if s.rad == 0 then s.rad = res * 1.5 + 5 end  -- first sample: start generous, not at zero
  local step = math.max(1.5, s.rad * 0.05)       -- online 95th percentile (grows fast, shrinks slowly)
  s.rad = s.rad + ((res > s.rad) and step * 0.95 or -step * 0.05)
end

-- Called every update with the enemy list (whichever core is driving): learning never stops.
function Mover.observe(enemies, player, f, shots)
  local now = {}
  local all = enemies
  if shots and #shots > 0 then -- shots are learned the same way (their real paths, not a straight line)
    all = {}
    for _, e in ipairs(enemies) do all[#all + 1] = e end
    for _, s in ipairs(shots) do all[#all + 1] = s end
  end
  for _, e in ipairs(all) do
    if e.Type ~= EntityType.ENTITY_FIREPLACE and e.Position then
      local h = GetPtrHash(e)
      now[h] = true
      local ring = hist[h] or {}
      hist[h] = ring
      local k = key(e)
      local m = model[k]
      if not m then m = newStats(); model[k] = m end
      local d = player.Position - e.Position
      d = d:Length() > 1 and d:Normalized() or Vector(0, 0)
      for hi, hh in ipairs(H) do
        local r = ring[(f - hh) % RING]
        if r and r.f == f - hh then
          learn(m, hi, 1, r.p + r.v * hh, e.Position, r.d)
          learn(m, hi, 2, r.p, e.Position, r.d)
          if hi == 1 then m.n = m.n + 1 end
        end
      end
      ring[f % RING] = { f = f, p = e.Position, v = e.Velocity, d = d }
    end
  end
  for h in pairs(hist) do if not now[h] then hist[h] = nil end end
end

-- Where e could be t updates from now (t <= 45): centre and radius of the "could be here" circle.
function Mover.predict(e, t, toPlayer, bounce)
  local m = model[key(e)]
  -- position on the learned curve: between two learned points, or scaled down before the first
  local function at(hi, b)
    local s = m[hi][b]
    return s.drift, s.rad
  end
  local hi = 1
  while hi < #H and H[hi] < t do hi = hi + 1 end
  local lo = (hi > 1) and hi - 1 or nil
  local wHi = lo and (t - H[lo]) / (H[hi] - H[lo]) or (t / H[1])
  if wHi > 1 then wHi = 1 end
  local sp = e.Velocity:Length()
  local prior = (sp + 3) * t * 0.8 + 10 -- cautious circle until there's data
  if e.Type == EntityType.ENTITY_PROJECTILE then prior = 6 + t * 0.6 end -- shots: assume nearly straight at first
  local n = m and m.n or 0
  local b = 1
  if m and m[hi][2].err < m[hi][1].err then b = 2 end
  -- Moving FAST = a dash or charge: it keeps going straight (bouncing off walls), whatever the type usually does.
  -- (2026-11-25: Dingle stands still most of the fight, so its learned model said "stays put" even mid-dash, and the
  -- bot was hit by every dash. The author: "it gets hit deliberately every single time when he dashes.")
  local dashing = e.Type ~= EntityType.ENTITY_PROJECTILE and sp > (Mover.dashSpeed or 5)
  local drift, rad = 0, prior
  if dashing then
    -- a straight line we can be confident about: a tight circle along it, no drift toward where Isaac is now
    local base = e.Position + e.Velocity * t
    if bounce then base = bounce(base, e.Size) end
    return base, e.Size + 8 + t * 0.4
  end
  if n > 0 then
    local dh, rh = at(hi, b)
    local dl, rl = 0, 0
    if lo then dl, rl = at(lo, b) end
    drift = dl + (dh - dl) * wHi
    rad = rl + (rh - rl) * wHi
    if n < 60 then -- not much data yet: lean on the cautious circle
      local k = n / 60
      rad = rad * k + prior * (1 - k)
    end
  end
  local base = (b == 1) and (e.Position + e.Velocity * t) or e.Position
  if bounce then base = bounce(base, e.Size) end
  return base + toPlayer * drift, rad + e.Size
end

----------------------------------------------------------------- known AI: Dingle (Level 1, 2026-11-26)
-- From Dingle's real state machine (decompiled AI + recorder, docs/research/RE_PILOT.md; the author picked "Level 1
-- first"), instead of the learned "could be here" circle:
--   * provably still: Idle (state 3) in its first 30 updates, Tired (16, then 31+ more of Idle), Dance/Whistle/Spit
--     (10/9/8): just its body, for exactly that long;
--   * a dash coming: BeforeSlide (11) lasts 21 updates, then Slide frames 1-5 creep (~2 px/update), the push comes at
--     frame ~6 and covers ~225 px (11 rising to 19 px/update). It aims at Isaac's position when the aim locks
--     (S.dingle_lock updates before the push), no lead. So each simulated plan aims the line at ITSELF at the lock
--     moment: a plan that is off the line by then is safe - the late sidestep, done exactly.
-- Anything else falls back to the learned model. Off with S.predict_known = 0 (for the A/B).
local function dashDist(dt)
  if dt <= 0 then return 0 end
  return math.min(225, 11 * dt + 0.27 * dt * dt)
end

function Mover.knownZone(e, t, S, cache)
  if e.Type ~= 261 or e.Variant ~= 0 then return nil end
  -- (one dash per enemy per update, shared by every sample time: the plans' lock records key on it)
  if cache and cache[e] ~= nil then
    local z0 = cache[e]
    if z0 == false then return nil end
    if z0.still and t > z0.still then return nil end
    return z0
  end
  local n = e.ToNPC and e:ToNPC()
  if not n or n.State == nil then return nil end
  local st, sf = n.State, n.StateFrame or 0
  local pos = e.Position
  local still = nil
  if st == 3 and sf <= 30 then still = 31 - sf
  elseif st == 16 then still = math.max(0, 60 - sf) + 31
  elseif st == 8 or st == 9 or st == 10 then still = 20 end
  if still then
    local z = { c = pos, cx = pos.X, cy = pos.Y, r = (e.Size or 13) + 6, mover = true, known = true, still = still }
    if cache then cache[e] = z end
    if t > still then return nil end
    return z
  end
  local tp = nil
  if st == 11 then
    tp = math.max(0, 21 - sf) + 6
  else
    local okS, anim, fr = pcall(function() local sp = e:GetSprite(); return sp:GetAnimation(), sp:GetFrame() end)
    if okS and anim == "Slide" and e.Velocity:Length() < 5 then
      tp = (fr <= 5) and (6 - fr) or 8 -- (the pause between dashes: the next push comes soon)
    end
  end
  if not tp then
    if cache then cache[e] = false end
    return nil
  end
  local z = { c = pos, cx = pos.X, cy = pos.Y, r = (e.Size or 13) + 8, mover = true, known = true,
              dash = { x = pos.X, y = pos.Y, tp = tp, tl = math.max(0, tp - (S.dingle_lock or 5)) } }
  if cache then cache[e] = z end
  return z
end

-- Where a known dash puts its danger for this plan at time t: the closest point of the stretch slid so far.
local function dashPoint(dsh, px, py, t, lock)
  if t < dsh.tp then return dsh.x, dsh.y end
  local ax, ay = px, py
  if lock then
    local a = lock[dsh]
    if a then ax, ay = a[1], a[2] end
  end
  local dx, dy = ax - dsh.x, ay - dsh.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 1 then return dsh.x, dsh.y end
  dx, dy = dx / d, dy / d
  local along = (px - dsh.x) * dx + (py - dsh.y) * dy
  along = math.max(0, math.min(dashDist(t - dsh.tp), along))
  return dsh.x + dx * along, dsh.y + dy * along
end

----------------------------------------------------------------- search
-- Sample times along the three moves (updates from now): precomputed predictions are shared by all plans.
-- An enemy's "could be here" zone from its CARD (forecast plan step 2): the forecast body position, with a radius that
-- grows with time (and faster when the card's rule doesn't apply right now). Only for the move kinds listed in
-- forecast_kinds: the ones the card check (test/card_check.lua) showed beating the learned guess. Chasers keep the
-- learned circle and its "homes in on wherever Isaac goes" handling for now.
function Mover.cardZone(e, t, S, ctx)
  local card = Forecast.cardFor(e.Type .. "." .. e.Variant)
  local m = card and card.move
  if not m or not m.kind then return nil end
  if not (("," .. (S.forecast_kinds or "") .. ","):find("," .. m.kind .. ",", 1, true)) then return nil end
  local h = GetPtrHash(e)
  local s = ctx.fcCache[h]
  if not s then
    local p, v = e.Position, e.Velocity
    local n = e.ToNPC and e:ToNPC()
    local tp = n and n.TargetPosition
    local okF, fr = pcall(function() return e:GetSprite():GetFrame() end)
    s = { x = p.X, y = p.Y, vx = v.X, vy = v.Y, size = e.Size or 13, state = n and n.State or -1,
          tx = tp and tp.X or 0, ty = tp and tp.Y or 0, frame = okF and fr or 0 }
    ctx.fcCache[h] = s
  end
  if not ctx.fcIsaac then
    local pp, pv = ctx.player.Position, ctx.player.Velocity
    ctx.fcIsaac = { x = pp.X, y = pp.Y, vx = pv.X, vy = pv.Y }
    local tl, br = ctx.room:GetTopLeftPos(), ctx.room:GetBottomRightPos()
    ctx.fcBounds = { x0 = tl.X, y0 = tl.Y, x1 = br.X, y1 = br.Y }
  end
  local x, y, sure = Forecast.body(card, s, t, ctx.fcIsaac, ctx.fcBounds)
  local r = s.size + S.fc_pad + t * (S.fc_grow + (1 - sure) * S.fc_unsure)
  return { c = Vector(x, y), cx = x, cy = y, r = r, mover = true, card = true }
end

local SEG = { { 2, 4, 6, 8 }, { 11, 14, 17, 20 }, { 25, 30, 35 } }
local SEG_END = { 8, 20, 35 }

local function cost_at(ctx, p, si, t, parts, lock)
  local S, w = ctx.S, ctx.w
  local wt = 1 / (1 + t / S.m_decay)
  local c = 0
  -- (parts: optional table; each block's share is added under its name, for the "why" line's breakdown)
  local mark0 = 0
  local function mark(name)
    if parts then parts[name] = (parts[name] or 0) + (c - mark0) end
    mark0 = c
  end
  local pr = ctx.pr
  local at = ctx.byT[t]
  -- (plain numbers, not the game's Vectors: in the real game every Vector "-" or ":Length()" is a call into the engine,
  -- and these loops run for every plan at every sample time. 2026-11-26: Sloth, Gurglings and the Duke's fly swarm
  -- made each plan take 20-30 ms against the game's 33 ms an update, and the game stuttered)
  local px, py = p.X, p.Y
  local sqrt = math.sqrt
  for _, z in ipairs(at.z) do
    local zx, zy = z.cx, z.cy
    if z.dash then -- a known dash (Dingle): aimed at where this plan was when the aim locked
      if lock and t >= z.dash.tl and not lock[z.dash] then lock[z.dash] = { px, py } end
      zx, zy = dashPoint(z.dash, px, py, t, lock)
    elseif z.bx then -- a chaser: it drifts toward THIS plan's spot (as far as it can get in time t)
      local tx, ty = px - z.bx, py - z.by
      local len = sqrt(tx * tx + ty * ty)
      if len > 1 then
        local k = math.min(z.drift, len) / len
        zx, zy = z.bx + tx * k, z.by + ty * k
      else
        zx, zy = z.bx, z.by
      end
    end
    local ex, ey = px - zx, py - zy
    local margin = sqrt(ex * ex + ey * ey) - z.r - pr
    if margin < 0 then
      -- graded: full cost near the enemy, fading to m_edge_hit at the circle's edge (a 95% circle's edge is a small
      -- chance). With 3-4 flies the whole room sat inside flat full-cost circles, every option looked equally bad
      -- and it drifted into corners (2026-11-25). Small circles (sure things) stay full cost.
      local depth = math.min(1, -margin / math.max(1, z.r + pr))
      local f = (z.r > S.m_grade_r) and (S.m_edge_hit + (1 - S.m_edge_hit) * depth) or 1
      c = c + S.m_hit * wt * f
    elseif margin < S.m_soft then c = c + (S.m_soft - margin) * S.m_soft_w * wt end
  end
  mark("enemies")
  for _, sp in ipairs(at.s) do
    local sx, sy, rr = sp.cx - px, sp.cy - py, pr + sp.r
    if sx * sx + sy * sy < rr * rr then c = c + S.m_hit * wt end
  end
  mark("shots")
  -- an aimed shot coming (learned tells: Dingle's "Dance" before "Spit"): the line from the shooter through where
  -- Isaac is now gets costly from just before it fires, so it steps sideways off that line in time
  for _, a in ipairs(w.aimed or {}) do
    if t >= a.eta - 4 then
      local dir = a.at - a.from
      local len = dir:Length()
      if len > 1 then
        local rel = p - a.from
        local along = rel:Dot(dir) / len
        local perp = math.abs(rel.X * dir.Y - rel.Y * dir.X) / len
        local wide = S.aim_line_w + (a.size or 0) -- (34 px was thinner than Dingle's own body: every dash hit)
        if along > 0 and perp < wide then c = c + S.m_hit * 0.8 * wt * (1 - perp / wide) end
      end
    end
  end
  mark("attack lines")
  -- floor hazards (spikes, creep, fires, leftovers) and TNT "caution": asked once per 10 px patch per update
  -- (each is a call into the game; ~1,500 of them per update were most of the big-room lag)
  local hk = (p.X // 10) * 4096 + (p.Y // 10)
  local hz = ctx.hazMemo[hk]
  if not hz then
    -- the tiles under Isaac's EDGES too, not just his centre (hit review: spikes under the edge of his body
    -- counted as safe; two spike hits in one room, then the run died)
    local e = ctx.pr - 2
    local st = math.max(Danger.staticAt(p), Danger.staticAt(p + Vector(e, 0)), Danger.staticAt(p + Vector(-e, 0)),
                        Danger.staticAt(p + Vector(0, e)), Danger.staticAt(p + Vector(0, -e)))
    hz = { math.max(st, ctx.creepAt(w, p)), Danger.cautionAt(p) }
    ctx.hazMemo[hk] = hz
  end
  if hz[1] > 0 then c = c + hz[1] * S.danger_w * wt end
  -- TNT and other "caution" squares: not damage, just not places to stand around in
  if hz[2] > 0 then c = c + hz[2] * S.m_caution * wt end
  mark("floor")
  -- Learned tells (wired in 2026-11-25 after the v2 core forgot them: it parked in Sloth's row and ate the
  -- shot). In a shooter's line: a little cost always, nearly a hit's cost while it's winding up to fire.
  for _, ln in ipairs(ctx.lines) do
    local rx, ry = px - ln.x, py - ln.y
    local inRow, inCol = math.abs(ry) < ln.half, math.abs(rx) < ln.half
    local hit = (ln.only == "row" and inRow) or (ln.only == "col" and inCol) or (not ln.only and (inRow or inCol))
    local reach = ln.reach or 420
    if hit and rx * rx + ry * ry < reach * reach then
      if ln.charge then
        if ln.active ~= false then c = c + S.m_charge_line * wt end -- (tell-gated dashers: only while telling)
      elseif ln.gated then
        if ln.active then c = c + S.m_hit * 0.8 * wt end -- known wind-up playing: get out of the line now
      elseif ln.eta and t >= ln.eta - 6 then c = c + S.m_hit * 0.8 * wt
      else c = c + S.m_line * wt end
    end
  end
  mark("row/col lines")
  if t <= 10 then
    for _, lz in ipairs(w.lasers) do
      if ctx.segDist(p, lz.Position, ctx.laserEnd(lz)) < pr + 18 then c = c + S.m_hit * wt end
    end
  end
  mark("lasers")
  for _, bm in ipairs(ctx.bombXY) do -- (positions and radii read from the game once per update, in choose)
    local bx, by = bm[1] - px, bm[2] - py
    if bx * bx + by * by < bm[3] * bm[3] then c = c + S.m_hit * wt end
  end
  mark("bombs")
  return c
end

-- reward for being lined up with an open lane to the target at time t (only the soonest counts)
local function aimed(ctx, p, t)
  local tp = ctx.targetAt and ctx.targetAt(t)
  if not tp then return false end
  -- lead the shot: line up with where the target will be when a tear fired from p ARRIVES, not where it is at t
  -- (the author, 2026-11-25: "predictive shots on the Haunt need work": lined up with a boss moving ~7 px/update,
  -- every tear passed behind it)
  if ctx.tearSpeed and ctx.tearSpeed > 0 then
    local flight = (tp - p):Length() / ctx.tearSpeed
    tp = ctx.targetAt(t + flight) or tp
  end
  local rel = tp - p
  local size = (ctx.target.Size or 10) + 8 + ctx.S.loose_aim * 0.5 -- roughly in line counts (we spray)
  local ok = (math.abs(rel.X) < size or math.abs(rel.Y) < size) and rel:Length() < ctx.range
             and rel:Length() > 30
  return ok and ctx.lane(ctx.room, p, tp) < 2
end

local function blockedAt(ctx, q)
  local key = (q.X // 10) * 4096 + (q.Y // 10)
  local v = ctx.wallMemo[key]
  if v == nil then v = ctx.blocked(ctx.room, q, ctx.canFly) > 0; ctx.wallMemo[key] = v end
  return v
end

local function run(ctx, plan, si, dir)
  -- Move along `dir` through segment si's sample times with Isaac's REAL movement: he speeds up and turns over
  -- several updates (learned acceleration) up to his learned top speed. The old sim jumped to a guessed 4.6 px
  -- per update; his real top speed is ~7.7 (2026-11-25), so every plan put him in the wrong place. Walls stop him.
  local p0, v0 = plan.p, plan.v or ctx.vel
  local x, y, vx, vy = p0.X, p0.Y, v0.X, v0.Y -- (plain numbers inside the loop: see cost_at)
  local prevT = (si == 1) and 0 or SEG_END[si - 1]
  local c, aimT = 0, plan.aimT
  local tx, ty = dir.X * ctx.speed, dir.Y * ctx.speed
  local acc = ctx.acc
  local wallMemo, mWall = ctx.wallMemo, ctx.S.m_wall
  local dfx, dfy = ctx.driftX or 0, ctx.driftY or 0 -- an outside push (Mover.observeDrift)
  -- Isaac moves his Velocity TWICE per game update (recordings 2026-11-26: position change / |Velocity| = 1.97 over
  -- 4,159 pairs; enemies move it once). His top speed is learned from his Velocity, so without this the plans moved
  -- him at half his real speed. Setting isaac_steps (1 = the old sim, 2 = measured); A/B decides.
  local ksteps = ctx.ksteps or 1
  local lock = nil -- where this plan was when a known dash locked its aim (copied: branches must not share it)
  if ctx.hasDash then
    lock = {}
    for k, v in pairs(plan.lock or {}) do lock[k] = v end
  end
  local p = p0
  for _, t in ipairs(SEG[si]) do
    local dt = t - prevT
    for _ = 1, dt do
      vx, vy = vx + (tx - vx) * acc + dfx, vy + (ty - vy) * acc + dfy
      local nx, ny = x + vx * ksteps, y + vy * ksteps
      local key = (nx // 10) * 4096 + (ny // 10)
      local blk = wallMemo[key]
      if blk == nil then blk = blockedAt(ctx, Vector(nx, ny)) end
      if blk then vx, vy = 0, 0; c = c + mWall else x, y = nx, ny end
    end
    p = Vector(x, y)
    c = c + cost_at(ctx, p, si, t, nil, lock)
    if not aimT and ctx.target and t <= 20 and aimed(ctx, p, t) then aimT = t end
    prevT = t
  end
  return { p = p, v = Vector(vx, vy), c = plan.c + c, first = plan.first or dir, firstIdx = plan.firstIdx, aimT = aimT,
           lock = lock }
end

-- Learning Isaac's own movement: top speed (90th percentile of speed along the commanded direction while moving
-- at full speed) and acceleration (how much of the gap to the commanded velocity closes per update).
Mover.top, Mover.acc = nil, 0.35
local lastV = nil
function Mover.observePlayer(player, speedGuess)
  -- learned per 1.0 of Isaac's speed stat, so speed items carry over without re-learning
  local ms = math.max(0.3, player.MoveSpeed)
  local v = player.Velocity / ms
  speedGuess = speedGuess / ms
  local cmd = Mover.lastDir
  if cmd and lastV and cmd:Length() > 0.9 then
    local along = v:Dot(cmd:Normalized())
    local top = Mover.top or speedGuess
    if along > 1 then
      local step = math.max(0.05, top * 0.02)
      Mover.top = top + ((along > top) and step * 0.9 or -step * 0.1)
    end
    local goal = cmd:Normalized() * (Mover.top or speedGuess)
    local gap = goal - lastV
    if gap:Length() > 1.5 then
      local a = (v - lastV):Dot(gap) / gap:LengthSquared()
      if a > 0 and a < 1.2 then Mover.acc = math.max(0.08, math.min(1, Mover.acc * 0.97 + a * 0.03)) end
    end
  end
  lastV = v
end

-- Outside pushes on Isaac (the author, 2026-11-26: the bot's best run, Depths I, died to a Gaping Maw that "sucks in
-- air and it brings in Isaac" onto the spikes around it - 3 spike hits). The plans assumed Isaac moves only where we
-- steer him, so the pull was invisible. Measure it: each update, how Isaac really moved minus how our steering should
-- have moved him (same acceleration model as run()) = the outside force. Averaged, it's added to every simulated step.
-- No enemy list: suction, water currents, wind all show up the same way. Collisions (a wall stopping us) give big
-- jumps and are ignored; it fades within ~half a second once the push stops.
-- A real push is STEADY (same direction update after update); our own model error flips with every turn. So two
-- averages: a fast one and a slow one, and the push counts only when it's strong enough and both point the same way.
Mover.drift = Vector(0, 0)
local fastX, fastY, slowX, slowY = 0, 0, 0, 0
local lastVD, lastFD = nil, nil
function Mover.observeDrift(player, f)
  local v = player.Velocity
  local fresh = Mover.lastFrame and lastVD and lastFD and f - lastFD == 1 and f - Mover.lastFrame <= 2
  local rx, ry = 0, 0
  if fresh and Mover.lastDir then
    local acc = Mover.acc or 0.35
    local top = (Mover.top or 4.6) * math.max(0.3, player.MoveSpeed)
    local tx, ty = Mover.lastDir.X * top, Mover.lastDir.Y * top
    local ex, ey = lastVD.X + (tx - lastVD.X) * acc, lastVD.Y + (ty - lastVD.Y) * acc
    rx, ry = v.X - ex, v.Y - ey
    if rx * rx + ry * ry >= 9 then rx, ry = 0, 0 end -- (3+ px/update: a collision or a hit's knockback, not a push)
  end
  fastX, fastY = fastX * 0.7 + rx * 0.3, fastY * 0.7 + ry * 0.3
  slowX, slowY = slowX * 0.92 + rx * 0.08, slowY * 0.92 + ry * 0.08
  local sl = math.sqrt(slowX * slowX + slowY * slowY)
  local fl = math.sqrt(fastX * fastX + fastY * fastY)
  local agree = sl > 0 and fl > 0 and (slowX * fastX + slowY * fastY) / (sl * fl) > 0.7
  if sl > 0.3 and agree then Mover.drift = Vector(slowX, slowY) else Mover.drift = Vector(0, 0) end
  lastVD, lastFD = v, f
end

-- Ways out from where a plan ends (the author, 2026-11-25: "it's still falling back to corners as a safe place").
-- Being safe at the END of the plan isn't enough: can we still run a full second from there? Count the 8
-- directions with open floor that nothing could reach by then; every closed one costs. Corners close 3-5.
-- (speed: plans ending in the same 16 px patch share one answer, and each wall check is asked once per spot
-- per update; asking the game thousands of times per update made big rooms run at half speed)
local function waysOut(ctx, p)
  local S = ctx.S
  local mkey = (p.X // 16) * 4096 + (p.Y // 16)
  if ctx.waysMemo[mkey] then return ctx.waysMemo[mkey] end
  local zones = ctx.byT[35].z
  local closed = 0
  for k = 1, 8 do
    local dir = ctx.NEXT[k]
    for step = 1, 3 do
      local q = p + dir * (S.m_escape * step / 3)
      -- a WALL closes a way for good (counts double); an enemy might move off (counts once). Before, a room full of
      -- wide-moving enemies made every spot look as closed as a corner, so corners stopped looking bad (2026-11-25)
      local wall = blockedAt(ctx, q)
      local bad = wall
      if not bad then
        local qx, qy = q.X, q.Y
        for _, z in ipairs(zones) do
          -- the LIKELY spot, not the 95% worst case: a room of jumpy spiders made every way look closed and
          -- it fled open space instead of killing them (2026-11-25, the author: 'way too carefully')
          local dx, dy, rr = qx - z.cx, qy - z.cy, z.r * S.m_trap_r + ctx.pr
          if dx * dx + dy * dy < rr * rr then bad = true; break end
        end
      end
      if bad then closed = closed + (wall and 2 or 1); break end
    end
  end
  ctx.waysMemo[mkey] = closed
  return closed
end

-- Ring-kite (the author, 2026-11-25, Gemini: "slowly let him chase you... circle the outside of the room so you always
-- have a clear line of sight to attack him"; it ran too far and wasted its shooting chances). Against a chasing boss
-- the bot runs a LANE around the room: a rounded rectangle about ring_margin from the walls whose corners are arcs of
-- radius ring_r, so it cuts every corner instead of running into one. Two parts: stay on the lane, and keep moving
-- along it in one direction (away from the boss), so the boss follows at a steady distance and the open line behind
-- it is always there to shoot down.
local function ringCost(ctx, plan)
  local S, rg = ctx.S, ctx.ring
  -- distance from the inner rectangle (room shrunk by margin + radius): on the lane it equals the radius
  local x = math.max(rg.x0 - plan.p.X, 0, plan.p.X - rg.x1)
  local y = math.max(rg.y0 - plan.p.Y, 0, plan.p.Y - rg.y1)
  local dr = math.sqrt(x * x + y * y)
  -- keep a real GAP from the boss (2026-11-25: Gemini cut inside the lane at the corners and touched it 4 times in a
  -- minute): a plan ending near where the boss will be costs; with the boss already close, the lane loosens so it can
  -- cut across and get away instead of following the lane into it
  local c = 0
  if rg.boss then
    local bp = rg.boss + rg.bossVel * 20
    local d = (plan.p - bp):Length()
    if d < S.ring_gap then c = c + (S.ring_gap - d) * S.ring_gap_w end
  end
  local laneW = (rg.boss and (ctx.player.Position - rg.boss):Length() < S.ring_gap) and S.ring_w * 0.3 or S.ring_w
  c = c + math.abs(dr - rg.r) * laneW
  -- flow along the lane: angle gained around the room's middle, in the chosen direction
  local a0 = math.atan(ctx.player.Position.Y - rg.cy, ctx.player.Position.X - rg.cx)
  local a1 = math.atan(plan.p.Y - rg.cy, plan.p.X - rg.cx)
  local da = a1 - a0
  if da > math.pi then da = da - 2 * math.pi elseif da < -math.pi then da = da + 2 * math.pi end
  c = c - S.ring_flow * math.max(-1, math.min(1, da * rg.dir / 0.35))
  return c
end
Mover.ringCost = ringCost

local function total(ctx, plan)
  local S = ctx.S
  local c = plan.c
  -- at the planned firing spot the planner already judged it safe enough; a tight spot (a channel between rocks
  -- below a spider Sack) must not scare it off for good (2026-11-25: it hovered outside while the Sack spawned)
  local trapW = S.m_trap
  if ctx.spot and (plan.p - ctx.spot):Length() < 45 then trapW = trapW * 0.2 end
  if ctx.ring then trapW = trapW * 0.4 end -- the kite lane runs along the walls on purpose
  c = c + waysOut(ctx, plan.p) * trapW
  -- Cornered: a wall close on a left/right side AND on an up/down side. With fast movers about, the middle often looks
  -- as "closed" as a corner (their circles fill it), so the plain ways-out count stopped telling them apart and it
  -- parked in corners against flies (2026-11-25). This cost grows with the number of movers within 400 px.
  if S.m_corner > 0 and not (ctx.spot and (plan.p - ctx.spot):Length() < 45) then
    local ck = (plan.p.X // 16) * 4096 + (plan.p.Y // 16)
    local corner = ctx.cornerMemo[ck]
    if corner == nil then
      local r = S.corner_gap
      local side = blockedAt(ctx, plan.p + Vector(r, 0)) or blockedAt(ctx, plan.p + Vector(-r, 0))
      local vert = blockedAt(ctx, plan.p + Vector(0, r)) or blockedAt(ctx, plan.p + Vector(0, -r))
      corner = side and vert
      ctx.cornerMemo[ck] = corner
    end
    if corner then
      local movers = 0
      local qx, qy = plan.p.X, plan.p.Y
      for _, z in ipairs(ctx.byT[20].z) do
        local dx, dy = z.cx - qx, z.cy - qy
        if z.mover and dx * dx + dy * dy < 400 * 400 then movers = movers + 1 end
      end
      -- (only when something could pin us there: with nothing moving nearby a corner is harmless. 2026-11-26: in a
      -- cleared room its own bomb sat at its feet in a strip that led to two corners; the corner cost made standing
      -- by the bomb look better than running, and it blew itself up - the author: "it in fact had an escape route")
      if movers > 0 then c = c + S.m_corner * math.min(2.5, 0.5 + movers / 2) end
    end
  end
  -- steady pull to the room's middle and a cost near walls (the old core had these; A/B 2026-11-25: no deaths vs 2/4).
  -- Not at a planned firing spot by a wall (the planner chose it).
  if ctx.ring then
    c = c + ringCost(ctx, plan) -- ring-kite: the lane replaces the pull to the middle (they'd fight each other)
  elseif not (ctx.spot and (plan.p - ctx.spot):Length() < 45) then
    c = c + (plan.p - ctx.room:GetCenterPos()):Length() * S.m_center
    if not ctx.room:IsPositionInRoom(plan.p, S.edge_margin) then c = c + S.m_edge end
  end
  -- Escape readiness (the author's rule of thumb, 2026-11-25: "position yourself so it won't be that hard to put
  -- yourself out of harm's way when he does attack"): standing in a dasher's row/column, or in the line of a shot
  -- that's coming, is fine for shooting it, but only where the SIDESTEP is open. Each blocked side (wall, rock, pit
  -- within two steps) costs half of m_line_escape.
  if S.m_line_escape > 0 then
    local function sidesBlocked(p, perp)
      local n = 0
      for _, sg in ipairs({ 1, -1 }) do
        if blockedAt(ctx, p + perp * (sg * S.escape_step)) or blockedAt(ctx, p + perp * (sg * S.escape_step * 2)) then
          n = n + 1
        end
      end
      return n
    end
    for _, ln in ipairs(ctx.lines) do
      if ln.threat then
        local rel = plan.p - ln.pos
        local inRow, inCol = math.abs(rel.Y) < ln.half, math.abs(rel.X) < ln.half
        if (inRow or inCol) and rel:Length() < 420 then
          c = c + S.m_line_escape * sidesBlocked(plan.p, inRow and Vector(0, 1) or Vector(1, 0)) / 2
        end
      end
    end
    for _, a in ipairs(ctx.w.aimed or {}) do
      local d = plan.p - a.from
      if d:Length() > 1 and d:Length() < 420 then
        local u = d:Normalized()
        c = c + S.m_line_escape * sidesBlocked(plan.p, Vector(-u.Y, u.X)) / 2
      end
    end
  end
  -- flow: keep doing what we were doing unless something better is clearly there (no 30x-a-second twitching)
  -- Crowd pressure: how much enemy is near where the plan ends (closer counts more). With 18 enemies in a big room it
  -- only reacted to the ones that could reach it within 1.2 s, never went for the empty half of the room, and got
  -- pinned in a corner (2026-11-25). This makes it drift toward open space before the crowd closes in.
  local qx, qy = plan.p.X, plan.p.Y -- (plain numbers below: see cost_at)
  if S.m_crowd > 0 then
    local r2 = S.crowd_r2
    for _, z in ipairs(ctx.byT[20].z) do
      if z.mover then
        local dx, dy = z.cx - qx, z.cy - qy
        local d = math.sqrt(dx * dx + dy * dy)
        if d < r2 then c = c + S.m_crowd * (r2 - d) / r2 end
      end
    end
  end
  -- Sandwich (the author, 2026-11-25: two Gapers closing from both sides, it stayed in the middle when there was a way
  -- out): a plan that ends between two enemies (where they'll be in ~0.7 s) on opposite sides costs, more the closer
  -- they are, so it steps out of the line between them early.
  if S.m_pincer > 0 then
    local zs = ctx.byT[20].z
    for i = 1, #zs do
      local a = zs[i]
      if a.mover then
        local vax, vay = a.cx - qx, a.cy - qy
        local la = math.sqrt(vax * vax + vay * vay)
        if la < S.pincer_r and la > 1 then
          for j = i + 1, #zs do
            local b = zs[j]
            if b.mover then
              local vbx, vby = b.cx - qx, b.cy - qy
              local lb = math.sqrt(vbx * vbx + vby * vby)
              if lb < S.pincer_r and lb > 1 and (vax * vbx + vay * vby) / (la * lb) < -0.5 then
                -- fades with the distance from the line between them, so stepping off that line pays (offline test
                -- K3: with a flat cost every nearby spot paid about the same and it never stepped out)
                local abx, aby = b.cx - a.cx, b.cy - a.cy
                local len = math.sqrt(abx * abx + aby * aby)
                local perp = len > 1 and math.abs((qx - a.cx) * aby - (qy - a.cy) * abx) / len or 0
                local off = math.max(0, 1 - perp / S.pincer_w)
                c = c + S.m_pincer * (1 - (la + lb) / (2 * S.pincer_r)) * off
              end
            end
          end
        end
      end
    end
  end
  -- Something underground (a burrowing worm, Pin, mid-jump bosses): it surfaces where Isaac stands. Standing still
  -- while one is hidden costs extra (hit review #8: Pin and Gluttony hit it while it stood; a worm in an L room).
  if ctx.hidden > 0 and plan.firstIdx == 0 then c = c + S.m_burrow end
  -- Standing still with no open lane to the target never ends a fight. A rock pocket is cheap on danger, so against
  -- Round Worms popping up beyond the rocks it stood in one for half the fight (mirror chat, 2026-11-25: "shoot -"
  -- in 49% of frames). Standing costs extra whenever this plan never lines up a shot.
  if ctx.target and plan.firstIdx == 0 and not plan.aimT then c = c + S.m_nolane end
  -- turning costs by how sharp the turn is: a slight bend is nearly free, a reversal is expensive
  local nd, od = ctx.DIRS[plan.firstIdx], Mover.lastDir
  if od then
    local nl, ol = nd:Length(), od:Length()
    if nl > 0 and ol > 0 then
      c = c + S.m_turn * (1 - nd:Dot(od) / (nl * ol)) / 2
    elseif nl > 0 or ol > 0 then
      c = c + S.m_turn * 0.08 -- starting or stopping: cheap (a big cost here froze it in place)
    end
  end
  if ctx.target then
    -- lined up only pays off on a target we can hurt NOW. A closed Host: walk up to bait it open (prefDist is
    -- the bait distance then), don't stand across the room plinking tears off it.
    local t = ctx.target
    local hurtable = t.kind or not t.IsVulnerableEnemy or (t:IsVulnerableEnemy() and not t:IsInvincible())
                     or (IsaacBotRedFire and IsaacBotRedFire(t)) -- a red fire: tears put it out
    -- (in boss fights lining up counts more: the author, 2026-11-25, "you don't want to be in a boss fight for as long
    -- as possible... right now it's just taking the safest way while incrementally doing damage")
    if plan.aimT and hurtable then c = c - S.m_aim * (ctx.bossAim or 1) * (1 - plan.aimT / 30) end
    if ctx.prefDist then
      local tp = ctx.targetAt(SEG_END[1])
      if tp then c = c + math.abs((plan.p1 - tp):Length() - ctx.prefDist) * S.m_dist_w end
    end
    -- walled-in target: the old planner's firing square, as a gentle pull when it's calm
    -- (always on: 'calm only' meant it stood still while spiders hopped about; real danger still outweighs it)
    -- next step of the route for the first short move, and the FINAL firing spot for where the plan ends (comparing
    -- the 1.2 s end point with a step one tile ahead made every walking plan 'overshoot': it stood still)
  end
  -- the walking goal counts with or without a target (a button to press has none: 2026-11-25 it stood still in a
  -- room of buttons because this pull only applied when there was a target)
  if ctx.wayPos then c = c + (plan.p1 - ctx.wayPos):Length() * S.m_way * (ctx.calm and 1.5 or 1) end
  -- the planner's firing spot. When it's calm (no shots in the air, nothing moving close) COMMIT to it, as the old core
  -- did (calm_commit): v2's gentle pull lost to the spread-out circles of far-off spiders, and the bot stood in the
  -- open for minutes while four Sacks kept spawning, never walking to the square below them (2026-11-25).
  if ctx.spot then c = c + (plan.p - ctx.spot):Length() * S.m_way * 0.7 * (ctx.calm and S.calm_commit or 1) end
  return c
end

local NEXT = {}
for k = 1, 8 do
  local a = (k - 1) / 8 * 2 * math.pi
  NEXT[k] = Vector(math.cos(a), math.sin(a))
end
NEXT[9] = Vector(0, 0)

-- ctx: S, w, room, player, speed, DIRS, target, ledPos, prefDist, wayPos, calm + helper functions.
-- Returns the index into DIRS of the first move, and its plan cost.
-- where the time goes, per section (ms, summed; the perf line prints and clears it). 2026-11-25: Gemini on the bench
-- cost 30 ms an update in 1.2.28 (the game has 33), up from under 24 at most in 1.2.24, and the game lagged.
Mover.prof = Mover.prof or { pre = 0, b1 = 0, b23 = 0, stand = 0, dbg = 0, calls = 0 }
local now = Isaac.GetTime
function Mover.choose(ctx)
  local S, w, player = ctx.S, ctx.w, ctx.player
  local P, tp0 = Mover.prof, now()
  P.calls = P.calls + 1
  ctx.pr = player.Size
  ctx.vel = player.Velocity
  -- Isaac's learned movement (top speed per speed stat, acceleration); the old constant until it's learned
  ctx.ksteps = S.isaac_steps or 1
  if Mover.top then ctx.speed = Mover.top * math.max(0.3, player.MoveSpeed)
  else ctx.speed = ctx.speed / ctx.ksteps end -- (the starting guess is a distance per update, not a velocity)
  ctx.acc = Mover.acc
  -- a measured outside push, only when it's real (tiny noise isn't worth bending every plan for)
  local dr = Mover.drift
  if dr and dr.X * dr.X + dr.Y * dr.Y > 0.04 then ctx.driftX, ctx.driftY = dr.X, dr.Y else ctx.driftX, ctx.driftY = 0, 0 end
  ctx.canFly = player.CanFly
  ctx.range = math.max(120, player.TearRange * 0.95)
  -- precompute every enemy's "could be here" circle and every shot's spot at each sample time, once:
  -- all the plans share them (that's what keeps this fast)
  ctx.byT = {}
  ctx.arcMemo = {} -- lobbed shots' height per update ahead (one simulation per shot per update)
  ctx.knownCache, ctx.hasDash = {}, false -- known-AI zones (Dingle), one per enemy per update
  ctx.fcCache, ctx.fcIsaac = {}, nil -- card forecasts: each enemy's state read once per update
  for si = 1, 3 do
    for _, t in ipairs(SEG[si]) do
      local zs, ss = {}, {}
      for _, e in ipairs(w.enemies) do
        local kz = (S.predict_known or 0) ~= 0 and e.Type ~= EntityType.ENTITY_FIREPLACE
                   and Mover.knownZone(e, t, S, ctx.knownCache) or nil
        local fz = (not kz) and (S.forecast or 0) ~= 0 and e.Type ~= EntityType.ENTITY_FIREPLACE
                   and Mover.cardZone(e, t, S, ctx) or nil
        if fz then
          zs[#zs + 1] = fz -- its card's forecast (forecast.lua) instead of the learned circle
        elseif kz then
          zs[#zs + 1] = kz -- known AI (Dingle): its real state instead of the learned circle
          if kz.dash then ctx.hasDash = true end
        elseif e.Type == EntityType.ENTITY_FIREPLACE then
          local fp = e.Position
          zs[#zs + 1] = { c = fp, cx = fp.X, cy = fp.Y, r = e.Size + S.fire_pad }
        else
          local d = player.Position - e.Position
          d = d:Length() > 1 and d:Normalized() or Vector(0, 0)
          local c, r = Mover.predict(e, t, d, ctx.bounce)
          -- Chasers and dashers (playbook) home in on wherever Isaac GOES, not where he is now. Measured toward the
          -- current spot, a far corner looked safe from a room of Dart Flies, and it parked there and got hit
          -- (2026-11-25, the author: "it still parks itself in the corner when coming close to flies"). For these
          -- the drift is re-aimed at each plan's own position in cost_at.
          local pbz = ctx.playbookOf and ctx.playbookOf(e)
          local home = pbz and (pbz.tags.chases or pbz.tags.dashes_at_isaac) and not (w.pushed and w.pushed[GetPtrHash(e)])
          local base, drift = nil, 0
          if home then
            base = Mover.predict(e, t, Vector(0, 0), ctx.bounce)
            drift = (c - base):Length()
          end
          -- mid-"that" animation (one that has hurt us before, like a charge): give it more room
          if w.hurtful and w.hurtful[GetPtrHash(e)] then r = r * S.m_hurtful end
          -- the author's rule: flies get knocked back by tears. A light enemy in our line of fire won't reach us, so it
          -- stays about where it is (the v2 core lost this: it fled homing flies into corners, 2026-11-25)
          if w.pushed and w.pushed[GetPtrHash(e)] then
            c = e.Position
            r = math.min(r, e.Size + 12 + t * 0.5)
          end
          -- the watcher's lesson for this enemy: more berth after repeated body hits (brain\watcher.py)
          local lz = ctx.lessonOf and ctx.lessonOf(e)
          if lz and lz.margin then r = r + lz.margin end
          zs[#zs + 1] = { c = c, cx = c.X, cy = c.Y, r = r, mover = true, base = base, drift = drift,
                          bx = base and base.X, by = base and base.Y }
        end
      end
      for _, s in ipairs(w.shots) do
        -- learned per shot type and shooter (Sloth's shot hit while a straight line said "danger 0")
        local d = player.Position - s.Position
        d = d:Length() > 1 and d:Normalized() or Vector(0, 0)
        local c, r = Mover.predict(s, t, d, nil)
        -- + the watcher's margin for this shooter's shots (after repeated shot hits from it)
        local pad = ctx.shotPadOf and ctx.shotPadOf(s.SpawnerType) or 0
        -- + the blast of shots that burst when they land (rules.lua R.shot_blast: Sloth's)
        local blast = ctx.shotBlast and ctx.shotBlast[s.SpawnerType] or 0
        -- LOBBED shots (gravity > 0.3: Sloth's bombs) follow a known arc: height(t) = Height + FallingSpeed*t +
        -- FallingAccel*t^2/2. Recorder + decompiled AI, 2026-11-26: Sloth's lob (height -45, fall -21.9, gravity 1.02)
        -- isn't aimed at Isaac and lands ~1.5 s later where its own velocity takes it; both Sloth hits came at landing.
        -- So: harmless while high overhead, a blast at the landing spot around landing time, gone after.
        local pr = s.ToProjectile and s:ToProjectile()
        local acc = pr and pr.FallingAccel or 0
        local skip = false
        if acc > 0.3 then
          -- the game's own fall rule, per update (decompiled; checked against the recording, 2026-11-26):
          --   FallingSpeed = FallingAccel + 0.1 + 0.9 * FallingSpeed;  Height += FallingSpeed;  lands above -5
          -- simulated once per shot per update (the arc is the same for every plan)
          local arc = ctx.arcMemo[s]
          if not arc then
            local h, fs = pr.Height or 0, pr.FallingSpeed or 0
            arc = { tl = 90 }
            for k = 1, 90 do
              fs = acc + 0.1 + 0.9 * fs
              h = h + fs
              arc[k] = h
              if h > -5 then arc.tl = k; break end
            end
            ctx.arcMemo[s] = arc
          end
          local h = arc[math.min(t, arc.tl)] or 0
          if t > arc.tl + 3 or h < S.lob_overhead then
            skip = true
          else
            c = s.Position + s.Velocity * math.min(t, arc.tl)
          end
        end
        -- shots that explode on landing (the game's EXPLODE projectile flag, Sloth's lob among them) get the blast
        -- even without a per-shooter entry in rules.lua R.shot_blast
        if blast == 0 and pr and pr.HasProjectileFlags and ProjectileFlags and ProjectileFlags.EXPLODE then
          local okF, ex = pcall(pr.HasProjectileFlags, pr, ProjectileFlags.EXPLODE)
          if okF and ex then blast = S.explode_blast end
        end
        if not skip then
          ss[#ss + 1] = { c = c, cx = c.X, cy = c.Y, r = r + S.hit_margin + pad + blast }
        end
      end
      ctx.byT[t] = { z = zs, s = ss }
    end
  end

  if ctx.target then
    local tgt = ctx.target
    ctx.targetAt = function(t)
      if not tgt.Position then return nil end
      local v = (ctx.leadVel and ctx.leadVel(tgt)) or tgt.Velocity or Vector(0, 0)
      local q = tgt.Position + v * math.min(t, 30)
      -- it can't leave the room (fast movers like the Haunt turn at the walls): keep the guess inside
      if ctx.room.GetClampedPosition then q = ctx.room:GetClampedPosition(q, (tgt.Size or 10)) end
      return q
    end
    ctx.tearSpeed = S.tear_speed * math.max(0.5, player.ShotSpeed)
  end

  ctx.NEXT = NEXT
  ctx.wallMemo, ctx.waysMemo, ctx.hazMemo, ctx.cornerMemo = {}, {}, {}, {}
  -- shooters' lines (from the learned tells): with an open lane, and when it's winding up, how soon it fires
  -- hidden enemies: no collision right now (underground or in the air), not fires
  ctx.hidden = 0
  for _, e in ipairs(w.enemies) do
    if e.Type ~= EntityType.ENTITY_FIREPLACE and e.EntityCollisionClass == EntityCollisionClass.ENTCOLL_NONE then ctx.hidden = ctx.hidden + 1 end
  end
  ctx.lines = {}
  local winding = {}
  for _, wu in ipairs(w.windups or {}) do winding[GetPtrHash(wu.e)] = wu.eta end
  for _, e in ipairs(w.shooters or {}) do
    -- Rows and columns are only dangerous for shooters that fire ALONG them: 4-way crosses (Clotty), lasers, and
    -- fixed turrets (Stone Grimace). Shooters that aim at Isaac (Boils' bursts, lobbers, spreads, moving single
    -- shooters) are just as dangerous anywhere, and their row/column is where we must stand to shoot them: costing it
    -- kept the bot out of every Boil's line in a room of three Boils, and it hardly fired for minutes (2026-11-25).
    -- Their aimed shots are covered by the "shot coming" line (w.aimed) instead.
    local pb = ctx.playbookOf and ctx.playbookOf(e)
    local alongLines = true
    if pb then
      local t = pb.tags
      -- (only INVULNERABLE stationary single shooters are fixed turrets: a Horf stands still but aims at Isaac.
      -- 1.2.11 counted every stationary shooter: 4 Horfs made every row and column "dangerous", it found nowhere to
      -- shoot from and circled scared, 2026-11-25)
      alongLines = t.shoots_ring or t.laser or (t.shoots_single and t.invulnerable) or false
    end
    if e.Position and alongLines then
      local h = GetPtrHash(e)
      -- KNOWN wind-ups (boss tactics, from the game's animation events): the line only costs while one plays, and then
      -- like a hit, with the sidestep kept open (threat). The author, 2026-11-26, Gluttony: "it gets too scared of
      -- standing in front of him... take advantage of the windows that you got" - the always-on line cost kept it out
      -- of the only places it can shoot from (Isaac fires in 4 directions), and it barely attacked.
      local tacS = ctx.tacticsOf and ctx.tacticsOf(e)
      local gatedS = tacS and tacS.tells and next(tacS.tells) ~= nil
      ctx.lines[#ctx.lines + 1] = { pos = e.Position, half = (e.Size or 13) + 14, eta = winding[h],
                                    gated = gatedS or nil, active = gatedS and ctx.telling and ctx.telling(e) or nil,
                                    threat = gatedS or nil }
    end
  end
  -- enemies the playbook says charge or dash at Isaac: their row and column are costly. The author's rule of thumb
  -- (2026-11-25, Dingle): "take advantage of the time windows, and position yourself so it won't be that hard to get
  -- out of harm's way when he does attack" - it pre-positioned off Dingle's lines long before any tell and so never
  -- hit him. So: an enemy with KNOWN tells (boss tactics) makes its lines costly only while a tell is playing; one
  -- without (a plain Charger charges the moment you line up) keeps the old always-on cost. Being in the line is then
  -- fine, as long as the sidestep is open (escape readiness, total()).
  if ctx.playbookOf then
    for _, e in ipairs(w.enemies) do
      local pb = ctx.playbookOf(e)
      if pb and (pb.tags.charges_on_line or pb.tags.dashes_at_isaac) and e.Position then
        local tac0 = ctx.tacticsOf and ctx.tacticsOf(e)
        local gated = tac0 and tac0.tells and next(tac0.tells) ~= nil
        local active = (not gated) or (ctx.telling and ctx.telling(e))
        -- (measured trigger range for Chargers/Gurglings: rules.lua R.charge_reach; others keep the old 420 px)
        local reach = ctx.chargeReach and ctx.chargeReach[e.Type .. "." .. e.Variant]
        ctx.lines[#ctx.lines + 1] = { pos = e.Position, half = (e.Size or 13) + 16, charge = true, active = active,
                                      threat = true, reach = reach }
      end
      -- line attacks with KNOWN wind-ups that aren't learned "shooters" (a laser isn't a projectile, so Gluttony never
      -- became one and nothing warned of his belly laser, 2026-11-26): the gated line, only while a wind-up plays
      local tacL = ctx.tacticsOf and ctx.tacticsOf(e)
      if pb and (pb.tags.laser or pb.tags.shoots_ring) and tacL and tacL.tells and next(tacL.tells) ~= nil
         and e.Position then
        local dup = false
        for _, ln in ipairs(ctx.lines) do if ln.gated and ln.pos == e.Position then dup = true; break end end
        if not dup then
          ctx.lines[#ctx.lines + 1] = { pos = e.Position, half = (e.Size or 13) + 14, gated = true,
                                        active = ctx.telling and ctx.telling(e) or nil, threat = true }
        end
      end
      -- boss tactics: "stay diagonal" / "never in its row" / "never in its column" (Gurglings, Gluttony, The Fallen...)
      local tac = ctx.tacticsOf and ctx.tacticsOf(e)
      if tac and e.Position and (tac.diag or tac.row or tac.col) then
        local only = (tac.diag or (tac.row and tac.col)) and nil or (tac.row and "row" or "col")
        -- (same rule: with known wind-ups, only while one plays)
        local gatedT = tac.tells and next(tac.tells) ~= nil
        local activeT = (not gatedT) or (ctx.telling and ctx.telling(e)) or false
        ctx.lines[#ctx.lines + 1] = { pos = e.Position, half = (e.Size or 13) + 18, charge = true, only = only,
                                      active = activeT, threat = gatedT or nil }
      end
    end
  end
  for _, wu in ipairs(w.windups or {}) do -- a wind-up from something not (yet) known as a shooter counts too
    local found = false
    for _, ln in ipairs(ctx.lines) do if ln.pos == wu.e.Position then found = true end end
    if not found and wu.e.Position then
      ctx.lines[#ctx.lines + 1] = { pos = wu.e.Position, half = (wu.e.Size or 13) + 14, eta = wu.eta }
    end
  end
  -- plain numbers for the hot loops (cost_at, total): read from the game once per update, not once per plan
  for _, ln in ipairs(ctx.lines) do ln.x, ln.y = ln.pos.X, ln.pos.Y end
  ctx.bombXY = {}
  for _, bm in ipairs(w.bombs) do
    -- a bomb costs a FULL heart: full hit cost, measured from Isaac's edge, bigger for big bombs (Mr. Boom etc.)
    local big = BombVariant and (bm.Variant == BombVariant.BOMB_BIG or bm.Variant == BombVariant.BOMB_MR_MEGA)
    local bp = bm.Position
    ctx.bombXY[#ctx.bombXY + 1] = { bp.X, bp.Y, S.bomb_r + ctx.pr + (big and 40 or 0) }
  end
  -- the target's guessed spot per look-ahead time, asked once per update (aimed() asks for every plan)
  if ctx.targetAt then
    local raw, memo = ctx.targetAt, {}
    ctx.targetAt = function(t)
      local k = math.floor(t + 0.5)
      local v = memo[k]
      if v == nil then v = raw(k) or false; memo[k] = v end
      return v or nil
    end
  end
  -- move 1: full-speed directions + standing still; the slow "fine positioning" steps only when lining up a
  -- shot on a target that's close to lined up (creeping everywhere looked awkward and slow)
  local tp1 = now()
  P.pre = P.pre + (tp1 - tp0)
  local beam = {}
  local start = { p = player.Position, c = 0 }
  local half = math.floor(#ctx.DIRS / 2)
  local nearLine = false
  if ctx.target and ctx.target.Position then
    local rel = ctx.target.Position - player.Position
    nearLine = math.min(math.abs(rel.X), math.abs(rel.Y)) < 40
  end
  for i = 0, #ctx.DIRS do
    if i <= half or nearLine then
      local pl = run(ctx, { p = start.p, c = 0, firstIdx = i }, 1, ctx.DIRS[i])
      pl.firstIdx, pl.p1 = i, pl.p
      beam[#beam + 1] = pl
    end
  end
  -- trim by the FULL score (distance, aim, ways out, turning), not danger alone: with no danger around, every
  -- plan tied at 0 and it kept 6 random ones, none walking to the target (it stood at the wall vs a Host)
  for _, pl in ipairs(beam) do pl.s = total(ctx, pl) end
  table.sort(beam, function(a, b) return a.s < b.s end)
  local keep = {}
  local stand = nil
  for _, pl in ipairs(beam) do if pl.firstIdx == 0 then stand = pl end end
  for k = 1, math.min(S.m_beam, #beam) do keep[#keep + 1] = beam[k] end
  if stand then
    local has = false
    for _, pl in ipairs(keep) do if pl == stand then has = true end end
    if not has then keep[#keep + 1] = stand end
  end
  local tp2 = now()
  P.b1 = P.b1 + (tp2 - tp1)
  -- moves 2 and 3: 8 directions + stop, best few kept each time
  for si = 2, 3 do
    local nextBeam = {}
    for _, pl in ipairs(keep) do
      for k = 1, 9 do
        local np = run(ctx, pl, si, NEXT[k])
        np.firstIdx, np.p1 = pl.firstIdx, pl.p1
        nextBeam[#nextBeam + 1] = np
      end
    end
    for _, pl in ipairs(nextBeam) do pl.s = total(ctx, pl) end
    table.sort(nextBeam, function(a, b) return a.s < b.s end)
    keep = {}
    for k = 1, math.min(S.m_beam, #nextBeam) do keep[#keep + 1] = nextBeam[k] end
  end

  local tp3 = now()
  P.b23 = P.b23 + (tp3 - tp2)
  -- best full plan, aim and distance included; its first move is what we do now
  local best, bestC, bestPl = 0, math.huge, nil
  local standC = nil
  for _, pl in ipairs(keep) do
    local c = total(ctx, pl)
    if c < bestC then best, bestC, bestPl = pl.firstIdx, c, pl end
    if pl.firstIdx == 0 and (not standC or c < standC) then standC = c end
  end
  -- standing still for the whole plan, scored even when the beam dropped it: the reflexes need it to decide whether to
  -- stand for a sure shot (blind review 2026-11-25: under this core it was never passed back, so the "stand and shoot
  -- straight" and "plant your feet" checks could never fire and every tear was fired on the move)
  -- (ALWAYS the full stand-still plan: the cheapest plan that merely STARTS by standing is "stand now, flee later",
  -- which looked cheap every update, so it never fled - next to its own bomb, in Dingle's line after the tell)
  do
    local zero = ctx.DIRS[0] or Vector(0, 0)
    local sp = { p = player.Position, v = ctx.vel, c = 0, firstIdx = 0 }
    local p1 = nil
    for si = 1, 3 do
      sp = run(ctx, sp, si, zero)
      sp.firstIdx = 0
      p1 = p1 or sp.p
      sp.p1 = p1 -- (total() reads p1; without it the core errored and the bot fell back to the old core every update)
    end
    standC = total(ctx, sp)
  end
  Mover.lastStandC = standC
  Mover.lastHidden = ctx.hidden
  local tp4 = now()
  P.stand = P.stand + (tp4 - tp3)
  -- why it chose this (for the log): danger part, ways out, total; and the same for standing still
  if bestPl then
    -- what the danger is made of where Isaac stands now (all sample times): which source is driving the choice
    local parts, here = {}, {}
    for si = 1, 3 do for _, t in ipairs(SEG[si]) do cost_at(ctx, player.Position, si, t, parts) end end
    for k, v in pairs(parts) do if v >= 1 then here[#here + 1] = string.format("%s %.0f", k, v) end end
    table.sort(here)
    Mover.debug = string.format("best move %d: total %.0f (danger %.0f, closed ways %d, aim %s) | stand: %s | %d plans kept"
      .. " | danger here: %s",
      best, bestC, bestPl.c, waysOut(ctx, bestPl.p), tostring(bestPl.aimT), standC and string.format("%.0f", standC) or "pruned",
      #keep, #here > 0 and table.concat(here, ", ") or "none")
  end
  P.dbg = P.dbg + (now() - tp4)
  Mover.last = { move = best, cost = bestC }
  Mover.lastMove = best
  Mover.lastDir = ctx.DIRS[best]
  Mover.lastFrame = Game():GetFrameCount()
  return best, bestC, standC
end

----------------------------------------------------------------- memory across restarts
-- "key,n,b,drift,rad,b,drift,rad,..." per type (the better guess per look-ahead point), ";" between types
function Mover.dump()
  local out = {}
  for k, m in pairs(model) do
    if m.n >= 20 then
      local parts = { k, math.floor(m.n) }
      for hi = 1, #H do
        for b = 1, 2 do
          local s = m[hi][b]
          parts[#parts + 1] = string.format("%.1f,%.1f,%.1f", s.err, s.drift, s.rad)
        end
      end
      out[#out + 1] = table.concat(parts, ",")
    end
  end
  return table.concat(out, ";")
end

function Mover.load(text)
  local n = 0
  for entry in string.gmatch(text or "", "[^;]+") do
    local f = {}
    for v in string.gmatch(entry, "[^,]+") do f[#f + 1] = v end
    if #f >= 2 + #H * 2 * 3 then
      local m = newStats()
      m.n = math.min(tonumber(f[2]) or 0, 200) -- carried-over knowledge, but new play can still move it
      local i = 3
      for hi = 1, #H do
        for b = 1, 2 do
          m[hi][b] = { err = tonumber(f[i]) or 0, drift = tonumber(f[i + 1]) or 0, rad = tonumber(f[i + 2]) or 0 }
          i = i + 3
        end
      end
      model[f[1]] = m
      n = n + 1
    end
  end
  return n
end

-- Human-readable: per type, how far it can get in 0.5 s and 1 s, and its pull toward Isaac.
function Mover.report()
  local rows = {}
  for k, m in pairs(model) do
    if m.n >= 20 then
      local b2 = m[2][2].err < m[2][1].err and "wander" or "keeps going"
      rows[#rows + 1] = string.format("%s %s: 0.5s %.0fpx (drift %.0f), 1s %.0fpx (drift %.0f), n=%d", k, b2,
        m[2][(m[2][2].err < m[2][1].err) and 2 or 1].rad, m[2][(m[2][2].err < m[2][1].err) and 2 or 1].drift,
        m[3][(m[3][2].err < m[3][1].err) and 2 or 1].rad, m[3][(m[3][2].err < m[3][1].err) and 2 or 1].drift, m.n)
    end
  end
  table.sort(rows)
  return table.concat(rows, "; ")
end

return Mover
