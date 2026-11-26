-- Isaac Bot reflexes (Stage 2): look-ahead dodging, positioning and aiming. Runs every game update (30/s).
--
-- Each update it tries 16 directions + standing still, plays each forward ~0.4 s against where every enemy
-- shot, enemy, laser and bomb will be, and adds up a cost:
--   big cost  = getting hit (sooner = worse), walking into rocks/pits/walls/spikes
--   small cost = bad position for fighting (too close/far from the target, not lined up for a shot, cornered)
-- The cheapest move wins. Shooting: nearest enemy it can hurt, led for its movement, in Isaac's 4 directions.
-- Every number lives in Reflex.S so the learning loop (Stage 7) and live "set" commands can tune it.

-- Has this entity EVER had collision? Cord pieces never do (ignore them); a jumping boss only loses it mid-air.
-- (A global table so danger.lua and eyes.lua share the same memory.)
IsaacBotSolidSeen = IsaacBotSolidSeen or {}

-- A lit RED fire: it shoots at Isaac, and tears put it out (the author, 2026-11-25: "make it so it hits the red fire
-- if it's a threat. You can shoot the red fire to prevent it from shooting you"). So it's a target, not just a hazard.
-- (Purple fires need a bomb and blue ones are loot: PLAN.md "To do later".)
function IsaacBotRedFire(e)
  return e.Type == EntityType.ENTITY_FIREPLACE and e.Variant == 1 and e.HitPoints > 1
end

-- A troll bomb lying as a PICKUP (bomb pickup, troll / super troll / golden troll subtype): it explodes by itself a
-- moment after it appears, like a lit bomb. Shared with danger.lua and main.lua's bomb logger.
function IsaacBotTrollPickup(e)
  if e.Type ~= EntityType.ENTITY_PICKUP or e.Variant ~= PickupVariant.PICKUP_BOMB then return false end
  local s = e.SubType
  return s == 3 or s == 5 or s == 6 -- BombSubType.BOMB_TROLL, BOMB_SUPERTROLL, BOMB_GOLDENTROLL
end
function IsaacBotSolid(e)
  local h = GetPtrHash(e)
  if e.EntityCollisionClass ~= EntityCollisionClass.ENTCOLL_NONE then IsaacBotSolidSeen[h] = true; return true end
  if IsaacBotSolidSeen[h] then return true end
  -- Never solid yet: a cord/chain segment hangs off a parent (skip it). A free-standing enemy that can be hurt
  -- is real (Boils spawn small with no collision: the plain "never solid" rule hid them, 0/3 cleared).
  return e.Parent == nil and e:IsVulnerableEnemy()
end

local Danger = include("danger")
local Tells = include("tells")
local Mover = include("mover") -- movement core v2 (learned reach + deeper search); S.core picks which one drives
local Risk = include("risk")   -- how bold to play right now (hearts, deal at stake, buffer, pace): scales S
IsaacBotRisk = Risk            -- shared with danger.lua / nav.lua / main.lua
local Strategy = include("strategy") -- Level 3: the run's profile (strengths, needs) and run-aware item value
IsaacBotStrategy = Strategy
local Reflex = {}
Reflex.risk = Risk
Reflex.strategy = Strategy
Reflex.mover = Mover
Reflex.tells = Tells

Reflex.S = {
  horizon = 12,        -- updates to look ahead (30 per second)
  sample = 2,          -- check every Nth update along the way
  dirs = 16,           -- directions tried (+ standing still)
  hit_margin = 10,     -- extra px around Isaac when checking shots
  touch_margin = 14,   -- extra px around Isaac when checking enemy bodies
  hit_cost = 1000,
  touch_cost = 700,
  wall_cost = 400,
  spike_cost = 300,    -- (old; spikes now come from the danger map)
  danger_w = 450,      -- cost per half heart of danger-map damage on a square Isaac would cross
  still_tolerance = 120, -- lined up: stand still to shoot straight unless standing costs this much more
  caution_w = 120,      -- cost of ending up on a "caution" square (next to TNT) during a fight
  bait_dist = 100,      -- shielded targets (Hosts) open when you come close: hold this distance to bait them
  stand_safe_r = 150,   -- only stand still to shoot if no moving enemy is closer than this
  boss_margin = 0,      -- extra px of berth around boss bodies (tried 18 + 1.6x crowd + 190 px: much WORSE,
  boss_crowd = 1.0,     -- 2/8 bosses vs 5/8: keeping farther away in a small room just meant more corners.
  boss_dist = 150,      -- Neutral now; left as knobs for the tuner)
  swarm_n = 3,          -- this many light enemies within swarm_r = a swarm (stop treating them as harmless)
  swarm_r = 150,
  orbit_w = 45,         -- reward for circling a moving target at fighting distance (circle-strafe)
  tele_r = 50,          -- a learned wind-up is playing: be at least this far from where we stand now...
  tele_w = 260,         -- ...or pay this (aimed shots go where you WERE when they fire)
  shooter_line_w = 70,  -- ending up in the row/column of a known shooter we're not fighting (open line)
  warn_w = 320,         -- still in the dash line of an enemy playing a learned warning animation
  dash_side = 30,       -- px either side of that line counted as "in the line" (A/B: 650/50 was worse: 0/4 vs 2/4)
  dash_speed = 5,       -- px/update: faster than this = a straight dash, not a homing walk
  dash_all = 1,         -- 1: the straight-dash rule also covers ordinary enemies (Trite leaps); 0: bosses only
  bounce = 1,           -- 1: straight-line predictions bounce off the walls; 0: they run through them
  homing_min = 0.8,     -- average heading-to-us cosine above this = a chaser (predict it follows); 1 = off
  kite_w = 0,           -- (A/B on Blighted Ovum 6+6 rounds: 60 = 33 hits vs 0 = 31: no gain, off) reward for moving AROUND a close chaser instead of straight away from it (0 = off)
  corner_w = 400,       -- runway rule: cost of having no open floor left in the 'away from danger' direction (0 = off)
  corner_r = 260,       -- px: enemies closer than this shape the 'away' direction
  corner_need = 160,    -- px of open floor wanted that way
  plan_wall = 30,       -- firing-spot planner: cost per wall/rock touching the square (corner = 5 of them)
  m_every = 2,          -- v2 thinks every Nth update and keeps its move in between (speed)
  core = 2,             -- 1 = old move scoring, 2 = mover.lua (learned reach, 1.2 s beam search)
  m_beam = 6,           -- v2: plans kept after each of the 3 moves
  m_decay = 20,         -- v2: danger at t updates ahead counts 1/(1+t/decay) (sooner = surer)
  m_hit = 1000,         -- v2: cost of being inside a 'could be here' circle
  m_soft = 14,          -- v2: px of margin wanted outside the circles...
  m_soft_w = 6,         -- ...cost per px short of it
  m_aim = 260,          -- v2: reward for being lined up with an open lane to the target (sooner = more)
  m_dist_w = 0.7,       -- v2: cost per px away from the preferred fighting distance
  m_way = 1.2,          -- v2: pull toward the planner's firing square when calm (walled-in targets)
  m_wall = 40,          -- v2: cost of pushing into a wall (wasted time)
  m_line = 0,           -- v2: cost per sample of standing in a known shooter's row/column (open lane)
  m_hurtful = 1.3,      -- v2: danger circle grows this much while an enemy is in a 'hurtful' animation
  m_caution = 60,       -- v2: cost of standing on a TNT 'caution' square
  m_trap_r = 0.45,      -- v2: share of an enemy's 'could be here' circle that blocks a way out (likely spot)
  pb_kill_w = 60,       -- playbook kill priority (0-3) bonus per level for targeting (scaled by low HP)
  m_charge_line = 80,   -- v2: cost per sample of standing in the row/column of an enemy that charges on line
  shot_coming_eta = 8,  -- updates until a 'shot coming' (pre-shooting animation) is assumed to fire
  aim_line_w = 34,      -- v2: px either side of an aimed shot's line that counts as in its way
  m_edge_hit = 0.15,    -- v2: share of the hit cost at the edge of an enemy's 'could be here' circle (graded)
  m_grade_r = 40,       -- v2: px: circles bigger than this are graded (uncertain); smaller ones stay full cost
  m_crowd = 60,         -- v2: per enemy, cost of a plan ending close to it (closer = more): drift to open space
  crowd_r2 = 260,       -- v2: px: enemies within this of a plan's end count for crowd pressure
  m_pincer = 200,       -- v2: cost of ending between two enemies on opposite sides (scaled by closeness)
  pincer_r = 160,       -- v2: px: enemies closer than this count for the sandwich rule
  pincer_w = 70,        -- v2: px off the line between the two enemies at which the sandwich cost has faded out
  bomb_r = 90,          -- v2: px from a live bomb's centre to the blast edge (Isaac's size is added)
  m_burrow = 200,       -- v2: cost of standing still while an enemy is hidden (underground / in the air)
  m_center = 0.25,      -- v2: cost per px of a plan's end from the room's middle (steady pull away from corners)
  m_edge = 150,         -- v2: cost of a plan ending within edge_margin of a wall
  m_trap = 45,          -- v2: cost per closed way out (of 8) where a plan ends: corners close 3-5
  m_escape = 120,       -- v2: px of open floor a way out needs (about a second of running)
  m_turn = 90,          -- v2: cost of turning (half-turn = full cost, slight bend ~0): flow, not twitching
  m_corner = 500,       -- v2: cost of ending in a corner (wall on a side AND above/below), x0.5-2.5 by movers near
  m_nolane = 150,       -- v2: cost of standing still when the plan never lines up a shot (rock pockets vs worms)
  boss_aim = 1.8,       -- boss fights: lining up a shot is worth this much more (finish it, don't chip at it)
  m_line_escape = 160,  -- v2: in a dasher's line / a coming shot's line, cost per blocked sidestep (half each side)
  escape_step = 45,     -- v2: px of one sidestep (checked at 1 and 2 steps)
  finish_w = 220,       -- target choice: bonus for an enemy our next 1 shot kills, fading to 0 at 5 shots
  commit_w = 90,        -- target choice: bonus for staying on the (damaged) enemy we've been shooting
  ring_margin = 70,     -- ring-kite vs chasing bosses: px from the walls to the lane...
  ring_r = 90,          -- ...whose corners are arcs this big (cuts every corner)
  ring_w = 3,           -- cost per px off the lane
  ring_flow = 220,      -- reward for moving along the lane in the chosen direction (per ~20 degrees)
  corner_gap = 60,      -- v2: px to a wall on both axes that counts as a corner
  fire_pad = 14,        -- px: extra no-touch distance around lit fires
  deep_k = 6,           -- how many of the best moves get the expensive checks (speed: the rest are cut early)
  deep_w = 0.5,         -- weight of the best follow-up move's cost (2-step look-ahead; 0 = off)
  kill_w = 400,         -- planner bonus for dangerous enemies with little HP left (danger per HP; 0 = off)
  spawner_w = 250,      -- planner bonus for firing at an enemy that's spawning others (Sack, nests)
  dodge_only_r = 130,   -- px: in a cleared room, only shots this close and coming at us interrupt walking
  gate_r = 130,         -- px: a poop/fire this close to an enemy we can't get a line on is a gate to break
  relax_s = 5,          -- s with no firing spot before each relax step (adjacent squares, then slow movers)
  loose_aim = 40,       -- px: fire when the target is this close to our row/column (spray; 0 = sure hits only)
  any_shot = 1,         -- 1: when the planned shot can't land, shoot any enemy a shot would hit (run and gun)
  kite_r = 220,         -- px: chasers closer than this get kited
  kite_center = 0.15,   -- extra pull to the room's middle while kiting (corners are where chasers catch us)
  respect_step = 0.15,  -- each half heart an enemy type deals us adds this much respect...
  respect_max = 1.6,    -- ...up to this. (It was 0.5 / 3: a feedback loop. Every boss maxed out at 3x
                        -- berth, the bot got squeezed into corners, took more hits, and grew more respect.)
  calm_align = 3,       -- no enemy shots in the air: lining up with the target counts this many times more
  calm_commit = 4,      -- calm (no shots/bombs/lasers, no enemy within calm_r): pull to the firing spot x this,
  calm_r = 140,         -- and ignore wall/corner/centre comfort (a Horf in a corner timed out the gauntlet)
  pref_dist = 150,     -- preferred distance from the target (shrunk if range is short)
  dist_w = 0.6,        -- cost per px away from the preferred distance
  align_w = 0.5,       -- cost per px off the target's row/column
  crowd_r = 110,       -- enemies closer than this push Isaac away
  crowd_w = 2.0,
  center_w = 0.25,     -- gentle pull toward the room's middle (corners are deadly)
  edge_margin = 50,
  edge_cost = 200,
  keep_w = 8,          -- bonus for keeping the last move (less jitter)
  fire_w = 1.4,        -- pull toward the next square on the path to the planned firing spot (per px)
  slow_step = 0.3,     -- slow-step speed (fraction of full) for lining up exactly
  on_spot = 10,        -- px: this close to the firing spot counts as standing on it
  plan_keep = 60,      -- a new firing plan must beat the current one by this much to switch
  plan_max_speed = 0.3, -- px/update: only plan firing spots against targets that truly stand still (Horfs,
                        -- turrets). Slow crawlers (Maggots, 0.5-1) moved the spot every re-plan: 45 s per wave
  light_mass = 4.5,     -- enemies lighter than this get knocked back by tears: no need to run from them
                        -- (measured 2026-11-25: Fly/Attack Fly 3, Pooter 4, Gaper 5, Hopper 10)
  light_crowd = 0.25,   -- ...so their "keep your distance" weight is scaled down to this
  plan_clearance = 70,  -- px (+ enemy size): firing spots must be this far from every MOVING enemy
  still_clearance = 30, -- ...and this far from enemies that stand still (Horfs, turrets)
  bomb_safe = 140,     -- want to end up at least this far from any live bomb (blast ~95 px)...
  bomb_w = 25,         -- ...cost per px short of that
  escape_r = 90,       -- "exit plan": from a spot, look this far in 8 directions...
  escape_w = 22,       -- ...and add this cost for every direction that's blocked (wall, rock, pit, enemy)
  escape_min = 3,      -- fewer open directions than this is a trap: extra cost per missing one
  trap_w = 60,
  tear_speed = 10,     -- px per update at shot speed 1.0 (for leading shots)
  speed_mul = 4.6,     -- px per update at MoveSpeed 1.0
}

Reflex.prof = { plan = 0, move = 0 } -- ms spent per part since the last perf report (main.lua resets it)
Reflex.status = { mode = "combat", active = false, move = -1, shoot = "", target = nil, cost = 0, threats = 0 }

local lastChoice = -1
local DIRS = {}
local DIRS8 = {}
for k = 1, 8 do
  local a = (k - 1) / 8 * 2 * math.pi
  DIRS8[k] = Vector(math.cos(a), math.sin(a))
end

-- Full-speed moves 1..n, then the same directions as slow steps n+1..2n (fine positioning: every full-speed
-- move overshot a firing spot 24 px away, so it stood still off the lane forever).
local function buildDirs(n)
  DIRS = { [0] = Vector(0, 0) }
  for i = 1, n do
    local a = (i - 1) / n * 2 * math.pi
    DIRS[i] = Vector(math.cos(a), math.sin(a))
    DIRS[n + i] = DIRS[i] * Reflex.S.slow_step
  end
end
buildDirs(Reflex.S.dirs)

function Reflex.set(key, value)
  if Reflex.S[key] ~= nil and tonumber(value) then
    Reflex.S[key] = tonumber(value)
    Risk.setBase(key, tonumber(value)) -- risk-scaled settings: the live value is the base, scaled again next tick
    if key == "dirs" then buildDirs(math.floor(Reflex.S.dirs)) end
    return true
  end
  return false
end

local function blocked(room, pos, canFly)
  if not room:IsPositionInRoom(pos, 8) then return Reflex.S.wall_cost end
  local c = room:GetGridCollisionAtPos(pos)
  if c == GridCollisionClass.COLLISION_NONE then
    return 0 -- spikes, creep and fires are priced from the shared danger map instead (see score)
  end
  if canFly and c == GridCollisionClass.COLLISION_PIT then return 0 end
  return Reflex.S.wall_cost
end

-- Line of fire (reading the room): walks the straight line from a to b in 20 px steps.
--   0 = clear, 1 = soft (poop or a lit fire in the way: our shots break it), 2 = blocked (rock, block, wall)
-- Tears fly over pits, so pits don't count.
-- Our OWN tears' lane. Spectral tears (Continuum, Ouija Board, The Wiz...) fly through rocks and poop
-- (2026-11-25: with Continuum in a room full of rocks and pits it saw almost no open line and hardly fired at the last
-- enemy for minutes). Enemy shots keep using the solid lane below.
Reflex.spectral = false
function Reflex.lane(room, a, b)
  if Reflex.spectral then return 0 end
  return Reflex.solidLane(room, a, b)
end
local function hasSpectral(player)
  local ok, yes = pcall(function()
    return player:HasTearFlags(TearFlags.TEAR_SPECTRAL)
  end)
  if ok then return yes end
  ok, yes = pcall(function()
    return (player.TearFlags & TearFlags.TEAR_SPECTRAL) == TearFlags.TEAR_SPECTRAL
  end)
  return ok and yes or false
end

-- 0 = open, 1 = only poop in the way, 2 = blocked (rocks, walls)
function Reflex.solidLane(room, a, b)
  local d = b - a
  local len = d:Length()
  if len < 1 then return 0 end
  local step = d / len * 20
  local soft = 0
  local p = a + step
  for _ = 1, math.floor(len / 20) - 1 do
    local ge = room:GetGridEntityFromPos(p)
    if ge then
      local col = ge.CollisionClass
      if col ~= GridCollisionClass.COLLISION_NONE and col ~= GridCollisionClass.COLLISION_PIT then
        if ge:GetType() == GridEntityType.GRID_POOP then soft = 1 else return 2 end
      end
    elseif not room:IsPositionInRoom(p, 0) then
      return 2
    end
    p = p + step
  end
  return soft
end

local LANE_COST = { [0] = 0, [1] = 60, [2] = 400 }

-- Best way to shoot `target` from `pos`: along its row or its column, whichever is cheaper once
-- "how far off the line" and "is the line actually open" are both counted.
-- Returns cost, axis ("row"/"col") and the lane state.
local function bestLane(room, pos, tp)
  local rowPoint = Vector(pos.X, tp.Y) -- stand here to shoot along the row
  local colPoint = Vector(tp.X, pos.Y) -- stand here to shoot along the column
  local rowState = Reflex.lane(room, rowPoint, tp)
  local colState = Reflex.lane(room, colPoint, tp)
  local rowCost = math.abs(pos.Y - tp.Y) * Reflex.S.align_w + LANE_COST[rowState]
  local colCost = math.abs(pos.X - tp.X) * Reflex.S.align_w + LANE_COST[colState]
  if rowCost <= colCost then return rowCost, "row", rowState end
  return colCost, "col", colState
end
Reflex.bestLane = bestLane

---------------------------------------------------------------- firing-position planner
-- The look-ahead only sees ~0.4 s (one tile), so on its own it never walks AROUND rocks to a square with a
-- clear shot. Every half second this maps every walkable square (one sweep), lists the squares lined up with
-- an enemy (same row/column, in range, nothing solid between), and picks the closest safe one. The cost
-- function then pulls Isaac along the real path to it, while dodging still outweighs everything.
local plan = { at = -999, target = nil, cell = nil, cellPos = nil, path = nil, banned = {}, forced = nil }
Reflex.plan = plan

-- walkable-square distance map from the player's square (8 directions, no corner cutting)
local function sweep(room, player, fires)
  local w, size = room:GetGridWidth(), room:GetGridSize()
  local function open(i)
    if i < 0 or i >= size or fires[i] then return false end
    local ge = room:GetGridEntity(i)
    if ge and ge:GetType() == GridEntityType.GRID_DOOR then return false end
    local c = room:GetGridCollision(i)
    if c == GridCollisionClass.COLLISION_NONE then
      if ge and (ge:GetType() == GridEntityType.GRID_SPIKES
                 or (ge:GetType() == GridEntityType.GRID_SPIKES_ONOFF and ge.State == 0)) then return player.CanFly end
      return true
    end
    return player.CanFly and c == GridCollisionClass.COLLISION_PIT
  end
  local start = room:GetGridIndex(player.Position)
  local dist, prev, queue, head = { [start] = 0 }, {}, { start }, 1
  while queue[head] do
    local cur = queue[head]; head = head + 1
    local cx, cy = cur % w, math.floor(cur / w)
    for dy = -1, 1 do
      for dx = -1, 1 do
        if dx ~= 0 or dy ~= 0 then
          local nx, ny = cx + dx, cy + dy
          local ni = nx + ny * w
          if nx >= 0 and nx < w and not dist[ni] and open(ni)
             and (dx == 0 or dy == 0 or (open(cx + dx + cy * w) and open(cx + (cy + dy) * w))) then
            dist[ni], prev[ni] = dist[cur] + 1, cur
            queue[#queue + 1] = ni
          end
        end
      end
    end
  end
  return dist, prev, start
end

local function firingCells(room, target, rangePx, minK)
  local w, size = room:GetGridWidth(), room:GetGridSize()
  local tIdx = room:GetGridIndex(target.Position)
  local tc, tr = tIdx % w, math.floor(tIdx / w)
  local out = {}
  for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
    for k = 1, 14 do
      local c, r = tc + d[1] * k, tr + d[2] * k
      if c < 0 or c >= w or r < 0 then break end
      local i = c + r * w
      if i >= size then break end
      local pos = room:GetGridPosition(i)
      local dist = (pos - target.Position):Length()
      if dist > rangePx then break end
      local col = room:GetGridCollision(i)
      if col == GridCollisionClass.COLLISION_NONE then
        if k >= (minK or 2) then
          local lane = Reflex.lane(room, pos, target.Position)
          if lane == 2 then break end
          out[#out + 1] = { idx = i, pos = pos, lane = lane, dist = dist, dir = d }
        end
      elseif col ~= GridCollisionClass.COLLISION_PIT then
        local ge = room:GetGridEntity(i)
        if not (ge and ge:GetType() == GridEntityType.GRID_POOP) then break end -- rocks/walls stop tears
      end
    end
  end
  return out
end

-- Learning from hits (in-game): each time an enemy TYPE hurts us, it earns more respect for the rest of the
-- session: a wider berth and a higher price on getting close, scaled by the damage. No per-enemy rules needed
-- (gauntlet 2026-11-25: Globins, a full heart per touch, killed it in 3 hits).
Reflex.respect = {}
function Reflex.learnHit(etype, amount)
  local r = Reflex.respect[etype] or 1
  Reflex.respect[etype] = math.min(Reflex.S.respect_max, r + Reflex.S.respect_step * math.max(1, amount or 1))
end
local function respectOf(e) return Reflex.respect[e.Type] or 1 end

-- Enemy playbook (knowledge\enemy_playbook.json, sent by the helper): each enemy type's known behaviour, so the bot
-- starts with it instead of learning it by getting hit (the author's idea, 2026-11-25). Key "type.variant".
Reflex.playbook = {}
function Reflex.loadPlaybook(text)
  local n = 0
  for entry in string.gmatch(text or "", "[^;]+") do
    local key, rest = entry:match("^([^=]+)=(.*)$")
    if key then
      local p = { tags = {}, k = 0, d = 0 }
      for t in string.gmatch(rest, "[^,]+") do
        local kv = t:match("^k(%d)$")
        local dv = t:match("^d(%d)$")
        if kv then p.k = tonumber(kv) elseif dv then p.d = tonumber(dv) else p.tags[t] = true end
      end
      Reflex.playbook[key] = p
      n = n + 1
    end
  end
  return n
end
-- Boss tactics (knowledge/boss_tactics.json, from wiki pages, guides and boss-guide videos; the author: "look up how
-- people beat them... the little cheeky things it can do to avoid taking damage"). Sent by the helper as
-- "type.variant=pd,flags,adds,tell|tell;..." flags: d = stay diagonal, r = avoid its row, c = avoid its column,
-- k = avoid corners. adds: ignore / kill_close / kill_first. tells: animations right before an aimed attack.
Reflex.bossTactics = {}
IsaacBotBossTactics = Reflex.bossTactics
-- rest animations: the boss is recovering from an attack, so closing in to hit is safe
local REST_ANIM = { Tired = true, Pant = true, Stop = true, Landing = true, Land = true, Rest = true, Recover = true,
              Stunned = true, Dizzy = true }
function Reflex.loadBossTactics(text)
  local n = 0
  for entry in string.gmatch(text or "", "[^;]+") do
    local key, pd, flags, adds, rest = entry:match("^([%d%.]+)=(%d*),(%a*),([%a_]*),?(.*)$")
    if key then
      local tells, windows = (rest or ""):match("^([^,]*),?(.*)$")
      local t = { pd = tonumber(pd), diag = flags:find("d") ~= nil, row = flags:find("r") ~= nil,
                  col = flags:find("c") ~= nil, corners = flags:find("k") ~= nil, ring = flags:find("g") ~= nil,
                  adds = adds ~= "" and adds or nil,
                  tells = {}, windows = {} }
      for a in string.gmatch(tells or "", "[^|]+") do t.tells[a] = true end
      -- attack windows: animations where it's safe to pour damage in (Dingle "Tired"/"Idle"/"Whistle")
      for a in string.gmatch(windows or "", "[^|]+") do t.windows[a] = true; t.hasWindows = true end
      Reflex.bossTactics[key] = t
      n = n + 1
    end
  end
  return n
end
-- The watcher's lessons (brain\watcher.py): per enemy, small capped adjustments it learned from repeated hits.
-- "type.var=margin,shotpad,bossdist;type=..." (a bare type = its shots, by shooter type)
Reflex.lessons = {}
function Reflex.loadLessons(text)
  Reflex.lessons = {}
  local n = 0
  for key, m, pad, dist in string.gmatch(text or "", "([%d%.]+)=(%d+),(%d+),(%d+)") do
    Reflex.lessons[key] = { margin = tonumber(m), pad = tonumber(pad), dist = tonumber(dist) }
    n = n + 1
  end
  return n
end
function Reflex.lessonOf(e)
  if not e or e.kind or not e.Type then return nil end
  return Reflex.lessons[e.Type .. "." .. e.Variant] or Reflex.lessons[tostring(e.Type)]
end
-- extra margin around shots fired by this shooter type (the watcher's "shot:<type>" lessons)
function Reflex.shotPadOf(spawnerType)
  local l = spawnerType and Reflex.lessons[tostring(spawnerType)]
  return l and l.pad or 0
end

-- Is this enemy telling an attack RIGHT NOW? (a tell animation from its boss tactics, a learned warning animation,
-- or an animation that usually leads into a shot)
function Reflex.telling(e)
  local tac = Reflex.tacticsOf(e)
  local a = Tells.animOf(e)
  if tac and a and tac.tells[a] then return true end
  local okW, warn = pcall(Tells.warning, e)
  if okW and warn then return true end
  local okS, coming = pcall(Tells.shotComing, e)
  return (okS and coming) or false
end

function Reflex.tacticsOf(e)
  if not e or e.kind or not e.Type then return nil end
  return Reflex.bossTactics[e.Type .. "." .. e.Variant] or Reflex.bossTactics[e.Type .. ".0"]
end

local function playbookOf(e)
  if not e or e.kind or not e.Type then return nil end
  return Reflex.playbook[e.Type .. "." .. e.Variant] or Reflex.playbook[e.Type .. ".0"]
end
Reflex.playbookOf = playbookOf

-- respect carries over between launches too ("type=value,...")
function Reflex.respectDump()
  local parts = {}
  for t, r in pairs(Reflex.respect) do parts[#parts + 1] = t .. "=" .. string.format("%.2f", r) end
  return table.concat(parts, ",")
end
function Reflex.respectLoad(text)
  for t, r in tostring(text):gmatch("(%d+)=([%d%.]+)") do
    Reflex.respect[tonumber(t)] = math.min(Reflex.S.respect_max, tonumber(r)) -- never above the cap
  end
end

-- Average speed per enemy over the last few seconds (erratic movers like Dips pause, so one moment lies).
-- NET movement: the average of the velocity VECTOR, so jittering in place (Horfs shake, Boils pulse) cancels
-- out to ~0 while a steady crawl (Maggots) keeps its speed. Averaging the plain speed made shaking Horfs look
-- like movers: no firing spot, no shots, timeout (gauntlet 0.9.3).
local velAvg = {}
local leadAvg = {}
-- Homing: how steadily a fast mover keeps pointing at Isaac (average cosine between its heading and the
-- direction to us, only while it's moving). A straight dash (Dingle's slide, a Trite leap) points at us when
-- it starts, then we sidestep and it doesn't turn: low. A chaser (Blighted Ovum at 6 px/update) keeps turning
-- after us: high. Speed alone can't tell them apart; this can.
local homeAvg = {}
function Reflex.trackSpeeds(enemies, player)
  local seen = {}
  for _, e in ipairs(enemies) do
    local h = GetPtrHash(e)
    seen[h] = true
    velAvg[h] = (velAvg[h] or e.Velocity) * 0.93 + e.Velocity * 0.07
    -- the velocity to LEAD shots by: starts at zero and settles in ~0.5 s. A steady mover (the Haunt sweeping) gets
    -- its full lead; a hopper's jumps average out (leading a spider by one hop's speed overshot it)
    leadAvg[h] = (leadAvg[h] or Vector(0, 0)) * 0.85 + e.Velocity * 0.15
    if player and e.Velocity:Length() > 1.5 then
      local to = player.Position - e.Position
      if to:Length() > 1 then
        local c = e.Velocity:Normalized():Dot(to:Normalized())
        homeAvg[h] = (homeAvg[h] or 0) * 0.95 + c * 0.05
      end
    end
  end
  for h in pairs(velAvg) do if not seen[h] then velAvg[h] = nil; homeAvg[h] = nil; leadAvg[h] = nil end end
end
function Reflex.leadVel(e)
  if not e or e.kind or not e.Velocity then return Vector(0, 0) end
  return leadAvg[GetPtrHash(e)] or Vector(0, 0)
end
function Reflex.homing(e) return homeAvg[GetPtrHash(e)] or 0 end
function Reflex.avgSpeed(e)
  if e.kind then return 0 end -- a poop/fire target (a plain table, not an entity): it never moves.
  -- (Before this check the planner crashed on poop targets, so the Eternal-Fly-in-a-pen room never got a plan.)
  local v = velAvg[GetPtrHash(e)]
  return v and v:Length() or e.Velocity:Length()
end

-- The brain (or watchdog) can point the fighting at one target for a while: an enemy or a poop/fire.
function Reflex.forceTarget(t, seconds)
  plan.forcedTarget = { t = t, untilF = Game():GetFrameCount() + 30 * (seconds or 8) }
  plan.at = -999
end

-- Best firing square for one target (used to build the brain's options). Returns idx, steps away, lane state.
function Reflex.spotFor(player, target)
  local room = Game():GetRoom()
  local fires = {}
  for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_FIREPLACE)) do
    if e.HitPoints > 1 then fires[room:GetGridIndex(e.Position)] = true end
  end
  local dist = sweep(room, player, fires)
  local range = math.max(120, player.TearRange * 0.9)
  local best, bestSteps, lane = nil, math.huge, nil
  for _, c in ipairs(firingCells(room, target, range)) do
    local s = dist[c.idx]
    if s and s + c.lane * 2 < bestSteps then best, bestSteps, lane = c.idx, s + c.lane * 2, c.lane end
  end
  return best, bestSteps, lane
end

function Reflex.banTarget(seconds)
  if plan.target and plan.target.Exists and plan.target:Exists() then
    plan.banned[GetPtrHash(plan.target)] = Game():GetFrameCount() + 30 * (seconds or 6)
  end
  plan.at = -999
end

function Reflex.forceCell(idx)
  plan.forced = { idx = idx, untilF = Game():GetFrameCount() + 30 * 6 }
  plan.at = -999
end

-- Relax ladder (the author, 2026-11-25: a spider sat in a rock pocket and the bot waited forever). The planner's
-- safe defaults (no square right next to a target, a gap around every enemy, only plan for targets that stand
-- still) can leave NO firing spot at all. Then, every `relax_s` seconds: 1 = adjacent squares and small gaps
-- allowed, 2 = slow movers planned too. Back to 0 in a new room.
local relaxSince, relaxRoom = nil, nil
local function relaxLevel(f)
  local roomIdx = Game():GetLevel():GetCurrentRoomIndex()
  if roomIdx ~= relaxRoom then relaxSince, relaxRoom = nil, roomIdx end
  if not relaxSince or Reflex.S.relax_s <= 0 then return 0 end
  return math.min(2, math.floor((f - relaxSince) / (30 * Reflex.S.relax_s)))
end
local function clearanceFor(e, relax)
  local S = Reflex.S
  -- fires burn on touch: they NEVER lose their gap (2026-11-25: relaxed to 0, it planned a spot next to a
  -- fire and walked into it)
  if e.Type == EntityType.ENTITY_FIREPLACE then return S.plan_clearance end
  if Reflex.avgSpeed(e) < 0.6 then return relax >= 1 and 0 or S.still_clearance end
  return relax >= 1 and S.plan_clearance * 0.5 or S.plan_clearance
end

local function planFire(player, room, w, targets, prefDist)
  local S = Reflex.S
  local f = Game():GetFrameCount()
  local relax = relaxLevel(f)
  Reflex.relax = relax
  -- an enemy wandered next to the planned spot: that spot is no good any more, re-plan now
  if plan.cellPos then
    for _, e in ipairs(w.enemies) do
      local clear = clearanceFor(e, relax)
      if (e.Position - plan.cellPos):Length() < e.Size + clear * 0.8 then plan.at = -999; break end
    end
  end
  if f - plan.at < 15 then return end
  plan.at = f
  local oldTarget, oldIdx = plan.target, plan.cell and plan.cell.idx
  plan.target, plan.cell, plan.cellPos, plan.path = nil, nil, nil, nil
  local fires = {}
  for _, e in ipairs(w.enemies) do
    if e.Type == EntityType.ENTITY_FIREPLACE then fires[room:GetGridIndex(e.Position)] = true end
  end
  local dist, prev, start = sweep(room, player, fires)
  local range = math.max(120, player.TearRange * 0.9)
  local best, bestScore = nil, math.huge
  local forced = plan.forced and f < plan.forced.untilF and plan.forced.idx or nil
  local bossOn = Reflex.bossAliveIn and Reflex.bossAliveIn(w.enemies)
  local bossAdds = Reflex.addsPolicy and Reflex.addsPolicy(w.enemies)
  for _, t in ipairs(targets) do
    local hash = t.Exists and GetPtrHash(t) or nil
    -- only for targets that (nearly) stand still: a chaser's square goes stale and the plan walked Isaac
    -- straight into Gapers (batch review: "fire from 25,13 at 25,13" right before a hit)
    local still = (t.Velocity == nil) or (Reflex.avgSpeed(t) < (relax >= 2 and 1.0 or S.plan_max_speed))
    -- no fixed firing spot for enemies that dash or charge (playbook): with Dingle in a corner the only line onto it
    -- ran down a wall, the planner sent the bot there, straight into the dash and spit lane (2026-11-25). The movement
    -- core keeps to open space instead and fires when the target comes roughly into line.
    local pbd = playbookOf(t)
    if pbd and (pbd.tags.dashes_at_isaac or pbd.tags.charges_on_line) then still = false end
    if still and not (hash and plan.banned[hash] and plan.banned[hash] > f) then
      for _, c in ipairs(firingCells(room, t, range, relax >= 1 and 1 or 2)) do
        local steps = dist[c.idx]
        if steps then
          -- clearance from every enemy: big for ones that move (chasers), small for ones that stand still
          -- (one big clearance for all made 3 bunched Horfs leave NO valid square: "no firing spot" for 90 s)
          local safe = true
          for _, e in ipairs(w.enemies) do
            local clear = clearanceFor(e, relax)
            if (e.Position - c.pos):Length() < e.Size + clear then safe = false; break end
          end
          if safe then
            local score = steps * 40 + c.lane * 80 + math.abs(c.dist - prefDist) * 0.3
            if hash and w.spawners and w.spawners[hash] then score = score - S.spawner_w end
            score = score - Reflex.finishBonus(t, player) * 1.5 -- finish it / stick with it (as pickTarget)
            -- boss fights (pickTarget's rule): the boss first, an add only when it's the threat; and keep
            -- boss_dist from the boss (Mega Fatty's blood bursts hit twice from 85-92 px, 2026-11-25)
            if bossOn and t.IsBoss then
              if t:IsBoss() then
                local tac = Reflex.tacticsOf(t)
                local keep = ((tac and tac.pd) or S.boss_dist) * ((Risk.window and REST_ANIM[Risk.window]) and 0.65 or 1)
                if c.dist < keep * 0.8 and not Risk.invincible then score = score + 300 end
              elseif bossAdds == "kill_first" then
                score = score - 150
              else
                score = score + math.max(0, 300 - Reflex.minionThreat(t, player, false))
              end
            end
            -- most danger per hit point first: weak things that keep hurting us die first (Sloth's Chargers did
            -- 9 of 18 hits while it chipped at Sloth's 90+ HP). Danger = learned respect (rises with hits taken).
            local pbt = playbookOf(t) -- the playbook's kill priority (0-3)
            -- (with a boss alive the "low HP first" pull is small: the threat rule above already decides adds)
            local lowHpW = (bossOn and t.IsBoss and not t:IsBoss()) and 0.3 or 1
            if pbt and t.HitPoints and t.HitPoints > 0 then score = score - lowHpW * S.pb_kill_w * pbt.k * math.min(1, 20 / t.HitPoints) end
            if hash and t.HitPoints and t.HitPoints > 0 and S.kill_w > 0 then
              score = score - lowHpW * S.kill_w * (respectOf(t) - 0.9) * math.min(1, 20 / t.HitPoints)
            end
            -- boxed-in squares are bad places to stand (the author: "it goes to the corner deliberately, like its
            -- pathfinding tells it to"): every wall/rock touching the square costs, a corner touches 5
            if S.plan_wall > 0 then
              local gw = room:GetGridWidth()
              local cc, cr = c.idx % gw, math.floor(c.idx / gw)
              for dy = -1, 1 do
                for dx = -1, 1 do
                  if dx ~= 0 or dy ~= 0 then
                    local ni = (cc + dx) + (cr + dy) * gw
                    if room:GetGridCollision(ni) ~= GridCollisionClass.COLLISION_NONE then score = score + S.plan_wall end
                  end
                end
              end
            end
            for _, sh in ipairs(w.shooters or {}) do -- a firing square in ANOTHER shooter's open line is worse
              if sh ~= t then
                local rel = c.pos - sh.Position
                if (math.abs(rel.X) < 22 or math.abs(rel.Y) < 22) and Reflex.solidLane(room, sh.Position, c.pos) < 2 then
                  score = score + 90
                end
              end
            end
            -- stick with the current target + spot unless something clearly better turns up (no flip-flopping)
            if t == oldTarget and c.idx == oldIdx then score = score - Reflex.S.plan_keep end
            if forced then score = (c.idx == forced) and -1 or score + 10000 end
            if score < bestScore then best, bestScore = { t = t, c = c }, score end
          end
        end
      end
    end
  end
  if not best then
    relaxSince = relaxSince or f
    return
  end
  if relax == 0 then relaxSince = nil end
  local path, cur = {}, best.c.idx
  while cur and cur ~= start do table.insert(path, 1, cur); cur = prev[cur] end
  plan.target, plan.cell, plan.cellPos, plan.path = best.t, best.c, best.c.pos, path
end

-- the next square on the planned path that isn't right under Isaac
local function waypoint(room, player)
  if not plan.path then return nil end
  for _, i in ipairs(plan.path) do
    local p = room:GetGridPosition(i)
    if (p - player.Position):Length() > 22 then return p end
  end
  return plan.cellPos
end

-- distance from point p to the segment a-b
local function segDist(p, a, b)
  local ab = b - a
  local len2 = ab:LengthSquared()
  if len2 < 0.01 then return (p - a):Length() end
  local t = math.max(0, math.min(1, (p - a):Dot(ab) / len2))
  return (p - (a + ab * t)):Length()
end

local CREEP = {}
for _, n in ipairs({ "CREEP_RED", "CREEP_GREEN", "CREEP_YELLOW", "CREEP_WHITE", "CREEP_BLACK", "CREEP_STATIC",
                     "CREEP_LIQUID_POOP" }) do
  if EffectVariant[n] then CREEP[EffectVariant[n]] = true end
end

-- Half hearts a spot would cost from creep (0 = clear). Isaac's own body (~10 px) counts as touching.
local function creepAt(w, p)
  for _, c in ipairs(w.creep or {}) do
    if (c.pos - p):Length() < c.r + 8 then return 1 end -- half a heart, like rules.lua R.danger.creep
  end
  return 0
end

-- Straight-line prediction that bounces off the room's walls (Blighted Ovum, 2026-11-25: died in 10 s; the
-- straight line ran out through the wall while the real body bounced back into us).
local function fold(v, lo, hi)
  local span = hi - lo
  if span <= 0 then return v end
  local x = (v - lo) % (2 * span)
  return lo + (x <= span and x or 2 * span - x)
end
local function bounced(w, pos, r)
  if not w.tl or Reflex.S.bounce <= 0 then return pos end
  return Vector(fold(pos.X, w.tl.X + r, w.br.X - r), fold(pos.Y, w.tl.Y + r, w.br.Y - r))
end

local function gather(player)
  local room = Game():GetRoom()
  local w = { shots = {}, enemies = {}, lasers = {}, bombs = {}, creep = {},
              tl = room:GetTopLeftPos(), br = room:GetBottomRightPos() }
  for _, e in ipairs(Isaac.GetRoomEntities()) do
    local ty = e.Type
    if ty == EntityType.ENTITY_EFFECT then
      -- each creep puddle by exact distance: the square-based danger map misses small puddles that don't
      -- cover a square's centre (Gurgling trails, 2026-11-25: 3 creep hits in one boss fight, then death)
      if CREEP[e.Variant] and not player.CanFly then
        w.creep[#w.creep + 1] = { pos = e.Position, r = e.Size * math.max(1, e.SpriteScale.X) * 0.8 }
      end
    elseif ty == EntityType.ENTITY_PROJECTILE then
      w.shots[#w.shots + 1] = e
    elseif ty == EntityType.ENTITY_LASER then
      if e.SpawnerType ~= EntityType.ENTITY_PLAYER and e.SpawnerType ~= EntityType.ENTITY_FAMILIAR then
        w.lasers[#w.lasers + 1] = e:ToLaser()
      end
    elseif ty == EntityType.ENTITY_BOMB or IsaacBotTrollPickup(e) then
      -- every live bomb is danger, including our own; and troll-bomb PICKUPS, which blow up by themselves (the
      -- author, 2026-11-25: "it stood on top of a troll bomb without moving": it only knew real bomb entities)
      w.bombs[#w.bombs + 1] = e
    elseif ty == EntityType.ENTITY_FIREPLACE then
      -- lit fires burn on touch (and red/purple ones shoot); the batch review caught 3 hits from them
      if e.HitPoints > 1 then w.enemies[#w.enemies + 1] = e end
    elseif e:IsActiveEnemy(false) and not e:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) and IsaacBotSolid(e) then
      -- (things that NEVER touch you - Gemini's 18 cord pieces, chains - aren't enemies to dodge or crowd:
      -- counting them, one Gemini looked like 20 enemies and squeezed the bot into a corner. But "no
      -- collision right now" isn't enough: Monstro has none mid-jump and must stay visible to dodge his landing)
      w.enemies[#w.enemies + 1] = e
    end
  end
  return w
end

-- Destructible things that can shield enemies: poop tiles and lit fireplaces.
local breakCache = { frame = -1 }
local function breakables(room)
  -- once per update: this walks every tile of the room (a 2x2 room has 448)
  local f = Game():GetFrameCount()
  if breakCache.frame == f then return breakCache.list end
  local list = {}
  breakCache = { frame = f, list = list }
  for i = 0, room:GetGridSize() - 1 do
    local ge = room:GetGridEntity(i)
    if ge and ge:GetType() == GridEntityType.GRID_POOP and ge.State < 1000
       and ge.CollisionClass ~= GridCollisionClass.COLLISION_NONE then
      list[#list + 1] = { Position = room:GetGridPosition(i), Velocity = Vector.Zero, kind = "poop" }
    end
  end
  for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_FIREPLACE)) do
    if e.HitPoints > 1 then list[#list + 1] = { Position = e.Position, Velocity = Vector.Zero, kind = "fire" } end
  end
  return list
end

-- Ring-kite against a CHASING boss (playbook "chases", or the tactics say "edges"; the author's Gemini rule): the lane
-- (mover.lua ringCost) and which way round to run. The direction keeps the boss behind: it only flips when the boss
-- cuts across in front of us. Nil = no ring (not a chaser, invincible, or the room is too small for a lane).
Reflex.ringDir = 1
function Reflex.ringFor(player, target, w, room)
  if Risk.invincible or not target or target.kind then return nil end
  -- the chaser to kite: the target if it chases, else any chasing boss in the room (Gemini: shooting the small twin
  -- while the big one chases)
  local function chaser(e)
    if e.Type == EntityType.ENTITY_FIREPLACE or not e:IsBoss() then return false end
    local pb, tac = playbookOf(e), Reflex.tacticsOf(e)
    return (pb and pb.tags.chases) or (tac and tac.ring) or false
  end
  local boss = (target.IsBoss and chaser(target)) and target or nil
  if not boss then
    for _, e in ipairs(w.enemies) do if chaser(e) then boss = e; break end end
  end
  if not boss then return nil end
  target = boss
  local S = Reflex.S
  local tl, br = w.tl or room:GetTopLeftPos(), w.br or room:GetBottomRightPos()
  local r = S.ring_r
  local half = math.min(br.X - tl.X, br.Y - tl.Y) / 2 - S.ring_margin - 10
  r = math.min(r, half)
  if r < 30 then return nil end
  local ring = { x0 = tl.X + S.ring_margin + r, x1 = br.X - S.ring_margin - r,
                 y0 = tl.Y + S.ring_margin + r, y1 = br.Y - S.ring_margin - r, r = r,
                 cx = (tl.X + br.X) / 2, cy = (tl.Y + br.Y) / 2 }
  local aI = math.atan(player.Position.Y - ring.cy, player.Position.X - ring.cx)
  local aB = math.atan(target.Position.Y - ring.cy, target.Position.X - ring.cx)
  local diff = aI - aB
  if diff > math.pi then diff = diff - 2 * math.pi elseif diff < -math.pi then diff = diff + 2 * math.pi end
  -- run so the gap to the boss grows; flip only when the boss is close ahead on our current way round
  local away = (diff >= 0) and 1 or -1
  if math.abs(diff) < 0.5 and away ~= Reflex.ringDir then Reflex.ringDir = away end
  ring.dir = Reflex.ringDir
  return ring
end

-- Boss fights (the author, 2026-11-25, after Mega Fatty: the bot shot its little adds for 4 minutes because low HP
-- scored better than the boss's big pool): "Staying alive comes first, but kill the boss before it kills you."
-- With a boss alive the boss is the target, and an add only wins when IT is the threat: close or closing in,
-- a dangerous type (playbook kill priority / danger, shooters, chargers), or we're in a tight spot.
local function bossAliveIn(enemies)
  for _, e in ipairs(enemies) do
    if e.Type ~= EntityType.ENTITY_FIREPLACE and e:IsBoss() and e:IsVulnerableEnemy() then return true end
  end
  return false
end
-- the boss tactics' adds policy for this fight (kill_first: the Haunt's Lil Haunts; ignore: Gemini's), or nil
local function addsPolicy(enemies)
  for _, e in ipairs(enemies) do
    if e.Type ~= EntityType.ENTITY_FIREPLACE and e:IsBoss() then
      local tac = Reflex.tacticsOf(e)
      if tac and tac.adds then return tac.adds end
    end
  end
  return nil
end
Reflex.addsPolicy = addsPolicy
local function minionThreat(e, player, crowded)
  local rel = player.Position - e.Position
  local d = rel:Length()
  local threat = 0
  if d < 160 then threat = threat + 260 * (1 - d / 160) end                       -- close
  local v = e.Velocity or Vector.Zero
  if d > 1 and v:Length() > 1 and v:Dot(rel / d) > 0.6 * v:Length() then         -- closing in on us
    threat = threat + 80
  end
  local pb = playbookOf(e)
  if pb then
    threat = threat + 45 * pb.k + 25 * math.max(0, pb.d - 1)
    if pb.tags.shoots_single or pb.tags.shoots_spread or pb.tags.charges_on_line or pb.tags.dashes_at_isaac
       or pb.tags.explodes_on_contact then threat = threat + 60 end
  end
  if crowded then threat = threat + 120 end                                        -- tight spot: clear room to move
  return threat
end
Reflex.bossAliveIn, Reflex.minionThreat = bossAliveIn, minionThreat

-- Finish it / stick with it (the author, 2026-11-25, Gurglings: "it doesn't make sense to target something, start
-- to do damage on it and then stop just because whatever's closest is closest and isn't in harm's way... he was
-- close to dying and all it would take was redirecting your shots a few times... it would immediately remove one
-- variable from taking damage"). A bonus (lower score = better) for:
--   * how few of OUR shots it would take to kill (1 shot = full finish_w, 5+ shots = none), and
--   * being the target we've already been damaging (commit_w), so it doesn't hop to whatever is nearest.
-- Threats still win: a close or dangerous enemy's own score outweighs this.
Reflex.lastTargetHash = nil
local function finishBonus(e, player)
  if not e or e.kind or not e.HitPoints or e.HitPoints <= 0 then return 0 end
  -- only enemies already worn down: a fresh spider is "one tear from dead" too, and outranked its Sack (tests 17, 17b)
  if not e.MaxHitPoints or e.HitPoints >= e.MaxHitPoints * 0.95 then return 0 end
  local S = Reflex.S
  local shots = e.HitPoints / math.max(0.5, player.Damage)
  local b = S.finish_w * math.max(0, math.min(1, (5 - shots) / 4))
  if Reflex.lastTargetHash == GetPtrHash(e) then b = b + S.commit_w end
  return b
end
Reflex.finishBonus = finishBonus

local function pickTarget(player, enemies, room)
  local best, bestScore = nil, math.huge
  local shielded = nil
  local bossOn = bossAliveIn(enemies)
  local close = 0
  for _, e in ipairs(enemies) do
    if e.Type ~= EntityType.ENTITY_FIREPLACE and (e.Position - player.Position):Length() < 130 then close = close + 1 end
  end
  local crowded = close >= 2
  for _, e in ipairs(enemies) do
    if IsaacBotRedFire(e) then
      -- a red fire shoots at us and tears put it out: a target. Close ones first; a far one waits behind enemies.
      local d = (e.Position - player.Position):Length()
      local score = (d < 260) and (d - 40) or (d + 60)
      if score < bestScore then best, bestScore = e, score end
    elseif e.Type == EntityType.ENTITY_FIREPLACE then
      -- other fires are hazards to avoid, not targets (unless one shields something; see breakables below)
    elseif bossOn and e:IsVulnerableEnemy() and not e:IsInvincible() then
      local d = (e.Position - player.Position):Length()
      local score
      local policy = addsPolicy(enemies)
      if e:IsBoss() then score = d * 0.5 - 100
      elseif policy == "kill_first" then score = d - 250                      -- the adds shield or feed the boss
      elseif policy == "ignore" then score = 150 + d - minionThreat(e, player, crowded) * (d < 90 and 1 or 0.4)
      else score = 150 + d - minionThreat(e, player, crowded) end
      score = score - finishBonus(e, player) -- a nearly dead boss/add, or the one we've been hitting
      if score < bestScore then best, bestScore = e, score end
    elseif e:IsVulnerableEnemy() and not e:IsInvincible() then
      local d = (e.Position - player.Position):Length()
      local score = d + (e:IsBoss() and -60 or 0) + math.min(e.HitPoints, 40) * 0.5
      -- most danger per hit point first (see planFire): Sloth's Chargers before Sloth
      local pbe = playbookOf(e)
      if pbe and e.HitPoints > 0 then score = score - Reflex.S.pb_kill_w * 0.5 * pbe.k * math.min(1, 20 / e.HitPoints) end
      if Reflex.S.kill_w > 0 and e.HitPoints > 0 then
        score = score - Reflex.S.kill_w * 0.5 * (respectOf(e) - 0.9) * math.min(1, 20 / e.HitPoints)
      end
      score = score - finishBonus(e, player) -- finish what's nearly dead; stick with what we've been hitting
      if score < bestScore then best, bestScore = e, score end
    else
      shielded = shielded or e
    end
  end
  if best or not shielded then return best end
  -- Nothing we can hurt, but something is shielded (e.g. a fly tied to a poop): break the nearest
  -- poop or fireplace to it, the way a player would. (the author spotted this, 2026-11-25.)
  -- ...but only something that's really AT it (2026-11-25: a Host, invulnerable while closed, made the bot
  -- "break" a fire across the room and then bomb it). Hosts and the like are fought by baiting them open.
  for _, b in ipairs(breakables(room)) do
    local d = (b.Position - shielded.Position):Length()
    if d < 70 and d < bestScore then best, bestScore = b, d end
  end
  if best then return best end
  -- Nothing to break either: aim at the shielded enemy itself and keep lined up. Many enemies are only
  -- SOMETIMES hurtable (Hosts open up to shoot): the shot lands the moment they open. (Hosts stood unfought.)
  local nearest, nd = nil, math.huge
  for _, e in ipairs(enemies) do
    if e.Type ~= EntityType.ENTITY_FIREPLACE then
      local d = (e.Position - player.Position):Length()
      if d < nd then nearest, nd = e, d end
    end
  end
  return nearest
end

local function laserEnd(lz)
  local ok, p = pcall(function() return lz:GetEndPoint() end)
  if ok and p then return p end
  return lz.Position + Vector.FromAngle(lz.Angle) * (lz.MaxDistance > 0 and lz.MaxDistance or 600)
end

-- cost of moving in direction d for the next few updates
-- Where enemy e will be after t updates, if we're at p (worst case for chasers; see the notes inside).
local function enemyAt(e, w, p, t)
  local S = Reflex.S
  local ep
      if w.pushed[GetPtrHash(e)] then
        ep = e.Position + e.Velocity * math.min(t, 2)
      else
        -- worst case for movers: they come straight at us at their usual (average) speed or faster
        -- (Globins move in bursts; predicting only their current speed let them land 3 hits)
        local sp = math.max(e.Velocity:Length(), Reflex.avgSpeed(e))
        -- Bosses normally keep their real movement (they jump/dash to a spot: assuming a charge misread
        -- Monstro's jump) - UNLESS they're in an animation that has hurt us before (Gemini's walk, Dingle's
        -- slide): then it's a charge, treat it as one.
        -- (a learned "hurtful" animation gives a bigger berth below, but does NOT turn a boss's jump into
        -- an assumed charge: as Monstro's jump animations collected hits, that misread his jumps again)
        -- ...except a boss in a hurtful animation WHILE ON THE GROUND (has collision): Gemini walking at us
        -- (76 hits). Mid-air (no collision, Monstro jumping) keeps the real-movement prediction.
        -- Only a SLOW hurtful mover homes in (walking). A fast one is a straight dash (Dingle's slide): its real
        -- velocity is the right prediction; assuming it bends toward us made the bot flee ALONG the dash line.
        local groundedCharge = e:IsBoss() and w.hurtful and w.hurtful[GetPtrHash(e)]
                               and e.EntityCollisionClass ~= EntityCollisionClass.ENTCOLL_NONE
                               and e.Velocity:Length() < S.dash_speed
        -- Same for ordinary enemies mid-leap (Trites, 2026-11-25: 2-3 hits per pair): a fast straight leap
        -- lands where it's aimed; bending the prediction toward us made the bot run along the leap line.
        local leaping = S.dash_all > 0 and not e:IsBoss() and e.Velocity:Length() >= S.dash_speed
        -- ...but a fast mover that keeps turning after us is a chaser, boss or not (Blighted Ovum)
        local homer = S.homing_min < 1 and Reflex.homing(e) >= S.homing_min
                      and e.EntityCollisionClass ~= EntityCollisionClass.ENTCOLL_NONE
        if homer then leaping = false end
        if sp > 0.5 and e.Type ~= EntityType.ENTITY_FIREPLACE
           and ((not e:IsBoss() and not leaping) or groundedCharge or homer) then
          local to = p - e.Position
          local chase = to:Length() > 1 and to:Normalized() * sp or Vector.Zero
          ep = e.Position + (e.Velocity * 0.4 + chase * 0.6) * t
        else
          ep = bounced(w, e.Position + e.Velocity * t, e.Size)
        end
      end
  return ep
end

local function score(player, room, w, d, speed, target, prefDist, center, choiceIndex, wayPos)
  local S = Reflex.S
  local cost = 0
  local pos, vel = player.Position, player.Velocity
  local pr = player.Size
  local canFly = player.CanFly
  local last = pos
  for t = S.sample, S.horizon, S.sample do
    -- momentum for the first couple of updates, then the new direction at full speed
    local mom = math.min(t, 2)
    local p = pos + vel * mom + d * speed * (t - mom)
    local wall = blocked(room, p, canFly)
    if wall > 0 then
      cost = cost + wall * (1 - t / (S.horizon + 2))
      p = last -- can't go through: stays at the last free spot
    end
    last = p
    local soon = (S.horizon - t + S.sample) / S.horizon -- 1 now ... small later
    for _, s in ipairs(w.shots) do
      local sp = s.Position + s.Velocity * t
      if (sp - p):Length() < pr + s.Size + S.hit_margin then cost = cost + S.hit_cost * soon end
    end
    for _, e in ipairs(w.enemies) do
      -- a light enemy in our line of fire is being knocked back: it won't keep coming at us
      local ep = enemyAt(e, w, p, t)
      local rs = respectOf(e) -- enemies that have hurt us get a wider berth
      if w.hurtful and w.hurtful[GetPtrHash(e)] then rs = rs + 1 end -- and more so mid-"that" animation
      -- bosses: big bodies and dashes faster than the look-ahead sees (~75% of hits were boss bodies)
      local bossPad = e:IsBoss() and S.boss_margin or 0
      if e.Type == EntityType.ENTITY_FIREPLACE then bossPad = S.fire_pad end -- the flame reaches past its body
      if (ep - p):Length() < pr + e.Size + S.touch_margin + bossPad + (rs - 1) * 12 then
        cost = cost + S.touch_cost * soon * rs
      end
    end
    for _, lz in ipairs(w.lasers) do
      if segDist(p, lz.Position, laserEnd(lz)) < pr + 18 then cost = cost + S.hit_cost * soon end
    end
    for _, b in ipairs(w.bombs) do
      if (b.Position - p):Length() < 95 then cost = cost + S.hit_cost * 0.5 * soon end
    end
    -- spikes, creep, lit fires, unkillable leftovers: the shared danger map, priced per half heart
    local dz = math.max(Danger.staticAt(p), creepAt(w, p))
    if dz > 0 then cost = cost + dz * S.danger_w * soon end
  end
  -- Second step (the author, 2026-11-25: "it puts itself in a corner, waits to get hit, then moves"). The
  -- look-ahead above is 0.4 s, so fleeing straight into a corner looked best: furthest from the enemy right
  -- now. Here: from where this move ends, the BEST of 8 follow-up moves for another look-ahead. In a corner
  -- every follow-up is blocked or runs back into the enemy, so the move that leads there pays for it now.
  if S.deep_w > 0 and #w.enemies > 0 and not w.cheap then
    local bestFollow = math.huge
    for k = 1, 8 do
      local dir = DIRS8[k]
      local c, q = 0, last
      for t2 = S.sample * 2, S.horizon, S.sample * 2 do
        local nq = last + dir * speed * t2
        if blocked(room, nq, canFly) > 0 then c = c + S.wall_cost * 0.5; break end
        q = nq
        local T = S.horizon + t2
        for _, e in ipairs(w.enemies) do
          if e.Type ~= EntityType.ENTITY_FIREPLACE then
            local ep = enemyAt(e, w, q, T)
            if (ep - q):Length() < pr + e.Size + S.touch_margin then c = c + S.touch_cost * respectOf(e) end
          end
        end
        for _, s in ipairs(w.shots) do
          if (s.Position + s.Velocity * T - q):Length() < pr + s.Size + S.hit_margin then c = c + S.hit_cost * 0.5 end
        end
        if c >= bestFollow then break end
      end
      if c < bestFollow then bestFollow = c end
      if bestFollow == 0 then break end
    end
    cost = cost + bestFollow * S.deep_w
  end
  local dzEnd = math.max(Danger.staticAt(last), creepAt(w, last))
  if dzEnd > 0 then cost = cost + dzEnd * S.danger_w end -- never park on a hurting square
  -- Killzone-style position evaluation: don't end up in the line of a known shooter we're NOT fighting
  -- (its next shot comes down that row/column)
  for _, e in ipairs(w.shooters or {}) do
    if e ~= target then
      local rel = last - e.Position
      local inLine = math.abs(rel.X) < 22 or math.abs(rel.Y) < 22
      if inLine and rel:Length() < 400 and Reflex.solidLane(room, e.Position, last) < 2 then
        cost = cost + S.shooter_line_w
      end
    end
  end
  -- an enemy is playing a learned WARNING (its next move usually hurts: a dash, a slam): get out of the
  -- line from it to where we are now, which is where a dash goes
  for _, e in ipairs(w.warnings or {}) do
    local dir = w.here - e.Position
    if dir:Length() > 1 then
      local n = dir:Normalized()
      local rel = last - e.Position
      local along = rel:Dot(n)
      local side = math.abs(rel.X * n.Y - rel.Y * n.X)
      if along > -20 and along < 500 and side < e.Size + player.Size + S.dash_side then cost = cost + S.warn_w end
    end
  end
  -- an enemy is winding up an attack it usually aims at us: don't still be standing where we are now
  for _, wu in ipairs(w.windups or {}) do
    local dd = (last - w.here):Length()
    if dd < S.tele_r then cost = cost + S.tele_w * (1 - dd / S.tele_r) end
  end
  local cz = Danger.cautionAt(last)
  if cz > 0 then cost = cost + cz * S.caution_w end -- don't fight next to TNT (a stray shot sets it off)
  -- where we end up: is it a good place to fight from?
  local fp = last
  if wayPos then
    -- a planned firing spot exists: follow the path to it (dodging costs above still win). When calm, commit:
    -- the pull is much stronger and the comfort rules below (walls, corners, centre) are skipped
    cost = cost + (fp - wayPos):Length() * S.fire_w * (w.calm and S.calm_commit or 1)
    if w.calm then
      if choiceIndex == lastChoice then cost = cost - S.keep_w end
      return cost
    end
  elseif target then
    local tp = w.ledPos or target.Position -- line up with where it WILL be
    local dist = (fp - tp):Length()
    -- Circle-strafe against movers (the author: "you can just go around and find a different angle"): reward
    -- moving AROUND the target at a fighting distance instead of parking and waiting for a clean line.
    -- Lines open up as we circle; the curved shots catch the near misses.
    if target.Velocity and Reflex.avgSpeed(target) > 0.6 and d:Length() > 0.5
       and dist > prefDist - 70 and dist < prefDist + 90 then
      local to = tp - fp
      if to:Length() > 1 then
        local n = to:Normalized()
        local tangential = math.abs(d.X * n.Y - d.Y * n.X) -- 1 = moving straight around it
        cost = cost - tangential * S.orbit_w
      end
    end
    cost = cost + math.abs(dist - prefDist) * S.dist_w
    -- lined up AND with an open line of fire; with no enemy shots in the air, lining up matters 3x as much
    -- (it stood a tile off a Clotty's row firing past it)
    cost = cost + bestLane(room, fp, tp) * (#w.shots == 0 and S.calm_align or 1)
  end
  for _, e in ipairs(w.enemies) do
    local dd = (fp - e.Position):Length()
    -- light ones get shot back, not fled... unless it's a swarm (3+ close): then they're a real threat
    -- (Attack Fly swarms from Duke of Flies were 63 hits)
    local cw = (e.Mass < S.light_mass and not w.swarm) and S.crowd_w * S.light_crowd or S.crowd_w
    local rs = respectOf(e)
    local cr = S.crowd_r + (rs - 1) * 25
    if e:IsBoss() then cr, cw = cr * S.boss_crowd, cw * 1.5 end
    if dd < cr then cost = cost + (cr - dd) * cw * rs end
  end
  -- Kiting a chaser (Blighted Ovum, 2026-11-25: nearly every hit was in a corner): running straight AWAY
  -- from something that homes in ends in a corner. Go AROUND it instead, and keep to the middle.
  if S.kite_w > 0 and d:Length() > 0.5 then
    for _, e in ipairs(w.enemies) do
      local rel = e.Position - fp
      if rel:Length() < S.kite_r and e.Velocity:Length() > 2 and Reflex.homing(e) >= S.homing_min then
        local n = rel:Normalized()
        local dn = d:Normalized()
        cost = cost - math.abs(dn.X * n.Y - dn.Y * n.X) * S.kite_w
        cost = cost + (fp - center):Length() * S.kite_center
      end
    end
  end
  -- live bombs (own ones too): a steep slope away from them, so it always heads OUT of the blast
  for _, b in ipairs(w.bombs) do
    local dd = (fp - b.Position):Length()
    if dd < S.bomb_safe then cost = cost + (S.bomb_safe - dd) * S.bomb_w end
  end
  cost = cost + (fp - center):Length() * S.center_w
  if not room:IsPositionInRoom(fp, S.edge_margin) then cost = cost + S.edge_cost end
  -- exit plan (the author's rule): count the ways out of this spot; corners and pockets are traps
  local open = 0
  for k = 1, 8 do
    local dir = DIRS8[k]
    local probe = fp + dir * S.escape_r
    local mid = fp + dir * (S.escape_r * 0.5)
    local free = blocked(room, mid, canFly) == 0 and blocked(room, probe, canFly) == 0
    if free then
      for _, e in ipairs(w.enemies) do
        if (e.Position - mid):Length() < e.Size + 20 or (e.Position - probe):Length() < e.Size + 20 then
          free = false; break
        end
      end
    end
    if free then open = open + 1 else cost = cost + S.escape_w end
  end
  if open < S.escape_min then cost = cost + (S.escape_min - open) * S.trap_w end
  -- Runway (the author, 2026-11-25: "it constantly corners itself"). Running straight AWAY from enemies looks
  -- fine until the wall arrives. So: from this spot, which way is "away from the danger" (closer enemies
  -- count more), and how much open floor is left that way (straight, or peeling off up to 90 degrees)?
  -- Little runway = it'll be pinned next: costly BEFORE it gets there, so it turns and circles instead.
  if S.corner_w > 0 and not w.cheap then
    local threat, pull = Vector(0, 0), 0
    for _, e in ipairs(w.enemies) do
      if e.Type ~= EntityType.ENTITY_FIREPLACE then
        local away = fp - e.Position
        local dd = away:Length()
        if dd < S.corner_r and dd > 1 then
          local k = (S.corner_r - dd) / S.corner_r
          threat = threat + away:Normalized() * k
          pull = pull + k
        end
      end
    end
    if pull > 0.25 and threat:Length() > 0.05 then
      local flee = threat:Normalized()
      local runway = 0
      for _, ang in ipairs({ 0, 45, -45, 90, -90 }) do
        local dir = flee:Rotated(ang)
        local run = 0
        while run < S.corner_need do
          local probe = fp + dir * (run + 20)
          if not room:IsPositionInRoom(probe, 12) or blocked(room, probe, canFly) ~= 0 then break end
          run = run + 20
        end
        runway = math.max(runway, run * (ang == 0 and 1 or (math.abs(ang) == 45 and 0.9 or 0.75)))
      end
      if runway < S.corner_need then
        cost = cost + (S.corner_need - runway) / S.corner_need * S.corner_w * math.min(pull, 2)
      end
    end
  end
  if choiceIndex == lastChoice then cost = cost - S.keep_w end
  return cost
end

-- Aim quality (so bad aiming shows up as a number, not something the author has to spot by eye):
-- every update we fire, could that shot actually hit the target? Counted per enemy type.
Reflex.aim = {}
local DIRV = { left = Vector(-1, 0), right = Vector(1, 0), up = Vector(0, -1), down = Vector(0, 1) }
-- Curved shots (the author, 2026-11-25: "you can curve your shots... by pressing sideways while shooting").
-- Tears inherit part of Isaac's sideways movement, so a moving Isaac bends his shots. How much is MEASURED
-- from the game (Reflex.calibrateCurve below), starting from a guess.
Reflex.curveK = 1.15     -- share of Isaac's sideways velocity a new tear keeps (self-calibrating;
                         -- measured 1.16 over 266 real shots on 2026-11-25, started from a 0.5 guess)
Reflex.curveSamples = 0

-- Would a shot fired now (Isaac moving at `pv`, nil = standing) reach `pos`? Accounts for the curve.
local function shotCanHitAt(room, player, shoot, pos, size, pv)
  local dir = DIRV[shoot]
  if not dir or not pos then return false end
  local rel = pos - player.Position
  local along = rel:Dot(dir)
  if along <= 0 or along > player.TearRange * 1.1 then return false end
  local offset = (dir.X ~= 0) and rel.Y or rel.X               -- signed: where the target sits sideways
  local drift = 0
  if pv then
    local side = (dir.X ~= 0) and pv.Y or pv.X
    local flight = along / (Reflex.S.tear_speed * math.max(0.5, player.ShotSpeed))
    drift = side * Reflex.curveK * flight                       -- how far the tear bends on the way
  end
  if math.abs(offset - drift) > (size or 10) + 8 then return false end
  return Reflex.lane(room, player.Position, pos) < 2
end

-- Real accuracy (the author, 2026-11-25: "it feels like it's just shooting randomly"): tears fired vs tears that
-- hit an enemy (main.lua counts the hits). Reported as an `aim` line.
Reflex.acc = { fired = 0, hit = 0, hitTears = {} }
function Reflex.tearHit(tear, viaPlayer)
  if tear and not viaPlayer then
    local h = GetPtrHash(tear)
    if Reflex.acc.hitTears[h] then return end -- piercing tears count once
    Reflex.acc.hitTears[h] = true
  end
  Reflex.acc.hit = math.min(Reflex.acc.fired, Reflex.acc.hit + 1)
end
function Reflex.accReport()
  local a = Reflex.acc
  local s = string.format("%d%% of %d tears hit", a.fired > 0 and math.floor(100 * a.hit / a.fired) or 0, a.fired)
  Reflex.acc = { fired = 0, hit = 0, hitTears = {} }
  return s
end

-- Watch our own fresh tears: compare their sideways speed with Isaac's sideways speed when fired.
local lastPlayerVel = Vector.Zero
function Reflex.calibrateCurve(player)
  for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_TEAR)) do
    if e.FrameCount == 1 and e.SpawnerType == EntityType.ENTITY_PLAYER then Reflex.acc.fired = Reflex.acc.fired + 1 end
    if e.FrameCount <= 1 and e.SpawnerType == EntityType.ENTITY_PLAYER then
      local v = e.Velocity
      local horizontal = math.abs(v.X) > math.abs(v.Y) -- fired left/right: sideways is Y
      local pSide = horizontal and lastPlayerVel.Y or lastPlayerVel.X
      local tSide = horizontal and v.Y or v.X
      if math.abs(pSide) > 1.5 then
        local k = tSide / pSide
        if k > -0.2 and k < 1.5 then
          Reflex.curveK = Reflex.curveK * 0.9 + k * 0.1
          Reflex.curveSamples = Reflex.curveSamples + 1
        end
      end
    end
  end
  lastPlayerVel = player.Velocity
end
local function shotCanHit(room, player, shoot, t)
  if not t then return false end
  return shotCanHitAt(room, player, shoot, t.Position, t.Size)
end
local function countAim(t, good)
  if not t then return end
  local key = t.kind and ("poop/fire") or (t.Type .. "." .. t.Variant)
  local a = Reflex.aim[key] or { fired = 0, good = 0 }
  a.fired = a.fired + 1
  if good then a.good = a.good + 1 end
  Reflex.aim[key] = a
end
function Reflex.aimReport()
  local parts = {}
  for k, a in pairs(Reflex.aim) do
    if a.fired >= 10 then parts[#parts + 1] = k .. "=" .. math.floor(100 * a.good / a.fired) .. "%/" .. a.fired end
  end
  Reflex.aim = {}
  return table.concat(parts, ",")
end

-- On the planned lane, lined up with its target (within the target's size + a tear's radius)?
function Reflex.linedUp(player)
  local d0 = plan.cell and plan.cell.dir
  if not (plan.target and plan.cellPos and d0) then return false end
  local off = (d0[1] ~= 0) and math.abs(player.Position.Y - plan.target.Position.Y)
                              or math.abs(player.Position.X - plan.target.Position.X)
  return off < math.max(10, (plan.target.Size or 10) * 0.7 + 6) and (plan.cellPos - player.Position):Length() < 40
end

-- Returns the control decision for this update: move vector (or nil = hands off) and shoot direction.
function Reflex.update(player)
  local S = Reflex.S
  local st = Reflex.status
  local room = Game():GetRoom()
  Danger.build(player)
  Reflex.spectral = hasSpectral(player)
  pcall(Reflex.calibrateCurve, player) -- learn how much our tears bend
  local w = gather(player)
  -- how bold to play (risk.lua): twice a second, then the safety settings follow it
  if Game():GetFrameCount() % 15 == 0 or not Risk.base then
    pcall(Risk.update, player, w.enemies)
    Risk.apply(S)
  end
  -- boss attack window (boss tactics): the boss is in an animation where it's safe to hit it (Dingle tired after
  -- its dashes). The author, 2026-11-25: "there are windows where he can lay damage and windows where he focuses on
  -- dodging. He is sitting in the predicted safe spot and it limits the damage he puts on." In a window: close in and
  -- pour damage in (risk.lua WINDOW); outside it, dodge as before. Checked every update: windows are short.
  local win = nil
  for _, e in ipairs(w.enemies) do
    if e.Type ~= EntityType.ENTITY_FIREPLACE and e:IsBoss() then
      local tac = Reflex.tacticsOf(e)
      if tac and tac.hasWindows then
        local a = Tells.animOf(e)
        -- never an animation that's also a tell (Dingle's Whistle comes right before the spit)
        if a and tac.windows[a] and not tac.tells[a] then win = a; break end
      end
    end
  end
  if win ~= Risk.window then
    Risk.window = win
    Risk.apply(S)
    Risk.lastSent = -1 -- log it
  end
  -- invincible window (Unicorn Stump & co., rules.lua R.invincible): checked every update, it only lasts seconds
  local inv = Risk.invincibleNow(player)
  if inv ~= Risk.invincible then
    Risk.invincible = inv
    Risk.apply(S)
    Risk.lastSent = -1 -- log the change
    if Risk.onInvincible then Risk.onInvincible(inv) end
  end
  st.threats = #w.shots + #w.lasers + #w.bombs
  Reflex.trackSpeeds(w.enemies, player)
  pcall(Mover.observe, w.enemies, player, Game():GetFrameCount(), w.shots) -- learning runs whichever core drives
  pcall(Mover.observePlayer, player, math.max(2.5, player.MoveSpeed * S.speed_mul)) -- and Isaac's own movement
  local lightNear = 0
  for _, e in ipairs(w.enemies) do
    if e.Mass < S.light_mass and (e.Position - player.Position):Length() < S.swarm_r then lightNear = lightNear + 1 end
  end
  w.swarm = lightNear >= S.swarm_n
  -- tells: learn which animations end in a shot, and spot wind-ups happening now
  pcall(Tells.update, w.enemies)
  w.windups, w.here, w.shooters, w.hurtful = {}, player.Position, {}, {}
  w.warnings = {}
  for _, e in ipairs(w.enemies) do
    local okH, hh = pcall(Tells.hurtful, e)
    if okH and hh then w.hurtful[GetPtrHash(e)] = hh end
    local okW, warn = pcall(Tells.warning, e)
    if okW and warn then w.warnings[#w.warnings + 1] = e end
    local ok, eta = pcall(Tells.windingUp, e)
    if ok and eta then w.windups[#w.windups + 1] = { e = e, eta = eta } end
    -- a shot coming soon (the animation that usually comes right before a shooting one): aimed at where Isaac is
    local ok3, coming = pcall(Tells.shotComing, e)
    if ok3 and coming then
      w.aimed = w.aimed or {}
      w.aimed[#w.aimed + 1] = { from = e.Position, at = player.Position, eta = (ok and eta) or S.shot_coming_eta,
                                size = e.Size or 0 } -- a big dasher's line is as wide as its body
    end
    local ok2, sh = pcall(Tells.isShooter, e.Type)
    if ok2 and sh then w.shooters[#w.shooters + 1] = e end
  end
  -- knockback: light enemies sitting in the lane we're shooting down get pushed back by our tears
  w.pushed = {}
  local lastShot = st.shoot
  if lastShot and lastShot ~= "" then
    local dir = ({ left = Vector(-1, 0), right = Vector(1, 0), up = Vector(0, -1), down = Vector(0, 1) })[lastShot]
    local reach = player.TearRange
    for _, e in ipairs(w.enemies) do
      -- light enemies, or ones the playbook says tears knock back (Suckers are heavier than the light-mass cut)
      local pbk = playbookOf(e)
      if e.Mass < S.light_mass or (pbk and pbk.tags.knocked_back_by_tears) then
        local rel = e.Position - player.Position
        local along = rel:Dot(dir)
        local side = math.abs(dir.X ~= 0 and rel.Y or rel.X)
        if along > 0 and along < reach and side < e.Size + 10 then w.pushed[GetPtrHash(e)] = true end
      end
    end
  end
  local real, hurtable = 0, 0
  for _, e in ipairs(w.enemies) do
    if e.Type ~= EntityType.ENTITY_FIREPLACE then
      real = real + 1
      if e:IsVulnerableEnemy() and not e:IsInvincible() then hurtable = hurtable + 1 end
    elseif IsaacBotRedFire(e) then
      -- a lit red fire keeps shooting: put it out, even in a cleared room
      real, hurtable = real + 1, hurtable + 1
    end
  end
  -- fires alone don't make a fight; and once the room counts as cleared, leftover unkillable things
  -- (spiked blocks, eternal flies...) are hazards to walk around, not a fight to win (the author's spiked block)
  -- Shots in the air used to make it a fight on their own. In a CLEARED room with nothing hurtable left, the shots
  -- come from unkillable things (a Constant Stone Shooter built into the room, 2026-11-25: it aimed at the statue
  -- and the stuck ladder started bombing it). Then: no fight, walk on; only dodge a shot that's about to arrive.
  local threats = st.threats
  st.dodgeOnly = false
  if threats > 0 and hurtable == 0 and room:IsClear() and not Reflex.forceFight then
    threats = 0
    for _, s in ipairs(w.shots) do
      local rel = player.Position - s.Position
      if rel:Length() < S.dodge_only_r and s.Velocity:Dot(rel) > 0 then threats = threats + 1 end
    end
    for _, lz in ipairs(w.lasers) do threats = threats + 1 end
    for _, b in ipairs(w.bombs) do
      if (b.Position - player.Position):Length() < 140 then threats = threats + 1 end
    end
    st.dodgeOnly = threats > 0
  end
  -- moving unkillable leftovers close by (Eternal Flies circling in a cleared room: the walker treated them as fixed
  -- hazards where they were a moment ago and walked into them 4 times, 2026-11-25) -> dodge-only too
  if hurtable == 0 and room:IsClear() and not Reflex.forceFight then
    for _, e in ipairs(w.enemies) do
      if e.Type ~= EntityType.ENTITY_FIREPLACE and Reflex.avgSpeed(e) > 0.6
         and (e.Position - player.Position):Length() < S.dodge_only_r then
        threats = threats + 1
        st.dodgeOnly = true
      end
    end
  end
  local fighting = threats > 0 or hurtable > 0 or (real > 0 and not room:IsClear())
                   or (real > 0 and Reflex.forceFight) -- gauntlet rounds count as real fights
  st.active = (st.mode ~= "off") and fighting
  if not st.active then
    st.move, st.shoot, st.target, lastChoice = -1, "", nil, -1
    return nil
  end

  local speed = math.max(2.5, player.MoveSpeed * S.speed_mul)
  local prefDist = math.min(S.pref_dist, player.TearRange * 0.55)
  local center = room:GetCenterPos()

  -- targets the planner may choose from: hurtable enemies, nearest first (or what shields them)
  local targets = {}
  for _, e in ipairs(w.enemies) do
    if (e.Type ~= EntityType.ENTITY_FIREPLACE and e:IsVulnerableEnemy() and not e:IsInvincible())
       or IsaacBotRedFire(e) then
      targets[#targets + 1] = e
    end
  end
  -- spawners first (a Sack making spiders): killing what they make is pointless until they're gone. Found by
  -- asking the game who spawned each live enemy - no per-enemy list.
  w.spawners = {}
  for _, e in ipairs(w.enemies) do
    local sp = e.SpawnerEntity
    if sp and sp:Exists() then w.spawners[GetPtrHash(sp)] = true end
  end
  table.sort(targets, function(a, b)
    local sa, sb = w.spawners[GetPtrHash(a)] and 1 or 0, w.spawners[GetPtrHash(b)] and 1 or 0
    if sa ~= sb then return sa > sb end
    return (a.Position - player.Position):LengthSquared() < (b.Position - player.Position):LengthSquared()
  end)
  while #targets > 5 do table.remove(targets) end
  local fallback = pickTarget(player, w.enemies, room)
  if #targets == 0 and fallback then targets[1] = fallback end
  -- a target chosen by the brain/watchdog wins while it's still there
  local ft = plan.forcedTarget
  if ft and Game():GetFrameCount() < ft.untilF then
    local alive
    if ft.t.kind then
      local ge = ft.t.idx and room:GetGridEntity(ft.t.idx)
      alive = (ge ~= nil) and ge.CollisionClass ~= GridCollisionClass.COLLISION_NONE
    else
      alive = ft.t:Exists() and not ft.t:IsDead()
    end
    if alive then targets, fallback = { ft.t }, ft.t else plan.forcedTarget = nil end
  else
    plan.forcedTarget = nil
  end
  local tPlan0 = Isaac.GetTime()
  local okPlan, planErr = pcall(planFire, player, room, w, targets, prefDist)
  -- Hurtable enemies, but no firing spot on any of them (boxed in by rocks, a poop as the only gate: the author
  -- 2026-11-25, "all it needs to do is shoot the poop"). Then the poops and fires right next to them become
  -- targets: break the gate, then fight.
  if okPlan and not plan.target and #targets > 0 then
    -- ...but only for an enemy that's really WALLED IN: no open line onto it from any side. (2026-11-25: in the
    -- Dingle fight the planner had no spot only because Dingle moves, and the bot shot poop instead of the boss.)
    local function walledIn(t)
      for _, dir in ipairs({ Vector(1, 0), Vector(-1, 0), Vector(0, 1), Vector(0, -1) }) do
        local from = t.Position + dir * 160
        if room:IsPositionInRoom(from, 10) and Reflex.lane(room, from, t.Position) == 0 then return false end
      end
      return true
    end
    local gates = {}
    for _, b in ipairs(breakables(room)) do
      for _, t in ipairs(targets) do
        if not t.kind and walledIn(t) and (b.Position - t.Position):Length() < S.gate_r then gates[#gates + 1] = b; break end
      end
    end
    if #gates > 0 then
      table.sort(gates, function(a, b)
        return (a.Position - player.Position):LengthSquared() < (b.Position - player.Position):LengthSquared()
      end)
      plan.at = -999 -- the planner just ran this update; let it run again for the gates
      okPlan, planErr = pcall(planFire, player, room, w, gates, prefDist)
    end
  end
  Reflex.prof.plan = Reflex.prof.plan + (Isaac.GetTime() - tPlan0)
  if not okPlan then
    plan.target, plan.path, plan.cell, plan.cellPos = nil, nil, nil, nil
    Reflex.planError = tostring(planErr)
  else
    Reflex.planError = nil
  end
  local target = plan.target or fallback
  if st.dodgeOnly then target = nil end -- cleared room, only unkillable shooters left: just dodge, don't aim
  if target and not target.kind and target.IsBoss and target:IsBoss() then
    -- fight bosses from farther out: the boss's own distance from the tactics file when there is one
    local tac = Reflex.tacticsOf(target)
    local extra = (Reflex.lessonOf(target) or {}).dist or 0 -- the watcher learned to keep farther from this boss
    if Risk.invincible then prefDist = S.pref_dist -- untouchable right now: point-blank, whatever the boss
    elseif tac and tac.pd then
      -- close in only in a REST window (after an attack: Tired, Pant, Stop, Landing...), not in Idle: an idling
      -- dasher dashes next
      local rest = Risk.window and REST_ANIM[Risk.window]
      prefDist = math.min((tac.pd + extra) * (rest and 0.65 or 1), player.TearRange * 0.85)
    else prefDist = math.max(prefDist, math.min(S.boss_dist + extra, player.TearRange * 0.8)) end
  end
  -- A shielded enemy that opens when you come close (Hosts: "you gotta walk up for them to open, and then
  -- they shoot. While they're shooting, that's your window to hit them." - the author): bait it from close range.
  if target and not target.kind and target.IsVulnerableEnemy
     and not (target:IsVulnerableEnemy() and not target:IsInvincible()) then
    prefDist = S.bait_dist
  end
  local wayPos = plan.target and waypoint(room, player) or nil
  -- dodging in a cleared room: keep walking where the walker was going (its next step and goal), not stand around
  local navSpot = nil
  if st.dodgeOnly and IsaacBotNavAim and Game():GetFrameCount() - IsaacBotNavAim.f < 45 then
    wayPos, navSpot = IsaacBotNavAim.pos, IsaacBotNavAim.final
  end
  -- Buttons (the author, 2026-11-25: a room of pressure plates guarded by invulnerable shooting heads; it fought the
  -- heads instead of walking to the buttons). Nothing hurtable + an unpressed plate = the nearest plate is the goal;
  -- the movement core still dodges on the way.
  local plateSpot = nil
  if hurtable == 0 then
    local best = math.huge
    for i = 0, room:GetGridSize() - 1 do
      local ge = room:GetGridEntity(i)
      if ge and ge:GetType() == GridEntityType.GRID_PRESSURE_PLATE and ge.State < 3 then
        local pos = room:GetGridPosition(i)
        local d = (pos - player.Position):Length()
        if d < best then best, plateSpot = d, pos end
      end
    end
    if plateSpot then wayPos, target = plateSpot, nil; st.goalText = "pressing a button" end
  end
  st.plan = plan.cell and plan.cell.idx or nil

  -- Where the target WILL be when a tear gets there. Positioning and aiming both use this (positioning used
  -- the current spot before, so against moving enemies it lined up with where they had been).
  local ledPos = nil
  if target then
    local tt = (target.Position - player.Position):Length() / (S.tear_speed * math.max(0.5, player.ShotSpeed))
    ledPos = target.Position + Reflex.leadVel(target) * math.min(tt, 30)
    pcall(function() ledPos = room:GetClampedPosition(ledPos, target.Size or 10) end) -- it turns at the walls
  end
  w.ledPos = ledPos
  -- calm = nothing in the air and nobody close: safe to commit to walking to the firing spot
  -- (only enemies that MOVE count, or anything right on top of us: two Horfs standing still 130 px away
  -- made it "not calm", and it froze one step from its firing spot)
  local calm = (#w.shots == 0 and #w.lasers == 0 and #w.bombs == 0)
  if calm then
    for _, e in ipairs(w.enemies) do
      if e.Type ~= EntityType.ENTITY_FIREPLACE then
        local d = (e.Position - player.Position):Length()
        if d < 70 or (d < S.calm_r and Reflex.avgSpeed(e) > 0.6) then calm = false; break end
      end
    end
  end
  w.calm = calm

  local best, bestCost, standCost = 0, math.huge, nil
  local usedV2 = false
  -- the plan looks 1.2 s ahead, so re-thinking every other update is plenty (halves the cost; big rooms lagged)
  local fNow = Game():GetFrameCount()
  if S.core == 2 and S.m_every > 1 and fNow % S.m_every ~= 0 and Mover.lastMove and Mover.lastFrame
     and fNow - Mover.lastFrame < S.m_every + 1 then
    best, bestCost, usedV2 = Mover.lastMove, 0, true
  elseif S.core == 2 then
    local tMove0 = Isaac.GetTime()
    local ring, bossAim = Reflex.ringFor(player, target, w, room), nil
    if target and not target.kind and target.IsBoss and target:IsBoss() then bossAim = S.boss_aim end
    Reflex.status.ring = ring ~= nil
    local okM, mi, mc = pcall(Mover.choose, { S = S, w = w, room = room, player = player, speed = speed, DIRS = DIRS,
      ring = ring, bossAim = bossAim,
      target = target, prefDist = prefDist, wayPos = wayPos,
      -- (ring-kiting: no fixed firing spot; the lane and the open line behind the boss do that job)
      spot = (not ring) and (plateSpot or navSpot or (plan.target and plan.cellPos)) or nil, calm = calm, blocked = blocked, creepAt = creepAt,
      bounce = function(pos, r) return bounced(w, pos, r) end, lane = Reflex.lane, segDist = segDist,
      laserEnd = laserEnd, playbookOf = playbookOf, tacticsOf = Reflex.tacticsOf, leadVel = Reflex.leadVel,
      lessonOf = Reflex.lessonOf, shotPadOf = Reflex.shotPadOf, telling = Reflex.telling })
    Reflex.prof.move = Reflex.prof.move + (Isaac.GetTime() - tMove0)
    if okM and mi then best, bestCost, usedV2 = mi, mc, true; Reflex.v2err = nil
    else Reflex.v2err = tostring(mi) end -- falls back to the old core this update; main.lua reports it
  end
  if not usedV2 then
    -- Two passes (the author, 2026-11-25: the game ran at half speed in big rooms). Pass 1 scores all moves
    -- without the expensive checks (2-step look-ahead, runway); pass 2 re-scores only the best few + standing.
    w.cheap = true
    local quick = {}
    for i = 0, #DIRS do
      quick[#quick + 1] = { i = i, c = score(player, room, w, DIRS[i], speed, target, prefDist, center, i, wayPos) }
    end
    w.cheap = false
    table.sort(quick, function(a, b) return a.c < b.c end)
    local finalists = { [0] = true }
    for k = 1, math.min(S.deep_k, #quick) do finalists[quick[k].i] = true end
    for i in pairs(finalists) do
      local c = score(player, room, w, DIRS[i], speed, target, prefDist, center, i, wayPos)
      if i == 0 then standCost = c end
      if c < bestCost or (c == bestCost and i < best) then best, bestCost = i, c end
    end
  end

  -- shooting: lead the target, then fire along whichever axis has the open line (not just the closest one)
  local shoot = nil
  st.target, st.walled = nil, false
  local d0 = plan.cell and plan.cell.dir
  local lined = false
  if plan.target and plan.cellPos and d0 then
    -- lined up = on the lane's axis within the target's size (not just "near the spot")
    local off = (d0[1] ~= 0) and math.abs(player.Position.Y - plan.target.Position.Y)
                               or math.abs(player.Position.X - plan.target.Position.X)
    lined = off < math.max(10, (plan.target.Size or 10) * 0.7 + 6) -- + about a tear's radius
             and (plan.cellPos - player.Position):Length() < 40
  end
  if lined or (plan.target and plan.cellPos and (plan.cellPos - player.Position):Length() < S.on_spot) then
    -- on the planned lane: shoot straight down it at the target
    local d = plan.cell.dir -- direction from the target to this square
    if d[1] == 1 then shoot = "left" elseif d[1] == -1 then shoot = "right"
    elseif d[2] == 1 then shoot = "up" else shoot = "down" end
    st.target = plan.target
  elseif target then
    local tp = target.Position
    local tt = (tp - player.Position):Length() / (S.tear_speed * math.max(0.5, player.ShotSpeed))
    tp = tp + target.Velocity * tt
    local dx, dy = tp.X - player.Position.X, tp.Y - player.Position.Y
    local _, axis, state = bestLane(room, player.Position, tp)
    if axis == "row" then shoot = (dx > 0) and "right" or "left"
    else shoot = (dy > 0) and "down" or "up" end
    -- walled in = no open (or poop-only) lane to the target from any of the 4 sides
    if state == 2 then
      st.walled = true
      for _, dir in ipairs({ Vector(1, 0), Vector(-1, 0), Vector(0, 1), Vector(0, -1) }) do
        local from = target.Position + dir * 220
        if room:IsPositionInRoom(from, 10) and Reflex.lane(room, from, target.Position) < 2 then
          st.walled = false; break
        end
      end
    end
    st.target = target
  end

  -- Would this shot land? Straight (standing still), or curved by the move we're about to make.
  local lands, curved = false, false
  if shoot and st.target then
    local t = st.target
    local tp = ledPos or t.Position
    lands = shotCanHitAt(room, player, shoot, tp, t.Size) or shotCanHit(room, player, shoot, t)
    if not lands then
      local pv = player.Velocity * 0.5 + DIRS[best] * speed * 0.5 -- where our speed is heading this update
      curved = shotCanHitAt(room, player, shoot, tp, t.Size, pv)
    end
  end
  -- Tears carry Isaac's movement: side-stepping while firing curves the shots off (the author: "it offsets itself
  -- by quite a bit"). The shot lands and nothing's forcing a move -> stand still and shoot straight.
  -- ...but never while something that moves is closing in (all 3 Globin hits came while standing still)
  local moverNear = false
  for _, e in ipairs(w.enemies) do
    if e.Type ~= EntityType.ENTITY_FIREPLACE and Reflex.avgSpeed(e) > 0.6
       and (e.Position - player.Position):Length() < S.stand_safe_r then moverNear = true; break end
  end
  if not moverNear and (lands or Reflex.linedUp(player)) and standCost and standCost - bestCost < S.still_tolerance then
    best = 0
  end
  -- Every tear starts a reload, so a shot that can't land delays the next real one: hold fire.
  -- (Gauntlet 2026-11-25: only 40-45% of shots could land against Gapers and Maggots.)
  -- (a shot that only lands thanks to the curve is fired WHILE moving: that's the pivot)
  -- Run AND shoot (the author, 2026-11-25: "why is it not shooting behind itself against these flies? You can
  -- shoot and run"). The planned target's shot won't land -> any enemy a shot WOULD hit right now, in any of
  -- the 4 directions (behind us while fleeing included), nearest first.
  if S.any_shot > 0 and not lands and not curved and not (st.target and st.target.kind) then
    local pv = player.Velocity * 0.5 + DIRS[best] * speed * 0.5
    local bestD, pick, pickDir = math.huge, nil, nil
    for _, e in ipairs(w.enemies) do
      if e.Type == EntityType.ENTITY_FIREPLACE or e:IsVulnerableEnemy() then
        local dd = (e.Position - player.Position):Length()
        if dd < bestD then
          for _, sd in ipairs({ "left", "right", "up", "down" }) do
            if shotCanHitAt(room, player, sd, e.Position, e.Size, pv) then
              bestD, pick, pickDir = dd, e, sd
              break
            end
          end
        end
      end
    end
    if pick then shoot, curved, st.target = pickDir, true, pick end
  end
  -- Spray when roughly in line (the author, 2026-11-25: "way too carefully" vs spiders). Jumpy enemies are never a
  -- SURE hit, so "only fire if it lands" meant it never fired at all; tears are free and spiders die in two.
  -- All 4 directions, lane from Isaac's real position (offline test K2: in a one-tile corridor the chosen axis
  -- pointed into rock, so a spider roughly in line to the right never got a tear).
  if shoot and not lands and not curved and st.target and not st.target.kind and S.loose_aim > 0 then
    -- where it will be when the tear gets there (a fast boss is long gone from where it is now)
    local tpos = st.target.Position
    if st.target.Velocity then
      local tt = (tpos - player.Position):Length() / (S.tear_speed * math.max(0.5, player.ShotSpeed))
      tpos = tpos + Reflex.leadVel(st.target) * math.min(tt, 30)
    end
    local rel = tpos - player.Position
    for _, sd in ipairs({ shoot, "left", "right", "up", "down" }) do
      local dir = ({ left = Vector(-1, 0), right = Vector(1, 0), up = Vector(0, -1), down = Vector(0, 1) })[sd]
      local along = rel:Dot(dir)
      local off = math.abs(dir.X ~= 0 and rel.Y or rel.X)
      if along > 0 and along < player.TearRange and off < S.loose_aim
         and Reflex.lane(room, player.Position, player.Position + dir * along) < 2 then
        shoot, curved = sd, true -- counts as "worth firing"
        break
      end
    end
  end
  if shoot and not lands and not curved and not (st.target and st.target.kind) then shoot = nil end
  lastChoice = best
  -- remember who we're shooting at (finishBonus: stick with the enemy we've been damaging)
  if st.target and not st.target.kind and shoot then Reflex.lastTargetHash = GetPtrHash(st.target) end
  st.move, st.cost = best, math.floor(bestCost)
  st.shoot = shoot or ""
  st.curved = curved
  if shoot then countAim(st.target, lands or curved) end
  return DIRS[best], shoot
end

return Reflex
