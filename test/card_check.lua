-- Card check (forecast plan step 1, 2026-11-26; docs/FORECAST_PLAN.md "The fallback", point 3): every enemy card's
-- body forecast against what the enemy really did in the recordings (the recorder's "rec" lines in runs/logs and
-- runs/live.log). For each recorded enemy track: where the card said it would be 6 and 16 updates later, and where
-- plain coasting (keep the current velocity) would have put it, both against where it really went.
--   better = the card beats coasting; same; WORSE = the card is wrong somewhere (a "move" fact to re-read).
-- Run: powershell -File tools\card_check.ps1   (writes runs/recorder/CARD_CHECK.md)

local root = MOD_DIR:gsub("/mod/isaac%-bot$", "")
local Forecast = dofile(MOD_DIR .. "/forecast.lua")
local okC, cards = pcall(dofile, MOD_DIR .. "/cards.lua")
if not okC then return "ERROR cards.lua: " .. tostring(cards) end
Forecast.setCards(cards)

local files = {}
local lf = io.open(root .. "/runs/recorder/rec_files.txt", "r")
if lf then for l in lf:lines() do if l ~= "" then files[#files + 1] = l end end lf:close() end
files[#files + 1] = root .. "/runs/live.log"

-- parse: one sample per rec line
local samples = {}
for _, path in ipairs(files) do
  local fh = io.open(path, "r")
  if fh then
    for line in fh:lines() do
      local body = line:match("^%d%d:%d%d:%d%d rec%s+(.*)$")
      if body then
        local f, pl, rest = body:match("^(%d+)|([^|]*)|(.*)$")
        if f then
          local p = {}
          for n in pl:gmatch("[^,]+") do p[#p + 1] = tonumber(n) end
          local s = { f = tonumber(f), ix = p[1], iy = p[2], ivx = p[3], ivy = p[4], e = {} }
          for part in rest:gmatch("[^;]+") do
            local v = {}
            for x in part:gmatch("[^,]+") do v[#v + 1] = x end
            if #v >= 19 then
              s.e[#s.e + 1] = { key = v[1], frame = tonumber(v[3]), state = tonumber(v[4]), x = tonumber(v[6]), y = tonumber(v[7]),
                                vx = tonumber(v[8]), vy = tonumber(v[9]), tx = tonumber(v[14]), ty = tonumber(v[15]),
                                size = 13 }
            end
          end
          if s.ix then samples[#samples + 1] = s end
        end
      end
    end
    fh:close()
  end
end

-- segments: runs of samples with no gap over 30 updates (a room change or a pause starts a new one); the floor's
-- bounds are taken from every position seen in the segment
local segs, cur = {}, nil
for _, s in ipairs(samples) do
  if not cur or s.f - cur[#cur].f > 30 or s.f < cur[#cur].f then cur = {}; segs[#segs + 1] = cur end
  cur[#cur + 1] = s
end

local stats = {}
local function add(key, t, eF, eB)
  local st = stats[key] or { n = 0, F = { [6] = {}, [16] = {} }, B = { [6] = {}, [16] = {} } }
  stats[key] = st
  if t == 6 then st.n = st.n + 1 end
  st.F[t][#st.F[t] + 1] = eF
  st.B[t][#st.B[t] + 1] = eB
end

for _, seg in ipairs(segs) do
  local b = { x0 = math.huge, y0 = math.huge, x1 = -math.huge, y1 = -math.huge }
  for _, s in ipairs(seg) do
    for _, e in ipairs(s.e) do
      b.x0, b.y0, b.x1, b.y1 = math.min(b.x0, e.x), math.min(b.y0, e.y), math.max(b.x1, e.x), math.max(b.y1, e.y)
    end
    b.x0, b.y0, b.x1, b.y1 = math.min(b.x0, s.ix), math.min(b.y0, s.iy), math.max(b.x1, s.ix), math.max(b.y1, s.iy)
  end
  b.x0, b.y0, b.x1, b.y1 = b.x0 - 14, b.y0 - 14, b.x1 + 14, b.y1 + 14
  -- tracks: link each enemy to the nearest of the same kind in the previous sample
  for i = 2, #seg do
    local s0, s1 = seg[i - 1], seg[i]
    for _, e in ipairs(s1.e) do
      local best, bd = nil, 40 + math.sqrt(e.vx * e.vx + e.vy * e.vy) * 3
      for _, p in ipairs(s0.e) do
        if p.key == e.key and not p.next then
          local d = math.sqrt((p.x - e.x) ^ 2 + (p.y - e.y) ^ 2)
          if d < bd then best, bd = p, d end
        end
      end
      if best then best.next = e; e.prevF = s0.f end
    end
  end
  for i, s in ipairs(seg) do
    local ivx, ivy = s.ivx, s.ivy
    if not ivx and seg[i - 1] then
      local dt = math.max(1, s.f - seg[i - 1].f)
      ivx, ivy = (s.ix - seg[i - 1].ix) / dt, (s.iy - seg[i - 1].iy) / dt
    end
    local isaac = { x = s.ix, y = s.iy, vx = ivx or 0, vy = ivy or 0 }
    for _, e in ipairs(s.e) do
      -- follow the track to the samples 6 and 16 updates later
      local q, f = e, s.f
      local at = {}
      for _ = 1, 10 do
        q = q.next
        if not q then break end
        f = f + 2
        at[f - s.f] = q
      end
      local card = Forecast.cardFor(e.key)
      for _, t in ipairs({ 6, 16 }) do
        local real = at[t]
        if real then
          local fx, fy = Forecast.body(card, e, t, isaac, b)
          local bx, by = e.x + e.vx * t, e.y + e.vy * t
          bx = math.max(b.x0, math.min(b.x1, bx)); by = math.max(b.y0, math.min(b.y1, by))
          add(e.key, t, math.sqrt((fx - real.x) ^ 2 + (fy - real.y) ^ 2), math.sqrt((bx - real.x) ^ 2 + (by - real.y) ^ 2))
        end
      end
    end
  end
end

local function median(xs)
  if #xs == 0 then return 0 end
  table.sort(xs)
  return xs[(#xs + 1) // 2]
end

local keys = {}
for k in pairs(stats) do keys[#keys + 1] = k end
table.sort(keys, function(a, b) return stats[a].n > stats[b].n end)
local out = { "# Card check: body forecasts vs recordings", "",
  string.format("%d recorded samples, %d segments. Error = px between forecast and where the enemy really was.", #samples, #segs),
  "Coasting = keep the current velocity (what the bot assumes without a card).", "",
  "| Enemy | Card | Move kind | Pairs | Card error 6 / 16 | Coasting error 6 / 16 | Verdict |",
  "|---|---|---|---|---|---|---|" }
local worse = 0
for _, k in ipairs(keys) do
  local st = stats[k]
  if st.n >= 20 then
    local card = Forecast.cardFor(k)
    local f6, f16, b6, b16 = median(st.F[6]), median(st.F[16]), median(st.B[6]), median(st.B[16])
    local verdict = "no card"
    if card then
      if f16 < b16 * 0.85 then verdict = "better"
      elseif f16 > b16 * 1.15 + 4 then verdict = "**WORSE**"; worse = worse + 1
      else verdict = "same" end
    end
    out[#out + 1] = string.format("| %s | %s | %s | %d | %.0f / %.0f | %.0f / %.0f | %s |", k, card and card.name or "-",
      card and card.move and card.move.kind or "-", st.n, f6, f16, b6, b16, verdict)
  end
end
out[#out + 1] = ""
out[#out + 1] = string.format("%d card(s) WORSE than coasting: re-read their `move` facts (targeted second read).", worse)
local text = table.concat(out, "\n")
local wf = io.open(root .. "/runs/recorder/CARD_CHECK.md", "w")
if wf then wf:write(text .. "\n"); wf:close() end
return text
