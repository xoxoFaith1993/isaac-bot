# Enemy cards: the format (forecast plan step 1)

One card per enemy in `knowledge/enemy_cards.json`. A card holds **game facts as plain numbers and words** (never
decompiled code), each with its label, plus a small machine-readable part the forecast (`mod/isaac-bot/forecast.lua`)
uses to predict where the enemy and its attacks will be. `tools/build_cards.py` turns the JSON into
`mod/isaac-bot/cards.lua` (the game's Lua can't read JSON files).

Units: **px per update**, **updates** (30 updates = 1 s), angles in degrees (0 = right, 90 = down). y grows downward.

```json
{
  "version": 1,
  "cards": {
    "29.1": {
      "name": "Trite",
      "same_as": ["29.0"],
      "move":    { "kind": "hop", "speed": 0, "notes": "..." },
      "attacks": [ { "kind": "...", "...": "..." } ],
      "body":    { "no_damage_states": [4], "flying": false },
      "terrain": { "creep": null, "pull": null },
      "facts": [
        { "cat": "move", "text": "Hops to the cell in TargetPosition; lands ~N updates after the jump starts",
          "src": "RE_ENEMIES Trite 0x52cd30", "checked": "2 readers" }
      ]
    }
  }
}
```

## `facts` (the human-readable part, always filled)

Every fact the RE notes give for this enemy, in one short sentence with its numbers.
- `cat`: `move` / `attack` / `timing` / `body` / `terrain`.
- `src`: which notes section and function address (e.g. `RE_ENEMIES E3 0x46f2a0`).
- `checked`: `1 reader` / `2 readers` / `recording` / `contradicted` (copy the label from the notes; for a
  contradicted fact, give the corrected value in `text` and say what the reading got wrong).

## `move` (where its BODY goes; contact hits)

`kind` is one of these, with its parameters (leave out any it doesn't need; `speed` is the steady px per update):

| kind | meaning | parameters |
|---|---|---|
| `pinned` | never moves (Gurdy, Gaping Maw, Haunt on its wall) | - |
| `chase` | straight at Isaac's current position | `speed` |
| `path_chase` | toward Isaac by the grid path; straight when within 70 px with a clear line | `speed` |
| `lead_chase` | toward Isaac's position + `lead` × his velocity | `speed`, `lead` |
| `wander` | slow random drift, not toward Isaac | `speed` |
| `axis_walk` | straight runs along an axis, stops at walls, not toward Isaac | `speed` |
| `bounce` | keeps its direction, bounces off walls (diagonal bouncers: Envy, the Duke) | `speed` |
| `dart` | picks a point (Isaac + 10 x his velocity, or a random spot) and darts there without re-aiming, then idles; the point is its `TargetPosition` while darting (spiders) | `dart_speed`, `dart_friction`, `stop` (fitted from recordings) |
| `hop` | jumps to a cell (its `TargetPosition`), harmless in the air, lands after `air` updates | `air` |
| `charge_line` | idles or wanders; charges along its row/column when Isaac is within `band` px of it and within `range` px (checked `lead` updates ahead), until a wall | `speed`, `band`, `range`, `lead`, `idle_speed` |
| `orbit` | circles a parent or point | `radius`, `speed` |
| `burrow` | underground then surfaces near Isaac | `speed` |
| `tethered` | moves with a parent (Gemini's baby), within `radius` | `radius`, `speed` |

Optional for any kind: `friction` (per-update velocity factor), `phases` (a list of `{state, kind, speed, updates}`
when it switches between kinds by AI state, e.g. Gemini's walk / rage / tired).

## `attacks` (shots, lasers, bombs, spawns: everything that isn't its body)

| kind | parameters |
|---|---|
| `aimed` | `speed`, `count` (1), `range`, `needs_line` (true/false), `cooldown` |
| `spread` | `count`, `angle` (degrees between shots), `speed`, `range`, `needs_line`, `cooldown` |
| `ring` | `count` (4/8/N), `speed`, `fixed` (true = fixed angles, not aimed) |
| `burst` | boss burst: `count`, `speed_min`, `speed_max`, `cone` (degrees), `lobbed` |
| `lob` | `fall` (the arc: height, falling speed, gravity), `blast` (px) |
| `laser_axis` | along its row/column: `trigger_band` (px), `range`, `warning` (updates) |
| `laser_diag` | diagonal beams: `warning` |
| `charge` | (when the charge is an attack of a non-`charge_line` mover) `speed`, `trigger` |
| `bomb` | `blast` (px), `fuse` (updates), `thrown_speed` |
| `spawn` | what it spawns (`"18.0"` etc.) and when |
| `pull` | see `terrain.pull` |
| `laser_aimed` | a laser aimed at Isaac (The Frail): `warning` |
| `slam` | a ground slam around itself (Hard Host): `radius` |
| `contact` | hurts on touch only (hazards, creep): `damage` |

Common optional fields for any attack: `tell` = `{ "anim": "Attack01", "frame": 17 }` (when the attack actually
fires), `state` (the AI state it fires in), `chance` (e.g. "1/7 per decision"), `when` (one plain sentence).

## `body`

`no_damage_states` (AI states it takes no damage in), `flying` (ignores rocks and pits), `size` if known,
`contact` (false if touching it doesn't hurt).

## `terrain`

- `creep`: `{ "variant": "red", "every": 7, "while": "speed > 3", "scale": 1.23 }` (a trail it leaves).
- `pull`: `{ "radius": 300, "strength": 0.6, "line_of_sight": false, "cycle": [150, 90] }` (Gaping Maw).
- `poop`: anything it places that blocks movement.

Reference cards that aren't enemies (`player.isaac`, `rule.projectiles`, `rule.contact`) hold Isaac's own numbers and shared rules; the forecast never looks them up by enemy key.

## Checking a card

`powershell -File tools\card_check.ps1` builds `cards.lua` and runs every card's body forecast against the recordings (`runs/recorder/CARD_CHECK.md`). A card WORSE than plain coasting points at its `move` facts: fix the card if it's a transcription slip, or queue a targeted second read of that one function. First run (2026-11-26): the Haunt (`pinned`, really moves along the wall) and the Big Spider (`lead_chase`, really darts to a fixed point) were caught and fixed; the spider's forecast is now 2.5x closer than coasting.

## What the forecast uses today (step 1)

Only `move` (the body's position over the next ~35 updates) and `body.no_damage_states`. Attacks and terrain are
filled in now so steps 2-3 can use them without re-reading the notes.
