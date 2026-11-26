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
  local drift, rad = 0, prior
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

----------------------------------------------------------------- search
-- Sample times along the three moves (updates from now): precomputed predictions are shared by all plans.
local SEG = { { 2, 4, 6, 8 }, { 11, 14, 17, 20 }, { 25, 30, 35 } }
local SEG_END = { 8, 20, 35 }

local function cost_at(ctx, p, si, t)
  local S, w = ctx.S, ctx.w
  local wt = 1 / (1 + t / S.m_decay)
  local c = 0
  local pr = ctx.pr
  local at = ctx.byT[t]
  for _, z in ipairs(at.z) do
    local zc = z.c
    if z.base then -- a chaser: it drifts toward THIS plan's spot (as far as it can get in time t)
      local to = p - z.base
      local len = to:Length()
      zc = (len > 1) and (z.base + to * (math.min(z.drift, len) / len)) or z.base
    end
    local margin = (p - zc):Length() - z.r - pr
    if margin < 0 then
      -- graded: full cost near the enemy, fading to m_edge_hit at the circle's edge (a 95% circle's edge is a small
      -- chance). With 3-4 flies the whole room sat inside flat full-cost circles, every option looked equally bad
      -- and it drifted into corners (2026-11-25). Small circles (sure things) stay full cost.
      local depth = math.min(1, -margin / math.max(1, z.r + pr))
      local f = (z.r > S.m_grade_r) and (S.m_edge_hit + (1 - S.m_edge_hit) * depth) or 1
      c = c + S.m_hit * wt * f
    elseif margin < S.m_soft then c = c + (S.m_soft - margin) * S.m_soft_w * wt end
  end
  for _, sp in ipairs(at.s) do
    if (sp.c - p):Length() < pr + sp.r then c = c + S.m_hit * wt end
  end
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
        if along > 0 and perp < S.aim_line_w then c = c + S.m_hit * 0.8 * wt * (1 - perp / S.aim_line_w) end
      end
    end
  end
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
  -- Learned tells (wired in 2026-11-25 after the v2 core forgot them: it parked in Sloth's row and ate the
  -- shot). In a shooter's line: a little cost always, nearly a hit's cost while it's winding up to fire.
  for _, ln in ipairs(ctx.lines) do
    local rel = p - ln.pos
    local inRow, inCol = math.abs(rel.Y) < ln.half, math.abs(rel.X) < ln.half
    local hit = (ln.only == "row" and inRow) or (ln.only == "col" and inCol) or (not ln.only and (inRow or inCol))
    if hit and rel:Length() < 420 then
      if ln.charge then c = c + S.m_charge_line * wt
      elseif ln.eta and t >= ln.eta - 6 then c = c + S.m_hit * 0.8 * wt
      else c = c + S.m_line * wt end
    end
  end
  if t <= 10 then
    for _, lz in ipairs(w.lasers) do
      if ctx.segDist(p, lz.Position, ctx.laserEnd(lz)) < pr + 18 then c = c + S.m_hit * wt end
    end
  end
  for _, bm in ipairs(w.bombs) do
    -- a bomb costs a FULL heart: full hit cost, measured from Isaac's edge, bigger for big bombs (Mr. Boom etc.)
    local big = BombVariant and (bm.Variant == BombVariant.BOMB_BIG or bm.Variant == BombVariant.BOMB_MR_MEGA)
    local br = S.bomb_r + pr + (big and 40 or 0)
    if (bm.Position - p):Length() < br then c = c + S.m_hit * wt end
  end
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
  local p, v = plan.p, plan.v or ctx.vel
  local prevT = (si == 1) and 0 or SEG_END[si - 1]
  local c, aimT = 0, plan.aimT
  local target = dir * ctx.speed
  local acc = ctx.acc
  for _, t in ipairs(SEG[si]) do
    local dt = t - prevT
    for _ = 1, dt do
      v = v + (target - v) * acc
      local np = p + v
      if blockedAt(ctx, np) then v = Vector(0, 0); c = c + ctx.S.m_wall else p = np end
    end
    c = c + cost_at(ctx, p, si, t)
    if not aimT and ctx.target and t <= 20 and aimed(ctx, p, t) then aimT = t end
    prevT = t
  end
  return { p = p, v = v, c = plan.c + c, first = plan.first or dir, firstIdx = plan.firstIdx, aimT = aimT }
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
        for _, z in ipairs(zones) do
          -- the LIKELY spot, not the 95% worst case: a room of jumpy spiders made every way look closed and
          -- it fled open space instead of killing them (2026-11-25, the author: 'way too carefully')
          if (q - z.c):Length() < z.r * S.m_trap_r + ctx.pr then bad = true; break end
        end
      end
      if bad then closed = closed + (wall and 2 or 1); break end
    end
  end
  ctx.waysMemo[mkey] = closed
  return closed
