-- Isaac Bot: an AI player for The Binding of Isaac: Repentance+.
--   Stage 0: two-way pipe to the helper on the PC + main-menu autopilot (slot 2, new run as Isaac).
--   Stage 1: eyes (eyes.lua) - the whole room as data, 10x a second, plus an in-game overlay.
--
--   mod -> helper : through the "isaac-bot-out" mod's save file (IsaacBotOut). log.txt is only written to
--                   disk late, so it gets a copy of events for debugging, nothing live.
--   helper -> mod : the helper writes "H|session" + its last 20 commands "seq|command|payload" into this
--                   mod's save-data file; we read it 10x a second with mod:LoadData() and run each new one.
--
-- Auto-start only happens while the helper runs with --auto (it sends "autostart").
-- Without the helper, the mod never touches the menu, so your own play is untouched.
-- A run is only ever started when SAVE SLOT 2 is the loaded slot (slot 1 is the player's own save).

local mod = RegisterMod("Isaac Bot", 1)
local json = require("json")
local Eyes = include("eyes")
local Reflex = include("reflex")
local Nav = include("nav")
local Rescue = include("rescue")
local Rules = include("rules")
local Danger = include("danger")
local Options = include("options")
-- handed to the watchdog so it can build the brain's multiple-choice menu
local MODS = { Reflex = Reflex, Nav = Nav, Danger = Danger, Options = Options, Rescue = Rescue, json = json }

local VERSION = "1.1.53"
Reflex.status.mode = "full" -- fight + walk + explore (Stage 3); "combat" = fights only, "off" = hands off
local TAG = "IBOT|"
local BOT_SLOT = 2
local POLL_EVERY = 6        -- render frames (60 per second) -> 10 checks a second
local STATE_EVERY = 3       -- game updates (30 per second) -> 10 snapshots a second
local GRID_CHECK_EVERY = 15 -- game updates -> twice a second
local RED = { 0.78, 0.16, 0.24 }

local helperSession = nil
local lastSeq = 0
local status = "waiting for helper"
local lastContact = -100000
local menuFrame = 0
local overlay = true
local lastGrid = nil
local lastSnap = nil
local eyesError = nil

-- main-menu autopilot
local auto = {
  wanted = false,     -- helper asked for a run
  disabled = false,   -- gave up; stays off until the game restarts
  slot = IsaacBotSlot, -- save slot the player actually picked (kept across a code reload)
  awaitSlot = false,
  wait = 0,           -- menu frames to wait before the next step
  elements = { 1, 2, 0 }, -- save-menu entries to try for slot 2 (1 = slot 2, found 2026-11-25)
  tries = 0,
  saveTries = 0,
  lastMenu = nil,
  forceEl = nil,
  asks = 0,
}

local function now()
  return Isaac.GetFrameCount()
end

local function send(kind, body)
  local line = kind .. "|" .. tostring(now()) .. "|" .. (body or "")
  Isaac.DebugString(TAG .. line)
  if IsaacBotOut then IsaacBotOut.push(line) end -- the outbox mod may load after us; it's there by run time
end
Nav.onNote = function(text) send("nav", text) end -- doors given up on, bounce breaks: into the log

-- The title, save and game-over screens don't read buttons through MC_MENU_INPUT_ACTION (only restart
-- and fullscreen go through it), so the helper sends a real Enter key to the game window instead.
-- We only ever ask for it on the title and save screens and on the bot's own (slot 2) game-over screen,
-- never on the game menu, where Enter could "Continue" the player's own run on slot 1.
local function needEnter(where)
  auto.asks = auto.asks + 1
  send("need", "enter|" .. where .. "|" .. auto.asks)
end

---------------------------------------------------------------- reflexes + controls (Stage 2)
-- The bot only drives in its own slot-2 runs. In "combat" mode it takes over while there's a fight and
-- hands the controls back when the room is clear, so the player can walk it to the next room.
local ctl = { move = nil, shoot = nil, bomb = false }
local MOVE = { left = ButtonAction.ACTION_LEFT, right = ButtonAction.ACTION_RIGHT,
               up = ButtonAction.ACTION_UP, down = ButtonAction.ACTION_DOWN }
local SHOOT = { left = ButtonAction.ACTION_SHOOTLEFT, right = ButtonAction.ACTION_SHOOTRIGHT,
                up = ButtonAction.ACTION_SHOOTUP, down = ButtonAction.ACTION_SHOOTDOWN }

local function botAllowed()
  return auto.slot == BOT_SLOT
end

local function controlValue(action)
  if not ctl.move then return nil end -- hands off
  local m = ctl.move
  if action == MOVE.left then return math.max(0, -m.X) end
  if action == MOVE.right then return math.max(0, m.X) end
  if action == MOVE.up then return math.max(0, -m.Y) end
  if action == MOVE.down then return math.max(0, m.Y) end
  for dir, a in pairs(SHOOT) do
    if action == a then return (ctl.shoot == dir) and 1 or 0 end
  end
  if action == ButtonAction.ACTION_BOMB then return ctl.bomb and 1 or 0 end
  if action == ButtonAction.ACTION_ITEM then return ctl.item and 1 or 0 end
  return nil
end

