# Boss tactics (floors 1-2, plus bench bosses)

`boss_tactics.json` is the machine-readable version. This page is for reading. Keys are `type.variant`, the same as
`enemy_playbook.json`. Repentance+ behaviour wins where versions differ. Made 2026-11-25.

**Why this exists.** The goal is no damage on floors 1-2, bosses included, because any hit lowers the devil deal
chance. The author's idea: look up how experienced players beat each boss, including the cheeky tricks, and give that
to the bot instead of letting it learn by getting hit.

**How sure is it?**
- *Animation names* marked "logged" come from the bot's own `tells.dat` / `telegraphs.txt`. They are the real names
  the game uses, with the frame the shots leave (`shots@Nf`). Other tells are described in words until `tells.lua`
  logs their names.
- *Wiki* facts are from bindingofisaacrebirth.wiki.gg (read 2026-11-25).
- *Inferred* means it's reasoned from the mechanic and needs a bench test.
- The written guide sites (GameRevolution, SuperCheats, Bamboo Gaming, TV Tropes, the fandom Sloth page) refused
  automated reads. YouTube video pages gave titles only (no description or transcript). So the player tips here come
  from the wiki pages, two search-result summaries of guide pages, and one Steam thread.

## What would help the bot most

1. **React to the tell animation, not the shot.** `tells.dat` shows how little warning some shots give once their
   animation starts:
   - Dingle's Spit: shots at frame 3.
   - The Haunt's SpitNoSkin: frame 3.
   - Lil Haunt's Shoot: frame 4.

   The tell is the animation *before*: Dance/Whistle → Spit, BeforeSlide → Slide, IdleNoSkin → LaserNoSkin,
   Sucking → Puking, Idle → Fart (21 f). Each `dodge` entry has `tell_anim` + `fires` + `shots_at_frame` for this.
2. **Target rules for multi-part bosses** (`target_order`, `never_aim`, `invulnerable_while`):
   - Haunt: Lil Haunts (260.10) first; the Haunt itself is invulnerable until all are dead.
   - Gemini: kill Suture (79.10) first. If Contusion dies first, Suture detaches and charges wildly.
   - Blighted Ovum: never shoot the ghost Suture (79.12). Only Contusion can die.
3. **Lane rules per boss** (`avoid_row_col`, `avoid_row`, `avoid_col`, `avoid_diagonals`):
   - Gurglings/Turdlings dash with no wind-up when lined up, so avoid their rows and columns.
   - Sloth's new Charger goes along Sloth's row.
   - Ovum's ghost fires a beam along its row.
   - The Haunt lasers down its column.
   - Famine and the Horseman head charge along rows.
   - Pride's lasers are diagonal.
4. **Lobbed shots hurt where they land.** Sloth's shot is an Ipecac lob (this answers the playbook's "unsure: shot
   path"; the bot saw danger 0 because the shot is up in the air). Predict the landing at Isaac's position when it
   fired. Keep moving the same way (`no_reverse`), because doubling back walks into it. The same applies to Pin's
   red shot and the Headless Horseman body.
5. **Creep lanes are walls.** 2 of the 3 Gurglings bench hits were red creep (1000.22) along their dash paths.
6. **Haunt phase 2 zone:** stay in the bottom half (it dashes at Isaac near the top wall). Keep 60+ px sideways from
   its column (laser), and shoot up as it slides across.
7. **Per-boss distance** (`pref_dist`): Dingle 200 (dash reaction time), Gemini 180, Mega Fatty 170 (its fart hit
   the bot twice at 85-92 px), Sloth 160.

**Wiring idea** (for the main session, not done here). Send it like the playbook: one `key=field:value,...` line per
boss, with tells as `tell_anim>fires@frame/how`. `tells.lua` already knows the current animation per entity, so a
lookup on (`key`, current anim) gives the dodge `how`. `reflex.lua`'s `boss_dist` can take `pref_dist` per boss.

## Playbook corrections found on the way (not edited here)

