-- Isaac Bot bestiary: the game's own facts about every enemy and boss, dumped from inside the game (REPENTOGON),
-- because the game's ResourceExtractor crashes on Repentance+ archives (2026-11-25).
-- Per entity (entities2.xml via XMLData): ids, name, HP, size, mass, contact damage, boss/champion flags, tags.
-- Per animation file: every animation's name, length, looping, and the frames its events fire on ("Shoot",
-- "Jump", "Land"...), so the bot knows each enemy's tells before it ever gets hit.
-- The per-floor RoomConfig pass is DISABLED: run mid-game it corrupted the live floor and crashed the game
-- (2026-11-25); see dump(). Written to this mod's save file; tools\bestiary_game.py copies it to knowledge\bestiary_game.json (local only:
-- game-derived data is never committed). Runs once per game version, in small slices so the game never stutters.

local mod = RegisterMod("Isaac Bot (bestiary)", 1)
local json = require("json")
local DUMP_VERSION = 1
local BUDGET_MS = 6     -- work per game update before yielding
local job = nil         -- the running coroutine
local started = false

local function say(kind, text)
  if IsaacBotOut then pcall(IsaacBotOut.push, "data|0|" .. kind .. "|" .. text) end
  Isaac.DebugString("[isaac-bot-bestiary] " .. text)
end

-- event names seen in Isaac's anm2 files; GetEventTriggerFrames needs the name, the game can't list them
local EVENTS = { "Shoot", "Shoot2", "Shoot3", "Shoot4", "Shot", "Fire", "Attack", "Attack2", "Spit", "Puke",
  "Vomit", "Laser", "LaserStart", "LaserEnd", "Brimstone", "Jump", "Land", "Landed", "Lift", "Leap", "Hop",
  "Spawn", "Spawn2", "Summon", "Birth", "Dash", "Charge", "ChargeStart", "Lunge", "Slam", "Stomp", "Smash",
  "Throw", "Explode", "Explosion", "Burrow", "DigIn", "DigOut", "Emerge", "Submerge", "Hide", "Appear",
  "Disappear", "Teleport", "Fart", "Inhale", "Suck", "Release", "Open", "Close", "Bounce", "Stop", "Start",
  "End", "Hit", "Swing", "Bite", "Grab", "Roar", "Scream", "Cough", "Sound", "Sound2", "Blood", "BloodStart",
  "BloodStop", "Shake", "Wake", "Sleep", "Turn", "Rise", "Fall", "Drop", "Step", "Squish" }

