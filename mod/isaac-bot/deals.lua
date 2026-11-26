-- Devil and angel deals (2026-11-26; the author, after the bot's first Mom kill: "I'd like to work on the devil deals
-- and angel deals weighing... phenomenal that he was able to get this far without taking any of those").
--
-- Level 1 - see them: after every boss on a deal floor, a "deal" line with the game's own devil and angel chance, the
--   door that opened (devil, angel or none) and why there might be none; in a deal room, every item with its price,
--   its worth to this run and the decision with the reason. tools/deals.py sums them up per run.
-- Level 2 - weigh them: a devil item is worth its value minus
--   * the hearts: each heart container paid costs more the fewer are left (`container` points x 6 / containers left
--     after paying), soul hearts a fixed `soul_heart` each;
--   * the path: the FIRST devil deal of a run ends the angel rooms for good, so it also pays for the angel items the
--     rest of the run could still have brought (deal floors left x `angel_odds` x `angel_item`). After one deal that
--     cost is gone (already on the devil path). Rule of thumb, to tune from the deal reports.
--   and the old hard floors stay: never below `keep_containers` heart containers or `keep_hp` half hearts.
-- Angel items are free: taken like any other item (nav.lua's item values), never weighed here.

local Deals = { why = nil }

local DEAL_TYPES = { [14] = "devil", [15] = "angel" }
Deals.TYPES = DEAL_TYPES

-- the game's view of the run: deal floor, chances, a deal already taken (all pcall'd: older APIs lack some calls)
function Deals.state(p)
  local st = { stage = 1, dealTaken = false, devilChance = nil, angelChance = nil, redHit = nil }
  pcall(function()
    local lv = Game():GetLevel()
    st.stage = lv:GetStage()
    st.redHit = lv:GetStateFlag(LevelStateFlag.STATE_REDHEART_DAMAGED)
  end)
  pcall(function() st.dealTaken = Game():GetDevilRoomDeal() and true or false end)
  pcall(function() st.devilChance = Game():GetRoom():GetDevilRoomChance() end)
  pcall(function() st.angelChance = Game():GetLevel():GetAngelRoomChance() end)
  if p then
    st.containers = math.floor((p:GetMaxHearts() or 0) / 2)
    st.soul = p:GetSoulHearts() or 0
    st.hp = (p:GetHearts() or 0) + (p:GetSoulHearts() or 0) + (p:GetBoneHearts() or 0) * 2
  end
  return st
end

-- Level 2: what a devil item is worth after its price. val = the item's worth to this run (strategy.lua itemValue),
-- cost = { red = half hearts of containers, soul = half hearts of soul }, st = Deals.state, D = rules R.deals.
-- Returns net points (> 0 = buy) and the reason.
function Deals.devilNet(val, cost, st, D)
  local containers = st.containers or 0
  local redC = math.floor((cost.red or 0) / 2)
  if redC > 0 and containers - redC < (D.keep_containers or 2) then
    return 0, string.format("would leave %d heart containers (keep %d)", containers - redC, D.keep_containers or 2)
  end
  if cost.soul and (st.soul or 0) < cost.soul then return 0, "not enough soul hearts" end
  if (st.hp or 0) - (cost.red or 0) - (cost.soul or 0) < (D.keep_hp or 4) then
    return 0, "would leave too little health"
  end
  local hearts = 0
  for k = 1, redC do hearts = hearts + (D.container or 20) * 6 / math.max(1, containers - k) end
  hearts = hearts + (D.soul_heart or 12) * (cost.soul or 0) / 2
  local path = 0
  if not st.dealTaken then
    local left = math.max(0, (D.last_deal_floor or 8) - (st.stage or 1))
    path = left * (D.angel_odds or 0.06) * (D.angel_item or 90)
  end
  local net = val - hearts - path
  local why = string.format("worth %d - hearts %d - angel path %d = %d", val, math.floor(hearts + 0.5),
    math.floor(path + 0.5), math.floor(net + 0.5))
  if net < (D.min_net or 10) then return 0, why .. " (under " .. (D.min_net or 10) .. ")" end
  return net, why
end

-- the deal door this boss room opened (nil = none): scans the room's doors
function Deals.doorHere()
  local room = Game():GetRoom()
  for slot = 0, 7 do
    local d = room:GetDoor(slot)
    if d and DEAL_TYPES[d.TargetRoomType] then return DEAL_TYPES[d.TargetRoomType], d:IsOpen() end
  end
  return nil
end

-- Level 1: the "deal" line after a boss (main.lua calls it once per cleared boss room)
function Deals.afterBossLine(p)
  local st = Deals.state(p)
  local door, open = Deals.doorHere()
  local why = ""
  if not door then
    if st.stage <= 1 then why = " (floor 1: no deals)"
    elseif st.redHit then why = " (red-heart damage this floor)"
    else why = " (the roll)" end
  end
  return string.format("after boss|stage %d|devil chance %s|angel chance %s|door %s|red hit %s|deal taken %s%s",
    st.stage, st.devilChance and string.format("%.2f", st.devilChance) or "?",
    st.angelChance and string.format("%.2f", st.angelChance) or "?", door and (door .. (open and "" or " (shut)")) or "none",
    tostring(st.redHit), tostring(st.dealTaken), why)
end

return Deals