- Gurdy Jr. (99.0): the wiki lists it as a chapter 2 boss (Caves, Catacombs, Flooded Caves), not floors 1-2.
- Rag Man (405.0): Cellar and Burning Basement only in Repentance+ (removed from Basement).
- The Haunt (260.0): Cellar only in Repentance+ (the playbook already notes this).
- Mega Fatty (264.0): Caves and Flooded Caves.
- Sloth (46.0): the shot is a lobbed Ipecac explosive, and Sloth wanders rather than chases.
- Pin (62.0): 100 HP in Repentance (180 was Rebirth).
- Gurglings (237.1): 60 HP each.

## Floor 1-2 boss lists (Repentance+, from the wiki floor pages)

- **Basement:** Dingle, Duke of Flies, Gemini, Steven, Larry Jr., Monstro, Gurglings, Famine, The Fallen, Headless
  Horseman, Dangle, Little Horn, Turdlings, Baby Plum.
- **Cellar:** Blighted Ovum, Duke of Flies, The Haunt, Pin, Widow, Famine, The Fallen, Headless Horseman, Little
  Horn, Rag Man, Baby Plum.
- **Burning Basement:** Duke of Flies, Larry Jr., Monstro, Famine, The Fallen, Headless Horseman, Little Horn, Rag
  Man, Dingle, Gemini, Steven, Gurglings, Dangle, Turdlings, Baby Plum.
- **Downpour:** Lil Blub, Wormwood, The Rainmaker, Min-Min.
- **Dross:** Clog, Colostomia, Wormwood, Lil Blub, Turdlet.
- **Minibosses** (any of these floors): Sloth, Lust, Wrath, Gluttony, Greed, Envy, Pride. Krampus can appear in a
  Devil Room (never the first of a run).

---

## The six bench bosses

### Dingle (261.0) and Dangle (261.1)
Bench: died with 6 hits. The logged causes split about evenly between puke shots (9.3) and body contact.

- **HP:** 300 (Dangle 375, the most of any chapter 1 boss).
- **Floors:** Basement, Burning Basement.
- **Animations logged:** Appear, Idle, Dance, Whistle, Spit, BeforeSlide, Slide, Tired.

| Attack | Tell | Fires | What | Dodge |
|---|---|---|---|---|
| Triple shot | Dance or Whistle | Spit @3f | 3 puke shots at Isaac | sideways, starting on the tell |
| Summon Dips | Whistle | then Spit | 1-3 Dips, then a triple shot at once | sideways (the shot follows) |
| Dash ×3 | BeforeSlide | Slide | 3 long dashes, each re-aimed at Isaac, bouncing off walls/rocks; ends in Tired | sideways, late, at 90°; never run along the line or into a corner |

- **Distance and position:** 200 px, open floor with room to step either way, no corners.
- **Attack windows:** Tired (after the dashes), Idle (it is stationary), Whistle.
- **Adds:** Dips (217.0): kill when close.
- **Tricks:**
  - Wait for the whole dash sequence to finish before moving in.
  - Its dashes knock Dips around and can leave poop that blocks shots.
- **Champions:**
  - Black: an 8-shot ring instead of 3 (stand off its 8 lines), spiders, one very fast dash.
  - Red: 4 short, slow dashes.
- **Dangle:** 2 dashes leaving slippery brown creep, Brownie Corns instead of Dips. It sometimes drops a Corn Mine; if
  the mine poisons it mid-dash, it leaves damaging green creep.

### Gemini (79.0 Contusion, 79.10 Suture); also Steven (79.1/79.11) and Blighted Ovum (79.2/79.12)
Bench: timed out with 4 hits (Contusion contact, a Suture shot, Suture contact).

- **HP:** 140 per twin.
- **Floors:** Basement, Burning Basement (Ovum: Cellar).
- **Animations logged** (type 79, both twins): WalkHori, WalkVert, Pant (Contusion); Walk01, Attack01 (attached
  Suture); Rage → Walk02 (Suture detaching).

| Part | Attack | Tell | Dodge |
|---|---|---|---|
| Contusion | chase, then a speed-up charge, then Pant | speeds up | sideways: cut across its path; shoot during Pant |
| Suture (attached) | 1 aimed shot, blocked by rocks | Attack01 (shots @17f) | sideways, or a rock between |
| Suture (detached) | furious charge with momentum | Rage → Walk02 | sideways, late; it overshoots |

- **Kill order:** Suture first. The wiki's phase rule: if Contusion dies first, Suture detaches and charges. If Suture
  dies first, nothing changes.
