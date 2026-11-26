# Second opinion: the Isaac Bot, judged cold

Written by an outside reviewer acting as a sceptical senior game-AI engineer. I read the repo docs, the mod code,
the Python helper, the tools, the tests and the recorded results in `runs/`. I did not read any other analysis of the
project. Everything below comes from the code and data in this repository. File references are repo-relative.

---

## 1. Verdict in plain words

For about a day of work this is a lot of working machinery, and some of it is genuinely clever. The game
integration, the room replay bench, the "why" logging and the in-game-engine tests are better than most hobby bots
and better than some studio playtest bots I have seen. A skilled game-AI developer given the same 24 hours would
probably have built less: fewer features, fewer bosses handled, no LLM, no risk layer. In exchange they would have
built one thing this project lacks almost completely: a measurement system that can tell a real improvement from
luck. That is the core problem. The bot is steered by anecdotes ("it parked in a corner against flies") turned into
new cost terms. It is then "checked" with 4-round A/B tests and small benches whose noise is larger than the effects
being measured. The movement core was rebuilt to escape "40 hand-tuned weights that fight each other". Within the
same day it grew back about 20 additive cost terms, and the settings table now holds about 125 knobs, many of them
dead. The architecture is not a dead end. The game I/O, the bench and the receding-horizon planner are a fair
base. But the way it is being improved is a dead end. More fixes made this way will plateau, and nobody will be
able to say whether the last twenty changes helped. Fix measurement first, and this can become a strong bot.

---

## 2. Scorecard (1 = poor, 5 = excellent)

| Area | Score | Why |
|---|---|---|
| Architecture | 3 | Sensible layers (eyes, mover, nav, risk, strategy, rescue) and a sound planner. But two movement cores coexist with a silent fallback, modules share state through globals, and there is no forward model or simulator. |
| Decision-making core | 2.5 | The beam search over learned reach circles is a reasonable baseline. The cost function is a pile of incommensurate heuristics, and key decisions (stand still, shoot or hold) are made outside the search by rules that partly don't work. |
| Measurement / evaluation | 1.5 | The right ideas (bench by layout ID, gauntlet, A/B) are let down by tiny samples, no confidence intervals, sequential A/B with drifting learned state, results not tied to versions, and a tuner that tunes dead knobs. |
| Testing | 3 | Running the real Lua in the game's own Lua DLL, plus hand-made mutation proofs, is excellent for navigation logic. Movement and dodging quality is effectively untested offline, and the mock's physics no longer match what the bot itself learned. |
| Code quality / maintainability | 2 | Readable and heavily commented, but: a 480-line `Reflex.update`, a flat 125-entry settings table shared by two cores and mutated in place by the risk layer, `pcall` around nearly everything, cross-module globals, and diary comments that make the code long. |
| Knowledge handling | 3 | Good instinct: game knowledge lives in data files, and unreviewed drafts are not sent. But most of the knowledge was written by AI sessions from wikis and guides, is not checked against the game, and is used as hard behaviour (tells, attack windows, "stay diagonal"). |
| Process / method | 2.5 | Diagnose-before-fix, the one-writer rule, a privacy hook and honest write-ups (`test/FOUND_BUGS.md`) are good habits. But changes ship every 10-20 minutes with several behaviour changes bundled together, and no measurement gate. "Fix the category" in practice means "add a term". |
| Readiness to scale to "best" | 1.5 | Evaluation runs in real time on one game instance, and outcomes are high-variance. Until throughput and statistics are fixed, scaling means adding hand-written rules for each boss and item, which does not get to "best". |

---

## 3. What is genuinely good

- **Clean game integration with no memory hacks.** Inputs go through `MC_INPUT_ACTION` (`mod/isaac-bot/main.lua:93-120`),
  exactly like a controller. The bot plays only on save slot 2, and the menu autopilot has explicit guards. Mod to PC
  messages travel through a second mod's save file (`mod/isaac-bot-out/`), with a measured 100 ms round trip. That
  is a neat workaround for a sandbox with no sockets.
