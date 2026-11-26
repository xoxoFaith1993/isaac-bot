-- Proof that each test guards its fix: every entry undoes ONE fix in memory (find -> replace in the bot's code
-- as it loads; the files in mod\ are never touched) and names the test that must then FAIL.
-- Run: C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File test\run.ps1 -Prove
-- If the bot's code changes so a `find` no longer matches, -Prove says STALE: update the find text here.
-- `find` is plain text (not a pattern); \n = line break (Windows line endings are ignored).

return {
  { test = "re-plans after a new run restarts", why = "forgetting the timers when the frame counter goes back",
    patches = { { file = "reflex", find = "if Reflex.lastFrameSeen and fNow0 < Reflex.lastFrameSeen then",
                  replace = "if false then" } } },

  { test = "Gemini's cord balls aren't enemies", why = "the cord rule and the seed check (stale 'seen solid' memory)",
    patches = { { file = "reflex", find = "if e.Parent ~= nil and not e:IsVulnerableEnemy() then return false end",
                  replace = "" },
                { file = "reflex", find = "if IsaacBotSolidSeen[h] == seed then return true end",
                  replace = "if IsaacBotSolidSeen[h] then return true end" } } },

  { test = "walks to the button in a cleared trap room", why = "walking onto an unpressed plate",
    patches = { { file = "nav", find = "if plateIdx then", replace = "if false then" } } },

  -- (No entry for tests 3-5 - dodge, corner, Host bait: tried m_hit+m_soft_w 0, m_trap 0, and "aim reward on a
  -- closed target" + no bait distance; each still passed. The fake's rough movement and the general distance
  -- pull hide those fixes, so those three are broad behaviour checks, not proofs of one fix.)

  { test = "moves toward a still target it can't hit yet", why = "beam trimmed by danger only (tied plans)",
    patches = { { file = "mover", find = "for _, pl in ipairs(beam) do pl.s = total(ctx, pl) end",
                  replace = "for _, pl in ipairs(beam) do pl.s = pl.c end" },
                { file = "mover", find = "for _, pl in ipairs(nextBeam) do pl.s = total(ctx, pl) end",
                  replace = "for _, pl in ipairs(nextBeam) do pl.s = pl.c end" } } },

  { test = "collects pennies across the room", why = "distance in the worth-it test",
    patches = { { file = "nav", find = "local worth = net > 0 and (net + 1000 - it.d * 0.01) or net",
                  replace = "local worth = net - it.d * 0.05" } } },

  { test = "no two-room bounce over a locked door", why = "deadEdge (failed doors only remembered per room visit)",
    patches = { { file = "nav", find = "  deadEdge[here .. \">\" .. hop] = {",
                  replace = "  local _forgotten = {" } } },

  { test = "loop breaker refuses to step straight back", why = "the loop breaker (looping() never fires)",
    patches = { { file = "nav", find = "  if #entries < 8 then return false end",
                  replace = "  if true then return false end" } } },

  { test = "tries a locked door again after finding a key", why = "forgiving a dead door when keys go up",
    patches = { { file = "nav", find = "if p:GetNumKeys() > d.keys or ", replace = "if " } } },

  { test = "shoots open a door walled off by poop", why = "shooting poop in front of a door",
    patches = { { file = "nav", find = "isPoop then\n            return { kind = \"shoot poop to the door",
                  replace = "false then\n            return { kind = \"shoot poop to the door" } } },

  { test = "secret-wall guess with pits in front is dropped", why = "the walkable-spot check in front of the wall",
    patches = { { file = "nav", find = "if room:GetGridCollision(standIdx) == GridCollisionClass.COLLISION_NONE",
                  replace = "if true" } } },

  { test = "steps off a trapdoor that opened under it", why = "stepping off a closed trapdoor",
    patches = { { file = "nav", find = "if goal.onFor > 30 then", replace = "if false then" } } },

  { test = "goes back to the cleared boss room for the trapdoor", why = "returning to a cleared boss room",
    patches = { { file = "nav", find = "if (R.room[info.type] or {}).boss and info.clear then return d end",
                  replace = "if false then return d end" } } },

  { test = "floor map survives a code reload", why = "IsaacBotNavState restore on reload",
    patches = { { file = "nav", find = "if IsaacBotNavState then", replace = "if false then" } } },

  { test = "hidden secret door isn't treated as a door", why = "the still-solid-wall check on secret doors",
    patches = { { file = "nav",
                  find = "if col == GridCollisionClass.COLLISION_WALL or col == GridCollisionClass.COLLISION_SOLID then return false end",
                  replace = "" } } },

  { test = "breaks the poop gate of a boxed-in enemy", why = "poop gates (gate_r 0)",
    patches = { { file = "reflex", find = "gate_r = 130,", replace = "gate_r = 0," } } },

  { test = "targets the spawner before its spiders", why = "spawner bonus in the firing planner (spawner_w 0)",
    patches = { { file = "reflex", find = "spawner_w = 250,", replace = "spawner_w = 0," } } },

  { test = "targets the spawner before its spiders", why = "spawners sorted first before the 5-target cut",
    patches = { { file = "reflex", find = "if sa ~= sb then return sa > sb end", replace = "" } } },

  { test = "never plans a firing spot next to a fire", why = "fires keep the full gap (planner clearance)",
    patches = { { file = "reflex", find = "if e.Type == EntityType.ENTITY_FIREPLACE then return S.plan_clearance end",
                  replace = "" } } },

  { test = "closed Host doesn't make it go for a far fire", why = "shield must be within 70 px",
    patches = { { file = "reflex", find = "if d < 70 and d < bestScore then", replace = "if d < bestScore then" } } },

  { test = "never siege-bombs a fire or a poop", why = "no siege toward a fire/poop",
    patches = { { file = "nav",
                  find = "if target.kind or target.Type == EntityType.ENTITY_FIREPLACE then siege = nil; return nil end",
                  replace = "" } } },

  { test = "sprays at a target that's roughly in line", why = "loose_aim (only sure hits fired)",
    patches = { { file = "reflex", find = "loose_aim = 40,", replace = "loose_aim = 0," } } },

  { test = "fights an enemy that has no collision yet (Boils)", why = "free-standing never-solid enemies count",
    patches = { { file = "reflex", find = "return e.Parent == nil and e:IsVulnerableEnemy()", replace = "return false" } } },

  { test = "doesn't cross spikes for a penny", why = "damage priced in the worth-it test",
    patches = { { file = "nav", find = "local net = val - Danger.cost(p, dmg)", replace = "local net = val" } } },

  { test = "cleared room with an unkillable shooter: walks on, only dodges", why = "dodge-only mode (any shot = a fight)",
    patches = { { file = "reflex",
                  find = "if threats > 0 and hurtable == 0 and room:IsClear() and not Reflex.forceFight then",
                  replace = "if false then" } } },

  { test = "cleared room with an unkillable shooter: walks on, only dodges", why = "no target while only dodging",
    patches = { { file = "reflex", find = "if st.dodgeOnly then target = nil end", replace = "" } } },

  { test = "weak door write-offs expire after a minute", why = "the 60 s expiry of weak write-offs",
    patches = { { file = "nav", find = "\n     or (soft and d.f and Game():GetFrameCount() - d.f > 30 * 60) then",
                  replace = " then" } } },

  { test = "locked door write-off doesn't expire after a minute", why = "locked doors excluded from the expiry",
    patches = { { file = "nav", find = "local soft = d.why ~= \"locked, no key\" and", replace = "local soft = true or" } } },

  { test = "only exit written off: still takes it", why = "forgiving written-off doors when nothing is left",
    patches = { { file = "nav", find = "if not hop and next(deadEdge) then", replace = "if false then" } } },

  { test = "no bounce between two rooms with a locked door each", why = "forgiving locked write-offs too",
    patches = { { file = "nav",
                  find = "if d.why ~= \"locked, no key\" and not tostring(d.why):find(\"rocks in the way\") then deadEdge[k] = nil",
                  replace = "if true then deadEdge[k] = nil" } } },

  { test = "no bounce between two rooms with a locked door each", why = "forgiving once per situation (+ all reasons)",
    patches = { { file = "nav", find = "if forgaveSig ~= sig then", replace = "if true then" },
                { file = "nav",
                  find = "if d.why ~= \"locked, no key\" and not tostring(d.why):find(\"rocks in the way\") then deadEdge[k] = nil",
                  replace = "if true then deadEdge[k] = nil" } } },

  { test = "sprays down a corridor at a target roughly in line", why = "loose aim trying all 4 directions",
    patches = { { file = "reflex", find = "for _, sd in ipairs({ shoot, \"left\", \"right\", \"up\", \"down\" }) do",
                  replace = "for _, sd in ipairs({ shoot }) do" } } },

  { test = "doesn't settle in a corner when enemies circle the middle", why = "wall-blocked ways counted once again",
    patches = { { file = "mover", find = "closed = closed + (wall and 2 or 1)", replace = "closed = closed + 1" } } },

  { test = "doesn't settle in a corner when enemies circle the middle", why = "all of 1.1.46 (wall x2, centre pull, edge cost)",
    patches = { { file = "mover", find = "closed = closed + (wall and 2 or 1)", replace = "closed = closed + 1" },
                { file = "reflex", find = "m_center = 0.25,", replace = "m_center = 0," },
                { file = "reflex", find = "m_edge = 150,", replace = "m_edge = 0," } } },
  -- (the centre/edge pull alone: 8% -> 16% in the fake, under the 20% line: not separately proven)

  { test = "keeps moving while an enemy is underground", why = "the cost of standing still with a burrower (m_burrow 0)",
    patches = { { file = "reflex", find = "m_burrow = 200,", replace = "m_burrow = 0," } } },

  { test = "leaves a secret room the way it came in", why = "only open, non-solid doors inside a secret room",
    patches = { { file = "nav", find = "if here and here.Data and SECRET_TYPES[here.Data.Type] then",
                  replace = "if false then" } } },

  { test = "gets clear of a bomb it just placed", why = "bomb danger in the v2 core",
    patches = { { file = "mover", find = "if (bm.Position - p):Length() < br then c = c + S.m_hit * wt end",
                  replace = "" } } },

  { test = "gets clear of a bomb it just placed", why = "bomb radius without Isaac's size, half the radius",
    patches = { { file = "mover", find = "local br = S.bomb_r + pr + (big and 40 or 0)",
                  replace = "local br = S.bomb_r * 0.5 + (big and 40 or 0)" } } },

  { test = "doesn't shoot poop next to a moving enemy in the open", why = "gates only for walled-in enemies",
    patches = { { file = "reflex", find = "if not t.kind and walledIn(t) and", replace = "if not t.kind and" } } },

  { test = "doesn't swap its card for a pill", why = "pocket slot check for pills/cards",
    patches = { { file = "nav", find = "(p:GetPill(0) == 0 and p:GetCard(0) == 0) and V.pill_card or 0",
                  replace = "V.pill_card" } } },
}
