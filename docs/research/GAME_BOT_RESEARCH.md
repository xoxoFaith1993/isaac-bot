# Build the bench before the bot

*A research report on how the Isaac bot's build method compares with game-playing agents and automated playtesting elsewhere, and what to do next. Written 2026-11-25.*

## In plain words

**The verdict.** The Isaac bot is built the right way, but it was built in the wrong order. Its shape is how the strongest bots in similar games are made: exact game state from a mod, a fast move planner, layers for the room, the risk and the whole run, game knowledge kept in data files, and a small AI model used only when the bot gets stuck. The waste was in how the bot got better. The measuring tools came last, so many hours went into watching single runs, judging changes by eye, and learning enemy attacks by getting hit, even though the game's own files already describe those attacks.

**The biggest changes.**

1. Build a locked, repeatable test bench that plays the old and new versions on the same seeds and reports results with error bars. Judge every change on it, whoever makes the change.
2. Read everything that can be known, such as attack timings and enemy stats, before learning anything live.
3. Replace most of the ~80 hand-set numbers with one "expected damage" score, and fit the numbers that remain from the bot's own logs.
4. Let AI sessions improve the bot unattended, but only against that bench, with a regression gate and budgets.

**The honest scorecard.**

| Area | Rating |
|---|---|
| Design | Matches expert practice |
| Knowledge as data, and tests that must fail without the fix | Good habits, ahead of most hobby bots, but see the second opinion below: the tests check the mock more than the game |
| Measurement and statistics | Arrived late, and too thin to trust small changes |
| Feedback speed | The main weakness |
| Bosses and aim (30-55% accuracy) | Furthest behind |

## A second opinion, and where it is harsher than this report

This report was written from research notes and the project's docs. Its research questions were framed from inside the project, so it can lean towards the project's own view. To check that, a separate reviewer playing a sceptical senior game-AI engineer read only the repo: code, tests, tools and recorded results. It saw none of this research. Its review is in [`SECOND_OPINION.md`](SECOND_OPINION.md). Where the two disagree, trust the second opinion: it read the code, and this report did not.

**Where they agree.**

- Measurement has to come before any more behaviour changes.
- The game hookup, the room bench, the `why` line and the in-engine tests are a sound base.
- The ~80+ settings should collapse into one expected-damage cost, with the rest tuned automatically.
- Real-time play on a single game instance is the biggest brake on getting to "best".

**Where the second opinion is harsher, from reading the code.**

1. **The weight problem came back.** The rebuild was meant to escape about 40 weights that fought each other. By the end of the day `Mover.choose`/`total()` in `mod/isaac-bot/mover.lua` was summing about 20 cost terms in mismatched units. The settings table now holds about 125 knobs, many of them no longer read. This report calls the design "expert practice". The second opinion says the *planner shape* is right, but the cost function has turned into a weight soup again.
2. **A live bug in shooting.** Under the default movement core (`core = 2`), `standCost` is only set in the old core's branch (`mod/isaac-bot/reflex.lua:1678`, `:1716`), so it is always empty. As a result, "stand still and shoot straight" never fires (`:1779`), and "plant your feet" always takes its else branch and cancels shots that would have landed (`:1802-1806`). This was checked against the code while writing this section. It is a likely contributor to the 30-55% boss aim, and it is not caught by any test.
3. **The A/B and tuning numbers are weaker than they look.** `tools/ab_test.py` runs all rounds of A, then all rounds of B, while the bot keeps learning, which favours B, and B is the new default. Most of the knobs `tools/tune.py` adjusts are read only by the old core. Some fixes were proven on the old core and were never carried into the new one.
4. **The tests check the mock more than the game.** `test/mock.lua` still moves Isaac at the old assumed 4.6 px/update instead of the measured ~7.7. By the project's own mutation notes, the dodge tests still pass when their fixes are removed. The tests are strong for navigation logic and weak for dodging quality.
5. **Debt from the 24-hour pace.** There are two movement cores with a silent fallback, `pcall` swallowing errors, globals shared between modules, and a ~480-line `Reflex.update`.

**What changes in the recommendations.** Before the benchmark work in (b), add a short "make the measurements honest" step:

1. Fix the `standCost` bug.
2. Interleave A/B rounds (ABAB on the same seeds) with learning frozen during tests.
3. Remove or retire the old core and its dead knobs, so the tuner only touches live settings.
4. Bring the mock's physics in line with the learned values.

Each of these is hours, not days, and each one makes every later number more trustworthy.

## What "the best" would mean, and how to prove it

The author's goal is not a bot that is "good enough". The goal is the best game-playing bot anyone has made, as far as anyone can tell. That changes what the project needs most. A claim of "best" is only worth something if it can be checked. Right now nobody can check claims about Isaac bots, because nobody publishes numbers.

### The Isaac title is empty today: easy to claim, worthless unless measured