- **Learned reach per enemy type.** `Mover.observe` / `learn` (`mod/isaac-bot/mover.lua:40-84`) compare two cheap
  hypotheses ("keeps velocity" or "stays put") at four horizons. They estimate drift toward Isaac and keep an online
  95th-percentile radius, using an asymmetric step (`mover.lua:48-49`). The update is cheap, keeps no history and
  degrades gracefully, and a new enemy type gets a cautious circle until data arrives. This is the right kind of
  idea for a 30 Hz Lua budget.
- **Self-measurement that found a real bug.** `Mover.observePlayer` (`mover.lua:286-307`) learns Isaac's own top speed
  and acceleration. That exposed the planner's assumed 4.6 px/update against a real ~7.7 (PLAN.md, 1.1.35-1.1.44).
  Checking your own model against the game is what professionals do, and it paid off here.
- **Receding-horizon beam search.** `Mover.choose` (`mover.lua:541-747`) searches 3 chained moves over ~1.2 s and keeps
  the best 6 at each step. Predictions are computed once per sample time and shared across all plans, and wall,
  hazard and ways-out lookups are memoised per 10-16 px patch. That took the average from 12-26 ms to about 3.5 ms
  per update (PLAN.md, lag section). The shape is right: model-predictive control with a cost function.
- **Explainability.** The `why` line (`mover.lua:731-741`) splits the cost at Isaac's current position by source
  (enemies, shots, attack lines, floor...). The hit log records what touched Isaac, the nearest shot and the risk
  level. Saved frames from Steam's background recording (`tools/look.py`, `runs/hitframes/`) let you check the log
  against what really happened. Most hobby bots are black boxes. This one tells you why it moved.
- **The room replay bench.** `tools/rooms.py` turns any room where the bot got hurt into a replayable test through
  the debug console's `goto` with the layout ID. It is cheap, uses real game physics, and grows from real failures.
  This is the seed of a proper evaluation suite.
- **Offline tests inside the game's own Lua engine.** `test/run.ps1` plus `test/mock.lua` run the bot's real modules
  in `Lua5.3.3r.dll`. `test/mutants.lua` patches each fix out in memory to prove its test fails without it. Hand-rolled
  mutation testing on a hobby project is rare and valuable. `tools/reload.ps1` refuses to reload a broken mod.
- **The risk layer as a concept.** `mod/isaac-bot/risk.lua` asks the right game-level questions: would a hit kill us,
  does red-heart damage cost the floor's devil/angel deal, is there a soul-heart buffer, is the room taking too long.
  Turning run state into how much a hit costs is exactly how a utility system should work. The execution is the
  problem (section 4), not the idea.
- **The LLM is used sensibly.** The local model never drives. It picks from a menu of options the code has already
  worked out (`brain/rescue_brain.py:choose`), and if its answer is unusable the choice falls back to a harmless one.
  That is the correct, limited role for a slow, unreliable model in a real-time loop.
- **Honest documentation.** `PLAN.md` records failures, rejected A/B results and the "respect" feedback loop.
  `test/FOUND_BUGS.md` writes up open bugs with measurements. `mutants.lua:11-13` admits that three dodge tests prove
  nothing. That honesty is the best predictor this project can improve.

---

## 4. What is wrong, weak or naive (ranked by how much it holds the bot back)

### 4.1 The measurement cannot tell signal from noise (biggest problem)

Evidence:
- **A/B tests are tiny and sequential.** `tools/ab_test.py:44-53` runs all N rounds of A and then all N rounds of B.
  PLAN.md reports N = 4: "0/4 vs 2/4. Rejected", "2/4 vs 3/4. Rejected", "1/4 vs 0/4. Kept". With 4 rounds per arm,
  differences like these are well inside chance (a 2/4 vs 3/4 split happens all the time between identical bots).
  Worse, the bot keeps learning during the test: motion reach (`motion.dat`), tells, respect and watcher lessons all
  update live. So arm B always runs on a bot that has learned more than arm A did, and B is "the code default in
  practice" (`ab_test.py:51`). The design is biased toward accepting the new setting.