- **Position:**
  - Circle the room centre at 180+ px from Contusion. That also keeps Isaac outside Suture's cord circle.
  - Never fight from a corner: it chases into Isaac and the baby swings around it.
- **Steven:**
  - The twins split at 50% of big Steven's HP anyway.
  - On death, big Steven fires two rows of 8 slow shots that pass over rocks. Be far away and step through a gap.
  - Steven Baby fires 8 outward when it dies.
- **Blighted Ovum:**
  - Ghost Suture (79.12) is invincible and dies with Contusion: never aim at it.
  - It fires a horizontal Brimstone whenever Isaac is level with it, so stay off its row.
  - Contusion leaves red creep and has no breather.
- **Champions:**
  - Blue: Suture's shots home.
  - Green: the twins start apart.

### The Haunt (260.0) and Lil Haunts (260.10)
Bench: timed out with 2 hits; died with 4 on a copy. Most hits were Lil Haunts.

- **HP:** 200 (Lil Haunt 25).
- **Floors:** Cellar.
- **Animations logged:**
  - Haunt: IdleSkin, AngrySkin, Peel (phase change), IdleNoSkin, LaserNoSkin, SpitNoSkin, AngryNoSkin.
  - Lil Haunts: Idle, Float, FloatChase, Shoot.

**Phase 1:** the Haunt is invulnerable. Three Lil Haunts orbit it, and one at a time leaves to chase Isaac.
- The orbiting ones and the Haunt still hurt on touch, so keep 160+ px from the Haunt.
- Fight the chasing Lil Haunt (kill first; 25 HP) away from the Haunt.
- The Lil Haunt mirrors Isaac's movement and stops to fire a blood shot *led* at where Isaac will be (Shoot @4f).
  Turn or stop when it slows down (`change_direction`); keeping the same direction walks into it.

**Phase change** (last Lil Haunt dead): AngrySkin → Peel. It moves to the upper wall, and the move can hit, so get
out of its way.

**Phase 2:** it slides left and right along the top wall.

| Attack | Tell | Dodge |
|---|---|---|
| Brimstone down its column | IdleNoSkin → LaserNoSkin (2 logged hits) | sideways: stay 60+ px off its moving column |
| 5 blood shots, downward fan | SpitNoSkin @3f | away: low in the room the gaps are wide |
| Dash at Isaac | Isaac near the top wall | stay in the bottom half |

- **Shooting spot:** lower half of the room, offset from its column, shooting up and leading it as it slides.
- **Trick:** it can get stuck trying to reach a spot, and then it stops attacking.
- **Champions:**
  - Black: 2 Lil Haunts; spiders instead of the laser.
  - Pink: 1 Lil Haunt; phase 2 has 100 HP, two diagonal lasers that bounce once, and 8 aimed shots.

### Gurglings (237.1) and Turdlings (237.2)
Bench: cleared in 89 s with 3 hits (2 red creep, 1 body).

- **HP:** 60 each (Turdlings 50).
- **Floors:** Basement, Burning Basement.
- **Animations logged:** WalkLeft, WalkRight, WalkVert, ChargeLeft/Right/Up/Down, Stop, Appear.

| Attack | Tell | Dodge |
|---|---|---|
| Cardinal rush to the wall | **none**: Walk* goes straight to Charge* when Isaac lines up | pre-emptive: stay off both Gurglings' rows and columns (diagonal) |
| Red creep along the dash path | any Charge* | treat the path as a wall for a few seconds |
| (Turdlings) 4 Brownie Corns in the cardinal directions after the wall hit | Stop | get off its row and column again |
| (Turdlings) fart knockback | after a wall hit | away |

- **Attack windows:** Stop (it pauses at the wall and spawns 0-2 Attack Flies), and while walking.
- **Adds:** kill Attack Flies when close. A fly in a Gurgling's path stops its dash.
- **With two of them:** if Isaac must share a line, share it with the farther one.
- **Trick (inferred, test it):** at long range, step onto its line and straight back off. It rushes into the wall and
  Stops, giving a free window. The slow bench clear was missed windows (60 HP each), not toughness.
- **Champions:**
  - Black: troll bombs instead of creep.
  - Yellow: three of them, faster, no creep.