-- floors to read (StbType ids from REPENTOGON's enums; names are ours)
local STAGES = {
  { 0, "Special rooms" }, { 1, "Basement" }, { 2, "Cellar" }, { 3, "Burning Basement" }, { 27, "Downpour" },
  { 28, "Dross" }, { 4, "Caves" }, { 5, "Catacombs" }, { 6, "Flooded Caves" }, { 29, "Mines" }, { 30, "Ashpit" },
  { 7, "Depths" }, { 8, "Necropolis" }, { 9, "Dank Depths" }, { 31, "Mausoleum" }, { 32, "Gehenna" },
  { 10, "Womb" }, { 11, "Utero" }, { 12, "Scarred Womb" }, { 33, "Corpse" }, { 13, "Blue Womb" },
  { 14, "Sheol" }, { 15, "Cathedral" }, { 16, "Dark Room" }, { 17, "Chest" }, { 26, "The Void" },
  { 34, "Mortis" }, { 35, "Home" }, { 36, "Ascent" },
}

local t0 = 0
local function tick()
  if Isaac.GetTime() - t0 > BUDGET_MS then coroutine.yield(); t0 = Isaac.GetTime() end
end

local function scalars(tbl)
  local out, kids = {}, 0
  for k, v in pairs(tbl) do
    local tv = type(v)
    if tv == "string" or tv == "number" or tv == "boolean" then out[k] = v
    elseif tv == "table" then kids = kids + 1 end
  end
  if kids > 0 then out._children = kids end
  return out
end

-- reading a missing field of a game object can throw instead of returning nil
local function field(obj, k)
  if obj == nil then return nil end
  local ok, v = pcall(function() return obj[k] end)
  if ok then return v end
  return nil
end

local function call(obj, name, ...)
  if not obj then return nil end
  local f = field(obj, name)
  if type(f) ~= "function" then return nil end
  local ok, r = pcall(f, obj, ...)
  if ok then return r end
  return nil
end

-- every enemy/boss row of entities2.xml (types 10-999)
local function readEntities(out)
  local n = XMLData.GetNumEntries(XMLNode.ENTITY)
  out.entity_entries = n
  local list, anmPaths = {}, {}
  for i = 1, n do
    local ok, e = pcall(XMLData.GetEntryByOrder, XMLNode.ENTITY, i)
    if ok and type(e) == "table" then
      local t = tonumber(e.id)
      if t and t >= 10 and t < 1000 then
        local row = scalars(e)
        local v, s = tonumber(e.variant) or 0, tonumber(e.subtype) or 0
        row.key = t .. "." .. v
        local okc, cfg = pcall(EntityConfig.GetEntity, t, v, s)
        if okc and cfg and call(cfg, "GetVariant") == v then
          row.cfg = { base_hp = call(cfg, "GetBaseHP"), stage_hp = call(cfg, "GetStageHP"),
            radius = call(cfg, "GetCollisionRadius"), mass = call(cfg, "GetMass"),
            contact_damage = call(cfg, "GetCollisionDamage"), shield = call(cfg, "GetShieldStrength"),
            is_boss = call(cfg, "IsBoss"), boss_id = call(cfg, "GetBossID"),
            can_champion = call(cfg, "CanBeChampion"), tags = call(cfg, "GetEntityTags"),
            friction = call(cfg, "GetFriction"), anm2 = call(cfg, "GetAnm2Path") }
        end
        local p = (row.cfg and row.cfg.anm2) or e.anm2path
        if type(p) == "string" and p ~= "" then row.anm2 = p; anmPaths[p] = true end
        list[#list + 1] = row
      end
    end
    tick()
  end
  out.entities = list
  return anmPaths
end

local function loadSprite(path)
  for _, p in ipairs({ "gfx/" .. path, path }) do
    local ok, s, loaded = pcall(Sprite, p, false)
    if ok and s and loaded ~= false then
      local all = call(s, "GetAllAnimationData")
      if type(all) == "table" and #all > 0 then return s, all end
    end
  end
  return nil
end

-- every animation of every enemy sprite, with event frames
local function readAnimations(out, anmPaths)
  local anims, missing = {}, 0
  for path in pairs(anmPaths) do
    local s, all = loadSprite(path)
    if not s then
      missing = missing + 1
    else
      local list = {}
      for _, a in ipairs(all) do
        local name = call(a, "GetName")
        if name then
          local rec = { name = name, len = call(a, "GetLength"), loop = call(a, "IsLoopingAnimation") }
          local ev = nil
          for _, en in ipairs(EVENTS) do
            local frames = call(s, "GetEventTriggerFrames", name, en)
            if type(frames) == "table" and #frames > 0 then
              local fs = {}
              for _, f in ipairs(frames) do fs[#fs + 1] = tonumber(f) or f end
              ev = ev or {}
              ev[en] = fs
            end
          end
          rec.events = ev
          list[#list + 1] = rec
        end
        tick()
      end
      anims[path] = list
    end
  end
  out.animations = anims
  out.anm2_missing = missing
end

local function get(container, i)
  local g = field(container, "Get")
  if type(g) ~= "function" then return nil end
  local ok, r = pcall(g, container, i)
  if ok then return r end
  return nil
end

local function size(container)
  if not container then return 0 end
  local ok, n = pcall(function() return container.Size end)
  if ok and type(n) == "number" then return n end
  ok, n = pcall(function() return #container end)
  if ok and type(n) == "number" then return n end
  return 0
end

-- each spawn point's possible entities (a spawn can roll one of several)
local function spawnEntries(sp)
  local res = {}
  local entries = field(sp, "Entries")
  if entries then
    local n = size(entries)
    local base = get(entries, 0) and 0 or 1
    for j = base, base + n - 1 do
      local e = get(entries, j)
      if e then res[#res + 1] = e end
    end
  end
  local pick = field(sp, "PickEntry")
  if #res == 0 and type(pick) == "function" then
    local n = tonumber(field(sp, "EntryCount")) or 1
    for j = 1, math.max(1, n) do
      local ok, e = pcall(pick, sp, (j - 0.5) / math.max(1, n))
      if ok and e then res[#res + 1] = e end
    end
  end
  return res
end

-- which enemies each floor's rooms spawn, split by room type (1 normal, 5 boss, 6 miniboss, 11 challenge...)
local function readRooms(out)
  local floors = {}
  for _, st in ipairs(STAGES) do
    local id, label = st[1], st[2]
    local f = { stb = id, name = label, rooms = 0, by_room_type = {} }
    local okS, stage = pcall(RoomConfig.GetStage, id)
    local set = okS and stage and call(stage, "GetRoomSet", 0)
    if not set then
      f.error = "no room set"
    else
      local n = size(set)
      local base = get(set, 0) and 0 or 1
      for i = base, base + n - 1 do
        local r = get(set, i)
        if r then
          f.rooms = f.rooms + 1
          local rt = tostring(field(r, "Type") or "?")
          local bucket = f.by_room_type[rt] or {}
          f.by_room_type[rt] = bucket
          local seen = {}
          local spawns = field(r, "Spawns")
          local ns = size(spawns)
          local sbase = (spawns and get(spawns, 0)) and 0 or 1
          for k = sbase, sbase + ns - 1 do
            local sp = spawns and get(spawns, k)
            if sp then
              for _, e in ipairs(spawnEntries(sp)) do
                local t = tonumber(field(e, "Type"))
                if t and t >= 10 and t < 1000 then
                  local key = t .. "." .. (tonumber(field(e, "Variant")) or 0)
                  if not seen[key] then seen[key] = true; bucket[key] = (bucket[key] or 0) + 1 end
                end
              end
            end
          end
        end
        tick()
      end
    end
    floors[#floors + 1] = f
  end
  out.floors = floors
end

local function dump()
  t0 = Isaac.GetTime()
  local began = Isaac.GetTime()
  local out = { v = DUMP_VERSION, made = os and os.time and os.time() or 0,
    repentogon = REPENTOGON and REPENTOGON.Version or nil, event_names_tried = EVENTS }
  local steps = {}
  local ok, anmPaths = pcall(readEntities, out)
  steps.entities = ok or tostring(anmPaths)
  if ok then
    local ok2, err2 = pcall(readAnimations, out, anmPaths)
    steps.animations = ok2 or tostring(err2)
  end
  -- NO per-floor room pass during a run: reading other stages' RoomConfig mid-run (first dump, 2026-11-25 20:36)
  -- left garbage RoomDescriptor data in the live floor's unvisited rooms and crashed the game at 20:49 loading one
  -- (access violation). readRooms is kept below for reference only and must never be called while a run is live;
  -- floor spawn lists come from the wiki (tools\wiki_bestiary.py) and the first dump's saved copy.
  steps.rooms = "disabled (corrupts the live floor)"
  out.steps = steps
  out.complete = (steps.entities == true and steps.animations == true)
  out.ms = Isaac.GetTime() - began
  local nAnm = 0
  for _ in pairs(out.animations or {}) do nAnm = nAnm + 1 end
  mod:SaveData(json.encode(out))
  say("ready", "bestiary: " .. #(out.entities or {}) .. " entities, " .. nAnm .. " sprites, " ..
    #(out.floors or {}) .. " floors, " .. out.ms .. " ms" .. (out.complete and "" or " (INCOMPLETE, see steps)"))
end

local function alreadyDone()
  if not mod:HasData() then return false end
  local ok, old = pcall(json.decode, mod:LoadData())
  if not ok or type(old) ~= "table" then return false end
  local okN, n = pcall(XMLData.GetNumEntries, XMLNode.ENTITY)
  -- any earlier complete dump counts (the first one, v1, already holds entities, sprites and floors)
  return type(old.v) == "number" and old.v <= DUMP_VERSION and old.complete == true and okN
    and old.entity_entries == n
end

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
  if started then return end
  started = true
  if not (XMLData and EntityConfig and RoomConfig) then
    say("error", "bestiary: REPENTOGON APIs missing (XMLData/EntityConfig/RoomConfig)")
    return
  end
  if alreadyDone() then say("ready", "bestiary: up to date, skipped"); return end
  job = coroutine.create(dump)
end)

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
  if not job then return end
  local ok, err = coroutine.resume(job)
  if not ok then say("error", "bestiary: " .. tostring(err)); job = nil
  elseif coroutine.status(job) == "dead" then job = nil end
end)