- **No noise floor.** PLAN.md itself found that the same settings scored 433 / 217 / 182, and 347 vs 261 even with
  seeded layouts. `runs/tune.jsonl` shows the tuner "keeping" `touch_margin` 14 → 10 and then 10 → 14, with the
  score improving both times (433 → 217 → 182). That is a textbook picture of a tuner following noise.
- **The tuner tunes knobs the bot no longer uses.** 8 of the 12 knobs in `tools/tune.py:28-33` (`touch_margin`,
  `crowd_r`, `crowd_w`, `orbit_w`, `tele_w`, `escape_w`, `shooter_line_w`, `horizon`) are read only by the old
  movement core's `score()` (`mod/isaac-bot/reflex.lua:1014-1250`). The default core is v2 (`reflex.lua:86`,
  `core = 2`), and the old core only runs when v2 throws an error. An overnight tuning run would be fitting pure noise.
- **Old evidence carried over to new code.** The Trite fix (`dash_all`), the Blighted Ovum fix (`homing_min`) and the
  wall-bounce setting were A/B'd on the old core in 1.0.x. In v2, those settings live only in the old core's
  `enemyAt` (`reflex.lua:974-1012`). v2 uses its own dash rule with a hard-coded `Mover.dashSpeed or 5`
  (`mover.lua:108`), which nothing sets, so `set|dash_speed=...` doesn't touch v2's prediction. The "proven"
  improvements may not exist in the bot that is running.
- **The bench is built from failures.** `rooms.py collect` saves only rooms with hits, and `run` replays them worst
  first (`tools/rooms.py:50-82, 107`). Rooms chosen because they went badly tend to do better on a replay whatever
  you change (regression to the mean), so the bench flatters every change. It also says nothing about the rooms that
  were fine, which is where regressions hide.
- **Results are not tied to what produced them.** `runs/bench.jsonl`, `gauntlet.jsonl` and `tune.jsonl` rows have no
  bot version, git hash, settings or learned-state fingerprint. `runs/HIT_REVIEW.md` ("Tooling fixes") found that
  test tagging marks 0 of 103 runs as tests, the "item-free" bench sometimes picked up items, and `hits.jsonl` cannot
  be joined to rooms. In 22 commits on one day, the version moved from 1.1.54 to 1.2.26.
- **The metrics are censored and gameable.** Bench hits stop at 6 because that is death (`runs/bench.jsonl` is full
  of `died ... hits 6`), and rooms time out at 90 s. A more timid bot turns deaths into timeouts and looks "better"
  on hits. No single score combines damage, clear time and timeouts with fixed weights.
- **Watcher lessons are judged on 4 encounters** (`brain/watcher.py:34-35, 274-299`). They are triggered when a
  cause's hit rate is high, then judged on the next 4 encounters. That is regression to the mean again: lessons will
  often be "kept" by luck. And the "rate before" uses all-time counts across many code versions (`watcher.py:70`).

What a professional would do: fix the evaluation suite before touching behaviour. That means a fixed set of rooms
and seeds, sampled from all real rooms (not only the failures) plus a failure set kept separately. Learned state is
frozen and read-only during evaluation. Arms are interleaved (ABAB...) on identical seeds and rooms, and compared
pairwise. Every result carries a confidence interval, and a sequential test such as SPRT decides when to stop. An
A/A run (the same build twice) gives the minimum detectable effect. Every row stores the git hash, a settings hash
and a learned-state hash.

### 4.2 The "one safety cost" has become a weight soup again

The README says the movement core runs "a short beam search ... with one safety cost". `mover.lua:375-530` (`total`)
adds, on top of the danger in `cost_at`: ways-out × `m_trap`, a corner cost scaled by nearby movers, a pull to the
room's centre, an edge cost, ring-kite lane, gap and flow terms, escape readiness per blocked sidestep, crowd
pressure, a pincer cost, a burrow cost, a no-lane cost, a turning cost, an aim reward × `boss_aim`, preferred
distance, the waypoint pull, and the firing-spot pull × `calm_commit`. `cost_at` itself has graded circles, a soft
margin, shots, aimed-shot lines, row/column lines, floor hazards, caution squares, lasers and bombs. The units don't
match: pixels × weight, counts × weight, and flat penalties all go into one sum.

