-- Isaac Bot outbox: the game -> PC direction.
-- The game holds log.txt in memory, so the bot's messages go into this mod's save-data file instead.
-- File layout:
--   S|<session>
--   T|<latest state snapshot>   (only the newest one; replaced 10x a second)
--   G|<latest room grid>        (only the newest one; replaced when the room or its rocks change)
--   id|kind|frame|body          (up to MAX event lines, newest last)
-- The helper reads the file and handles every event id it hasn't seen yet.

local out = RegisterMod("Isaac Bot (outbox)", 1)

IsaacBotOut = {
  session = tostring(Isaac.GetTime()),
  id = 0,
  buf = {},
  latest = {},       -- key ("T", "G") -> text
  dirty = false,
  MAX = 40,
  WRITE_EVERY = 3,   -- render frames -> up to 20 writes a second, only when there's something new
}

function IsaacBotOut.push(line)
  local o = IsaacBotOut
  o.id = o.id + 1
  o.buf[#o.buf + 1] = o.id .. "|" .. line
  if #o.buf > o.MAX then table.remove(o.buf, 1) end
  o.dirty = true
end

function IsaacBotOut.setLatest(key, text)
  IsaacBotOut.latest[key] = text
  IsaacBotOut.dirty = true
end

local function flush()
  local o = IsaacBotOut
  if not o.dirty then return end
  local parts = { "S|" .. o.session }
  if o.latest.T then parts[#parts + 1] = "T|" .. o.latest.T end
  if o.latest.G then parts[#parts + 1] = "G|" .. o.latest.G end
  for _, l in ipairs(o.buf) do parts[#parts + 1] = l end
  out:SaveData(table.concat(parts, "\n"))
  o.dirty = false
end

out:AddCallback(ModCallbacks.MC_POST_RENDER, function()
  if Isaac.GetFrameCount() % IsaacBotOut.WRITE_EVERY == 0 then flush() end
end)

-- Main menu (REPENTOGON callback): keep flushing so menu autopilot messages get out too.
local menuFrame = 0
out:AddCallback(ModCallbacks.MC_MAIN_MENU_RENDER, function()
  menuFrame = menuFrame + 1
  if menuFrame % IsaacBotOut.WRITE_EVERY == 0 then pcall(flush) end
end)

out:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, flush)
