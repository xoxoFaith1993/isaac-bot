-- Isaac Bot game data: the game's own knowledge, dumped once per launch for the helper and the brain.
-- Items, trinkets and cards from the game's ItemConfig (name, quality 0-4, type, charges, tags), plus the
-- English description from External Item Descriptions when that mod is on. Written to this mod's save file;
-- the helper copies it to knowledge\gamedata.json in the bot's folder.

local data = RegisterMod("Isaac Bot (game data)", 1)
local json = require("json")
local done = false

local function eidText(kind, id)
  local ok, r = pcall(function()
    local t = EID and EID.descriptions and EID.descriptions["en_us"] and EID.descriptions["en_us"][kind]
    local e = t and t[id]
    if type(e) == "table" then return { name = e[2] or e.name, desc = e[3] or e.description } end
    return nil
  end)
  return ok and r or nil
end

local function clean(s)
  if type(s) ~= "string" then return nil end
  return (s:gsub("#", " / "):gsub("{{.-}}", ""):gsub("%s+", " "))
end

local function dump()
  local cfg = Isaac.GetItemConfig()
  local out = { made = Isaac.GetTime(), items = {}, trinkets = {}, cards = {} }
  local n = cfg:GetCollectibles().Size - 1
  for id = 1, n do
    local it = cfg:GetCollectible(id)
    if it then
      local e = eidText("collectibles", id)
      out.items[#out.items + 1] = { id = id, name = (e and e.name) or it.Name, quality = it.Quality, type = it.Type,
        charges = it.MaxCharges, tags = it.Tags, desc = clean(e and e.desc) }
    end
  end
  for id = 1, cfg:GetTrinkets().Size - 1 do
    local it = cfg:GetTrinket(id)
    if it then
      local e = eidText("trinkets", id)
      out.trinkets[#out.trinkets + 1] = { id = id, name = (e and e.name) or it.Name, desc = clean(e and e.desc) }
    end
  end
  for id = 1, cfg:GetCards().Size - 1 do
    local it = cfg:GetCard(id)
    if it then
      local e = eidText("cards", id)
      out.cards[#out.cards + 1] = { id = id, name = (e and e.name) or it.Name, desc = clean(e and e.desc) }
    end
  end
  data:SaveData(json.encode(out))
  if IsaacBotOut then IsaacBotOut.push("data|0|ready|" .. #out.items .. " items, " .. #out.trinkets .. " trinkets, " .. #out.cards .. " cards") end
end

-- once per launch, at the first run start (EID has loaded its tables by then)
data:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
  if done then return end
  done = true
  local ok, err = pcall(dump)
  if not ok and IsaacBotOut then IsaacBotOut.push("error|0|gamedata: " .. tostring(err)) end
end)