The settings table (`reflex.lua:50-181`) has about 125 entries. The risk layer then multiplies 16 of them in place
(`risk.lua:18-37, 67-91`). A boss "window" multiplies some of the same ones again, and an invincibility window
overrides them. So the effective weight of, say, `m_soft` depends on risk level × window × base, while `m_corner`
is unscaled. These interactions are exactly the "weights that fight each other" problem the rebuild was meant to
remove. `test/FOUND_BUGS.md` #3 shows it: the pincer cost fires 1,600 times in a run and still doesn't steer,
because other terms swamp the difference between plans. The fix proposed there is yet another hand-shaped falloff.

What a professional would do: put every cost in one physical currency, the expected half-hearts lost (from a
calibrated probability of being hit) plus seconds lost, converted by the risk layer's price of a hit. Then remove
comfort terms (centre pull, edges, corners, crowd) unless an ablation on the evaluation suite proves each one
earns its place. Corners should lose because the hit probability over the horizon is high there, not because of
four separate corner rules. Whatever weights remain should be tuned automatically (CMA-ES or Bayesian
optimisation) against the frozen suite, with rooms held out to catch overfitting.

### 4.3 Decisions made outside the planner, and at least one silent bug

The planner picks a move, then `Reflex.update` overrides it with post-hoc rules: stand still to shoot straight,
plant your feet, run-and-gun, spray (`reflex.lua:1771-1862`). Two of these depend on `standCost`, which is only set
by the old core (`reflex.lua:1716`). Under the default v2 core, `standCost` is always `nil`. So:

- the "stand still and shoot straight" rule at `reflex.lua:1779` never fires;
- the "plant your feet" rule at `reflex.lua:1786-1808` can never plant, so it always takes the `else` branch and
  sets `lands = false, curved = false`. In v2, plant-feet therefore *cancels* sure shots whenever the planned move
  would bend the tear, which is the opposite of its purpose. The commit history shows these rules were tuned and
  A/B-switched (1.2.23-1.2.25) on the assumption that they worked.

`Mover.choose` computes the standing-still cost (`standC`, `mover.lua:728`) but never returns it. That one missing
return value is the kind of bug a frozen evaluation suite plus a "which rules fired" counter would catch in minutes.

There is a related smell: `mover.lua:671` compares `ln.pos == wu.e.Position`. That relies on vector equality, which
the mock defines (`test/mock.lua:21`). I could not confirm from the repo that the game's `Vector` userdata compares
by value. If it doesn't, the comparison is always false, and wind-ups add duplicate lines.

What a professional would do: put shooting into the search (an action is move × fire direction, and the tear's
expected hit is part of the reward), or at least make the planner return everything the later rules need. Log, per
evaluation, how often each override fires, and alert when a rule fires 0% or 100% of the time.

### 4.4 No forward model, and everything runs in real time

Every evaluation (bench, gauntlet, A/B, tuner, overnight) runs at 1× speed on one game instance. Commands are
written to `runs/send.txt` and the tools wait with `sleep(1.2)` (`tools/gauntlet.py`, `tools/rooms.py:85-88`).
A bench round is 20-90 s plus setup, so one night gives a few hundred rounds, and the noise in 4.1 needs hundreds
of rounds per comparison. That is the throughput wall.

It also caps the planner. The enemy predictions are open-loop, per-type statistics (`Mover.predict`,
`mover.lua:87-130`): a circle that contains the enemy 95% of the time, regardless of its animation or attack state
(apart from a fast-dash special case and a 1.3× growth during "hurtful" animations). For a boss, one type-level
circle blurs every attack into one large uncertain blob. That is why the bot sees danger everywhere against bosses
and flies, and why corner and crowd terms had to be added. The data to do better (animations, tells) is already
collected, but the model doesn't use it.

