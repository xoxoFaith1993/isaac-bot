-- Isaac Bot options: the multiple-choice brain's menu.
-- The CODE does the geometry (which square has a clear shot, which poop is in the way, what a route costs)
-- and turns the situation into a short list of real options in plain words; the local model only CHOOSES.
-- Exam 2026-11-25: asked this way, even the old 12B model judged 25.5/28 and gemma4:12b 28/28; asked to read
-- an ASCII map it kept saying "bomb".
--
-- Options.build(player, fighting, mods) -> list of { id = "A", text = "...", act = function() ... end }
-- Options.facts(player, fighting)       -> a few lines of plain facts for the brain

local R = include("rules")
local Options = {}

local KNOWN = { [10] = "Gaper", [12] = "Horf", [13] = "Fly", [14] = "Pooter", [15] = "Clotty", [16] = "Mulligan",
                [18] = "Attack Fly", [21] = "Maggot", [23] = "Charger", [24] = "Globin", [25] = "Boom Fly",
                [26] = "Maw", [27] = "Host", [29] = "Hopper", [30] = "Boil", [31] = "Spitty", [96] = "Eternal Fly",
                [217] = "Dip", [261] = "Dingle", [20] = "Monstro", [33] = "Fireplace" }

-- Enemy name: from the game's own data via REPENTOGON when possible, else a small built-in list.
local function nameOf(e)
  local ok, n = pcall(function()
    local x = XMLData.GetEntityByTypeVarSub(e.Type, e.Variant, e.SubType)
    return x and (x.name or x.Name)
  end)
  if ok and type(n) == "string" and n ~= "" and not n:find("^#") then return n end
  return KNOWN[e.Type] or ("enemy " .. e.Type .. "." .. e.Variant)
end
Options.nameOf = nameOf

local ROOM = { [1] = "normal", [2] = "shop", [4] = "treasure", [5] = "boss", [6] = "miniboss", [7] = "secret",
               [8] = "super secret", [9] = "arcade", [10] = "curse", [11] = "challenge", [12] = "library",
               [13] = "sacrifice", [14] = "devil", [15] = "angel", [20] = "chest", [24] = "planetarium" }

local function cr(room, idx)
  local w = room:GetGridWidth()
  return (idx % w) .. "," .. math.floor(idx / w)
end

local function letter(n) return string.char(64 + n) end

