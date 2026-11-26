-- Isaac Bot run strategy (Level 3): an overall view of the run, not just the room (the author, 2026-11-25: "we need a
-- whole new layer of critical thinking... an overall view of item choice, current health, stats, where we're at").
--
-- 1. Run profile: what the build is good and bad at (damage, tear rate, range, shot speed, speed, flight, defence,
--    health) and how strong it is for this floor (our damage per second against what the floor usually needs).
-- 2. Run-aware item value: an item's worth = its rating FOR THIS BOT (knowledge/item_ratings.json, sent by the helper)
--    plus how well it fixes this run's weaknesses. Rating 0 ("hurts this bot") = never take it. Choice pedestals
--    (take one, the rest vanish): only the best one is wanted.
-- The profile also nudges the risk layer: a strong build ends fights fast, a weak one plays it safer.
local Strategy = { ratings = {}, profile = nil, lastProfile = -999 }
local Deals = include("deals") -- devil/angel deal weighing (2026-11-26)
Strategy.deals = Deals

-- "id=rating,carry,tag,tag;..."  (tags = item_ratings.json tag_codes: dmg, tear, rng, ss, spd, hp, fly, spec, def...)
function Strategy.loadRatings(text)
  local n = 0
  for entry in string.gmatch(text or "", "[^;]+") do
    local id, rest = entry:match("^(%d+)=(.*)$")
    if id then
      local parts = {}
      for t in string.gmatch(rest, "[^,]+") do parts[#parts + 1] = t end
      local r = { rating = tonumber(parts[1]) or 2, carry = tonumber(parts[2]) or 0, tags = {} }
      for i = 3, #parts do r.tags[parts[i]] = true end
      Strategy.ratings[tonumber(id)] = r
      n = n + 1
    end
  end
  return n
end

-- What this floor usually asks of us: a plain Isaac (3.5 damage, ~2.7 tears/s = ~9.5 dps) is fine on floor 1, and
-- the need grows ~30% a floor.
local function floorNeed(stage) return 9.5 * (1 + 0.3 * math.max(0, (stage or 1) - 1)) end

-- The run profile. needs[tag] = 0..1 (how much an item with that tag would help right now).
function Strategy.makeProfile(p)
  local stage = 1
  pcall(function() stage = Game():GetLevel():GetStage() end)
  local tears = 30 / (p.MaxFireDelay + 1)
  local dps = p.Damage * tears
  local hp = 0
  pcall(function() hp = p:GetHearts() + p:GetSoulHearts() + p:GetBoneHearts() * 2 end)
  local strength = dps / floorNeed(stage)
  local hasDef = false
  for id, r in pairs(Strategy.ratings) do -- any held item the ratings tag as defensive (Holy Mantle, The Wafer...)
    if r.tags.def and p:HasCollectible(id) then hasDef = true; break end
  end
  local function clamp(x) return math.max(0, math.min(1, x)) end
  local needs = {
    dmg = clamp(1.3 - strength),               -- damage and tears are the two halves of dps
    tear = clamp(1.2 - strength) * 0.8,
    rng = clamp((300 - p.TearRange) / 150),    -- short range = must fight close (risky for this bot)
    ss = clamp((1.0 - p.ShotSpeed) / 0.4),     -- slow tears miss movers
    spd = clamp((1.1 - p.MoveSpeed) / 0.4),    -- slow = can't dodge
    hp = clamp((8 - hp) / 6),
    soul = clamp((8 - hp) / 6),
    heal = clamp((6 - hp) / 6),
    def = hasDef and 0.2 or 0.7,               -- defence is always good for a no-hit bot
    fly = p.CanFly and 0 or 0.4,
    spec = 0.3, hom = 0.4, prc = 0.3,
  }
  return { stage = stage, dps = dps, tears = tears, strength = strength, hp = hp, needs = needs, hasDef = hasDef }
end

function Strategy.update(p)
  local f = Game():GetFrameCount()
  -- (math.abs: a new run restarts the frame counter; it kept the OLD run's profile, 2026-11-26)
  if Strategy.profile and math.abs(f - Strategy.lastProfile) < 90 then return Strategy.profile end
  Strategy.lastProfile = f
  local ok, prof = pcall(Strategy.makeProfile, p)
  if ok then Strategy.profile = prof end
  return Strategy.profile
end

-- Short text for the log: "strength 1.12 (dps 10.6 / floor needs 9.5) needs: rng 0.5, def 0.7"
function Strategy.report()
  local pr = Strategy.profile
  if not pr then return "no profile yet" end
  local top = {}
  for k, v in pairs(pr.needs) do if v >= 0.4 then top[#top + 1] = string.format("%s %.1f", k, v) end end
  table.sort(top)
  return string.format("strength %.2f (dps %.1f, floor %d)|needs %s", pr.strength, pr.dps, pr.stage,
    #top > 0 and table.concat(top, ", ") or "nothing much")
end

-- Points an item is worth to this run (same scale as rules.lua values: base 30 + 15 per rating step, plus the fit).
-- nil = no rating known (the caller falls back to the game's quality). 0 = don't take it.
function Strategy.itemValue(p, id, V)
  local r = Strategy.ratings[id]
  if not r then return nil end
  if r.rating <= 0 then return 0 end
  local pr = Strategy.profile or Strategy.update(p)
  local fit = 0
  if pr then
    for tag in pairs(r.tags) do fit = fit + (pr.needs[tag] or 0) end
  end
  return V.item_base + V.item_per_quality * r.rating + math.floor(20 * math.min(2, fit))
end

-- Level 3, steps 3-4: things with a PRICE. Devil deals cost hearts, the shop costs coins. Returns points (0 = don't).
--   devil (Price < 0): only a strong item for this run (run value >= R.deals.min_value), and never below
--     R.deals.keep_containers heart containers / R.deals.keep_hp half hearts after paying.
--   shop (Price > 0): worth it when the value beats the price (1 coin = 1 point) and a small reserve stays; keys,
--     bombs and hearts only when we're short of them.
local PRICE = { [-1] = { red = 2 }, [-2] = { red = 4 }, [-3] = { soul = 6 }, [-4] = { red = 2, soul = 4 },
                [-7] = { soul = 2 }, [-8] = { soul = 4 }, [-9] = { red = 2, soul = 2 } }
function Strategy.buyValue(p, pk, V, R)
  local price = pk.Price or 0
  local D = R.deals or {}
  if price == -1000 then price = 0 end -- PRICE_FREE
  if price < 0 then
    if not D.take then return 0 end
    local cost = PRICE[price]
    if not cost or pk.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then return 0 end
    local val = Strategy.itemValue(p, pk.SubType, V) or 0
    -- weighed in deals.lua (2026-11-26, the deal work levels 1-2): worth minus the hearts (dearer the fewer are left)
    -- minus the angel rooms a first deal gives up; the old floors (2 containers, 2 hearts) stay
    local net, why = Deals.devilNet(val, cost, Deals.state(p), D)
    Deals.why = why
    return net
  end
  if price > 0 then
    local coins = p:GetNumCoins()
    if coins < price then return 0 end
    local S = R.shop or {}
    local v, val = pk.Variant, 0
    if v == PickupVariant.PICKUP_COLLECTIBLE then
      val = Strategy.itemValue(p, pk.SubType, V) or 0
    elseif v == PickupVariant.PICKUP_KEY then
      val = (p:GetNumKeys() == 0) and (S.key_if_none or 12) or 0
    elseif v == PickupVariant.PICKUP_BOMB then
      val = (p:GetNumBombs() == 0) and (S.bomb_if_none or 10) or 0
    elseif v == PickupVariant.PICKUP_HEART then
      local missing = p:GetMaxHearts() - p:GetHearts()
      val = (missing >= 2) and (S.heart_if_missing or 12) or (p:CanPickSoulHearts() and pk.SubType == 3 and 10 or 0)
    end
    local reserve = (v == PickupVariant.PICKUP_COLLECTIBLE) and 0 or (S.reserve or 5)
    if val <= price or coins - price < reserve then return 0 end
    return val - price
  end
  return 0
end

-- Level 3, step 6: cards and pills (knowledge/consumable_ratings.json, sent by the helper as
-- "c<id>=<use>,<rating>;p<effect>=<use>,<rating>,<bad 0/1>;..."). use: now/fight/boss/hurt/clear/never/manual.
Strategy.cards, Strategy.pills = {}, {}
function Strategy.loadConsumables(text)
  local n = 0
  for kind, id, use, rating, bad in string.gmatch(text or "", "([cp])(%d+)=(%a+),(%d)(,?%d?)") do
    local e = { use = use, rating = tonumber(rating), bad = bad == ",1" }
    if kind == "c" then Strategy.cards[tonumber(id)] = e else Strategy.pills[tonumber(id)] = e end
    n = n + 1
  end
  return n
end

local lastPocket = -999
local function useFits(e, ctx)
  if not e or e.rating <= 0 then return false end
  if e.use == "now" then return true end
  if e.use == "fight" then return ctx.enemies >= 3 or (ctx.boss and ctx.enemies > 0) end
  if e.use == "boss" then return ctx.boss and ctx.enemies > 0 end
  if e.use == "hurt" then return ctx.missingRed >= 2 end
  if e.use == "clear" then return ctx.enemies == 0 end
  return false
end
-- Press "use card/pill" now? ctx = { enemies, boss, missingRed }. Unknown pills are a gamble: only when the risk
-- layer is relaxed (healthy, nothing at stake) and the room is clear.
function Strategy.wantPocket(p, ctx)
  local f = Game():GetFrameCount()
  if math.abs(f - lastPocket) < 45 then return false end -- (abs: survives the frame counter restarting in a new run)
  local card = p:GetCard(0)
  if card and card > 0 then
    if useFits(Strategy.cards[card], ctx) then lastPocket = f; return true end
    return false
  end
  local pill = p:GetPill(0)
  if not pill or pill <= 0 then return false end
  local known, effect = false, nil
  pcall(function()
    local pool = Game():GetItemPool()
    known = pool:IsPillIdentified(pill)
    effect = pool:GetPillEffect(pill, p)
  end)
  if known and effect then
    local e = Strategy.pills[effect]
    if e and e.bad then return false end
    if useFits(e, ctx) then lastPocket = f; return true end
    return false
  end
  local Risk = IsaacBotRisk
  if ctx.enemies == 0 and Risk and not Risk.atStake and Risk.level >= 0.5 then lastPocket = f; return true end
  return false
end

-- How strong this run is for its floor, as a risk nudge: strong builds end fights fast, weak ones stay careful.
function Strategy.riskNudge()
  local pr = Strategy.profile
  if not pr then return 0 end
  if pr.strength >= 1.5 then return 0.1 end
  if pr.strength < 0.7 then return -0.1 end
  return 0
end

return Strategy