What a professional would do: log full traces (every update: all entities with position, velocity, animation and
frame, and the bot's inputs). Then evaluate predictors offline at thousands of times real speed. Measure
calibration: does the "95%" circle really contain the enemy 95% of the time, per type and per animation? Condition
the reach model on (type, animation), which `tells.lua` already tracks. Use the traces as a "ghost replay"
simulator to tune the dodging core without the game. Separately, find out whether the game can run faster than
real time or as several instances (section 7).

### 4.5 Technical debt from the 24-hour pace

- **Two movement cores.** The old core (`reflex.lua:974-1250`, about 280 lines) stays as a silent per-update fallback
  when v2 errors (`reflex.lua:1699-1719`). So the bot can switch between two differently tuned brains mid-fight, and
  results don't say how often that happened (HIT_REVIEW.md noticed a frozen `why` line and could not tell which core
  was driving).
- **`pcall` around nearly everything** (`main.lua:542-694`, `reflex.lua:1396-1468`). A broken module degrades quietly
  instead of failing a test run. Errors are sent once per distinct message, which is useful live, but no evaluation
  counts or fails on them.
- **Shared mutable globals:** `IsaacBotRisk`, `IsaacBotStrategy`, `IsaacBotNavAim`, `IsaacBotSolidSeen`,
  `IsaacBotRedFire`, `IsaacBotTrollPickup`. Module-level state in `mover.lua` (`model`, `hist`, `Mover.lastDir`) is
  read inside the cost function (the turning cost). The design is hard to test in isolation and hard to reason
  about across a `luamod` reload.
- **`Reflex.update` is about 480 lines** (`reflex.lua:1389-1874`) mixing sensing, tells, risk, targeting, planning,
  aiming, shot classification and status. `nav.lua` is 1,080 lines.
- **Silent `except: pass`** in the helper's knowledge senders (`brain/helper.py:312-313, 329-330, 365-366`). A
  malformed knowledge file just stops being sent.
- **Diary-style comments** (dates, quotes, incident stories) next to every rule. They preserve the "why", which is
  good, but they bury the logic. That history belongs in commit messages or a decision log.

### 4.6 Tests that test the mock, not the game

The offline harness is good for navigation, but it says little about fighting:
- `Mock.step` moves Isaac at a fixed 4.6 px/update with instant acceleration (`test/mock.lua:452-470`). The bot itself
  found that the real figure is ~7.7 px/update with acceleration. The mock models the old, wrong belief.
- Enemies in the mock either chase in a straight line or orbit (`mock.lua:471-482`). None of them telegraphs, hops,
  dashes, lobs or bounces.
- `test/mutants.lua:11-13` admits that the dodge, corner and Host-bait tests still pass with their fixes removed.
  `FOUND_BUGS.md` says of the corner observation: "It may just be the fake."
- No test covers the shooting overrides, so the `standCost` bug in 4.3 passes every check.

What a professional would do: keep the mock for logic. Promote movement tests to replays of recorded real
trajectories (from the traces in 4.4) and measure the result as a rate over many seeds, not one pass/fail.

### 4.7 Knowledge of unknown accuracy used as hard behaviour

`knowledge/boss_tactics.json` (2,047 lines) and `enemy_playbook.json` (15,736 lines) were largely written by AI
sessions from wiki pages, guides and videos (`docs/HOW_WE_WORK.md` section 6, `brain/helper.py:333-336`). Their
contents drive behaviour directly. Animation names become tells and attack windows (`reflex.lua:1407-1422`). Tags
like `chases` or `dashes_at_isaac` change how predictions home in (`mover.lua:567-573`). "Stay diagonal" and "never
in its row" become always-on costs (`mover.lua:661-666`). Draft entries are rightly held back
(`helper.py:303-306`), but nothing checks the "reviewed" entries against the game, for example that every animation
name in the tactics file exists in that boss's animation set and leads into the claimed attack. The model exam
(`knowledge/exam.json`, 28 questions) is too small, and was produced by the same process it is meant to check.

What a professional would do: check knowledge automatically against game data (the bestiary tools are a start).
Measure each entry's effect, playbook on versus off for that enemy, on the suite. Treat knowledge as a prior that
learning can override, not as a rule.

### 4.8 Process: shipping faster than you can measure