mod:AddCallback(ModCallbacks.MC_INPUT_ACTION, function(_, ent, hook, action)
  if not ctl.move or not ent or ent.Type ~= EntityType.ENTITY_PLAYER then return nil end
  local v = controlValue(action)
  if v == nil then return nil end
  if hook == InputHook.GET_ACTION_VALUE then return v end
  if hook == InputHook.IS_ACTION_PRESSED then return v > 0.3 end
  if hook == InputHook.IS_ACTION_TRIGGERED then
    return (action == ButtonAction.ACTION_BOMB or action == ButtonAction.ACTION_ITEM) and v > 0.5
  end
  return nil
end)

-- arena test: a wave of Basement enemies around the room; reports clear time and hits taken
local POOL = { "10.0", "12.0", "13.0", "14.0", "15.0", "18.0", "23.0", "26.0", "29.0", "217.0" }
local arena = nil

-- Room replay bench ("goroom"): one real room layout, fought from full health; reports clear time and hits.
local bench = nil
local function benchRoomStart()
  -- only the room "goto" makes (the debug room, index -3), not whatever room the bot walks into next
  if bench and not bench.started and Game():GetLevel():GetCurrentRoomIndex() == -3 then
    bench.started = Game():GetFrameCount()
  end
end
local function benchCheck(send)
  if not (bench and bench.started) then
    if bench and Game():GetFrameCount() - bench.asked > 300 then send("bench", "failed|room didn't load"); bench = nil end
    return
  end
  local f = Game():GetFrameCount()
  local secs = string.format("%.1f", (f - bench.started) / 30)
  local result = nil
  if Isaac.GetPlayer(0):IsDead() then result = "died"
  elseif Game():GetRoom():IsClear() and f - bench.started > 15 then result = "cleared"
  elseif f - bench.started > 30 * 90 then result = "timeout" end
  if result then
    send("bench", result .. "|" .. secs .. "|" .. bench.hits .. "|" .. bench.kind .. "." .. bench.variant)
    bench = nil
  end
end

local function spawnAt(t, v, near, minDist)
  local room, p = Game():GetRoom(), Isaac.GetPlayer(0)
  local pos
  for _ = 1, 20 do
    pos = room:GetRandomPosition(40)
    if (pos - p.Position):Length() >= (minDist or 150) then break end
  end
  pos = room:FindFreePickupSpawnPosition(pos, 0, true)
  return Isaac.Spawn(t, v, 0, pos, Vector.Zero, nil)
end

