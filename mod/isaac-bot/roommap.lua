-- Room map (forecast plan step 3, 2026-11-26; docs/FORECAST_PLAN.md). One picture of the room for the positioning
-- brain (position.lua): for every tile, can Isaac stand there, does it hurt, when can Isaac get there, and when can the
-- nearest enemy. The author, 2026-11-26: "The best people on the top of the leaderboard know the map... They know
-- where to go when things fall shy. They have a game plan ready at any situation."
--
--   RoomMap.build(room, player, enemies, opt) -> map
--     opt = { speed = Isaac's px per update, espeed = slowest an enemy is assumed to move (px/update),
--             margin = updates Isaac must be there ahead of every enemy }
--   map:ours(i)          a tile Isaac gets to clearly first, open and harmless
--   map:roomFrom(i, cap) how many "ours" tiles Isaac can still reach going on from i (a flood fill), up to cap
--   map:pos(i), map:index(pos), map:nextStep(i)  tile centre, tile of a point, the first step on the way to tile i
--
-- Plain numbers inside (no game Vectors in the loops): it is built every update in a fight, in rooms up to 28x16.

local Danger = include("danger")
local RoomMap = {}
RoomMap.__index = RoomMap

local GCC = GridCollisionClass
local sqrt, huge = math.sqrt, math.huge

function RoomMap.build(room, player, enemies, opt)
  local W, H = room:GetGridWidth(), room:GetGridHeight()
  local N = W * H
  local o = room:GetGridPosition(0)
  local fly = player.CanFly
  local open, haz = {}, {}
  for i = 0, N - 1 do
    local cc = room:GetGridCollision(i)
    if fly then open[i] = cc ~= GCC.COLLISION_WALL and cc ~= GCC.COLLISION_WALL_EXCEPT_PLAYER
    else open[i] = cc == GCC.COLLISION_NONE end -- rocks, poops (Larry Jr.'s too), pits, blocks: closed
    haz[i] = (not fly) and Danger.staticCell(i) > 0 -- spikes, harmful creep (Gurglings), lit fires
  end
  local speed = math.max(1, opt.speed or 4.6)
  local stepT = 40 / speed -- updates per tile
  -- when the nearest enemy can get to each tile: a straight line from its edge at its speed (at least `espeed`, so a
  -- resting enemy isn't treated as harmless). Fires and cords don't walk.
  local movers = {}
  local pr = player.Size or 10
  for _, e in ipairs(enemies) do
    if e.Type ~= EntityType.ENTITY_FIREPLACE and e.Position and (not IsaacBotSolid or IsaacBotSolid(e)) then
      local v = e.Velocity
      -- its speed now or its learned average, whichever is higher (a hopper resting between hops isn't slow), and at
      -- least `espeed` (2 px/update as a floor made a slow Gaper own two thirds of the room: offline test 77)
      local sp = math.max(opt.espeed or 1, v and sqrt(v.X * v.X + v.Y * v.Y) or 0, opt.speedOf and opt.speedOf(e) or 0)
      movers[#movers + 1] = { e.Position.X, e.Position.Y, (e.Size or 13) + pr, sp }
    end
  end
  local te = {}
  for i = 0, N - 1 do
    if open[i] then
      local cx, cy = o.X + 40 * (i % W), o.Y + 40 * (i // W)
      local best = huge
      for _, m in ipairs(movers) do
        local dx, dy = cx - m[1], cy - m[2]
        local t = (sqrt(dx * dx + dy * dy) - m[3]) / m[4]
        if t < best then best = t end
      end
      te[i] = best
    end
  end
  -- when Isaac can get to each tile: a breadth-first walk over open, harmless tiles that he reaches before any enemy
  -- (the far side of a crowd isn't "ours" just because it's far from them: the walk there goes through them - offline
  -- test 73, 2026-11-26). 4 neighbours: a little slow on diagonals, the safe side for "Isaac gets there first".
  local margin = opt.margin or 6
  local start = room:GetGridIndex(player.Position)
  local ti, prev = {}, {}
  if start and start >= 0 and start < N then
    ti[start] = 0
    local q, head = { start }, 1
    while q[head] do
      local i = q[head]; head = head + 1
      local r, c = i // W, i % W
      local nt = ti[i] + stepT
      for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
        local rr, cc = r + d[1], c + d[2]
        if rr >= 0 and cc >= 0 and rr < H and cc < W then
          local j = rr * W + cc
          if ti[j] == nil and open[j] and not haz[j] and nt + margin < (te[j] or huge) then
            ti[j], prev[j] = nt, i
            q[#q + 1] = j
          end
        end
      end
    end
  end
  return setmetatable({ W = W, H = H, N = N, ox = o.X, oy = o.Y, open = open, haz = haz, ti = ti, prev = prev, te = te,
                        start = start, stepT = stepT, margin = opt.margin or 6, roomMemo = {} }, RoomMap)
end

function RoomMap:pos(i) return Vector(self.ox + 40 * (i % self.W), self.oy + 40 * (i // self.W)) end

function RoomMap:index(p)
  local c, r = (p.X - self.ox + 20) // 40, (p.Y - self.oy + 20) // 40
  if c < 0 or r < 0 or c >= self.W or r >= self.H then return nil end
  return math.floor(r * self.W + c)
end

-- a tile Isaac gets to clearly before any enemy, open and harmless
function RoomMap:ours(i)
  local t = self.ti[i]
  return t ~= nil and t + self.margin < (self.te[i] or huge)
end

-- how many "ours" tiles Isaac can still reach going on from tile i (arriving at i when the map says he can) within
-- `depth` steps, up to cap. A corner, a tunnel or a pocket closed by poops has few; open floor away from the enemies
-- has many. (Depth-limited: counted without a limit, a pocket with a one-tile gap scored as much as open floor,
-- because the whole room is reachable through the gap - offline test 76, 2026-11-26.)
function RoomMap:roomFrom(i, cap, depth)
  depth = depth or 4
  local key = (i * 256 + cap) * 16 + depth
  local v = self.roomMemo[key]
  if v then return v end
  local t0 = self.ti[i]
  if not t0 then return 0 end
  local W, H, open, haz, te, stepT, margin = self.W, self.H, self.open, self.haz, self.te, self.stepT, self.margin
  local seen, steps, q, head, n = { [i] = t0 }, { [i] = 0 }, { i }, 1, 0
  while q[head] and n < cap do
    local j = q[head]; head = head + 1
    n = n + 1
    if steps[j] < depth then
      local r, c = j // W, j % W
      local nt = seen[j] + stepT
      for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
        local rr, cc = r + d[1], c + d[2]
        if rr >= 0 and cc >= 0 and rr < H and cc < W then
          local k = rr * W + cc
          if seen[k] == nil and open[k] and not haz[k] and nt + margin < (te[k] or huge) then
            seen[k], steps[k] = nt, steps[j] + 1
            q[#q + 1] = k
          end
        end
      end
    end
  end
  self.roomMemo[key] = n
  return n
end

-- the first tile to walk to on the way to tile i (nil when i is where Isaac is, or out of reach)
function RoomMap:nextStep(i)
  if self.ti[i] == nil then return nil end
  local cur = i
  while self.prev[cur] and self.prev[cur] ~= self.start do cur = self.prev[cur] end
  if cur == self.start then return nil end
  return cur
end

return RoomMap