Commits land every 5-20 minutes, and each often bundles 3-5 behaviour changes (see `git log`, 1.2.7-1.2.26). The
"improvement loop" in `docs/HOW_WE_WORK.md` section 3 has "measure" as step 6, but in practice measurement neither
gates a change nor is attributed to one. "Fix the category, not the room" is a good principle, but in the code it
mostly shows up as a new term, knob or special case per watched incident (corner rule, pincer rule, burrow rule,
no-lane rule, ring-kite...). This is overfitting to whatever the author happened to watch, and to the four
Basement bosses the gauntlet uses. The roadmap also spends effort on side features, Linux support and LLM exams
while the core still dies on floor 1-2 in most runs. (Since this review, the side features have been dropped from
the plan.) About 150 runs are recorded in
`runs/runs.jsonl`. Every one ended in death, one reached floor 4 and one floor 3 (test deaths are mixed in,
because tagging is broken).

### 4.9 Smaller risks the author may not see

- **The bot under test is not the code under test.** Learned files (`motion.dat`, `tells.dat`, `respect.dat`,
  `lessons.json`, `tuned.json`) persist across code versions and keep changing during tests. Two runs of the same
  commit are different bots. The "respect" feedback loop in PLAN.md (every boss maxed out at 3× berth) is the kind of
  runaway this causes. Others like it would be invisible without frozen-state evaluation.
- **Latency and replanning.** v2 plans every 2nd update and repeats the last move in between (`reflex.lua:1682-1684`,
  `m_every = 2`). Inputs take effect on the next input poll. Against 1-3 frame telegraphs late in the game, 2-3 updates
  of lag matter. It is fine for Basement, but worth measuring before it is blamed on the cost function.