function Options.facts(p, fighting, Danger)
  local room = Game():GetRoom()
  local hp = Danger.hp(p)
  local lines = {
    string.format("Health: %s hearts (%d red half-hearts of %d, %d soul/black half-hearts). Bombs %d, keys %d, coins %d.",
      hp / 2, p:GetHearts(), p:GetEffectiveMaxHearts(), p:GetSoulHearts(), p:GetNumBombs(), p:GetNumKeys(), p:GetNumCoins()),
    "Room: " .. (ROOM[room:GetType()] or ("type " .. room:GetType())) .. (room:IsClear() and ", cleared (doors open)" or ", NOT cleared (doors shut)"),
  }
  local en = {}
  for _, e in ipairs(Isaac.GetRoomEntities()) do
    if e:IsActiveEnemy(false) and not e:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
      en[#en + 1] = nameOf(e) .. " at " .. cr(room, room:GetGridIndex(e.Position)) .. " ("
        .. math.floor(e.HitPoints) .. " hp" .. ((e:IsVulnerableEnemy() and not e:IsInvincible()) and "" or ", can't be hurt") .. ")"
    end
  end
  lines[#lines + 1] = "Enemies: " .. (#en > 0 and table.concat(en, "; ") or "none")
  lines[#lines + 1] = "Isaac is at " .. cr(room, room:GetGridIndex(p.Position)) .. (fighting and ", in a fight" or ", walking")
  return table.concat(lines, " / ") -- one line: it travels inside the outbox's one-line messages
end

function Options.build(p, fighting, M)
  local Reflex, Nav, Danger = M.Reflex, M.Nav, M.Danger
  local room = Game():GetRoom()
  local list = {}
  local function add(text, act)
    if #list < 7 then list[#list + 1] = { id = letter(#list + 1), text = text, act = act } end
  end
  local bombs = p:GetNumBombs()

  if fighting then
    -- 1. each hurtable enemy, with where to shoot it from
    local foes = {}
    for _, e in ipairs(Isaac.GetRoomEntities()) do
      if e:IsActiveEnemy(false) and not e:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
         and e:IsVulnerableEnemy() and not e:IsInvincible() then foes[#foes + 1] = e end
    end
    table.sort(foes, function(a, b) return (a.Position - p.Position):Length() < (b.Position - p.Position):Length() end)
    for k = 1, math.min(3, #foes) do
      local e = foes[k]
      local idx, steps, lane = Reflex.spotFor(p, e)
      if idx then
        add(string.format("Target the %s at %s: shoot it from square %s (%d steps away, %s line)", nameOf(e),
              cr(room, room:GetGridIndex(e.Position)), cr(room, idx), steps, lane == 0 and "clear" or "poop in the"),
            function() Reflex.forceTarget(e, 10); Reflex.forceCell(idx) end)
      else
        add(string.format("Target the %s at %s (no clear straight line to it from anywhere right now)", nameOf(e),
              cr(room, room:GetGridIndex(e.Position))),
            function() Reflex.forceTarget(e, 8) end)
      end
    end
    -- 2. poops near enemies (shooting one can open a lane or free a shielded enemy)
    local seen = 0
    for i = 0, room:GetGridSize() - 1 do
      local ge = room:GetGridEntity(i)
      if seen < 2 and ge and ge:GetType() == GridEntityType.GRID_POOP and ge.CollisionClass ~= GridCollisionClass.COLLISION_NONE then
        local gp = room:GetGridPosition(i)
        local near
        for _, e in ipairs(Isaac.GetRoomEntities()) do
          if e:IsActiveEnemy(false) and (e.Position - gp):Length() < 130 then near = e; break end
        end
        if near then
          seen = seen + 1
          local poop = { Position = gp, Velocity = Vector.Zero, kind = "poop", idx = i }
          add(string.format("Shoot the poop at %s, right next to the %s (tears break poop: frees a stuck/shielded enemy or opens a lane)",
                cr(room, i), nameOf(near)),
              function() Reflex.forceTarget(poop, 10) end)
        end
      end
    end
    -- 3. a bomb, only within the bomb budget
    if bombs >= R.bombs.siege_min and foes[1] then
      add(string.format("Bomb the rock between Isaac and the %s (uses 1 of %d bombs)", nameOf(foes[1]), bombs),
          function() M.Rescue.wantSiege = true end)
    end
    add("Keep dodging and keep shooting at the current target (do nothing new)", function() end)
    return list
  end

  -- walking (room cleared)
  -- 1. doors, with what's behind them and what the way there costs
  for slot = 0, 7 do
    local d = room:GetDoor(slot)
    if Nav.visibleDoor(d) and d:IsOpen() then
      local info = Nav.roomInfo(d.TargetRoomIndex)
      local path = Nav.findPath(room, room:GetGridIndex(p.Position), d:GetGridIndex(), p.CanFly, false)
      local dmg = Danger.pathDamage(path)
      local kind = ROOM[d.TargetRoomType] or "unknown"
      add(string.format("Leave through door %d to a %s room (%s)%s", slot, kind,
            (info and info.visited > 0) and "already visited" or "NOT visited yet",
            path and (dmg > 0 and (", the way there costs " .. dmg .. " half hearts") or "") or ", NO path from here"),
          function() Nav.useDoor(p, slot) end)
    end
  end
  -- 2. pickups still here, with value and risk
  for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP)) do
    local val = Nav.value(p, e)
    if val > 0 and #list < 6 then
      local path = Nav.findPath(room, room:GetGridIndex(p.Position), room:GetGridIndex(e.Position), p.CanFly, false)
      local dmg = path and Danger.pathDamage(path) * 2 or nil
      add(string.format("Go get the pickup at %s (worth %d points%s)", cr(room, room:GetGridIndex(e.Position)), val,
            dmg == nil and "; no path: blocked" or (dmg > 0 and ("; there and back costs " .. dmg .. " half hearts") or "; safe")),
          function() Nav.fetch(p, e) end)
    end
  end
  -- 3. the nearest poop (shooting it may open a way)
  local bestPoop, bd = nil, math.huge
  for i = 0, room:GetGridSize() - 1 do
    local ge = room:GetGridEntity(i)
    if ge and ge:GetType() == GridEntityType.GRID_POOP and ge.CollisionClass ~= GridCollisionClass.COLLISION_NONE then
      local d = (room:GetGridPosition(i) - p.Position):Length()
      if d < bd then bestPoop, bd = i, d end
    end
  end
  if bestPoop then
    add("Shoot the poop at " .. cr(room, bestPoop) .. " (tears break it; it may be blocking a way)",
        function() Nav.shootPoop(p, bestPoop) end)
  end
  if bombs >= R.bombs.watchdog_min then
    add(string.format("Bomb the nearest rock (uses 1 of %d bombs)", bombs), function() Nav.bombNearest(p) end)
  end
  add("Wait here a moment (do nothing)", function() end)
  return list
end

return Options