### Sloth (46.0, miniboss)
Bench: timed out with 5 hits; 7 of its 8 logged hits were its shot.

- **HP:** 80-220 by stage.
- **Floors:** any floor 1-2 miniboss room.
- **Animations logged:** WalkHori, WalkVert, Attack, Appear.

| Attack | Tell | Dodge |
|---|---|---|
| Ipecac shot: lobbed explosive, aimed at Isaac's spot, hurts where it lands | Attack @5f | no_reverse: keep moving one way; stay 60+ px from the predicted landing |
| Charger spawn: charges horizontally the way Sloth faces | Attack | never stand on Sloth's row |

- **Why the bot misread it:** logged hits came during WalkHori/WalkVert, after the Attack. The shot is in the air for
  a while, which is why the bot saw danger 0.
- **Wiki strategy:** keep moving in one direction. Doubling back to dodge Chargers is what gets players hit by the
  Ipecac.
- **Distance and adds:** 160 px. Kill Chargers (23.0) and Attack Flies when close. It often comes with 2 Chargers,
  Splashers or Attack Flies.

### Mega Fatty (264.0)
Bench: 3 hits on a Caves I copy, all from its blood bursts at 85-92 px.

- **HP:** 600.
- **Floors:** Caves, Flooded Caves (not floors 1-2, but on the bench).
- **Animations logged:** Idle, Jumping, Landing, Sucking, Puking, Fart.

| Attack | Tell | Dodge |
|---|---|---|
| Off-screen leap onto Isaac, then a big red creep puddle | Jumping | keep moving until Landing, then off the creep |
| Short slide + hop toward Isaac | slides | sideways |
| Inhale: pulls Isaac in | Sucking | walk straight away for the whole animation |
| Vomit rain: shots go up and fall following Isaac | Sucking → Puking @3f | keep moving, never stop |
| Fart: hurts up close, then 1-3 Dips or a shot cluster | Idle → Fart @21f | away (keep 170 px) |

- **Attack windows:** Idle, Landing, Fart (from range).
- **Adds:** Dips: kill when close.
- **Champions:**
  - Brown: rock waves, no vomit.
  - Red: smaller; 6 shots on landing; 4 shot streams.

---

## Other floor 1-2 bosses (brief)

| Boss (id) | HP | Keep | Lanes / zone | Key dodges | Adds |
|---|---|---|---|---|---|
| Monstro (20.0) | 250 | 160 | open, no corners | spit cluster: sideways; off-screen jump: keep moving, then 120+ px from the landing ring | kill close |
| Larry Jr. (19.0) | 22/seg | 100 | open | never in front of the head on its line; don't get boxed in by body and poop | — |
| Duke of Flies (67.0) | 110 | 150 | centre, no corners | it sends flies out at 5-6 orbiting: keep the fly count down | flies: kill close; 6 more on death |
| Widow (100.0) | 130 | 160 | open | long leap: keep moving; white creep slows: off creep | Sacks 30.2, Spiders 85.0: kill close |
| Pin (62.0) | 100 | 150 | open | under: never stand still; red lob (Attack1 @47f): no_reverse; it jumps out of the same spot after the shot | — |
| Baby Plum (908.0) | 234 | 180 | centre, off her 8 lines for the slam | stream: sideways; spiral: circle with it; slam rings: away | — (death ring of 10) |
| Famine (63.0) | 240 | 160 | **off its row**, mid-room | horizontal charge; phase 2 head 3-shot spread: move slowly up/down | Pooters: kill close |
| The Fallen (81.0) | 105-420 | 170 | **diagonal** when it halts | 3+4 spreads: sideways; 4-way cardinal Brimstone after the chase | splits at 50%: kill both |
| Headless Horseman (82.0 body, 83.0 head) | — | 160 | **off the head's row** | head side charges ×1-3; body's lobbed red shots leave creep: no_reverse | — |
| Little Horn (404.0) | 200 | 120 | keep moving | pits under Isaac; troll bombs pop up near Isaac: 100+ px away | Dark Ball: kill close |
| Rag Man (405.0) | 200 | 170 | rocks between | homing shots 1/3/5: behind_rocks; rolling head: sideways | Raglings die with it: focus Rag Man |
| Lil Blub (901.0) | 200 | 180 | open | 6 streams: far, between them; low-HP jump chain: keep moving | Small Leeches 810: kill close; death rain |
| The Rainmaker (902.0) | 240 | 180 | open | 2 lines of 6 from the edges: move vertically; rings and bursts: away | — |
| Min-Min (913.0) | 280 | 170 | off the floor lights | Willo ring shots: away; ring chase: keep moving; vanish attack | Willos 808: ignore (die with her) |
| Wormwood (62.3) | 200 | 150 | diagonal when it lunges | lunge 4 cardinal shots; below 33% it pierces Isaac's spot 3-6×: keep moving | leeches: kill close |
| Clog (914.0) | 420 | 160 | open | spiral lines: circle through the gaps; fart lines knock back | **Drips 870: kill first** (they enable the water spin) |
| Colostomia (917.0) | 380 | 170 | **off row and column** | hop + slide on the nearest cardinal line; explosive gas: never near bombs; phase 2 jumps: away | — |
| Turdlet (918.0) | 190 | 170 | no corners | huddle (~7 s) → tail launch: get far | — (splits at 30 HP) |