- **Hard-coded system-drive check** in `tools/overnight.py:71`, against the repo's own "no hard-coded paths" rule.
- **Bench reset.** `newrun` sometimes walked into a treasure room before the bench started (HIT_REVIEW.md tooling #4).
  Every bench row should assert "0 items" from the `power` line, or be discarded.

---

## 5. If I were taking over tomorrow: first 10 actions, in order

1. **Stamp every result.** Add git hash, settings hash, learned-state hash, item count and core-in-use to every hit,
   room, bench, gauntlet and run row. Fix test tagging. *Why:* without this, no past or future number means anything.
2. **Freeze learning during evaluation.** Add a read-only mode for motion, tells, respect and watcher lessons, loaded
   from a named snapshot. *Why:* otherwise A/B results are biased and two runs of the same build differ.
3. **Build the fixed evaluation suite and measure the noise.** About 40 rooms sampled from all real rooms seen
   (stratified by floor and room type), plus the failure set kept separately, plus the 4 Basement bosses, each with
   fixed seeds. Run an A/A test (the same build twice, about 5 tries per room) to get the minimum detectable effect.
   *Why:* this tells you what "better" can even mean at your sample size.
4. **Replace `ab_test.py` with interleaved, paired, sequential testing.** ABAB on identical room and seed, a paired
   difference in a fixed composite score (damage + time + timeout penalty, deaths uncensored), a confidence interval,
   and an SPRT stop rule. *Why:* 4 rounds per arm in sequence accepts noise and favours B.
5. **Fix the `standCost` bug, delete the old core and the dead knobs.** Make `Mover.choose` return the stand cost.
   Keep a knob registry of which code reads each setting, and make `set|` fail loudly on dead keys. Point `tune.py`
   only at live knobs. *Why:* the running bot is currently not the one the tuning and A/B history describe.
6. **Make errors fatal in evaluation.** Count every `pcall` failure and every v2→v1 fallback per run, and fail the
   evaluation if any occur. *Why:* silent degradation corrupts measurements.
7. **Log full traces.** Every update: entities (type, variant, position, velocity, animation, frame), projectiles,
   Isaac's state and inputs. *Why:* this is the dataset that turns real-time debugging into offline engineering.
8. **Evaluate and rebuild prediction offline.** Measure circle calibration per (type, animation) and condition the
   reach model on animation. Replay recorded enemy trajectories against the planner as a ghost simulator to tune
   dodging at thousands of times real speed. *Why:* prediction quality is the ceiling on dodging, and it can be
   improved without the game running.
9. **Collapse the cost function into expected damage + time.** Express danger as a hit probability, price it with
   the risk layer, then ablate every comfort term on the suite and keep only those that pay. Tune what remains with
   CMA-ES against the suite, with rooms held out. *Why:* this ends the weight soup and makes the risk layer exact
   instead of 16 multipliers.
10. **Set a ladder metric and a baseline.** For example: no-damage rate on floors 1-2, Mom kill rate, and floor
    reached, over 100+ seeded item-free runs. Record the author playing the same seeds as a human baseline. Only
    then go back to features (deals, items, bosses), each judged by the ladder. *Why:* "best" needs a number, and a
    human baseline keeps it honest.

---

## 6. Is "best Isaac bot anyone has made" realistic with this approach?

**Against public prior art, probably yes, and soon.** Publicly visible Isaac bots seem to be narrow: a reinforcement
learning (PPO) agent for the Monstro fight on the SerpentAI framework, simple neural networks on a browser remake,
and a few Lua agent experiments. I found no public bot that plays whole Repentance+ runs with navigation, item
logic and boss handling. A bot that reaches floor 4 by itself may already be near the top of what is publicly
documented. I cannot rule out private or unpublicised work. But that bar is low, and it is the wrong one to aim at.

**The meaningful bar** is a bot that regularly beats Mom and It Lives with arbitrary items and characters, and
handles late-game bullet hell. For this approach to get there, these things would have to be true:
- evaluation throughput of thousands of room-fights per day, through faster-than-real-time play, parallel
  instances, or a trace-driven simulator good enough for dodging;
- a statistically sound improvement loop, so changes accumulate instead of random-walking;
- enemy prediction conditioned on attack state, calibrated offline, so that the planner's danger is real;
- a cost function in real units, with weights tuned by optimisation rather than by watching;
- general handling of weapon types (Brimstone, Mom's Knife, Tech, homing, flight, charge shots) through an
  abstract "how my attack hits" model rather than one rule per item.

**The biggest single obstacle is evaluation throughput combined with noise.** The game runs in real time, on one
instance, with outcomes that vary hugely from round to round. You cannot improve something faster than you can
measure it, and right now one honest comparison costs an evening. Everything else (cost design, prediction, item
generality) is ordinary engineering once that is solved.

**As a repeatable method for other games:** the documented loop (watch, diagnose with logs and frames, fix the
category, test, reload safely, measure) is a good skeleton, and `docs/HOW_WE_WORK.md` explains it well. What it
lacks is the backbone that makes it transferable: versioned, frozen-state, statistically tested evaluation, and
trace logging with offline replay. Add those two and the method generalises. Without them, every game will end up
where this one is: a growing pile of rules whose net effect nobody knows.

---

## 7. Questions I could not answer from the repo

1. Can the game run faster than real time (a speed mod, a REPENTOGON hook, a debug command), or as several
   instances or VMs at once? This decides the whole strategy.
2. How often does v2 throw and fall back to the old core in real play? Neither the logs nor the results record it.
3. What is the distribution of update times? The perf line gives averages and maxima, but how many updates go over
   16 ms in big rooms with many enemies?
4. Does the game's `Vector` compare by value with `==` (`mover.lua:671`), as the mock's does?
5. How much of the recorded real-play damage happened with items held, and how much under each code version? The
   data can't currently say.
6. Are the animation names in `boss_tactics.json` (tells and attack windows) checked against the game's own
   animation data for each boss, and how many failed that check?
7. Is there any recording of skilled human play on fixed seeds to compare against, or to learn from?
8. What exactly counts as "best": a metric (Mom kill rate? win streaks? no-hit floors?), on which characters, items
   and seeds?
9. Does a `luamod` reload restore learned state and module-level state (`Mover.lastDir`, `hist`, risk base values)
   consistently? Can a reload in the middle of a bench round change its result?
10. Were any of the PLAN.md A/B "kept" decisions repeated after the v2 rebuild, or are they all old-core evidence?