local function startArena(n)
  local p = Isaac.GetPlayer(0)
  p:AddHearts(24)
  local names = {}
  for _ = 1, n do
    local pick = POOL[math.random(#POOL)]
    local t, v = pick:match("(%d+)%.(%d+)")
    spawnAt(tonumber(t), tonumber(v))
    names[#names + 1] = pick
  end
  arena = { start = Game():GetFrameCount(), hits = 0, dmg = 0, wave = table.concat(names, ","), n = n }
  send("arena", "start|" .. n .. "|" .. arena.wave)
end

-- Enemy gauntlet: random rocks + N of one enemy type, measured (clear time, hits, aim quality). So bad
-- fighting against any enemy shows up in a table instead of someone having to spot it. "gauntlet|T.V|N|ROCKS"
local function startGauntlet(spec)
  local t, v, n, rocks, seed = spec:match("^(%d+)%.(%d+)|(%d+)|(%d+)|?(%d*)$")
  if not t then send("gauntlet", "bad spec " .. spec); return end
  -- With a seed, rocks and spawn spots are the same every time (the auto-tuner needs identical rounds:
  -- with random layouts the SAME settings scored 433, 217 and 182). Without one, random as before.
  local rng = nil
  if seed and seed ~= "" then rng = RNG(); rng:SetSeed(tonumber(seed) + 1, 35) end
  local room, p = Game():GetRoom(), Isaac.GetPlayer(0)
  p:AddHearts(24)
  -- clean slate: leftovers from a round that timed out (Duke + his flies once crashed the next Monstro round)
  for _, e in ipairs(Isaac.GetRoomEntities()) do
    if (e:IsActiveEnemy(true) and not e:HasEntityFlags(EntityFlag.FLAG_FRIENDLY))
       or e.Type == EntityType.ENTITY_PROJECTILE then
      e:Remove()
    end
  end
  local placed = {}
  if rng then p.Position = room:GetCenterPos(); p.Velocity = Vector.Zero end -- same start spot too
  local function pickIdx()
    if rng then return rng:RandomInt(room:GetGridSize()) end
    return room:GetGridIndex(room:GetRandomPosition(40))
  end
  for _ = 1, tonumber(rocks) do
    for _ = 1, 25 do
      local idx = pickIdx()
      local pos = room:GetGridPosition(idx)
      local inside = room:IsPositionInRoom(pos, 30) and room:GetGridCollision(idx) == GridCollisionClass.COLLISION_NONE
      local okSpot = inside and (pos - p.Position):Length() > 110 and room:GetGridEntity(idx) == nil
      for slot = 0, 7 do
        if okSpot and room:GetDoor(slot) and (room:GetDoorSlotPosition(slot) - pos):Length() < 90 then okSpot = false end
      end
      if okSpot and Isaac.GridSpawn(GridEntityType.GRID_ROCK, 0, pos, true) then placed[#placed + 1] = idx; break end
    end
  end
  for _ = 1, tonumber(n) do
    if rng then
      -- seeded spawn spot: a free floor square at least 170 px from Isaac
      local pos
      for _ = 1, 40 do
        local idx = rng:RandomInt(room:GetGridSize())
        local gp = room:GetGridPosition(idx)
        if room:IsPositionInRoom(gp, 40) and room:GetGridCollision(idx) == GridCollisionClass.COLLISION_NONE
           and (gp - p.Position):Length() >= 170 then pos = gp; break end
      end
      Isaac.Spawn(tonumber(t), tonumber(v), 0, pos or room:GetCenterPos(), Vector.Zero, nil)
    else
      spawnAt(tonumber(t), tonumber(v), nil, 170)
    end
  end
  Reflex.aimReport() -- reset the aim counters
  arena = { start = Game():GetFrameCount(), hits = 0, dmg = 0, wave = t .. "." .. v, n = tonumber(n),
            gauntlet = true, rocks = placed }
  send("gauntlet", "start|" .. spec .. "|items " .. p:GetCollectibleCount())
end

local function endArena(result, f)
  local line = result .. "|" .. arena.n .. "|" .. (f - arena.start) .. "|" .. arena.hits .. "|" .. arena.dmg .. "|" .. arena.wave
  if arena.gauntlet then
    send("gauntlet", line .. "|" .. Reflex.aimReport())
    send("curve", string.format("tears keep %.2f of Isaac's sideways speed (%d samples)", Reflex.curveK, Reflex.curveSamples))
    local room = Game():GetRoom()
    for _, idx in ipairs(arena.rocks or {}) do room:RemoveGridEntity(idx, 0, false) end
  else
    send("arena", line)
  end
  arena = nil
end

mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, ent, amount, flags, source)
  if ent.Type ~= EntityType.ENTITY_PLAYER then return nil end
  local src = source and (tostring(source.Type) .. "." .. tostring(source.Variant)) or "?"
  local p = ent.Position
  -- what actually touched Isaac: the game credits a shot to its shooter ("46.0" for Sloth's shot), so also log the
  -- real entity, its distance and size (hit review: Sloth's body or its shot? this settles it)
  local via = ""
  local se = source and source.Entity
  if se then
    via = string.format("|via %d.%d d=%.0f size=%.0f", se.Type, se.Variant, (se.Position - p):Length(), se.Size or 0)
  end
  -- the nearest enemy shot at the moment of the hit: Sloth's hits came with Sloth 116-184 px away, so it's the shot;
  -- this shows what the bot misjudges about it (size vs. visual scale, height, speed)
  local best, bd = nil, math.huge
  for _, s in ipairs(Isaac.FindByType(EntityType.ENTITY_PROJECTILE)) do
    local d = (s.Position - p):Length()
    if d < bd then best, bd = s, d end
  end
  if best and bd < 120 then
    local pr = best:ToProjectile()
    via = via .. string.format("|shot %d d=%.0f size=%.0f scale=%.2f height=%.0f speed=%.1f from=%d", best.Variant, bd,
      best.Size or 0, pr and pr.Scale or -1, pr and pr.Height or 0, best.Velocity:Length(), best.SpawnerType or 0)
  end
  send("hit", src .. "|" .. tostring(amount) .. "|" .. math.floor(p.X) .. "," .. math.floor(p.Y)
       .. "|move " .. tostring(Reflex.status.move) .. via)
  if arena then arena.hits = arena.hits + 1; arena.dmg = arena.dmg + amount end
  if bench and bench.started then bench.hits = bench.hits + 1 end
  if source and source.Type and source.Type > 0 then pcall(Reflex.learnHit, source.Type, amount) end
  if source and source.Entity then
    -- credit the animation the attacker (or the shot's shooter) was in
    local who = source.Entity.SpawnerEntity or source.Entity
    pcall(Reflex.tells.onHit, who)
  end
  return nil
end, EntityType.ENTITY_PLAYER)

-- Shots that appear AWAY from whoever fired them = a burst (a landing shot splitting up). Logged to confirm what
-- Sloth's shot does; one line per burst (shots from the same spot in the same frame are counted together).
local burst = { f = -1 }
mod:AddCallback(ModCallbacks.MC_POST_PROJECTILE_INIT, function(_, pr)
  local sp = pr.SpawnerEntity
  if not sp or not botAllowed() then return end
  local fromShooter = (pr.Position - sp.Position):Length()
  if fromShooter < 60 then return end
  local f = Game():GetFrameCount()
  if burst.f == f and (burst.pos - pr.Position):Length() < 40 then burst.n = burst.n + 1; return end
  if burst.f >= 0 and burst.n then
    send("burst", string.format("%d shots from %d.%d at %.0f px from it, %.0f px from Isaac", burst.n, burst.t,
      burst.v, burst.dist, burst.toP))
  end
  burst = { f = f, pos = pr.Position, n = 1, t = sp.Type, v = sp.Variant, dist = fromShooter,
            toP = (pr.Position - Isaac.GetPlayer(0).Position):Length() }
end)

---------------------------------------------------------------- commands from the helper
local function handle(seq, cmd, payload)
  if cmd == "ping" then
    send("pong", seq .. "|" .. payload)
  elseif cmd == "hello" then
    send("hello", VERSION)
  elseif cmd == "overlay" then
    overlay = (payload ~= "0")
  elseif cmd == "bot" then
    -- "off" or "combat" (Stage 3 adds "full")
    Reflex.status.mode = payload
    send("bot", "mode " .. payload)
  elseif cmd == "set" then
    -- live tuning: "key=value"
    local k, v = payload:match("^([%w_]+)=([%d%.%-]+)$")
    send("set", payload .. (k and Reflex.set(k, v) and " ok" or " unknown"))
  elseif cmd == "do" and Isaac.IsInGame() and botAllowed() then
    -- the multiple-choice brain picked option <id> from the menu the watchdog sent
    local o = Rescue.options and Rescue.options[payload]
    if o then
      local ok, err = pcall(o.act)
      Rescue.brainAnswered()
      send("brain", "chose " .. payload .. ": " .. o.text .. (ok and "" or (" (failed: " .. tostring(err) .. ")")))
    else
      send("brain", "chose " .. payload .. " but that option is gone")
    end
  elseif cmd == "rescue" and Isaac.IsInGame() and botAllowed() then
    -- the brain's answer to a "stuck" report: "action|arg"
    local action, arg = payload:match("^(%a+)|?(.*)$")
    local p = Isaac.GetPlayer(0)
    local okAct = false
    local fighting = Reflex.status.active
    if fighting and action == "goto" then
      -- mid-fight: the brain's square becomes the firing spot the reflexes walk to
      local c, r = arg:match("(%d+),(%d+)")
      if c then Reflex.forceCell(tonumber(c) + tonumber(r) * Game():GetRoom():GetGridWidth()); okAct = true end
    elseif action == "bomb" and p:GetNumBombs() < Rules.bombs.brain_min then
      -- over the bomb budget: treat it as "try something else" instead (the author: conserve bombs)
      if fighting then Reflex.banTarget(8) else Nav.replan() end
      action, okAct = "replan (bomb refused: only " .. p:GetNumBombs() .. " bombs)", true
    elseif fighting and action == "replan" then Reflex.banTarget(8); okAct = true
    elseif fighting and action == "bomb" then Rescue.wantSiege = true; okAct = true
    elseif action == "replan" then Nav.replan(); okAct = true
    elseif action == "bomb" then okAct = Nav.bombNearest(p, Rules.bombs.brain_min)
    elseif action == "leave" then okAct = Nav.leaveAny(p)
    elseif action == "door" then okAct = Nav.useDoor(p, tonumber(arg) or -1)
    elseif action == "goto" then
      local c, r = arg:match("(%d+),(%d+)")
      okAct = c and Nav.gotoCell(p, tonumber(c), tonumber(r)) or false
    elseif action == "shake" or action == "wait" then okAct = true
    end
    Rescue.brainAnswered()
    send("brain", (action or "?") .. " " .. (arg or "") .. (okAct and " (doing it)" or " (couldn't)"))
  elseif cmd == "gauntlet" and Isaac.IsInGame() and botAllowed() then
    startGauntlet(payload)
  elseif cmd == "tellsload" then
    local ok, n = pcall(Reflex.tells.load, payload)
    send("learned", "loaded " .. tostring(ok and n or 0) .. " remembered enemy tells")
  elseif cmd == "goroom" and Isaac.IsInGame() and botAllowed() then
    -- replay one room: "goroom|normal|123" loads layout 123 of this floor's room set (debug console goto),
    -- full health first; the result comes back as "bench|cleared|died|timeout|seconds|hits"
    local kind, variant = payload:match("^(%a+)|(%d+)")
    if kind then
      Isaac.GetPlayer(0):AddHearts(24)
      bench = { kind = kind, variant = variant, asked = Game():GetFrameCount(), hits = 0 }
      -- console: "d.<id>" = a layout from this floor's own room set, "s.<type>.<id>" = special rooms (boss etc.)
      local cmdline = (kind == "normal") and ("goto d." .. variant) or ("goto s." .. kind .. "." .. variant)
      local out = Isaac.ExecuteCommand(cmdline)
      send("bench", cmdline .. ": " .. tostring(out))
    end
  elseif cmd == "stage" and Isaac.IsInGame() and botAllowed() then
    -- bench: go to the floor a saved room belongs to ("stage|1a" = Cellar I); its layouts only exist there
    local out = Isaac.ExecuteCommand("stage " .. payload)
    send("bench", "stage " .. payload .. ": " .. tostring(out))
  elseif cmd == "map" then
    local ok, rep = pcall(Nav.mapReport)
    send("map", tostring(rep))
  elseif cmd == "reload" then
    -- reload this mod's code inside the running game (seconds, instead of closing and relaunching Isaac)
    send("reload", "reloading the bot's code")
    Isaac.ExecuteCommand("luamod isaac-bot")
  elseif cmd == "motionload" then
    local ok, n = pcall(Reflex.mover.load, payload)
    send("learned", "loaded remembered movement of " .. tostring(ok and n or 0) .. " enemy types")
  elseif cmd == "respectload" then
    pcall(Reflex.respectLoad, payload)
    send("learned", "loaded remembered enemy respect: " .. payload)
  elseif cmd == "newrun" and Isaac.IsInGame() and botAllowed() then
    -- a clean, item-free run for testing (the author: an item made the results an outlier)
    send("newrun", "restarting the run")
    Isaac.ExecuteCommand("restart")
  elseif cmd == "arena" and Isaac.IsInGame() and botAllowed() then
    startArena(tonumber(payload) or 4)
  elseif cmd == "heal" and Isaac.IsInGame() and botAllowed() then
    Isaac.GetPlayer(0):AddHearts(24)
  elseif cmd == "spawn" then
    -- test tool (bot's slot-2 runs only): "type.variant" spawned a few tiles away from Isaac
    local t, v = payload:match("^(%d+)%.?(%d*)$")
    local inGame = Game():GetFrameCount() > 0 and Isaac.GetPlayer(0) ~= nil
    if not (inGame and auto.slot == BOT_SLOT and t) then
      send("spawned", "skipped " .. payload .. " (in run " .. tostring(inGame) .. ", slot " .. tostring(auto.slot)
           .. ", IsInGame " .. tostring(Isaac.IsInGame and Isaac.IsInGame()) .. ")")
    else
      local room, p = Game():GetRoom(), Isaac.GetPlayer(0)
      local pos = room:FindFreePickupSpawnPosition(p.Position + Vector(160, -60), 0, true)
      Isaac.Spawn(tonumber(t), tonumber(v) or 0, 0, pos, Vector.Zero, nil)
      send("spawned", payload)
    end
  elseif cmd == "autostart" then
    if not auto.wanted and not auto.disabled and not Isaac.IsInGame() then
      auto.wanted = true
      send("auto", "on")
    end
  end
  status = "helper connected"
  lastContact = now()
end

local function poll()
  local ok, raw = pcall(function()
    if not mod:HasData() then return nil end
    return mod:LoadData()
  end)
  if not ok or not raw or raw == "" then return end
  local session = raw:match("^H|(%d+)")
  if not session then return end
  -- A new helper session (helper restarted, or our first read): its old pings are stale, so only
  -- act on an autostart; from then on run every command with a higher number than the last one.
  local fresh = (session ~= helperSession)
  helperSession = session
  local newest = fresh and 0 or lastSeq
  for seq, cmd, payload in raw:gmatch("\n(%d+)|([%w_]+)|([^\n]*)") do
    seq = tonumber(seq)
    payload = payload:gsub("\r$", "") -- Windows line endings: never let a hidden "\r" ride along
    if fresh then
      if cmd == "autostart" then handle(seq, cmd, payload) end
    elseif seq > lastSeq then
      handle(seq, cmd, payload)
    end
    if seq > newest then newest = seq end
  end
  lastSeq = newest
end

local function label(text)
  Isaac.RenderText("IBOT " .. VERSION .. ": " .. text, 50, 250, RED[1], RED[2], RED[3], 1)
end

---------------------------------------------------------------- eyes
local reflexError = nil
local walledFrames = 0
local perf = { n = 0, sum = 0, max = 0 }
local lastV2Err = nil

-- Active item: fully charged, not on the never-list, and a fight worth it (boss or Rules.active.min_enemies).
local NEVER_ACTIVE = {}
for _, id in ipairs(Rules.active.never) do NEVER_ACTIVE[id] = true end
local lastActiveUse = -999
local function wantActive(p)
  local id = p:GetActiveItem(ActiveSlot and ActiveSlot.SLOT_PRIMARY or 0)
  if not id or id <= 0 or NEVER_ACTIVE[id] then return false end
  local f = Game():GetFrameCount()
  if f - lastActiveUse < 30 then return false end
  local cfg = Isaac.GetItemConfig():GetCollectible(id)
  if not cfg or cfg.MaxCharges <= 0 then return false end
  if p:GetActiveCharge() + p:GetBatteryCharge() < cfg.MaxCharges then return false end
  local n, boss = 0, false
  for _, e in ipairs(Isaac.GetRoomEntities()) do
    if e:IsActiveEnemy(false) and e:IsVulnerableEnemy() and not e:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
      n = n + 1
      if e:IsBoss() then boss = true end
    end
  end
  if not boss and n < Rules.active.min_enemies then return false end
  lastActiveUse = f
  send("active", id .. "|" .. (cfg.Name or "?") .. "|" .. (boss and "boss" or (n .. " enemies")))
  return true
end

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
  pcall(benchCheck, send)
  local f = Game():GetFrameCount()

  -- reflexes every update (bot's own slot only); when there's no fight, the navigator walks
  if botAllowed() then
    local p = Isaac.GetPlayer(0)
    Reflex.forceFight = (arena ~= nil) -- the start room counts as "cleared", so tell the reflexes it's a fight
    local t0 = Isaac.GetTime()
    local ok, move, shoot = pcall(Reflex.update, p)
    -- how long the bot's thinking takes (a game update has ~33 ms; over ~16 ms the game starts to slow down)
    local msReflex = Isaac.GetTime() - t0
    local bomb = false
    if ok and Reflex.status.active and Reflex.status.mode == "full" then
      -- enemies walled in by stone (no poop lane) for 4+ s: bomb a way in
      walledFrames = Reflex.status.walled and walledFrames + 1 or 0
      if walledFrames > 30 * Rules.bombs.siege_after_s or Nav.siegeActive() or Rescue.wantSiege then
        local ok2, m2, s2, b2 = pcall(Nav.siege, p, Reflex.status.target)
        if ok2 and m2 then move, shoot, bomb = m2, s2 or shoot, b2 end
      end
    elseif ok and not move and Reflex.status.mode == "full" and not p:IsDead() then
      walledFrames = 0
      ok, move, shoot, bomb = pcall(Nav.update, p)
    end
    -- the rescue ladder watches for any lack of progress and can take over for a "shake"
    if ok and Reflex.status.mode == "full" then
      local ok3, m3, s3 = pcall(Rescue.update, p, Nav, Reflex.status.active, send, Reflex, MODS)
      if ok3 and (m3 or s3) then move, shoot = m3 or move, s3 or shoot end
      if not ok3 then send("error", "rescue: " .. tostring(m3)) end
    end
    -- whole bot tick (fighting + walking + watchdog) and the fighting part alone
    local ms = Isaac.GetTime() - t0
    perf.n, perf.sum, perf.max = perf.n + 1, perf.sum + ms, math.max(perf.max, ms)
    perf.rsum = (perf.rsum or 0) + msReflex
    if perf.n >= 300 then
      send("perf", string.format("bot avg %.1f ms (fighting %.1f: planner %.1f, moves %.1f), max %d ms, %d enemies, room %dx%d",
        perf.sum / perf.n, perf.rsum / perf.n, Reflex.prof.plan / perf.n, Reflex.prof.move / perf.n, perf.max,
        Isaac.CountEnemies(), Game():GetRoom():GetGridWidth(), Game():GetRoom():GetGridHeight()))
      perf.n, perf.sum, perf.max, perf.rsum = 0, 0, 0, 0
      Reflex.prof.plan, Reflex.prof.move = 0, 0
    end
    if ok then
      ctl.move, ctl.shoot, ctl.bomb = move, shoot, bomb and true or false
      ctl.item = Reflex.status.active and Reflex.status.mode == "full" and wantActive(p)
      if Reflex.v2err and Reflex.v2err ~= lastV2Err then send("error", "mover: " .. Reflex.v2err) end
      if f % 30 == 0 and Reflex.status.active and Reflex.mover.debug then send("why", Reflex.mover.debug) end
      lastV2Err = Reflex.v2err
      reflexError = nil
    else
      ctl.move, ctl.shoot = nil, nil
      if reflexError ~= tostring(move) then
        reflexError = tostring(move)
        send("error", "reflex: " .. reflexError)
      end
    end
  else
    ctl.move, ctl.shoot = nil, nil
  end

  -- what the tells have learned so far, every 30 s (the helper keeps it in knowledge\telegraphs.txt)
  if f % 900 == 0 and f > 0 then
    local ok, rep = pcall(Reflex.tells.report)
    if ok and rep ~= "" then send("tells", rep) end
    -- machine-readable copy so the helper can hand it back after a restart (learning carries over)
    local ok2, raw = pcall(Reflex.tells.dump)
    if ok2 and raw ~= "" then send("tellsraw", raw) end
    local ok3, resp = pcall(Reflex.respectDump)
    if ok3 and resp ~= "" then send("respectraw", resp) end
    -- movement core v2: what it has learned about how far each enemy type gets (kept across restarts)
    local ok4, mraw = pcall(Reflex.mover.dump)
    if ok4 and mraw ~= "" then send("motionraw", mraw) end
    local ok5, mrep = pcall(Reflex.mover.report)
    if ok5 and mrep ~= "" then send("motion", mrep) end
  end

  -- arena finished?
  if arena and f % 15 == 0 then
    local p = Isaac.GetPlayer(0)
    local left = Isaac.CountEnemies()
    if p:IsDead() or p:GetHearts() + p:GetSoulHearts() <= 0 then
      endArena("died", f)
    elseif left == 0 then
      endArena("cleared", f)
    elseif f - arena.start > 30 * 150 then -- (90 s was too short for bosses with base Isaac's damage)
      endArena("timeout", f)
    end
  end

  if f % STATE_EVERY == 0 then
    local ok, snap = pcall(Eyes.snapshot)
    if ok then
      local st = Reflex.status
      local goalText = Reflex.status.active and "" or Nav.status.goal
      if Reflex.status.active then
        -- what the firing planner is doing (or why not), so stuck fights can be read from the log
        local pl = Reflex.plan
        local room = Game():GetRoom()
        local w = room:GetGridWidth()
        if pl.cell and pl.target then
          local ti = room:GetGridIndex(pl.target.Position)
          goalText = "fire from " .. (pl.cell.idx % w) .. "," .. math.floor(pl.cell.idx / w) .. " at "
                     .. (ti % w) .. "," .. math.floor(ti / w) .. (pl.target.kind and (" (" .. pl.target.kind .. ")") or "")
        else
          goalText = "no firing spot" .. ((Reflex.relax or 0) > 0 and (" (relaxed " .. Reflex.relax .. ")") or "") .. (Reflex.planError and (": " .. Reflex.planError) or "")
        end
      end
      if Rescue.level > 0 then goalText = "RESCUE " .. Rescue.level .. " (" .. Rescue.step .. ") | " .. goalText end
      snap.bot = { st.mode, st.active and 1 or 0, st.move, st.shoot, st.cost, st.threats, goalText }
      lastSnap = snap
      if IsaacBotOut then IsaacBotOut.setLatest("T", json.encode(snap)) end
      eyesError = nil
    elseif eyesError ~= tostring(snap) then
      eyesError = tostring(snap)
      send("error", "eyes: " .. eyesError)
    end
  end
  if f % GRID_CHECK_EVERY == 0 then
    local ok, g = pcall(Eyes.grid)
    if ok and g ~= lastGrid then
      lastGrid = g
      if IsaacBotOut then IsaacBotOut.setLatest("G", g) end
    elseif not ok then
      send("error", "grid: " .. tostring(g))
    end
  end
end)

mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
  local level = Game():GetLevel()
  -- room id (type, variant, stage, layout name) so a room that went wrong can be replayed with "goroom"
  local d = level:GetCurrentRoomDesc().Data
  send("room", level:GetCurrentRoomIndex() .. "|" .. Game():GetRoom():GetType() .. "|" ..
    (d and (d.Variant .. "|" .. level:GetStage() .. level:GetStageType() .. "|" .. tostring(d.Name)) or "?"))
  benchRoomStart()
  lastGrid = nil -- force a fresh map
  pcall(Nav.newRoom)
end)

mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, function()
  local level = Game():GetLevel()
  send("floor", level:GetStage() .. "|" .. level:GetStageType() .. "|" .. math.floor(Game().TimeCounter / 30))
  -- what the bot is carrying (the author: a strong item can make a run look good and hide bugs; a bad one the
  -- opposite): item ids and the stats that matter, once per floor, so scores can be read like for like
  pcall(function()
    local p = Isaac.GetPlayer(0)
    local ids = {}
    local cfg = Isaac.GetItemConfig()
    for id = 1, 800 do
      if cfg:GetCollectible(id) and p:HasCollectible(id) then ids[#ids + 1] = id end
    end
    send("power", string.format("dmg %.2f|tears %.2f|speed %.2f|range %.0f|items %s", p.Damage,
      30 / (p.MaxFireDelay + 1), p.MoveSpeed, p.TearRange, table.concat(ids, ",")))
  end)
  pcall(Nav.newLevel)
end)

---------------------------------------------------------------- end of a run: log it, get past the screen
local ending = nil -- set when the run is over; we ask the helper for Enter until we're back on the menu

mod:AddCallback(ModCallbacks.MC_POST_GAME_END, function(_, isGameOver)
  local level = Game():GetLevel()
  local result = isGameOver and "died" or "won"
  send("runend", result .. "|" .. level:GetStage() .. "|" .. level:GetStageType() .. "|"
       .. math.floor(Game().TimeCounter / 30) .. "|" .. tostring(auto.slot))
  if auto.slot == BOT_SLOT then ending = { since = Isaac.GetFrameCount() } end
end)

---------------------------------------------------------------- overlay (what the bot sees)
local function mark(text, pos, r, g, b, scale)
  local sp = Isaac.WorldToScreen(pos)
  scale = scale or 0.5
  Isaac.RenderScaledText(text, sp.X - 3 * scale * #text, sp.Y - 6 * scale, scale, scale, r, g, b, 1)
end

local function drawOverlay()
  local s = lastSnap
  if not s then return end
  for _, e in ipairs(s.e) do
    mark((e[9] == 1 and "BOSS " or "") .. e[7] .. "hp", Vector(e[3], e[4] - 30), 1, 0.25, 0.25, 0.5)
  end
  for _, t in ipairs(s.t) do
    mark("o", Vector(t[1], t[2]), 1, 0.85, 0.2, 0.6)
    -- where this tear will be in ~1/3 s (10 updates)
    mark(".", Vector(t[1] + t[3] * 10, t[2] + t[4] * 10), 1, 0.4, 0.1, 0.9)
  end
  for _, b in ipairs(s.b) do mark("BOMB", Vector(b[1], b[2] - 20), 1, 0.2, 0.2, 0.5) end
  for _, k in ipairs(s.k) do mark("$", Vector(k[3], k[4]), 0.4, 1, 0.4, 0.6) end
  local counts = string.format("sees: %d enemies, %d shots, %d pickups", #s.e, #s.t, #s.k)
  Isaac.RenderScaledText(counts, 50, 240, 0.5, 0.5, RED[1], RED[2], RED[3], 1)
  -- what the reflexes decided: X on the target, a short trail of dots where Isaac is heading
  local st = Reflex.status
  if st.active then
    local t = st.target
    if t and (t.kind or t:Exists()) then mark("X", t.Position, 1, 1, 0.2, 0.8) end
    if Reflex.plan.cellPos then mark("[ ]", Reflex.plan.cellPos, 0.3, 0.8, 1, 0.7) end -- planned firing spot
    local p = Isaac.GetPlayer(0)
    if ctl.move and ctl.move:Length() > 0 then
      for i = 1, 3 do mark("*", p.Position + ctl.move * (14 * i), 0.3, 1, 0.5, 0.5) end
    end
    Isaac.RenderScaledText("bot: fighting, shoot " .. (st.shoot ~= "" and st.shoot or "-"), 50, 232, 0.5, 0.5, 0.3, 1, 0.5, 1)
  else
    Isaac.RenderScaledText("bot: " .. st.mode .. " (room clear, your controls)", 50, 232, 0.5, 0.5, 0.6, 0.6, 0.6, 1)
  end
end

---------------------------------------------------------------- in a run
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
  arena = nil -- a test from the previous (dead) run never carries over
  auto.wanted = false
  auto.tries, auto.saveTries, auto.disabled = 0, 0, false
  ending = nil
  send("start", VERSION .. "|" .. tostring(continued) .. "|slot " .. tostring(auto.slot))
end)

mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
  local f = now()
  if f % POLL_EVERY == 0 then poll() end
  if f - lastContact > 300 and status == "helper connected" then
    status = "helper quiet"
  end
  if overlay then pcall(drawOverlay) end
  -- run over (death or win screen, bot's slot only): ask for Enter every 2 s until we're back on the menu
  if ending and (f - ending.since) > 120 and (f - ending.since) % 120 == 0 then
    needEnter("gameover")
  end
  label(status)
end)

---------------------------------------------------------------- main menu
-- At boot the game "loads" every slot (selected = false) just to draw them. Only a real pick counts:
-- selected = true, or the first slot load after we asked for Enter on the save screen.
mod:AddCallback(ModCallbacks.MC_POST_SAVESLOT_LOAD, function(_, slot, selected, raw)
  if selected or auto.awaitSlot then
    auto.slot = slot
    IsaacBotSlot = slot -- global: survives a code reload (luamod), so the bot knows it's still on its own slot
    auto.awaitSlot = false
  end
  send("slot", tostring(slot) .. "|" .. tostring(selected) .. "|" .. tostring(raw))
end)

local function giveUp(why)
  send("auto", "gave up: " .. why)
  auto.wanted = false
  auto.disabled = true
  auto.forceEl = nil
end

local function autopilot()
  if auto.wait > 0 then auto.wait = auto.wait - 1 return end
  local menu = MenuManager.GetActiveMenu()

  if auto.slot == BOT_SLOT and menu ~= MainMenuType.TITLE and menu ~= MainMenuType.SAVES then
    send("auto", "starting run as Isaac on slot " .. BOT_SLOT)
    auto.wanted = false
    auto.forceEl = nil
    Isaac.StartNewGame(PlayerType.PLAYER_ISAAC)
    return
  end

  if auto.tries >= 8 then
    giveUp("could not load slot " .. BOT_SLOT .. " (menu " .. tostring(menu) .. ", slot " .. tostring(auto.slot) .. ")")
    return
  end

  if menu == MainMenuType.TITLE then
    needEnter("title")
    auto.tries = auto.tries + 1
    auto.wait = 60
  elseif menu == MainMenuType.SAVES then
    local el = auto.elements[auto.saveTries % #auto.elements + 1]
    auto.saveTries = auto.saveTries + 1
    auto.forceEl = el -- kept highlighted every frame until Enter lands
    SaveMenu.SetSelectedElement(el)
    auto.awaitSlot = true
    send("auto", "saves: highlighting entry " .. el .. " (menu says " .. tostring(SaveMenu.GetSelectedElement()) .. ")")
    needEnter("saves " .. el)
    auto.tries = auto.tries + 1
    auto.wait = 90
  elseif auto.slot ~= nil and auto.slot ~= BOT_SLOT then
    send("auto", "slot " .. tostring(auto.slot) .. " is loaded, not " .. BOT_SLOT .. "; back to the save screen")
    MenuManager.SetActiveMenu(MainMenuType.SAVES)
    auto.tries = auto.tries + 1
    auto.wait = 45
  else
    send("auto", "waiting on menu " .. tostring(menu) .. ", slot " .. tostring(auto.slot))
    auto.wait = 60
  end
end

mod:AddCallback(ModCallbacks.MC_MAIN_MENU_RENDER, function()
  menuFrame = menuFrame + 1
  local ok, menu = pcall(MenuManager.GetActiveMenu)
  if ok and menu ~= auto.lastMenu then
    send("menu", tostring(auto.lastMenu) .. " -> " .. tostring(menu))
    auto.lastMenu = menu
    if menu ~= MainMenuType.TITLE then auto.wait = math.min(auto.wait, 15) end -- moved on: act soon
  end
  if ok and menu == MainMenuType.SAVES and auto.forceEl and auto.wanted then
    pcall(SaveMenu.SetSelectedElement, auto.forceEl)
  end
  if menuFrame % POLL_EVERY == 0 then poll() end
  if auto.wanted then
    local ok2, err = pcall(autopilot)
    if not ok2 then
      send("auto", "error: " .. tostring(err))
      auto.wanted = false
    end
    label("autopilot: going to slot " .. BOT_SLOT)
  else
    label(status)
  end
end)

send("loaded", VERSION)
-- reloaded mid-run (the "reload" command): say so like a run start, so the helper hands back what was learned
if Isaac.IsInGame() and IsaacBotSlot then
  send("start", VERSION .. "|reload|slot " .. tostring(IsaacBotSlot))
end