**Minibosses:**
- **Lust:** turn often so it can't build speed; tears barely knock it back.
- **Wrath:** throws a bomb when it can see Isaac. Use rocks to block its view and keep 100 px from bombs.
- **Gluttony:** a belly Brimstone when Isaac is on a cardinal line, so stay diagonal. It also fires 8-way shots, so
  keep distance.
- **Greed:** 3-shot spreads in the cardinal direction nearest Isaac, so stay diagonal. Kill its Hoppers.
- **Envy:** stay mid-room, away from corners. Its heads split 3 times and get faster.
- **Pride:** X-shaped lasers, so stand on its row or column, never its diagonals. It spawns troll bombs in random
  spots, so stay away from them.
- **Krampus (Devil Room):** 4 Brimstones that can rotate 90°, plus a dash before the rotating version. Keep moving.

---

## Sources

Wiki pages (bindingofisaacrebirth.wiki.gg, read 2026-11-25):
- Bench bosses:
  [Dingle](https://bindingofisaacrebirth.wiki.gg/wiki/Dingle) ·
  [Dangle](https://bindingofisaacrebirth.wiki.gg/wiki/Dangle) ·
  [Gemini](https://bindingofisaacrebirth.wiki.gg/wiki/Gemini) ·
  [Steven](https://bindingofisaacrebirth.wiki.gg/wiki/Steven) ·
  [Blighted Ovum](https://bindingofisaacrebirth.wiki.gg/wiki/Blighted_Ovum) ·
  [The Haunt](https://bindingofisaacrebirth.wiki.gg/wiki/The_Haunt) ·
  [Lil' Haunt](https://bindingofisaacrebirth.wiki.gg/wiki/Lil%27_Haunt) ·
  [Gurglings](https://bindingofisaacrebirth.wiki.gg/wiki/Gurglings) ·
  [Turdlings](https://bindingofisaacrebirth.wiki.gg/wiki/Turdlings) ·
  [Sloth](https://bindingofisaacrebirth.wiki.gg/wiki/Sloth) ·
  [Mega Fatty](https://bindingofisaacrebirth.wiki.gg/wiki/Mega_Fatty)
- Basement, Cellar and Burning Basement bosses:
  [Monstro](https://bindingofisaacrebirth.wiki.gg/wiki/Monstro) ·
  [Larry Jr.](https://bindingofisaacrebirth.wiki.gg/wiki/Larry_Jr.) ·
  [The Duke of Flies](https://bindingofisaacrebirth.wiki.gg/wiki/The_Duke_of_Flies) ·
  [Gurdy Jr.](https://bindingofisaacrebirth.wiki.gg/wiki/Gurdy_Jr.) ·
  [Widow](https://bindingofisaacrebirth.wiki.gg/wiki/Widow) ·
  [Pin](https://bindingofisaacrebirth.wiki.gg/wiki/Pin) ·
  [Baby Plum](https://bindingofisaacrebirth.wiki.gg/wiki/Baby_Plum) ·
  [Famine](https://bindingofisaacrebirth.wiki.gg/wiki/Famine) ·
  [The Fallen](https://bindingofisaacrebirth.wiki.gg/wiki/The_Fallen) ·
  [Headless Horseman](https://bindingofisaacrebirth.wiki.gg/wiki/Headless_Horseman) ·
  [Little Horn](https://bindingofisaacrebirth.wiki.gg/wiki/Little_Horn) ·
  [Rag Man](https://bindingofisaacrebirth.wiki.gg/wiki/Rag_Man)
- Downpour and Dross bosses:
  [Lil Blub](https://bindingofisaacrebirth.wiki.gg/wiki/Lil_Blub) ·
  [The Rainmaker](https://bindingofisaacrebirth.wiki.gg/wiki/The_Rainmaker) ·
  [Min-Min](https://bindingofisaacrebirth.wiki.gg/wiki/Min-Min) ·
  [Wormwood](https://bindingofisaacrebirth.wiki.gg/wiki/Wormwood) ·
  [Clog](https://bindingofisaacrebirth.wiki.gg/wiki/Clog) ·
  [Colostomia](https://bindingofisaacrebirth.wiki.gg/wiki/Colostomia) ·
  [Turdlet](https://bindingofisaacrebirth.wiki.gg/wiki/Turdlet)
- Minibosses:
  [Lust](https://bindingofisaacrebirth.wiki.gg/wiki/Lust) ·
  [Wrath](https://bindingofisaacrebirth.wiki.gg/wiki/Wrath) ·
  [Gluttony](https://bindingofisaacrebirth.wiki.gg/wiki/Gluttony) ·
  [Greed](https://bindingofisaacrebirth.wiki.gg/wiki/Greed) ·
  [Envy](https://bindingofisaacrebirth.wiki.gg/wiki/Envy) ·
  [Pride](https://bindingofisaacrebirth.wiki.gg/wiki/Pride) ·
  [Krampus](https://bindingofisaacrebirth.wiki.gg/wiki/Krampus)
- Floor pages:
  [Basement](https://bindingofisaacrebirth.wiki.gg/wiki/Basement) ·
  [Cellar](https://bindingofisaacrebirth.wiki.gg/wiki/Cellar) ·
  [Burning Basement](https://bindingofisaacrebirth.wiki.gg/wiki/Burning_Basement) ·
  [Downpour](https://bindingofisaacrebirth.wiki.gg/wiki/Downpour) ·
  [Dross](https://bindingofisaacrebirth.wiki.gg/wiki/Dross)
- Read, but no boss tips for these bosses (it only covers which items work on them):
  [The Lost (Strategy)](https://bindingofisaacrebirth.wiki.gg/wiki/The_Lost_(Strategy))

Guides and players (only partly readable):
- Dingle: [Bamboo Gaming, Dingle](https://www.bamboogaming.net/the-binding-of-isaac/bosses/dingle). Seen only through
  a search summary; the page itself refused automated reads. Tips: keep a turning lane open, dodge across each dash,
  attack after the sequence.
- The Haunt: [Bamboo Gaming, The Haunt](https://www.bamboogaming.net/the-binding-of-isaac/bosses/the-haunt). Search
  summary only. Tips: keep space from the ghosts, leave the upper wall to the boss.
- Sloth: [Binding of Isaac wiki (fandom), Sloth](https://bindingofisaac.fandom.com/wiki/Sloth). Search summary only.
  Tip: keep moving one way; doubling back gets you hit by the Ipecac.
- Famine: [Steam discussion](https://steamcommunity.com/app/250900/discussions/0/3122660456793418717). Phase 1: stay
  mid-room; phase 2: move slowly up and down.
- No-hit videos, title only (no description or transcript readable):
  [All 122 Bosses, No Hit](https://www.youtube.com/watch?v=JLvaW-zUs5g) ·
  [All Bosses, No Damage / Hard Mode](https://www.youtube.com/watch?v=sScz3U-eWsY) ·
  [Dingle, minimal items (Repentance+)](https://www.youtube.com/watch?v=oX-HqHJ9z1Q).
  Watching these frame by frame (e.g. with `tools/look.py`-style frame grabs) would be the next step for the tricks
  the text sources don't give.

The bot's own data: `knowledge/tells.dat`, `knowledge/telegraphs.txt` (animation names, shot frames, hits per
animation), `knowledge/bench_rooms.json` (hit causes per bench room).
