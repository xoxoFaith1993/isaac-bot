-- Isaac Bot rescue ladder: ONE watchdog for every kind of stuck, instead of a fix per situation.
-- "Progress" = a new room, damage dealt to enemies, or something collected. No progress for a while
-- (rules.lua: R.stuck) climbs the ladder, one step every few seconds:
--   replan -> shake -> bomb -> leave -> report (log it for a developer, allow last-resort rooms, start over)
-- Rescue.update(...) returns an override (move, shoot) while a "shake" is running, else nil.

local R = include("rules")
local Rescue = { level = 0, step = "", reports = 0 }

local st = { room = nil, enemyHp = nil, stash = nil, since = 0, done = {} }

local function totalEnemyHp()
  local hp = 0
  for _, e in ipairs(Isaac.GetRoomEntities()) do
    if e:IsActiveEnemy(false) and e:IsVulnerableEnemy() then hp = hp + e.HitPoints end
  end
  return hp
end

local function stash(p)
  return p:GetNumCoins() + p:GetNumBombs() * 100 + p:GetNumKeys() * 10000 + p:GetCollectibleCount() * 1000000
      + p:GetHearts() * 7 + p:GetSoulHearts() * 13 + p:GetPill(0) * 3 + p:GetCard(0) * 5 + p:GetTrinket(0) * 11
end

local function reset(f)
  st.since, st.done, Rescue.level, Rescue.step = f, {}, 0, ""
  Rescue.wantSiege = false
end

-- the brain answered: give its choice a fair chance before the ladder starts again
function Rescue.brainAnswered()
  reset(Game():GetFrameCount())
end

-- send: function(kind, body) for reports; nav/reflex: the modules; fighting: reflexes are in a fight.
-- In a fight the steps mean: replan = switch target, shake = spray aim, bomb = try a siege bomb,
-- leave = (doors are shut) nothing, report = ask the brain.
Rescue.wantSiege = false
function Rescue.update(p, nav, fighting, send, reflex, M)
  local f = Game():GetFrameCount()
  local roomIdx = Game():GetLevel():GetCurrentRoomIndex()
  local hp = totalEnemyHp()
  local s = stash(p)

  local progressed = (roomIdx ~= st.room) or (s ~= st.stash) or (st.enemyHp and hp < st.enemyHp - 0.4)
  st.room, st.stash, st.enemyHp = roomIdx, s, hp
  if progressed or p:IsDead() or p:IsHoldingItem() then reset(f); return nil end

  local limit = (fighting and R.stuck.fight_s or R.stuck.walk_s) * 30
  local idle = f - st.since
  if idle < limit then Rescue.level, Rescue.step = 0, ""; return nil end

  local ladder = R.stuck.ladder
  local lvl = math.min(#ladder, 1 + math.floor((idle - limit) / (R.stuck.step_s * 30)))
  Rescue.level, Rescue.step = lvl, ladder[lvl]
  local first = not st.done[lvl]
  st.done[lvl] = true
  local step = ladder[lvl]

  if step == "replan" then
    if first and not fighting then nav.replan() end
    if first and fighting and reflex then reflex.banTarget(8) end -- can't make headway on this one: pick another
  elseif step == "shake" then
    -- walk toward open ground (room centre) and spray tears all around: breaks poop/fires, wakes things up
    local room = Game():GetRoom()
    local to = room:GetCenterPos() - p.Position
    local dirs = { "up", "right", "down", "left" }
    local shoot = dirs[math.floor(f / 8) % 4 + 1]
    if fighting then return nil, shoot end -- in a fight the reflexes keep steering (dodging comes first)
    if to:Length() > 40 then return to:Normalized(), shoot end
    return Vector(0, 0), shoot
  elseif step == "bomb" then
    if first and not fighting then nav.bombNearest(p) end
    if first and fighting then Rescue.wantSiege = true end
  elseif step == "leave" then
    if first and not fighting then nav.leaveAny(p) end
  elseif step == "report" then
    if first and M and M.Options then
      -- the multiple-choice brain: the code lists the real options, the model picks one ("do|<id>")
      local ok, list = pcall(M.Options.build, p, fighting, M)
      if ok and list and #list > 0 then
        Rescue.options = {}
        local menu = {}
        for _, o in ipairs(list) do Rescue.options[o.id] = o; menu[#menu + 1] = { id = o.id, text = o.text } end
        local okF, facts = pcall(M.Options.facts, p, fighting, M.Danger)
        send("ask", M.json.encode({ facts = okF and facts or "", options = menu, goal = nav.status.goal or "" }))
      elseif not ok then
        send("error", "options: " .. tostring(list))
      end
    end
    if first then
      Rescue.reports = Rescue.reports + 1
      local lv = Game():GetLevel()
      send("stuck", table.concat({ lv:GetStage(), roomIdx, Game():GetRoom():GetType(), fighting and "fight" or "walk",
        nav.status.goal or "", math.floor(p.Position.X) .. "," .. math.floor(p.Position.Y),
        "enemyhp " .. math.floor(hp), "bombs " .. p:GetNumBombs(), "keys " .. p:GetNumKeys() }, "|"))
      -- curse rooms etc. only when the WALKING has run out of places to go; a stuck fight isn't a reason
      -- (it once walked into a curse room right after a Clotty stall and took 2 hits)
      if not fighting and (nav.status.goal == "nothing to do" or nav.status.goal == "no path, skipping") then
        nav.lastResort = true
      end
      nav.replan()
    end
    if idle - limit > (#ladder) * R.stuck.step_s * 30 then reset(f) end -- climb the ladder again
  end
  return nil
end

return Rescue