end

local function total(ctx, plan)
  local S = ctx.S
  local c = plan.c
  -- at the planned firing spot the planner already judged it safe enough; a tight spot (a channel between rocks
  -- below a spider Sack) must not scare it off for good (2026-11-25: it hovered outside while the Sack spawned)
  local trapW = S.m_trap
  if ctx.spot and (plan.p - ctx.spot):Length() < 45 then trapW = trapW * 0.2 end
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
      for _, z in ipairs(ctx.byT[20].z) do
        if z.mover and (z.c - plan.p):Length() < 400 then movers = movers + 1 end
      end
      c = c + S.m_corner * math.min(2.5, 0.5 + movers / 2)
    end
  end
  -- steady pull to the room's middle and a cost near walls (the old core had these; A/B 2026-11-25: no deaths vs 2/4).
  -- Not at a planned firing spot by a wall (the planner chose it).
  if not (ctx.spot and (plan.p - ctx.spot):Length() < 45) then
    c = c + (plan.p - ctx.room:GetCenterPos()):Length() * S.m_center
    if not ctx.room:IsPositionInRoom(plan.p, S.edge_margin) then c = c + S.m_edge end
  end
  -- flow: keep doing what we were doing unless something better is clearly there (no 30x-a-second twitching)
  -- Crowd pressure: how much enemy is near where the plan ends (closer counts more). With 18 enemies in a big room it
  -- only reacted to the ones that could reach it within 1.2 s, never went for the empty half of the room, and got
  -- pinned in a corner (2026-11-25). This makes it drift toward open space before the crowd closes in.
  if S.m_crowd > 0 then
    for _, z in ipairs(ctx.byT[20].z) do
      if z.mover then
        local d = (z.c - plan.p):Length()
        if d < S.crowd_r2 then c = c + S.m_crowd * (S.crowd_r2 - d) / S.crowd_r2 end
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
        local va = a.c - plan.p
        local la = va:Length()
        if la < S.pincer_r and la > 1 then
          for j = i + 1, #zs do
            local b = zs[j]
            if b.mover then
              local vb = b.c - plan.p
              local lb = vb:Length()
              if lb < S.pincer_r and lb > 1 and va:Dot(vb) / (la * lb) < -0.5 then
                -- fades with the distance from the line between them, so stepping off that line pays (offline test
                -- K3: with a flat cost every nearby spot paid about the same and it never stepped out)
                local ab = b.c - a.c
                local len = ab:Length()
                local perp = len > 1 and math.abs((plan.p - a.c).X * ab.Y - (plan.p - a.c).Y * ab.X) / len or 0
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
    if plan.aimT and hurtable then c = c - S.m_aim * (1 - plan.aimT / 30) end
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
function Mover.choose(ctx)
  local S, w, player = ctx.S, ctx.w, ctx.player
  ctx.pr = player.Size
  ctx.vel = player.Velocity
  -- Isaac's learned movement (top speed per speed stat, acceleration); the old constant until it's learned
  if Mover.top then ctx.speed = Mover.top * math.max(0.3, player.MoveSpeed) end
  ctx.acc = Mover.acc
  ctx.canFly = player.CanFly
  ctx.range = math.max(120, player.TearRange * 0.95)
  -- precompute every enemy's "could be here" circle and every shot's spot at each sample time, once:
  -- all the plans share them (that's what keeps this fast)
  ctx.byT = {}
  for si = 1, 3 do
    for _, t in ipairs(SEG[si]) do
      local zs, ss = {}, {}
      for _, e in ipairs(w.enemies) do
        if e.Type == EntityType.ENTITY_FIREPLACE then
          zs[#zs + 1] = { c = e.Position, r = e.Size + S.fire_pad }
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
          zs[#zs + 1] = { c = c, r = r, mover = true, base = base, drift = drift }
        end
      end
      for _, s in ipairs(w.shots) do
        -- learned per shot type and shooter (Sloth's shot hit while a straight line said "danger 0")
        local d = player.Position - s.Position
        d = d:Length() > 1 and d:Normalized() or Vector(0, 0)
        local c, r = Mover.predict(s, t, d, nil)
        -- + the watcher's margin for this shooter's shots (after repeated shot hits from it)
        local pad = ctx.shotPadOf and ctx.shotPadOf(s.SpawnerType) or 0
        ss[#ss + 1] = { c = c, r = r + S.hit_margin + pad }
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
      alongLines = t.shoots_ring or t.laser or (t.shoots_single and (t.invulnerable or t.stationary)) or false
    end
    if e.Position and alongLines then
      local h = GetPtrHash(e)
      ctx.lines[#ctx.lines + 1] = { pos = e.Position, half = (e.Size or 13) + 14, eta = winding[h] }
    end
  end
  -- enemies the playbook says charge when Isaac lines up (Chargers): their row and column are costly while alive
  if ctx.playbookOf then
    for _, e in ipairs(w.enemies) do
      local pb = ctx.playbookOf(e)
      if pb and (pb.tags.charges_on_line or pb.tags.dashes_at_isaac) and e.Position then
        ctx.lines[#ctx.lines + 1] = { pos = e.Position, half = (e.Size or 13) + 16, charge = true }
      end
      -- boss tactics: "stay diagonal" / "never in its row" / "never in its column" (Gurglings, Gluttony, The Fallen...)
      local tac = ctx.tacticsOf and ctx.tacticsOf(e)
      if tac and e.Position and (tac.diag or tac.row or tac.col) then
        local only = (tac.diag or (tac.row and tac.col)) and nil or (tac.row and "row" or "col")
        ctx.lines[#ctx.lines + 1] = { pos = e.Position, half = (e.Size or 13) + 18, charge = true, only = only }
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
  -- move 1: full-speed directions + standing still; the slow "fine positioning" steps only when lining up a
  -- shot on a target that's close to lined up (creeping everywhere looked awkward and slow)
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

  -- best full plan, aim and distance included; its first move is what we do now
  local best, bestC, bestPl = 0, math.huge, nil
  local standC = nil
  for _, pl in ipairs(keep) do
    local c = total(ctx, pl)
    if c < bestC then best, bestC, bestPl = pl.firstIdx, c, pl end
    if pl.firstIdx == 0 and (not standC or c < standC) then standC = c end
  end
  -- why it chose this (for the log): danger part, ways out, total; and the same for standing still
  if bestPl then
    Mover.debug = string.format("best move %d: total %.0f (danger %.0f, closed ways %d, aim %s) | stand: %s | %d plans kept",
      best, bestC, bestPl.c, waysOut(ctx, bestPl.p), tostring(bestPl.aimT), standC and string.format("%.0f", standC) or "pruned",
      #keep)
  end
  Mover.last = { move = best, cost = bestC }
  Mover.lastMove = best
  Mover.lastDir = ctx.DIRS[best]
  Mover.lastFrame = Game():GetFrameCount()
  return best, bestC
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