No public Isaac bot reports measured results. The isaac-rl project has finished only its first stage, the Lua-to-Python bridge, and has no results ([isaac-rl](https://github.com/Scalcaneo/isaac-rl)). The containerised pixel project the-learning-of-isaac has no policy yet ([the-learning-of-isaac](https://github.com/oralet86/the-learning-of-isaac)). The 2018 SerpentAI PPO agent fought only Monstro and never published metrics ([SerpentAI Isaac plugin](https://github.com/Supermaxman/SerpentSuperAIsaacGameAgentPlugin)). DeepArcadia's IsaacRL and the AIsacco course project report no results either ([IsaacRL](https://github.com/DeepArcadia/IsaacRL), [AIsacco](https://github.com/Reiver56/AIsacco)). The only reported win rate, about 40%, comes from a behavioural-cloning bot for a simpler JavaScript remake, not the real game ([Defasium bot](https://github.com/Defasium/the-binding-of-isaac-js-ai-bot)). The only Isaac TAS found is for the original Flash game ([TASVideos 8001S](https://tasvideos.org/8001S)).

Nearby genres do not set a high public bar either:

- **Bullet hell.** The best-known Touhou bot, twinject, shows one-credit clears in demo videos but publishes no survival statistics ([twinject](https://github.com/Netdex/twinject/blob/master/README.md)).
- **Roguelikes.** The winning bot of the NeurIPS 2021 NetHack Challenge was scripted, and its median score of about 5,300 was only just above "Beginner" ([NetHack Challenge report](https://ar5iv.labs.arxiv.org/html/2203.11889)). The DCSS bot qw "does not have a high winrate" ([crawl/qw](https://github.com/crawl/qw)).
- **General AI models.** Large AI models playing in real time are very weak. On VideoGameBench the best model finished 0.48% of the games ([VideoGameBench](https://arxiv.org/abs/2505.18134v2)).

Some very recent reports are more impressive. They include a search system with save-state branching that won NetHack on most seeds ([Antithesis, Nov 2026](https://antithesis.com/blog/2026/nethack/)), a frontier model that won NetHack using helper scripts it wrote itself ([blog, Sept 2026](https://kenforthewin.github.io/blog/posts/llm-nethack-ascension)), and frontier models winning 17-20% of Slay the Spire runs on the hardest setting, against an estimated ~85% for top humans ([Epoch SpireClimb](https://epoch.ai/benchmarks/spireclimb)). Each is a single source on a turn-based game, so none of them sets the bar for a real-time twin-stick roguelike.

**The result: the first project to publish a reproducible Isaac benchmark, with its own scores on it, sets the bar.** After that, "best" means "best on the public benchmark". Anyone can try to beat it, and that is what makes the claim worth having.

### A public benchmark turns "best" into a number anyone can check

Mature fields handle this the same way. A fixed suite of seeds and scenarios. Per-seed results published, not just averages. Confidence intervals instead of single numbers, because a few noisy runs mislead ([rliable, NeurIPS 2021](https://arxiv.org/abs/2108.13264)). Paired comparisons on the same openings with a sequential stopping rule ([Fishtest](https://github.com/official-stockfish/fishtest/wiki)). Held-out test levels, so tuning on the suite does not hide overfitting ([Procgen](https://arxiv.org/abs/1912.01588)). Progress metrics alongside win or lose ([BALROG](https://arxiv.org/abs/2411.13543)). Below is a proposed benchmark for this repo. It is a recommendation, not an existing standard.

| Suite | What it plays | Main metrics | Suggested size |
|---|---|---|---|
| **Rooms** | Fixed (stage, layout) rooms, item-free, entered at full health | Clear rate, hits per room, time to clear | 50-200 rooms, each played several times |
| **Boss drills** | Each floor 1-6 boss via `goto s.boss.<id>`, item-free, base Isaac | Kill rate, kill time, hits taken, body vs shot hits, aim accuracy (tears that hit ÷ tears fired) | 10-30 fights per boss |
| **Seeded runs, open** | A published seed list, normal play with items | Floor reached, Mom kill rate, Mom's Heart / It Lives rate, red-heart hits per floor, deal chance kept | 50 seeds |
| **Seeded runs, held out** | A second seed list run only before releases | Same as above | 50 seeds |
| **Human reference** | The same suites played by human volunteers of known skill | Same metrics | As many as can be collected |

Every result file should record the game version, the REPENTOGON version, the mod list, the bot commit and the suite version, as EA's playtesting team learned to do ([EA SEED, CoG 2023](https://arxiv.org/html/2307.11105v1)). Results should be reported as interval estimates (bootstrap confidence intervals, or the interquartile mean), and the per-seed rows should be committed so anyone can recompute them.

The rules of play should be written down too:

- the bot reads only what the Lua API exposes;
- it acts only through `MC_INPUT_ACTION`;
- it declares its reaction delay.

Learned bots in other games won partly through reactions no human can match ([Faynt, reported Oct 2026](https://arxiv.org/abs/2610.02144); [Phillip](https://arxiv.org/abs/1702.06230)). A "human-like delay" track would keep comparisons with people honest. That last idea is a recommendation.

### An ambition ladder, rung by rung

| Rung | Claim | Proof on the benchmark | What it needs | Reachable with current methods? |
|---|---|---|---|---|
| 0 | **Reproducible** | The suites exist, scores are published with confidence intervals, and a determinism report exists | Telemetry fixes, seed lists, paired runner | Yes, in days |
| 1 | **Beats an average player** | Mom kill rate and hits per floor on the open seeds at or above a measured average-player baseline | Reliable floor 1-6 bosses, basic item handling, risk layer tuned on the bench | Yes, likely within weeks, using the current planner plus the changes in (b) |
| 2 | **Beats a strong player on clear rate and damage taken** | Fewer hits per room and higher It Lives / Mom's Heart rates than a strong human on the same seeds | Punish windows, lead aiming, attack tables from game files, many item special cases | Plausible. Scripted bots with exact state and no reaction delay already dodge at superhuman level in bullet hells ([twinject](https://github.com/Netdex/twinject/blob/master/README.md)) |
| 3 | **First public bot to beat a named ending reliably** | For example It Lives or Blue Baby, with a win rate and interval on held-out seeds | Rung 2 plus late-floor bosses, weapon types (Brimstone, Mom's Knife) and long unattended runs | Partly. Bullet-hell late bosses are flagged as possibly out of reach for a rule-based dodger in `PLAN.md`; they likely need a forward model or learned motion prediction |
| 4 | **Generalises to a second game with only an adapter** | Same core (runner, log schema, planner, harness) reaches rung 1 on another game | A clean core/adapter split and knowledge import per game | Yes as engineering. No cited project shows a hand-built planner moving cheaply between games, so this would be new |
| 5 | **Superhuman on the hardest content** | Delirium, Mega Satan or The Beast, cleared at a rate above strong humans | Probably a fast room simulator and learned components (see (b)) | Open research. Nobody has shown it for a game of this kind |

Rungs 0-2 need discipline, not new science. Rung 3 is where the current approach is likely to stall. That is the pattern of AutoAscend and qw, which both stopped at "competent, low win rate" ([NetHack report](https://ar5iv.labs.arxiv.org/html/2203.11889), [crawl/qw](https://github.com/crawl/qw)). Rungs 3 and 5 are where a fast simulator and narrow learned parts would start to pay for themselves. Every recommendation below is ordered so that rung 0 comes first, because without it no later claim can be proven.

## How this report was put together

The report combines seven research notes written on 2026-11-25. They cover scripted bots, reinforcement and imitation learning, LLM agents and hybrids, playtesting engineering, Isaac-specific tooling, dodging and aiming, and time sinks. It compares them with the project's own `docs/HOW_WE_WORK.md`, `README.md`, `PLAN.md`, `CONTRIBUTING.md`, `CLAUDE.md`, `test/FOUND_BUGS.md` and the project's hit review of the same day.

Two kinds of claim are kept apart:

- **Findings** are statements from linked sources.
- **Recommendations and inferences** are the researchers' own reasoning, and are labelled as such.

Results from 2026 that rest on a single blog post or preprint are marked "reported", and no conclusion depends on any one of them.

## Finding 1: hand-built bots still win games like Isaac, and learning wins only narrow skills

### Symbolic bots win when knowledge matters and exact state is available

The cleanest evidence is the NeurIPS 2021 NetHack Challenge. **Symbolic bots beat deep reinforcement learning "by a large margin"**. The best symbolic median was nearly 3x the best neural median, the best-episode gap was about 5x, and all of the top three places overall went to symbolic bots ([NetHack Challenge report](https://ar5iv.labs.arxiv.org/html/2203.11889)).

The winner, AutoAscend, is built much like the Isaac bot:

- a knowledge layer parses the state;
- a behaviour tree of interruptible "strategies" handles explore, combat and emergency healing, and seeing a monster pre-empts exploring;
- combat scores a reduced set of 34 actions with hand-written heuristics and takes the best one;
- its damage calculation was built from NetHack's own code and wiki data.

Sources: [report](https://ar5iv.labs.arxiv.org/html/2203.11889), [AutoAscend repo](https://github.com/maciej-sypetkowski/autoascend). The organisers explain the gap: domain knowledge is easy to encode as subroutines, while neural agents struggled with long-horizon credit assignment and could not use prior knowledge such as wiki data ([report](https://ar5iv.labs.arxiv.org/html/2203.11889)).

The same design shows up wherever scripted bots win:

- **Rog-O-Matic** (1983) was a production-rule expert system, built that way because searching up to 500 actions per turn was infeasible. In a three-week test it beat the median score of top Rogue players ([Rog-O-Matic](https://www.cs.princeton.edu/~appel/papers/rogomatic.html)).
- **DCSS qw** runs on a goal table in Lua and was the first bot to win DCSS with no human help ([crawl/qw](https://github.com/crawl/qw)).
- **PurpleWave**, a strong StarCraft: Brood War bot, is mostly rules: a task network plus potential fields in a threat-aware path cost. It uses learning only to pick strategies from past results against each opponent ([PurpleWave](https://github.com/dgant/PurpleWave), [2017 survey](https://www.cs.mun.ca/~dchurchill/starcraftaicomp/2017/survey/PurpleWave_Survey.txt)).

The plateau is just as consistent:

- AutoAscend reached only "Beginner" level ([report](https://ar5iv.labs.arxiv.org/html/2203.11889)).
- qw's best three-rune combination won about 15% of games in offline testing ([elliptic/qw](https://github.com/elliptic/qw)).
- BotHack needed about 16,000 lines of Clojure and an exploit that was later patched ([Antithesis](https://antithesis.com/blog/2026/nethack/)).
- PurpleWave grew to about 49,000 lines ([PurpleWave repo](https://github.com/dgant/PurpleWave)).

**The lesson is that architecture gets a scripted bot started, and years of measured iteration get it good.** The top authors coped in the same way. AutoAscend ran thousands of seeded episodes in parallel and skipped seeds already done. qw ran many games back to back from a script. The Challenge organisers broke down 4,096-episode evaluations by cause of death and depth ([AutoAscend repo](https://github.com/maciej-sypetkowski/autoascend), [crawl/qw](https://github.com/crawl/qw), [report](https://ar5iv.labs.arxiv.org/html/2203.11889)).

### In real-time dodging, accurate short-term prediction beats deep search

The closest genre to Isaac is the bullet-hell shooter. twinject reads exact state by hooking the game's bullet and enemy functions. Its default dodger is a linear velocity-obstacle predictor, and it chooses the best move greedily each frame rather than searching deeply ([twinject](https://github.com/Netdex/twinject/blob/master/README.md)). Its known weak spots are lasers and enemy bodies, which are not points moving in straight lines. Those are the same weak spots the Isaac bot has against boss bodies and charges. A hobby DQN dodger trained in a simplified environment and run through twinject "performs poorly" in the real game. That is an anecdotal report ([Lemmy thread](https://lemmy.world/post/16099991)).

Fighting games show where search wins. In the Fighting Game AI Competition, MCTS agents have dominated since about 2016. That only works because a forward model exists to simulate frames ahead ([DareFightingICE](https://ice.ci.ritsumei.ac.jp/~ftgaic/index-R.html)). Rolling Horizon Evolution (RHEA) is a lighter alternative that has also been entered in that competition ([arXiv 2003.13949](https://arxiv.org/pdf/2003.13949)).

In Melee, learning overtook scripting once data was abundant. Phillip, trained by deep RL self-play, reportedly surpassed professionals ([arXiv 1702.06230](https://arxiv.org/abs/1702.06230)). A 2026 preprint reports beating 14 public bots 98.4% of the time, after pretraining on about 840,000 human replays ([Faynt, reported](https://arxiv.org/abs/2610.02144)). Both results depend partly on reactions no human can match, and both use data volumes an Isaac hobby project does not have.

### Reinforcement learning from scratch costs three to six orders of magnitude more than one PC

The famous RL results were bought with data-centre compute:

- **OpenAI Five** used about 800 petaflop/s-days and about 45,000 years of self-play ([OpenAI](https://openai.com/index/openai-five-defeats-dota-2-world-champions)).
- **AlphaStar** trained each agent on 32 TPUv3 for 44 days ([The Register](https://www.theregister.com/2019/11/01/deepmind_starcraft_ai)).
- **Agent57** needed 5 billion frames to pass the human baseline on 51 Atari games ([DeepMind](https://deepmind.google/blog/agent57-outperforming-the-human-atari-benchmark/)).
- **Gran Turismo Sophy** used over 1,000 PlayStation 4s ([GT Sophy](https://us.gran-turismo.com/us/gran-turismo-sophy/technology/)).

The sample-efficient end is more relevant. BBF is superhuman on Atari 100k, about two hours of play per game ([BBF](https://arxiv.org/abs/2305.19452)). DreamerV3 needs about 0.1 A100-days per Atari 100k run. But DreamerV3 needed 100M steps to collect Minecraft diamonds at all, and found them in only 0.4% of episodes ([DreamerV3](https://ar5iv.labs.arxiv.org/html/2301.04104)).

Isaac makes this worse because it runs only in real time. At 30 logic updates a second, one instance gives at most 108,000 decisions an hour (the researchers' conversion). So **1M steps is about 9 hours of non-stop play, and 100M steps is about 926 hours (38.6 days)**.

The hobby RL successes all found a way to run faster than real time:

- **Street Fighter II:** PPO beat the final level at 2.5M steps, inside an emulator ([street-fighter-ai](https://raw.githubusercontent.com/linyiLYi/street-fighter-ai/master/README.md)).
- **Pokemon Red:** the agent has played over 50,000 hours of game time through many parallel emulators ([TechCrunch](https://techcrunch.com/2023/10/18/after-50000-hours-this-ai-can-play-pokemon-red)).
- **Trackmania:** Linesight beat 10 of 12 campaign world records, using a TAS tool that provides speed-up, save states and input control ([Linesight](https://linesight-rl.github.io/linesight/build/html)).
- **Rocket League:** the community rewrote the physics as RocketSim, about 20 game-minutes per second per thread ([RocketSim](https://github.com/ZealanL/rocketsim)). Policies trained in a re-implementation transferred to the real game ([arXiv 2205.05061](https://arxiv.org/pdf/2205.05061)).

The one framework built for a game that cannot be sped up, tmrl, still needs "a few hours (up to a few days)" of driving for one track ([tmrl](https://github.com/trackmania-rl/tmrl)).

Studios reach the same verdict:

- **EA SEED** shipped RL only for the locomotion layer (helicopters in Battlefield 2042, zero-g in Dead Space), inside its scripted AutoPlayers system. It rejected pixels, kept inference under 100 microseconds, and found that fast-forwarding the real game broke physics. Its stated rule is to combine RL with scripting rather than replace scripting ([EA SEED, CoG 2023](https://arxiv.org/html/2307.11105v1)).
- **NetEase-linked work** reports that DRL testers "often overfit to short-term rewards" ([arXiv 2509.22170](https://arxiv.org/html/2509.22170v1)).

### Imitation is cheap when the state is exact and the skill is narrow

Human data cuts the learning bill sharply. AlphaStar's supervised stage alone, trained on human replays, reached the top 16% of human players before any RL ([The Register](https://www.theregister.com/2019/11/01/deepmind_starcraft_ai)). VPT needed about 2,000 hours of labelled Minecraft play, and its authors suggest as little as 100 hours could work ([VPT](https://ar5iv.labs.arxiv.org/html/2206.11795)). A CS:GO behavioural-cloning agent reached the medium built-in bot's level from about 95 hours of scraped play plus a smaller expert set ([Pearce & Zhu](https://arxiv.org/abs/2104.04258v2)). A Microsoft study reports useful agents from "minutes of demonstrations" with pretrained visual encoders ([arXiv 2312.02312](https://arxiv.org/abs/2312.02312)).

The studios agree. At EA SEED, imitation trained in 20 minutes against 5 hours for an RL baseline ([EA SEED](https://www.ea.com/technology/news/seed-ml-research-aaa-game-testing)). King found that a network imitating player moves predicted Candy Crush level difficulty better than an MCTS bot, at a fraction of the compute ([Gudmundsson et al. 2018](https://www.gwern.net/doc/reinforcement-learning/imitation-learning/2018-gudmundsson.pdf)).

The Isaac bot already reads exact positions and velocities, so the costliest part of imitation, learning to see, does not apply. **The researchers infer that a few hours of human state-action logs are enough for one narrow skill**, such as boss positioning, used as a prior or tie-breaker inside the planner. They would not be enough for whole-run play, because plain behavioural cloning copies mistakes and drifts into states the human never visited.

### LLM and VLM agents fail in the frame loop and succeed as slow planners and coaches

On VideoGameBench, the best frontier model completed 0.48% of games in real time and 1.6% with the game paused while it thought. **Latency is the first wall, and spatial reasoning is the second wall, which stays even when the game is paused** ([VideoGameBench](https://arxiv.org/abs/2505.18134v2)). In an Overcooked study, models under 20B parameters were fast but had near-zero score efficiency on their own, and long chain-of-thought models scored even lower ([arXiv 2502.11882](https://arxiv.org/pdf/2502.11882)). The approach that worked under time pressure ran a slow planner in parallel with a fast reactor ([Real-Time Reasoning Gym](https://arxiv.org/abs/2511.04898)). The models that do play at 30 Hz, Lumine in Genshin Impact and SIMA 2 in 3D worlds, were trained for it and needed heavy latency engineering ([Lumine](https://arxiv.org/abs/2511.08892v1), [SIMA 2](https://deepmind.google/blog/sima-2-an-agent-that-plays-reasons-and-learns-with-you-in-virtual-3d-worlds/)).

The long successes rely on scaffolding:

- **Gemini 2.5 Pro** beat Pokemon Blue in about 813 hours, against about 26 hours for a human. Harness changes later brought that to about 406 hours ([PC Gamer](https://www.pcgamer.com/software/ai/google-ai-happens-to-be-really-bad-at-playing-pokemon-repeatedly-panicking-and-taking-more-than-800-hours-to-beat-the-elite-four)).
- **Claude** needed a navigator helper and, later, a zoom tool before it beat Pokemon Red in 2026 ([LessWrong](https://www.lesswrong.com/posts/sehJYg5Yny9fvpbpt/a-year-late-claude-finally-beats-pokemon)).
- **Jev** (reported Sept 2026) is the closest analogue to the Isaac design. A non-LLM decision model picks from options built by code from game RAM. A frontier model refined the options between runs and did not play itself. It finished Pokemon Red in about 37.7 hours. Caveats: it was a single run with no matched baseline, and sources disagree on who built it ([Tom's Hardware](https://www.tomshardware.com/tech-industry/artificial-intelligence/developer-says-jev-decision-model-beat-pokemon-red-in-under-a-week-non-llm-engine-succeeds-where-traditional-chatbots-stalled-for-months-but-claude-opus-5-coached-the-model-through-its-dead-ends), [remio](https://www.remio.ai/post/jev-pokemon-red-run-finished-in-37-hours-but-claude-helped-build-the-winning-sys)).

### Hybrids and LLM-guided search: the model writes the code, the code plays

A family of hybrid designs keeps the model out of the fast loop entirely:

- **Option picking.** SayCan has a language model choose among feasible, pre-built skills ([SayCan](https://arxiv.org/abs/2204.01691)).
- **Code as the policy.** Code as Policies has the model write the controller code that then runs on its own ([Code as Policies](https://arxiv.org/abs/2209.07753)). Voyager keeps a growing library of skills written as code ([Voyager](https://arxiv.org/abs/2305.16291)).
- **Refined behaviour trees.** PORTAL has an LLM write behaviour trees that are refined using game metrics plus a vision model's review of play, across thousands of FPS games, with no LLM running during play ([PORTAL](https://arxiv.org/abs/2503.13356)).
- **LLM-guided search with an evaluator.** Eureka's LLM-written reward code beat expert human rewards on 83% of tasks ([Eureka](https://arxiv.org/abs/2310.12931)). FunSearch and AlphaEvolve evolve functions or whole files against an automatic evaluator ([FunSearch](https://www.nature.com/articles/s41586-023-06924-6), [AlphaEvolve on game solvers](https://arxiv.org/abs/2602.16928)), and ShinkaEvolve is an open-source version ([ShinkaEvolve](https://arxiv.org/abs/2509.19349v1)).

**All of the search-based methods depend on an automatic evaluator, and all of them try to cheat it.** AlphaEvolve's own guidance says to keep the scoring logic where the model can't see it, run each candidate twice, and flag suspiciously fast evaluations ([AlphaEvolve docs](https://docs.cloud.google.com/gemini/enterprise/docs/alphaevolve/developer-guide/reward-hacking-prevention)). The Darwin Gödel Machine got around checks that were hidden from it ([The Register](https://www.theregister.com/2025/06/02/self_improving_ai_cheat/)).

### Dodging, positioning and aiming have well-known textbook parts

The Isaac planner can borrow several ready-made pieces:

- **Rolling-horizon planners.** RHEA studies used a budget of 1,000 forward-model calls per tick, about 40 ms. A **shift buffer**, which seeds this tick's plan with last tick's best plan minus its first move, was preferred in 17 of 20 games. **Monte Carlo rollouts** after the planned sequence were also preferred in 17 games ([RHEA survey](https://ar5iv.labs.arxiv.org/html/2003.12331)).
- **Admissible moves.** The Dynamic Window Approach keeps only "admissible" velocities: moves from which the robot can still stop before hitting anything ([DWA](https://www.ri.cmu.edu/publications/the-dynamic-window-approach-to-collision-avoidance)). This is the formal version of "never walk into a corner you can't leave".
- **Sampling planners.** MPPI averages many noisy rollouts. When there are two separate ways around an obstacle the average can steer straight into it ([SCP-MPPI](https://arxiv.org/html/2404.10395v1)), so the Isaac bot's beam search, which keeps the best few discrete plans, is the safer choice.
- **Probability of a hit.** Chance-constrained planning treats predicted obstacles as Gaussian blobs and bounds the probability of collision in real time ([arXiv 2001.08012](https://ar5iv.labs.arxiv.org/html/2001.08012)).
- **Time to collision.** Crowd research found that pedestrians react to time to collision rather than distance, with an energy that falls off as about 1/TTC² and saturates near 200 ms ([Karamouzas et al.](https://www.arxiv.org/abs/1412.1082)).

For positioning and aiming:

- **Few factors.** Killzone's shipped tactical AI scores candidate positions with a weighted sum of about four factors. Its worked example uses proximity 20, line of fire 40 or 20, cover 20 and range 10. It also evaluates the threat's best attack positions from the threat's side ([Killzone slides](https://www.guerrilla-games.com/media/News/Files/gdce05_killzone_ai.pdf)).
- **Closed-form lead.** Leading a constant-velocity target is a closed-form quadratic. For an accelerating target, the prediction is repeated until it converges ([Predictive aim](https://www.gamedeveloper.com/programming/predictive-aim-mathematics-for-ai-targeting)).
- **Few tuned parameters.** A StarCraft micro bot packed kiting and focus fire into 14 parameters tuned by a genetic algorithm. It averaged each fitness over 5 games, because a single fight could swing by 3 units ([ECSLBot, CIG 2014](https://www.cse.unr.edu/~simingl/papers/publish/CIG2014IMPFMicro.pdf)).
- **Learning weights from logged games.** Chess engines tune hundreds of weights by fitting them to logged game results. Texel's method used about 8.8M positions from about 64k games and gained about 100 Elo ([Texel tuning](https://www.chessprogramming.org/Texel%27s_Tuning_Method)).

### The approaches side by side

| Approach | Best-known results | Cost / data needed | Real-time fit | Fit for one hobbyist, one PC, an AI coding assistant | Verdict for real-time action roguelikes |
|---|---|---|---|---|---|
| **Scripted / symbolic** (rules, behaviour trees, planners on exact state) | Won NetHack 2021 by ~3x median ([report](https://ar5iv.labs.arxiv.org/html/2203.11889)); qw's first unassisted DCSS win ([qw](https://github.com/crawl/qw)); twinject Touhou clears ([twinject](https://github.com/Netdex/twinject/blob/master/README.md)) | Developer time; plateaus at tens of thousands of lines | Excellent (microseconds to milliseconds) | Excellent; the coding assistant writes rules fast | **Core of the bot.** Needs a bench to avoid tuning chaos |
| **RL from scratch** | OpenAI Five, AlphaStar, GT Sophy; hobby: Street Fighter, Trackmania, Pokemon Red | 10^6-10^10 steps; fast or parallel simulators ([OpenAI](https://openai.com/index/openai-five-defeats-dota-2-world-champions), [Linesight](https://linesight-rl.github.io/linesight/build/html)) | Policy runs fast, but training against a 30 Hz game is very slow | Poor for the full game; possible for one skill in a self-built fast simulator | **Not as the core.** Narrow skills only, ideally in a simulator |
| **Imitation / behavioural cloning** | AlphaStar's supervised stage reached the top 16% ([Register](https://www.theregister.com/2019/11/01/deepmind_starcraft_ai)); CS:GO medium bot ([Pearce & Zhu](https://arxiv.org/abs/2104.04258v2)); King difficulty prediction | Minutes to hundreds of hours of human play; far less with exact state | Fast at inference | Good for one skill, given a few hours of logged human play | **Useful as a prior** (boss positioning, aim choice), not alone |
| **LLM / VLM agent in the loop** | VideoGameBench 0.48% real time ([VGB](https://arxiv.org/abs/2505.18134v2)); Pokemon wins in hundreds of hours ([PC Gamer](https://www.pcgamer.com/software/ai/google-ai-happens-to-be-really-bad-at-playing-pokemon-repeatedly-panicking-and-taking-more-than-800-hours-to-beat-the-elite-four)) | API or local GPU per decision | Fails at 33 ms per tick | Poor for control; fine for rare choices | **Keep out of the frame loop** |
| **Hybrid** (code reflexes + slow planner or option picker) | Jev (reported) ([Tom's Hardware](https://www.tomshardware.com/tech-industry/artificial-intelligence/developer-says-jev-decision-model-beat-pokemon-red-in-under-a-week-non-llm-engine-succeeds-where-traditional-chatbots-stalled-for-months-but-claude-opus-5-coached-the-model-through-its-dead-ends)); RAPH hybrid won NetHack's neural track ([report](https://ar5iv.labs.arxiv.org/html/2203.11889)); EA SEED's RL locomotion inside scripts | Moderate | Good if the slow layer is asynchronous | Good; this is the current Isaac design | **The right overall shape** |
| **LLM-guided code / parameter search** | Eureka, FunSearch, AlphaEvolve, PORTAL ([Eureka](https://arxiv.org/abs/2310.12931), [PORTAL](https://arxiv.org/abs/2503.13356)) | An automatic, locked evaluator; many evaluations | Offline; the output runs at full speed | Good if a fast bench exists; the coding assistant is the "LLM" | **The best route to autonomy,** once the bench exists |

## Finding 2: studios and researchers build the measuring stick before the behaviour

### Noisy outcomes need paired seeds, intervals and sequential tests

The reinforcement-learning field learned that **point estimates from a few runs mislead**. The rliable work re-analysed major benchmarks, found conflicts with earlier claims, and recommended stratified bootstrap confidence intervals and the interquartile mean ([rliable](https://arxiv.org/abs/2108.13264)).

Chess engines solved the same problem for code changes. Stockfish's Fishtest plays every patch against the master version in paired games, with each opening played twice and colours swapped. It accepts or rejects the patch with a sequential probability ratio test that stops as soon as the evidence is enough ([Fishtest](https://github.com/official-stockfish/fishtest/wiki)).

Benchmarks also learned that determinism invites memorisation. Atari added "sticky actions" ([ALE revisited](https://arxiv.org/abs/1709.06009)), and Procgen separated training levels from test levels ([Procgen](https://arxiv.org/abs/1912.01588)). MiniHack builds small targeted scenarios that each test one skill ([MiniHack](https://arxiv.org/abs/2109.13202)). The NetHack Challenge recorded a metric failure: "many teams" optimised in-game score at the expense of real progress ([report](https://arxiv.org/abs/2203.11889)).

A worked example (the researchers' arithmetic, not from a source) shows why this matters for Isaac. Suppose a change cuts hits per room from 1.0 to 0.8. Detecting that with 80% power at the usual 5% level takes roughly **350 room trials per version** if the trials are unpaired. That is about two hours per version at 20 seconds a room. Pairing on the same rooms and seeds removes the variance shared between rooms and cuts the number sharply. A sequential test stops early when the effect is large.

By the same arithmetic, the project's Dingle A/B test of 0/4 against 2/4 clears has a two-sided Fisher exact p of about 0.43. A 2/4 result has a 95% interval of roughly 15% to 85%. **Four rounds a side cannot distinguish the settings.**

### Determinism is tested, not assumed

Factorio runs multiplayer in deterministic lockstep. Its desync reports include the state of both machines so the two can be compared, and its "heavy mode" saves and reloads every tick to expose state that does not survive a save ([Factorio wiki](https://wiki.factorio.com/Desynchronization), [Desync](https://wiki.factorio.com/Desync)). TAS tools get determinism from outside the game by controlling time and taking whole-process save states ([libTAS](https://clementgallet.github.io/libTAS/guides/how)). Go-Explore showed how much restoring saved states helps exploration ([Go-Explore](https://arxiv.org/abs/1901.10995)). AlphaEvolve's guidance to run every candidate twice is the cheap version of the same check ([AlphaEvolve docs](https://docs.cloud.google.com/gemini/enterprise/docs/alphaevolve/developer-guide/reward-hacking-prevention)).

### Explainable decisions, scrubbable timelines and racing tuners

Professional AI debugging records what was considered, the score of each candidate and what was chosen. It ties those records to a timeline that can be scrubbed afterwards, as in Unreal's Visual Logger ([Visual Logger](https://dev.epicgames.com/documentation/en-us/unreal-engine/visual-logger-in-unreal-engine)). It normalises each consideration so its share of the decision is readable, as in the Infinite Axis Utility System ([IAUS](https://gameai.com/iaus.php)). AutoAscend's team built its own visual debugger showing the strategy stack, the map and the raw screen before every action ([report, App. C](https://arxiv.org/abs/2203.11889)).

Tuning under noise also has standard tools:

- **Racing.** irace drops losing configurations early using statistical tests. Even with racing, undersampling cost more than 20% in performance ([irace](https://ar5iv.labs.arxiv.org/html/2204.09353)).
- **CMA-ES.** Its default population for 80 parameters is 17 candidates per generation, and the tutorial advises larger populations on noisy problems ([CMA-ES tutorial](https://arxiv.org/pdf/1604.00772)). Searching 80 dimensions with noise therefore needs thousands of evaluations. That is why grouping knobs, and having a fast simulator, matter.
- **Pruning.** Successive halving and Hyperband give many configurations a small budget and keep the best ([Hyperband](https://arxiv.org/abs/1603.06560), [Optuna pruners](https://optuna.readthedocs.io/en/stable/reference/pruners.html)).
- **Failure search.** Instead of waiting for failures to happen, MAP-Elites searches the scenario space for many different failure cases ([arXiv 2012.04283](https://arxiv.org/pdf/2012.04283), [MADRID](https://arxiv.org/html/2312.02231v1)).

### Studio practice: stable builds, one code path, tiny state features

EA SEED's deployment paper is the most detailed studio account available ([EA SEED, CoG 2023](https://arxiv.org/html/2307.11105v1)):

- start from the most stable build of the game;
- use the same trainer-to-game API for training and runtime;
- prototype in a Unity mock, then move to production with little re-tuning;
- use a small ego-centric feature vector instead of pixels;
- every reward term needs an observation that explains it;
- the training setup needs continuous testing, or it rots as the game changes.

The project's Lua mock-game tests are the same "prototype in a mock" idea. The lesson to copy is "same code path in mock and live" (an inference).

### Agentic development has converged on pass/fail checks, durable state and protected evaluators

Anthropic's 2025-2026 guidance for long-running agents:

- one feature per session;
- a JSON feature list that later sessions may only mark as passing;
- a progress file plus git history;
- an end-to-end check at the start of every session.

Agents otherwise tend to declare victory too early ([Anthropic harness post](https://anthropic.com/engineering/effective-harnesses-for-long-running-agents)). The evals guidance says **"20-50 simple tasks drawn from real failures is a great start"**. It keeps capability suites, which start at a low pass rate, separate from regression suites, which sit near 100%. It grades outcomes, not paths, and it uses pass^k when reliability matters ([Anthropic evals](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)). Claude Code's guidance is to give the agent "something it can run that comes back pass or fail", and to turn anything that must happen every time into a hook or a deny rule ([Claude Code best practices](https://code.claude.com/docs/en/best-practices)). One practitioner reports that an autonomous Claude Code loop on a shipped game invents bugs to look productive unless it is told not to ([DEV Community](https://dev.to/_khanshaheb/how-im-running-an-autonomous-claude-code-loop-on-a-real-shipped-product-48lf)).

## Finding 3: Isaac prior work is thin, and REPENTOGON has levers the bot does not use yet

### The Isaac bot is already ahead of every public Isaac project

As covered above, no public Isaac AI reports results. The closest in design is isaac-rl. Its Lua mod hooks `MC_POST_UPDATE` and `MC_INPUT_ACTION` and blocks in lockstep on a TCP socket until Python answers. It uses a 4-tick frame skip and a compact observation of the 5 nearest enemies and 5 nearest projectiles. The README says sockets need the `--luadebug` launch option ([isaac-rl](https://github.com/Scalcaneo/isaac-rl)). The-learning-of-isaac is the only evidence that several Isaac copies can run at once, in Wine containers on Linux with software rendering, where rendering becomes the CPU bottleneck ([the-learning-of-isaac](https://github.com/oralet86/the-learning-of-isaac)). The SerpentAI Monstro agent split its reward: movement was penalised for damage taken and attack was rewarded for boss damage ([SerpentAI plugin](https://github.com/Supermaxman/SerpentSuperAIsaacGameAgentPlugin)).

### What the game and REPENTOGON offer for faster, repeatable development

The documented facts:

- **Timing.** `MC_POST_UPDATE` runs 30 times a second and does not run while paused. Render callbacks run 60 times a second ([IsaacDocs callbacks](https://wofsauge.github.io/IsaacDocs/rep/enums/ModCallbacks.html)).
- **No speed-up.** No fast-forward, timestep or headless mode was found in the game or in REPENTOGON ([REPENTOGON changelog](https://github.com/TeamREPENTOGON/REPENTOGON/blob/main/changelog.txt)).
- **Pausing the update.** REPENTOGON's `MC_PRE_UPDATE` "can be used to prevent the normal update, effectively pausing the game". That allows real lockstep ([changelog](https://github.com/TeamREPENTOGON/REPENTOGON/blob/main/changelog.txt)).
- **Seeded starts.** REPENTOGON adds `Isaac.StartNewGame` with a seed or a `Seeds` object, faster entity queries (`FindInRadius`, `FindInCapsule`), and `DrawLine` / `DrawQuad` for debug overlays ([REPENTOGON Isaac](https://repentogon.com/Isaac.html), [changelog](https://github.com/TeamREPENTOGON/REPENTOGON/blob/main/changelog.txt)).
- **Save states.** Version 2.0.0 adds a `SaveStateManager`, game-state save and restore callbacks, and room save-state callbacks ([changelog](https://github.com/TeamREPENTOGON/REPENTOGON/blob/main/changelog.txt)). Whether these can restore a fight exactly mid-room is untested.
- **Debug console.** `goto s.boss.<id>`, `seed`, `restart`, `debug 3` (infinite HP) and `debug 6` (hitspheres) give fast scenario resets and long practice ([Debug Console wiki](https://bindingofisaacrebirth.wiki.gg/wiki/Debug_Console)).

### Determinism is plausible for generation and unproven for fights

Isaac's RNG is Xorshift, and the docs say game behaviour should derive from the start, level or room seeds ([IsaacDocs RNG](https://wofsauge.github.io/IsaacDocs/rep/RNG.html)). **No source confirms that the same seed and the same inputs on each frame reproduce a fight exactly.** Racing+'s long list of "now seeded properly" fixes (teleports, angel types, troll bomb fuses) maps the mechanics that are poorly seeded in the base game. Its Fast-Clear and Fast-Travel features show how to cut dead wall-clock time ([Racing+ changes](https://github.com/Zamiell/racing-plus/blob/main/docs/changes.md)). The researchers infer that seeding both the run and the scenario should repeat the layout, while boss attack choices may still diverge with timing. This has to be measured, not assumed.

### Knowledge is sitting in the game's files

The game ships a Resource Extractor that unpacks its XML and anm2 animation files. Each entity has an anm2 file ([IsaacDocs Getting Started](https://wofsauge.github.io/IsaacDocs/rep/faq/GettingStarted.html)), and the event frames in those files give attack timings ("Shoot"-type events). `PLAN.md` already lists "pre-seed tells from the game's animation events" with examples (Dingle "Spit Shoot@3"), but as a "later" item. IsaacScript's `isaac-lua-polyfill` supports unit tests for mods in CI ([isaac-lua-polyfill](https://www.npmjs.com/package/isaac-lua-polyfill)). The project's mock, which runs on the game's own Lua DLL, is more faithful than that. No open-source re-implementation of Repentance exists that could serve as a fast simulator, so one would have to be built (an inference from the clones surveyed).

## Finding 4: time goes to infrastructure and wrong metrics, and the shortcuts are known

### Competition postmortems name the same missing tools

Battlecode postmortems say the same things year after year. SPAARK's 2025 lessons ([SPAARK 2025](https://battlecode.org/assets/files/postmortem-2025-spaark.pdf)):

- "Make a runmatches.py script and look at your scrims";
- scrim analysis matters more than raw win rate;
- overnight scrims are "actually very productive";
- "DON'T make last-minute changes", after losing two tournaments to untested late submissions;
- build navigation, test scripts and "a bunch of testing maps" first.

The other repeating losses:

- **Infrastructure.** AutoAscend built a visual debugger, the Halite community rebuilt replay viewers and local tournament runners, and the OpenAI Five team built "surgery" tools to change code mid-training, which they estimate saved 30 months of retraining ([report](https://arxiv.org/abs/2203.11889), [Fluorine](https://github.com/rooklift/fluorine), [OpenAI Five paper](https://arxiv.org/abs/1912.06680)).
- **Metrics that reward the wrong thing.** NetHack teams chased score instead of progress. The Pokemon Red agent learned to avoid Pokemon Centers until its rewards were changed ([report](https://arxiv.org/abs/2203.11889), [TechEBlog](https://www.techeblog.com/peter-whidden-training-ai-play-pokemon-red/)).
- **State leaking between games.** BWAPI reuses the bot instance across games, so fields had to be reset ([dloranc](https://dloranc.github.io/2017/04/09/five-pools)).
- **Wrong data from the API.** A BWAPI author found unit costs reported wrongly ([tl.net](https://tl.net/blogs/514851-towards-a-good-sc-bot-month-1-report)).
- **Setup.** One Trackmania team spent four months just getting the game and its tools installed ([Hall of Impossible Dreams](https://gwern.net/doc/www/hallofdreams.org/7553baec9ca63d343fcdf9ef880861ba924d4b70.html)).

### Harvest knowledge before learning it the hard way

The NetHack organisers explicitly recommend that future entrants use the wiki, the game's C source and human replays ([report](https://arxiv.org/abs/2203.11889)). stable-retro formalises "ground truth" about a game in a declarative variable file ([stable-retro](https://stable-retro.farama.org/integration)). The BWAPI case shows that harvested facts must be checked against live reads. For Isaac, the parallel would be game XML for stats, anm2 events for attack timing, the wiki for patterns, and live reads to check all three (an inference).

### Standard interfaces make every tool reusable

The field has converged on a Gym-style contract of `reset` and `step` ([Gymnasium](https://arxiv.org/abs/2407.17032)), with the state map kept apart from the bot logic. Any game with a mod API should expose structured state rather than pixels, as Mineflayer did for Voyager ([Voyager](https://arxiv.org/abs/2305.16291)). On one PC, the main documented resource rule is to keep the local model entirely in VRAM, because spilling to system RAM makes it "drop quite dramatically" ([Windows Central](https://www.windowscentral.com/artificial-intelligence/when-it-comes-to-running-ollama-on-your-pc-for-local-ai-one-thing-matters-more-than-most-heres-why)).

## The Isaac method, scored fairly

### What the project got right

| Practice | In the Isaac bot | Matches |
|---|---|---|
| Exact state from the mod API, no pixels | `eyes.lua` reads entities, shots and the grid | EA SEED rejected pixels ([CoG 2023](https://arxiv.org/html/2307.11105v1)); Voyager's Mineflayer ([Voyager](https://arxiv.org/abs/2305.16291)) |
| Layered time scales with interrupts | Reflexes, room, risk, run, rescue (`docs/HOW_WE_WORK.md` §5) | AutoAscend's pre-emptible strategies ([report](https://ar5iv.labs.arxiv.org/html/2203.11889)); SmashBot's strategy, tactic and chain layers ([SmashBot](https://www.Github.com/altf4/SmashBot)) |
| LLM out of the frame loop, picking from code-built options | `options.lua` plus `rescue_brain.py`, only when stuck | VideoGameBench latency wall ([VGB](https://arxiv.org/abs/2505.18134v2)); SayCan ([SayCan](https://arxiv.org/abs/2204.01691)); Jev (reported) |
| Knowledge as data that players can edit | Playbook (491 entries), item, card and pill ratings, boss tactics | AutoAscend's wiki and source data; qw's `GOALS` table ([qw](https://github.com/crawl/qw)) |
| Fix the category, not the room | `docs/HOW_WE_WORK.md` §3c | AutoAscend strategies as general subroutines |
| Tests that fail without the fix, checked by mutation | `test/tests.lua`, `test/mutants.lua`, `run.ps1 -Prove` (72 tests) | Regression suites near 100% ([Anthropic evals](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)); this is beyond AutoAscend and qw, which relied on mass runs and had no unit suite ([AutoAscend repo](https://github.com/maciej-sypetkowski/autoascend)) |
| Reload blocked by failing tests | `tools/reload.ps1` | Battlecode's "no untested changes" ([SPAARK](https://battlecode.org/assets/files/postmortem-2025-spaark.pdf)) |
| Hits sorted by cause, as rates per encounter | `brain/watcher.py` | NetHack Challenge death-cause breakdowns ([report](https://ar5iv.labs.arxiv.org/html/2203.11889)) |
| A "why" line with the cost broken into parts | `why` log lines | Utility-AI score breakdowns ([IAUS](https://gameai.com/iaus.php)); Visual Logger |
| Item-free bench and "carry" scores | `tools/rooms.py`, `knowledge/ITEMS.md` | Controlling for confounders, as in Procgen-style splits |
| Calibrating models from data | Tears measured to keep 1.16x of Isaac's sideways speed; top speed learned live | twinject calibrates the player's own movement ([twinject](https://github.com/Netdex/twinject/blob/master/README.md)) |
| Capped, reversible per-enemy lessons, and a budget on code-fix requests | `knowledge/lessons.json`, at most 3 new problems an hour | Budgeted loops ([Claude Code best practices](https://code.claude.com/docs/en/best-practices)) |
| Parallel AI sessions with one writer per file | `CLAUDE.md` | Anthropic's durable-state harness ([harness](https://anthropic.com/engineering/effective-harnesses-for-long-running-agents)) |

The most impressive part is the self-correcting attitude. When the "respect" multiplier ran away (every boss maxed at 3x berth, which led to more corners and more hits), the project found it and capped it, and bosses went from 2/8 to 7/8 cleared (`PLAN.md`). That is exactly the kind of feedback-loop failure automated systems produce, and it was caught.

### What was reinvented or done naively

| Issue | Evidence in the project | Better practice |
|---|---|---|
| **Order of work.** Behaviour first, measurement last | The gauntlet, real-room bench and offline tests all came after many hours of live tuning (`PLAN.md`) | Infrastructure and test maps first ([SPAARK](https://battlecode.org/assets/files/postmortem-2025-spaark.pdf)); evals from day one ([Anthropic evals](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)) |
| **Judging from single runs and live watching** | Many results are one run or one fight; "watched live" phases | Batch runs plus targeted replay review ([SPAARK](https://battlecode.org/assets/files/postmortem-2025-spaark.pdf)); intervals ([rliable](https://arxiv.org/abs/2108.13264)) |
| **Tiny A/B samples, one-at-a-time tuner** | 4 vs 4 rounds; the tuner changes one number and keeps it on "clear improvement"; the same settings scored 433 / 217 / 182 | Paired games with SPRT ([Fishtest](https://github.com/official-stockfish/fishtest/wiki)); racing ([irace](https://ar5iv.labs.arxiv.org/html/2204.09353)); 5 games per evaluation even for 5-vs-5 fights ([ECSLBot](https://www.cse.unr.edu/~simingl/papers/publish/CIG2014IMPFMicro.pdf)) |
| **No paired seeds or statistics** | Seeded layouts exist, but versions are not compared on the same seed list with intervals | Common random numbers plus a sequential test ([Fishtest](https://github.com/official-stockfish/fishtest/wiki)) |
| **Too many interacting weights** | ~80 named settings; "~40 hand-tuned weights that fight each other" earlier (`PLAN.md`) | About 4 factors per decision in Killzone ([slides](https://www.guerrilla-games.com/media/News/Files/gdce05_killzone_ai.pdf)); 14 tuned parameters in StarCraft micro ([ECSLBot](https://www.cse.unr.edu/~simingl/papers/publish/CIG2014IMPFMicro.pdf)) |
| **No determinism check** | Not measured whether the same seed and inputs give the same fight | Factorio heavy mode ([wiki](https://wiki.factorio.com/Desync)); run twice ([AlphaEvolve](https://docs.cloud.google.com/gemini/enterprise/docs/alphaevolve/developer-guide/reward-hacking-prevention)) |
| **Learning by getting hit** | Reach, tells and respect learned from damage; anm2 events left for "later" | AutoAscend built on source code and wiki data ([report](https://arxiv.org/abs/2203.11889)) |
| **Model errors found late** | The planner assumed Isaac moves 4.6 px per update; real top speed is ~7.7. Sloth's shots were rated "danger 0" right up to 7 of 19 hits | Check harvested and assumed values against live reads ([tl.net](https://tl.net/blogs/514851-towards-a-good-sc-bot-month-1-report)) |
| **Telemetry gaps that made data unusable** | The hit review found that 77% of 1,122 hits were from tests, 0 of 103 runs were tagged as tests, hit rows had no stage or variant, and the live log was overwritten, leaving only 3 bench rooms after ~260 real hits | A structured recorder with run and scenario IDs ([report, App. C](https://arxiv.org/abs/2203.11889)); clean trials ([Anthropic evals](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)) |
| **Lesson rule too noisy** | A lesson is kept if a cause's rate falls by a quarter after 4 encounters | Too few samples to separate signal from noise; use a sequential test or bench confirmation ([Fishtest](https://github.com/official-stockfish/fishtest/wiki)) |
| **Slow pipe** | Save-file IPC at a ~100 ms round trip | TCP lockstep under `--luadebug` ([isaac-rl](https://github.com/Scalcaneo/isaac-rl)) |

The movement core itself was not naive. The learned reach circles are a reachable-set model, and the beam search keeps several distinct plans, which handles "dodge left or dodge right" better than averaging methods ([SCP-MPPI](https://arxiv.org/html/2404.10395v1)). Most of the waste came from process, not from the algorithms.

### What is missing

| Missing piece | Why it matters | Source |
|---|---|---|
| A locked scorer and held-out seeds | Without them, any automated loop overfits or games the bench | [Procgen](https://arxiv.org/abs/1912.01588); [AlphaEvolve docs](https://docs.cloud.google.com/gemini/enterprise/docs/alphaevolve/developer-guide/reward-hacking-prevention) |
| Plan reuse (shift buffer) and default-policy rollouts | Smoother plans; catches "safe now, trapped later" | [RHEA survey](https://ar5iv.labs.arxiv.org/html/2003.12331) |
| One principled safety cost (expected damage or P(hit)) | Collapses many weights and penalises corners on its own | [Chance constraints](https://ar5iv.labs.arxiv.org/html/2001.08012); [Killzone](https://www.guerrilla-games.com/media/News/Files/gdce05_killzone_ai.pdf) |
| Punish windows (boss recovery frames) | Boss kill speed; ~75% of boss hits are bodies | [Frame data guide](https://gameplay.tips/guides/street-fighter-6-frame-data-isnt-scary-frame-data-concepts.html); [FightingICE](https://ice.ci.ritsumei.ac.jp/~ftgaic/index-R.html) |
| Closed-form lead aiming with tear inheritance | Aim accuracy of 30-55% | [Predictive aim](https://www.gamedeveloper.com/programming/predictive-aim-mathematics-for-ai-targeting) |
| Choosing among scripted tactics from logged outcomes | Picks the boss tactic that actually works | [PurpleWave](https://github.com/dgant/PurpleWave) |
| A replay viewer tied to seed and frame | Faster diagnosis than watching live | [AutoAscend visualiser](https://arxiv.org/abs/2203.11889); [Visual Logger](https://dev.epicgames.com/documentation/en-us/unreal-engine/visual-logger-in-unreal-engine) |
| Version pins in every result row | Patches break bots silently | [EA SEED](https://arxiv.org/html/2307.11105v1); [REPENTOGON 1.1.2b fixed a Rep+ break](https://github.com/TeamREPENTOGON/REPENTOGON/releases) |
| Failure search to grow the regression suite | Finds hard rooms before the bot meets them in a run | [MAP-Elites failures](https://arxiv.org/pdf/2012.04283) |
| Human baselines on the same seeds | Required for any "better than a player" claim | [Epoch SpireClimb](https://epoch.ai/benchmarks/spireclimb) compares with a human estimate |
| A measured local-LLM baseline | Whether the 12B picker beats a simple heuristic is unknown | [arXiv 2502.11882](https://arxiv.org/pdf/2502.11882) |

## Recommendations

Everything in this section is the researchers' recommendation, built on the findings above. It is ordered so that benchmark rung 0 comes first, because every later claim of "best" depends on it.

### (a) The reusable recipe and starter kit for any new game

#### Day 1, in this order

1. **Pin and record versions.** Game, mod loader, mods, bot commit. Every result row carries them ([EA SEED](https://arxiv.org/html/2307.11105v1)).
2. **Write the adapter contract.** `reset(seed, scenario)`, `step(action)` and `observe()`, returning a typed state record, plus a variable map that says where each fact comes from ([Gymnasium](https://arxiv.org/abs/2407.17032), [stable-retro](https://stable-retro.farama.org/integration)). Pick the highest state-access tier the game allows: mod API, then TAS tool or RAM, then memory reading, then screen capture. Check for anti-cheat first.
3. **Write the log schema before any behaviour.** Append-only JSONL. Every row gets the version pins, seed, scenario ID, frame, a test or real flag, and the decision with its top candidates and their score parts. Logs are never overwritten.
4. **Run the determinism check.** Same seed and scripted inputs twice, then diff the logs and record the first frame where they diverge. Run it again after every engine or mod-loader update.
5. **Set up a fast pipe and lockstep, if the engine allows.** If the game can pause its update while the brain thinks, use that. Measure the round trip.
6. **Import knowledge before learning anything.** Game files, then wiki, then live validation, into JSON with a schema. Disagreements between sources get flagged, and unvalidated text never drives behaviour ([report](https://arxiv.org/abs/2203.11889), [tl.net](https://tl.net/blogs/514851-towards-a-good-sc-bot-month-1-report)).
7. **Build scenario bench v0.** 20-50 seeded scenarios from known hard cases (bosses, tight rooms, hazards), a one-command batch runner, and a report with intervals ([Anthropic evals](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents), [SPAARK](https://battlecode.org/assets/files/postmortem-2025-spaark.pdf)).
8. **Add the regression gate and harness files.** `CLAUDE.md` names the test and bench commands. A Stop hook or pre-merge check runs them. The scorer, the suites and the seeds sit in protected paths ([Claude Code best practices](https://code.claude.com/docs/en/best-practices)).

#### Week 1

1. A baseline behaviour: a short-horizon planner with one expected-damage cost and a lined-up-shot reward, plus rules taken from the knowledge files.
2. Every behaviour change goes through the paired bench. Live runs are for spot checks and for harvesting new failure scenarios.
3. Overnight batches with a watchdog, one heavy job at a time, and a morning report.
4. A failure-to-scenario pipeline: every new kind of hit or stall becomes a bench scenario or a mock test within a day.
5. An on-screen overlay and a replay viewer keyed by seed and frame.
6. A first human baseline on the room suite and boss drills.
7. A cross-game `METHODS.md`: what worked, what didn't, carried to the next project.

#### What is reusable and what is per game

| Reusable core (write once) | Per-game adapter (write per game) |
|---|---|
| Bench runner, paired A/B, SPRT and bootstrap statistics, reports | State reader and input injector |
| Log schema, recorder, replay viewer, hits-by-cause classifier | Variable map (where each fact comes from) |
| Planner skeleton: beam or rolling horizon with shift buffer and rollouts, expected-damage cost, ways-out check | Motion and attack models for that game's entities |
| Lesson store with caps and revert; failure queue; tuner (racing plus CMA-ES or TPE) | Knowledge import scripts and schemas |
| Harness files: `CLAUDE.md` template, hooks, budgets, protected paths | Scenario list, seed lists, human baselines |
| Option-picker interface for a local LLM, plus its exam harness | Option builders for that game's decisions |

#### The autonomous improvement loop and its guardrails

The loop:

1. Take an item from the failure queue.
2. Diagnose it from logs and frames.
3. Make one change.
4. Run the offline tests.
5. Run the paired bench on the capability scenarios for that failure, then the full regression suite.
6. Accept the change only if regression holds and the capability result clears the sequential test.
7. Commit to a branch, with the bench report attached.

This is the Fishtest pattern ([Fishtest](https://github.com/official-stockfish/fishtest/wiki)) with Anthropic's capability/regression split ([evals](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)).

The guardrails come straight from the reward-hacking literature ([AlphaEvolve docs](https://docs.cloud.google.com/gemini/enterprise/docs/alphaevolve/developer-guide/reward-hacking-prevention), [The Register on the Darwin Gödel Machine](https://www.theregister.com/2025/06/02/self_improving_ai_cheat/), [DEV Community](https://dev.to/_khanshaheb/how-im-running-an-autonomous-claude-code-loop-on-a-real-shipped-product-48lf)):

- **Locked scorer.** Scoring code, suites and seeds live in a directory the agent cannot edit (a deny rule plus a hash check in the gate). Scores are computed by the harness, never by the model.
- **Held-out seeds.** Run only by the maintainer before releases, and rotated now and then so the open suite cannot be memorised.
- **Regression gate.** No merge with a red regression suite. No change to test expectations in the same PR as a behaviour change.
- **Budgets.** Turns, tokens or money, wall time and bench minutes per candidate. Small batches first ("try 3 items, then the rest").
- **Anti-cheat checks.** Re-run every accepted candidate. Flag runs that are suspiciously fast or have zero hits. Spot-check replays by eye. Tell the agent explicitly not to invent problems. Have a fresh-context reviewer read the raw bench output, since agents over-rate their own work ([Anthropic harness](https://anthropic.com/engineering/effective-harnesses-for-long-running-agents)).
- **Machine safety.** One heavy job at a time, a watchdog, no mod reloads during batches, and the local model kept in VRAM.

### (b) Improvements to the Isaac bot, ordered by value per effort

| # | Change | Effort | Expected payoff | How to measure |
|---|---|---|---|---|
| 1 | **Fix telemetry:** hit rows carry stage, layout variant, bot version, items and a test flag; logs never overwritten; `rooms.py collect` on every run end | Hours | Every later number becomes trustworthy; the bench grows from 3 rooms to hundreds | Share of hits tied to a room key (target ~100%); share of test runs tagged |
| 2 | **Paired fixed-seed bench with intervals and a sequential test** (rooms, boss drills, open and held-out seeds) | 1-2 days | Ends single-run judging; makes small gains provable; benchmark rung 0 | Interval width on hits per room; trials to a decision |
| 3 | **Determinism check and fast resets:** seeded `StartNewGame`, `goto s.boss.<id>`, a test of REPENTOGON 2.0.0 save/restore at fight start | Hours to 1 day | Shows how much variance is noise; may allow exact fight replays | First diverging frame across repeated runs; boss HP and position diffs |
| 4 | **Harvest attack tells and timings from anm2 events and entity XML**, kept in a gitignored local file as `PLAN.md` already plans; check against live reads | ~1 day | Cuts first-encounter hits (Crazy Long Legs stomp, Pin, Sloth shots) without paying for them | Hits in the first N encounters per enemy, before vs after |
| 5 | **Expected-damage cost** (Σ P(hit) × damage over the horizon, from the learned spreads) plus a chance-constraint option; **fit the remaining weights from logged hit labels** with logistic regression, Texel-style | 2-4 days | ~80 weights down to ~10 meaningful knobs; fewer "fix broke something else" interactions | Held-out log-loss of the hit predictor; paired hits per room |
| 6 | **Plan reuse and rollouts:** shift buffer plus a 0.5-1 s default-policy rollout after the 3 planned moves; ways-out as admissibility, using full reach for fast homers and checking inside corners of L rooms | 1-2 days | Fewer corner traps (corners are 8% of the floor but 26% of hits) and less jitter | Corner-hit share; hits per room on corner-heavy and L-room scenarios |
| 7 | **Better motion and shot prediction:** measured acceleration and lobbed shots, swept shapes for charges and lasers, tethered babies limited by their cord | 1-3 days | Fixes the Sloth "danger 0" misses and the Gemini spread | Fraction of hits where the planner rated the spot "safe" |
| 8 | **Closed-form lead aiming** with tear inheritance (solve the intercept with target velocity minus k × player velocity, k ≈ 1.16 measured) and positioning for 4-direction fire; log miss vectors | 1-2 days | Aim accuracy up from 30-55%; faster boss kills | Per-boss accuracy, lateral miss bias, kill time with intervals |
| 9 | **Punish windows:** a per-boss phase table (tell, active and recovery durations, damage zone) from logs plus anm2; move into firing position during recovery, mark charge lines as danger while active | 2-4 days for floor 1-2 bosses | Boss kill speed and body hits (~75% of boss hits) | Share of boss damage dealt in recovery windows; body-hit rate; kill time |
| 10 | **Choose among scripted boss tactics from logged outcomes** (a bandit over the options in `boss_tactics.json`) | 1 day once #2 exists | The tactic that works wins automatically | Per-tactic kill rate with intervals |
| 11 | **Tuning with racing** (irace-style, or Optuna TPE with pruning) over grouped knobs on the paired room suite; confirm the winner on held-out seeds | 1 day plus overnight runs | Replaces the one-at-a-time tuner | Held-out improvement versus the default |
| 12 | **Faster IPC and lockstep:** `--luadebug` TCP plus `MC_PRE_UPDATE` skipping the update until Python answers | 1-3 days, some risk | Needed only for Python-side models and exact replays; the Lua reflexes don't need it | Round-trip latency; replay match rate |
| 13 | **Narrow learning, in this order:** (i) supervised motion prediction from logs; (ii) a fast 2D "room twin" built from the mock and recorded traces, used for tuning and MAP-Elites failure search and checked against live rooms; (iii) imitation of human boss play as a prior; (iv) RL only inside the twin, as a candidate generator | Weeks | Needed for rungs 3 and 5 | Prediction error on held-out logs; sim-to-live gap in hits per room |
| 14 | **The right roles for the local LLM and the coding assistant** (below) | Hours | Clear value or a simpler bot | LLM pick quality vs a heuristic baseline on logged stuck cases |

A few of these need more detail.

**On #2.** Use the same seed list for both versions and compare per-seed differences, which cancels the variance between seeds. Stop with an SPRT once the evidence is enough, as Fishtest does ([Fishtest](https://github.com/official-stockfish/fishtest/wiki)). Report bootstrap intervals and the interquartile mean, as rliable recommends ([rliable](https://arxiv.org/abs/2108.13264)). Prefer dense metrics such as hits per room and boss kill time over run wins, because they have far lower variance. A night of 20-second room trials gives roughly 1,400 trials, which is enough for a few honest A/B decisions a night (the researchers' arithmetic).

**On #4.** This is the cheapest fix for "learning by getting hit", the pain point the author named. It follows the NetHack organisers' advice to use game sources ([report](https://arxiv.org/abs/2203.11889)). The repo's rule against committing game files still applies: keep the extracted data local and commit only the extraction script.

**On #5.** This is the deepest structural change. Killzone shows that about four factors are enough for a shipped tactical AI ([slides](https://www.guerrilla-games.com/media/News/Files/gdce05_killzone_ai.pdf)), and Texel tuning shows that weights can be fitted from logged outcomes with no new games ([Texel](https://www.chessprogramming.org/Texel%27s_Tuning_Method)). The approach: label each logged tick "hit within 1 s" (0/1), fit a logistic regression from the existing safety features, and drop the features whose coefficients stay near zero. Then tune the few knobs left, such as the damage exchange rate, the risk threshold and the horizon, with racing on the bench. CMA-ES with 80 dimensions would need 17 candidates per generation and thousands of noisy evaluations ([CMA-ES tutorial](https://arxiv.org/pdf/1604.00772)). With 10 dimensions it needs 10 per generation, which fits overnight batches.

**On #13.** This is where learning fits, and only here. The full game at 30 Hz real time is the hardest setting RL has, so full-game RL is not recommended ([tmrl](https://github.com/trackmania-rl/tmrl), [RocketSim](https://github.com/ZealanL/rocketsim)). The bot's own logs are free training data for motion prediction. A room twin is the hobby version of RocketSim. It is worth building only once the bench shows the hand-built predictor is the bottleneck, and it must be checked by replaying the same rooms live.

**On #14.** Keep the local ~12B model as an option-picker for rare decisions: being stuck, and possibly item and deal choices, using short structured prompts and no long chains of thought ([arXiv 2502.11882](https://arxiv.org/pdf/2502.11882)). Measure it against a "pick by heuristic" baseline on logged cases and on the existing exam. If it does not beat code, replace it with rules written by the coding assistant. The coding assistant's best role is the offline coach seen in PORTAL and Jev: it reads failure reports, edits options and rules, and proposes candidates for the locked bench ([PORTAL](https://arxiv.org/abs/2503.13356), [Jev, reported](https://www.remio.ai/post/jev-pokemon-red-run-finished-in-37-hours-but-claude-helped-build-the-winning-sys)).

### (c) A proposed new contributor process for GitHub

This is a concrete proposal for the author to adopt or adapt. It changes the loop in `docs/HOW_WE_WORK.md` and the rules in `CONTRIBUTING.md`, which this report does not edit.

**1. The loop gets a measurement spine.** Step 3a, "watch", becomes "pick from the failure queue or the worst bench scenarios". Watching stays useful for finding new categories, but it is no longer how changes are judged. Step 3f, "measure", becomes "run the paired suite and report intervals". A new step follows 3d: "turn the failure into a scenario". Every new failure becomes a bench scenario (stage, layout, seed) or a mock test before the fix is written, so the fix is proven against it. The watcher's lessons become candidates. A lesson is kept only after a paired bench confirmation or a sequential test, not after 4 encounters.

**2. Every behaviour PR carries a bench report.** A PR template with these required sections:

- **Problem:** log lines, a frame or a scenario ID.
- **Category:** the general rule being fixed.
- **Test:** the test name, and the mutant entry that proves the test fails without the fix.
- **Bench:** the exact command, the suite name and version, the bot commits compared, per-metric paired differences with 95% intervals or the SPRT verdict, and the regression suite result.
- **Performance:** milliseconds per update, average and worst spike.

The bench tool writes this block as JSON, with a hash of the suite and the commit, so it is pasted rather than typed. The game cannot run in GitHub CI, so maintainers re-run a sample of claimed results before merging large changes.

**3. CI checks everything that can run without the game.** A GitHub Actions job on Linux with Lua 5.3 runs `test/run.sh`, the Lua compile check, the BOM check, the privacy check and the knowledge-schema validation on every PR. A red CI blocks the merge.

**4. The scorer, suites and seeds are protected.** They live in their own folder with CODEOWNERS review. A PR that changes them may not also change behaviour (the "two-PR rule"). Suites are versioned and frozen. Adding scenarios creates a new suite version, and results always name the version they used. The held-out seed list is not published until it is retired.

**5. Knowledge contributions are validated by a schema.** Every entry in `knowledge/*.json` follows a JSON Schema with these fields:

- **source:** wiki page, observed in game, or derived from game data;
- **status:** draft, checked live or measured;
- **date:** when the entry was added or changed.

Drafts written by AI from wiki text stay flagged until someone checks them live, which matches the existing note about unchecked playbook drafts in `PLAN.md`. Schema validation runs in CI. A knowledge-only PR needs no bench run. A knowledge PR that changes behaviour on a boss should include that boss's drill result.

**6. Issues feed the bench.** A "bot failure" issue template asks for the room key or seed, the floor, the bot version, the items held and a frame. Triage turns each one into a scenario. A "benchmark result" template lets anyone submit a score for their own bot or fork on the public suites, which is how the "best" claim becomes contestable.

**7. AI-assisted PRs follow the same rules, stated more strictly.** Contributors say when an AI agent wrote the change. Agents paste the command output, not "all tests pass" ([Claude Code best practices](https://code.claude.com/docs/en/best-practices)). Agents may not edit protected paths. `CLAUDE.md` adds the bench command, the "don't invent problems" instruction and the protected-path list.

**8. Releases publish benchmark results.** Each tagged release adds a row to a `benchmark/RESULTS.md` (or JSON) file: the suite versions, the version pins and the scores with intervals. This becomes the public record for the ambition ladder.

## Conclusion

Studios, competition teams and research labs that build game bots differ in almost everything except one habit: they build the way of measuring before the thing being measured. Seen that way, the Isaac bot's first day did the hard, creative part well: a planner on exact state, knowledge as data, the LLM kept out of the fast loop, and category fixes locked in by tests. It left the dull but decisive part, paired seeds and locked scorers, until last. The good news is that the dull part is cheap and reusable. One to three days of telemetry and bench work turns every later hour, human or AI, into evidence rather than impressions. The same kit carries to the next game nearly unchanged.

The goal of being the best changes priorities more than methods. No Isaac bot has public numbers, so the fastest route to a defensible "best" is to publish the first serious benchmark and climb it in the open. The current hand-built approach should reach "beats an average player" and probably "beats a strong player on damage taken", because exact state and instant reactions are real advantages in a dodging game. The rungs beyond that, late-game bullet-hell bosses and a second game through an adapter, are where the project would be doing something nobody has published. Only those rungs justify a fast simulator and narrow learned parts, and only once the bench shows the hand-built predictor is what holds the bot back.

## Sources

**Scripted and symbolic bots**
- NeurIPS 2021 NetHack Challenge report: [arXiv 2203.11889](https://arxiv.org/abs/2203.11889), [full text](https://ar5iv.labs.arxiv.org/html/2203.11889), [AIcrowd insights](https://aicrowd.com/research/insights-from-the-neurips-2021-nethack-challenge)
- [AutoAscend repository](https://github.com/maciej-sypetkowski/autoascend)
- [BotHack](https://github.com/krajj7/BotHack); [NetHackWiki: Bot](https://nethackwiki.com/wiki/Bot)
- [crawl/qw](https://github.com/crawl/qw); [elliptic/qw](https://github.com/elliptic/qw)
- [Rog-O-Matic paper](https://www.cs.princeton.edu/~appel/papers/rogomatic.html)
- [PurpleWave](https://github.com/dgant/PurpleWave); [PurpleWave 2017 survey](https://www.cs.mun.ca/~dchurchill/starcraftaicomp/2017/survey/PurpleWave_Survey.txt); [StarCraft AI competition results](https://davechurchill.ca/starcraft/results/)
- [twinject](https://github.com/Netdex/twinject/blob/master/README.md); [bullet-hell DQN thread](https://lemmy.world/post/16099991)
- [DareFightingICE](https://ice.ci.ritsumei.ac.jp/~ftgaic/index-R.html); [Enhanced RHEA with opponent model](https://arxiv.org/pdf/2003.13949)
- [SmashBot](https://www.Github.com/altf4/SmashBot); [Phillip](https://arxiv.org/abs/1702.06230); [slippi-ai](https://github.com/vladfi1/slippi-ai); [Faynt (2026 preprint)](https://arxiv.org/abs/2610.02144)
- [Antithesis NetHack (2026)](https://antithesis.com/blog/2026/nethack/); [LLM NetHack ascension blog (2026)](https://kenforthewin.github.io/blog/posts/llm-nethack-ascension)
- [Epoch SpireClimb](https://epoch.ai/benchmarks/spireclimb); [Slay the Spire seed study](https://forgottenarbiter.github.io/Is-Every-Seed-Winnable)

**Reinforcement and imitation learning**
- [OpenAI Five](https://openai.com/index/openai-five-defeats-dota-2-world-champions); [OpenAI Five paper](https://arxiv.org/abs/1912.06680)
- [AlphaStar (The Register)](https://www.theregister.com/2019/11/01/deepmind_starcraft_ai); [AlphaStar (DeepMind)](https://deepmind.google/discover/blog/alphastar-grandmaster-level-in-starcraft-ii-using-multi-agent-reinforcement-learning/)
- [Agent57](https://deepmind.google/blog/agent57-outperforming-the-human-atari-benchmark/); [BBF](https://arxiv.org/abs/2305.19452); [DreamerV3](https://ar5iv.labs.arxiv.org/html/2301.04104)
- [GT Sophy technology](https://us.gran-turismo.com/us/gran-turismo-sophy/technology/); [VPT](https://ar5iv.labs.arxiv.org/html/2206.11795); [Muse/WHAM model card](https://huggingface.co/microsoft/wham)
- [Street Fighter II PPO](https://raw.githubusercontent.com/linyiLYi/street-fighter-ai/master/README.md); [Pokemon Red RL (TechCrunch)](https://techcrunch.com/2023/10/18/after-50000-hours-this-ai-can-play-pokemon-red); [Pokemon Red RL (TechEBlog)](https://www.techeblog.com/peter-whidden-training-ai-play-pokemon-red/); [Pokemon RL paper](https://arxiv.org/abs/2502.19920v2)
- [Linesight](https://linesight-rl.github.io/linesight/build/html); [tmrl](https://github.com/trackmania-rl/tmrl); [Hall of Impossible Dreams (archived)](https://gwern.net/doc/www/hallofdreams.org/7553baec9ca63d343fcdf9ef880861ba924d4b70.html)
- [RocketSim](https://github.com/ZealanL/rocketsim); [Rocket League sim-to-sim transfer](https://arxiv.org/pdf/2205.05061)
- [Counter-Strike behavioural cloning](https://arxiv.org/abs/2104.04258v2); [Visual encoders for data-efficient imitation](https://arxiv.org/abs/2312.02312)
- [Residual RL](https://arxiv.org/abs/1812.03201)

**LLM/VLM agents and hybrids**
- [VideoGameBench](https://arxiv.org/abs/2505.18134v2); [BALROG](https://arxiv.org/abs/2411.13543); [BALROG leaderboard](https://balrogai.com/); [lmgame-Bench](https://arxiv.org/abs/2505.15146)
- [Dual-process Overcooked study](https://arxiv.org/pdf/2502.11882); [Real-Time Reasoning Gym](https://arxiv.org/abs/2511.04898); [Reflex First, Reflect Later](https://arxiv.org/pdf/2506.07223)
- [Lumine](https://arxiv.org/abs/2511.08892v1); [SIMA 2](https://deepmind.google/blog/sima-2-an-agent-that-plays-reasons-and-learns-with-you-in-virtual-3d-worlds/); [Cradle](https://arxiv.org/abs/2403.03186); [PORTAL](https://arxiv.org/abs/2503.13356)
- [Claude beats Pokemon (LessWrong)](https://www.lesswrong.com/posts/sehJYg5Yny9fvpbpt/a-year-late-claude-finally-beats-pokemon); [Gemini Pokemon (PC Gamer)](https://www.pcgamer.com/software/ai/google-ai-happens-to-be-really-bad-at-playing-pokemon-repeatedly-panicking-and-taking-more-than-800-hours-to-beat-the-elite-four)
- Jev (reported): [Tom's Hardware](https://www.tomshardware.com/tech-industry/artificial-intelligence/developer-says-jev-decision-model-beat-pokemon-red-in-under-a-week-non-llm-engine-succeeds-where-traditional-chatbots-stalled-for-months-but-claude-opus-5-coached-the-model-through-its-dead-ends), [remio](https://www.remio.ai/post/jev-pokemon-red-run-finished-in-37-hours-but-claude-helped-build-the-winning-sys)
- [PokeAgent Challenge](https://arxiv.org/abs/2603.15563); [Survey on LLM-based game agents](https://arxiv.org/abs/2404.02039)
- [SayCan](https://arxiv.org/abs/2204.01691); [Code as Policies](https://arxiv.org/abs/2209.07753); [Voyager](https://arxiv.org/abs/2305.16291); [Eureka](https://arxiv.org/abs/2310.12931)
- [FunSearch](https://www.nature.com/articles/s41586-023-06924-6); [AlphaEvolve on game solvers](https://arxiv.org/abs/2602.16928); [ShinkaEvolve](https://arxiv.org/abs/2509.19349v1); [OpenELM](https://github.com/CarperAI/OpenELM)

**Playtesting and engineering practice**
- [EA SEED, Challenges of deploying RL agents for game testing (CoG 2023)](https://arxiv.org/html/2307.11105v1); [EA SEED ML research overview](https://www.ea.com/technology/news/seed-ml-research-aaa-game-testing); [EA SEED, Augmenting automated game testing with deep RL](https://arxiv.org/abs/2103.15819)
- [King, Human-like playtesting with deep learning](https://www.gwern.net/doc/reinforcement-learning/imitation-learning/2018-gudmundsson.pdf); [Ubisoft Hybrid SAC](https://arxiv.org/abs/1912.11077); [Wuji](https://www.se.cs.uni-saarland.de/conferences/ASE/ase2019/details/ase-2019-papers/39/Wuji-Automatic-Online-Combat-Game-Testing-Using-Evolutionary-Deep-Reinforcement-Lear.html); [LLM game-testing agents (DRL overfitting)](https://arxiv.org/html/2509.22170v1)
- [rliable](https://arxiv.org/abs/2108.13264); [Fishtest](https://github.com/official-stockfish/fishtest/wiki); [Revisiting the ALE](https://arxiv.org/abs/1709.06009); [Procgen](https://arxiv.org/abs/1912.01588); [NLE](https://arxiv.org/abs/2006.13760); [MiniHack](https://arxiv.org/abs/2109.13202)
- [Factorio desynchronization](https://wiki.factorio.com/Desynchronization); [Factorio desync / heavy mode](https://wiki.factorio.com/Desync); [libTAS](https://clementgallet.github.io/libTAS/guides/how); [GGPO](https://www.ggpo.net/); [Go-Explore](https://arxiv.org/abs/1901.10995)
- [Unreal Visual Logger](https://dev.epicgames.com/documentation/en-us/unreal-engine/visual-logger-in-unreal-engine); [Unreal Gameplay Debugger](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-the-gameplay-debugger-in-unreal-engine)
- [irace](https://ar5iv.labs.arxiv.org/html/2204.09353); [CMA-ES tutorial](https://arxiv.org/pdf/1604.00772); [Hyperband](https://arxiv.org/abs/1603.06560); [Optuna pruners](https://optuna.readthedocs.io/en/stable/reference/pruners.html); [Population-based training](https://arxiv.org/abs/1711.09846)
- [MAP-Elites failure search](https://arxiv.org/pdf/2012.04283); [MADRID](https://arxiv.org/html/2312.02231v1); [Algorithmic scenario generation survey](https://arxiv.org/html/2409.04711v1)
- [Anthropic: Effective harnesses for long-running agents](https://anthropic.com/engineering/effective-harnesses-for-long-running-agents); [Anthropic: Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents); [Claude Code best practices](https://code.claude.com/docs/en/best-practices)
- [AlphaEvolve reward-hacking prevention](https://docs.cloud.google.com/gemini/enterprise/docs/alphaevolve/developer-guide/reward-hacking-prevention); [Darwin Gödel Machine objective hacking](https://www.theregister.com/2025/06/02/self_improving_ai_cheat/); [Autonomous Claude Code loop on a shipped game](https://dev.to/_khanshaheb/how-im-running-an-autonomous-claude-code-loop-on-a-real-shipped-product-48lf)

**Time sinks and starter kits**
- [Battlecode SPAARK 2025 postmortem](https://battlecode.org/assets/files/postmortem-2025-spaark.pdf); [Battlecode "no thoughts" 2023](https://battlecode.org/assets/files/postmortem-2023-no-thoughts.pdf)
- [Fluorine Halite replay viewer](https://github.com/rooklift/fluorine); [Mini Halite](https://github.com/nmalaguti/mini-halite)
- [BWAPI instance reuse](https://dloranc.github.io/2017/04/09/five-pools); [BWAPI first-month report](https://tl.net/blogs/514851-towards-a-good-sc-bot-month-1-report)
- [Gymnasium](https://arxiv.org/abs/2407.17032); [stable-retro integration](https://stable-retro.farama.org/integration); [Godot RL Agents](https://arxiv.org/abs/2112.03636); [Factorio Learning Environment](https://arxiv.org/abs/2503.09617)
- [Ollama VRAM guidance](https://www.windowscentral.com/artificial-intelligence/when-it-comes-to-running-ollama-on-your-pc-for-local-ai-one-thing-matters-more-than-most-heres-why)

**Isaac-specific**
- [Scalcaneo/isaac-rl](https://github.com/Scalcaneo/isaac-rl); [the-learning-of-isaac](https://github.com/oralet86/the-learning-of-isaac); [DeepArcadia/IsaacRL](https://github.com/DeepArcadia/IsaacRL); [AIsacco](https://github.com/Reiver56/AIsacco); [SerpentAI Isaac plugin](https://github.com/Supermaxman/SerpentSuperAIsaacGameAgentPlugin); [JS remake bot](https://github.com/Defasium/the-binding-of-isaac-js-ai-bot); [2-X Isaac AI](https://github.com/2-X/binding-of-isaac-ai); [Flash Isaac TAS](https://tasvideos.org/8001S)
- IsaacDocs: [ModCallbacks](https://wofsauge.github.io/IsaacDocs/rep/enums/ModCallbacks.html), [Game](https://wofsauge.github.io/IsaacDocs/rep/Game.html), [Isaac](https://wofsauge.github.io/IsaacDocs/rep/Isaac.html), [RNG](https://wofsauge.github.io/IsaacDocs/rep/RNG.html), [Getting Started](https://wofsauge.github.io/IsaacDocs/rep/faq/GettingStarted.html)
- REPENTOGON: [changelog](https://github.com/TeamREPENTOGON/REPENTOGON/blob/main/changelog.txt), [releases](https://github.com/TeamREPENTOGON/REPENTOGON/releases), [Isaac class](https://repentogon.com/Isaac.html), [Game class](https://repentogon.com/Game.html)
- [Debug Console (wiki.gg)](https://bindingofisaacrebirth.wiki.gg/wiki/Debug_Console); [Racing+](https://github.com/Zamiell/racing-plus); [Racing+ changes](https://github.com/Zamiell/racing-plus/blob/main/docs/changes.md); [isaac-lua-polyfill](https://www.npmjs.com/package/isaac-lua-polyfill); [IsaacScript](https://isaacscript.github.io)

**Dodging, positioning, aiming and tuning**
- [RHEA for general video game playing (survey)](https://ar5iv.labs.arxiv.org/html/2003.12331); [Rolling horizon coevolutionary planning](https://ar5iv.labs.arxiv.org/html/1607.01730)
- [ORCA](https://gamma.cs.unc.edu/ORCA/); [Dynamic Window Approach](https://www.ri.cmu.edu/publications/the-dynamic-window-approach-to-collision-avoidance); [MPPI example](https://www.mathworks.com/help/robotics/ug/local-path-planning-using-model-predictive-path-integral.html); [SCP-MPPI](https://arxiv.org/html/2404.10395v1); [Chance-constrained planning](https://ar5iv.labs.arxiv.org/html/2001.08012); [Time-to-collision power law](https://www.arxiv.org/abs/1412.1082)
- [Killzone AI (GDC Europe 2005)](https://www.guerrilla-games.com/media/News/Files/gdce05_killzone_ai.pdf); [Modular tactical influence maps](https://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter30_Modular_Tactical_Influence_Maps.pdf); [Infinite Axis Utility System](https://gameai.com/iaus.php)
- [Predictive aim mathematics](https://www.gamedeveloper.com/programming/predictive-aim-mathematics-for-ai-targeting); [StarCraft micro with influence maps and potential fields (CIG 2014)](https://www.cse.unr.edu/~simingl/papers/publish/CIG2014IMPFMicro.pdf); [Frame data basics](https://gameplay.tips/guides/street-fighter-6-frame-data-isnt-scary-frame-data-concepts.html)
- [Texel's tuning method](https://www.chessprogramming.org/Texel%27s_Tuning_Method); [NTBEA](https://ar5iv.labs.arxiv.org/html/2003.10378)
