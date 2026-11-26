-- Positioning brain (forecast plan step 3, 2026-11-26; docs/FORECAST_PLAN.md). The slow layer over the reflexes:
-- twice a second it picks a HOME SPOT from the room map (roommap.lua); the reflexes keep dodging every update and,
-- when nothing is coming, walk to it.
--
-- The author, 2026-11-26: "This game is solely made on positioning properly"; "They know where to go when things fall
-- shy. They have a game plan ready at any situation"; "If you have an escape plan that you know for certain that you
-- won't get hurt in, then focus on laying damage down and getting a good angle".
--
-- Three fixed goals, in order, the same for every enemy (enemy knowledge goes into the forecast, never in here):
--   1. no hit:   only tiles Isaac gets to first (the map's "ours"), and not in a line attacker's row or column where
--                neither sidestep is open (Gluttony's rock gap);
--   2. way out:  the most room to move from there, up to "plenty" (S.pos_sure tiles = a sure way out);
--   3. damage:   with plenty of room, a tile in line with the target at a good distance; with little room the way out
--                wins (it counts half).
-- The home spot is kept until another one is clearly better (S.pos_keep), so it doesn't flip-flop.

local Position = { home = nil, idx = nil, at = -999, why = "", score = nil }

-- in a line attacker's row/column with no open, harmless tile to step to on either side
local function trapped(map, i, lines)
  if #lines == 0 then return false end
  local W = map.W
  local x, y = map.ox + 40 * (i % W), map.oy + 40 * (i // W)
  for _, ln in ipairs(lines) do
    local dx, dy = x - ln.x, y - ln.y
    if dx * dx + dy * dy < 420 * 420 then
      local inRow, inCol = math.abs(dy) < ln.half, math.abs(dx) < ln.half
      if inRow or inCol then
        local a, b
        if inRow then a, b = i - W, i + W else a, b = i - 1, i + 1 end
        local okA = map.open[a] and not map.haz[a]
        local okB = map.open[b] and not map.haz[b]
        if not okA and not okB then return true end
      end
    end
  end
  return false
end

-- in line with the target, within range, nothing solid between: a tear from here can land
local function laneTo(map, i, tp, range, room, solidLane)
  if not tp then return false, 0 end
  local p = map:pos(i)
  local dx, dy = tp.X - p.X, tp.Y - p.Y
  local d = math.sqrt(dx * dx + dy * dy)
  if d > range then return false, d end
  if math.abs(dx) > 20 and math.abs(dy) > 20 then return false, d end
  return solidLane(room, p, tp) == 0, d
end

-- ctx = { S, f, room, map, target position (tp), prefDist, range, lines, solidLane, reacting }
-- Returns the home spot (Vector) and the next tile on the way there (Vector or nil).
function Position.update(ctx)
  local S, map, f = ctx.S, ctx.map, ctx.f
  -- goal 1 broken right where Isaac stands (in a line attacker's row/column, no sidestep): the reflexes must COMMIT
  -- to the home spot, not drift toward it (offline test 74: the shot lane on Gluttony held it 55 px short, in his row)
  Position.leave = map.start ~= nil and trapped(map, map.start, ctx.lines)
  local due = math.abs(f - Position.at) >= S.pos_every or ctx.reacting
  -- the home spot stopped being ours (an enemy got closer to it than we are): choose again now
  if Position.idx and not (map:ours(Position.idx) and not trapped(map, Position.idx, ctx.lines)) then due = true end
  if not due and Position.idx then
    local nx = map:nextStep(Position.idx)
    return Position.home, nx and map:pos(nx) or nil
  end
  Position.at = f
  local cap, sure = S.pos_cap, S.pos_sure
  local best, bestS, oldS = nil, math.huge, nil
  local nOurs = 0
  for i = 0, map.N - 1 do
    local t = map.ti[i]
    if t and t <= S.pos_reach and map:ours(i) and not trapped(map, i, ctx.lines) then
      nOurs = nOurs + 1
      local roomN = map:roomFrom(i, cap, S.pos_depth)
      -- goal 2: room to move, counted only up to "plenty" (more than a sure way out isn't worth giving up the damage
      -- goal for - offline test 77), then the walk there
      local s = -math.min(roomN, sure) + (t / map.stepT) * S.pos_travel
      -- goal 3: damage - full value with a sure way out, half without
      if ctx.tp then
        local lane, d = laneTo(map, i, ctx.tp, ctx.range, ctx.room, ctx.solidLane)
        if lane then
          local w = (roomN >= sure) and 1 or 0.5
          local near = math.max(0, 1 - math.abs(d - ctx.prefDist) / math.max(40, ctx.prefDist))
          s = s - S.pos_lane * w * (0.5 + 0.5 * near)
        end
      end
      if i == Position.idx then oldS = s end
      if s < bestS then best, bestS = i, s end
    end
  end
  if not best then
    -- nowhere is ours (surrounded): no home spot; the reflexes dodge on their own
    Position.home, Position.idx, Position.score = nil, nil, nil
    Position.why = "no tile is ours"
    return nil, nil
  end
  -- no good home: the best one has too little room (the tiles Isaac reaches first have shrunk into a corner as a crowd
  -- closed in). A home there would hold him in the trap; without one the reflexes dodge out past them (offline test
  -- 73: with the corner as home it spent 20 of 240 updates in the corner, 0 without the brain)
  if map:roomFrom(best, cap, S.pos_depth) < S.pos_min then
    Position.home, Position.idx, Position.score = nil, nil, nil
    Position.why = "no good home (cornered): reflexes only"
    return nil, nil
  end
  if oldS and oldS <= bestS + S.pos_keep then best, bestS = Position.idx, oldS end
  Position.idx, Position.score = best, bestS
  Position.home = map:pos(best)
  Position.why = string.format("home %d,%d: room %d, %d tiles ours", best % map.W, best // map.W,
    map:roomFrom(best, cap, S.pos_depth), nOurs)
  local nx = map:nextStep(best)
  return Position.home, nx and map:pos(nx) or nil
end

function Position.reset() Position.home, Position.idx, Position.at, Position.score = nil, nil, -999, nil end

return Position
