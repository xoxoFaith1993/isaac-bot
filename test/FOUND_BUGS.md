# Bugs found by the offline tests

Real problems in the bot's current code, found by `test\tests.lua`. They're written up here instead of fixed
because the test session doesn't touch `mod\`. Each has a KNOWN test at the bottom of `tests.lua`. A KNOWN result
doesn't block `tools\reload.ps1`. When the fix lands, the test prints `FIXED?`: check it, then move it into the
normal tests and add a proof entry in `mutants.lua`.

Found 2026-11-25 against the mod as it was that afternoon (nav.lua ~909 lines, reflex.lua ~1272).
Open: #3 (the 1.1.51 sandwich cost doesn't steer yet). #1 and #2 were fixed in 1.1.41.

## 1. RESOLVED in 1.1.41: the two-room bounce came back when both rooms had a dead door, and the log flooded

**Resolved (1.1.41, main session):** the forgive step now forgives only weak reasons (not "locked, no key" or
"rocks in the way"), once per situation (orgaveSig = floor + keys + bombs + health), with one note. Now test 28
("no bounce between two rooms with a locked door each") measures 1 room change and 2 notes in 60 s. Proof entries:
forgiving locked write-offs (2 changes = fails), and forgiving every time (fails).

**Original write-up:**

**Where:** `nav.lua`, `chooseGoal`, the new block
`if not hop and next(deadEdge) then ... "nothing to do: forgave all written-off doors"` (around line 595).

**Scenario (K1):** room A (84) has a locked door to treasure room 83. Room B (85) has a locked door to treasure
room 86. A and B are joined. No keys, and nothing else is left on the floor.

**What happens:** in B, door 86 is written off and there's nothing left, so it forgives every written-off door.
A's door to 83 is then "possible" again, so it goes to A. In A, door 83 is written off, and nothing is left again:
it forgives everything, B's door 86 is possible again, and it goes back to B. That's the 1.0.8 bounce. The loop
breaker stops it after 8 entries, but only for its 25 s window, and then it starts again.
Measured: **22 room changes in 60 s.** If crossing a room takes over ~3 s, 8 entries never fit into 25 s and
the loop breaker never fires at all.

**Second symptom, the log:** inside one update, the loop of up to 6 tries runs
"write off → nothing left → forgive all → try again → write off...". That's up to 4 `Nav.onNote` calls per update.
Measured: **5,003 nav notes in 60 s**, and each one is a `send("nav", ...)` from main.lua.

**Third, milder:** in the plain one-locked-door case (test 7), once everything else is explored, it walks all the
way back to the locked door it already wrote off, though nothing changed (same keys, bombs and health). Then it
stands there with the note spam above.

**Keep in mind:** test 27 ("only exit written off: still takes it") checks the forgiving that 1.1.36 added on
purpose. A fix for K1 has to keep test 27 passing. Test 27's door was written off for a weak reason ("walking there
failed"); K1's doors were written off as "locked, no key", with the key count unchanged.

**Possible fix (for the main session to decide):** forgive only once per "nothing changed" state, for example
only if keys, bombs or health went up since the door was written off (the per-door forgiveness `edgeDead` already
does that), or at most once per N seconds per floor. Don't forgive doors whose reason is "locked, no key" while the
key count is unchanged. Also print the note once per state change, not every update.

## 2. RESOLVED in 1.1.41: no spray shot down a corridor at a target that's roughly in line

**Resolved (1.1.41, main session):** loose aim tries the chosen direction, then all 4, with the lane taken from
Isaac's real position along that direction. Now test 29 ("sprays down a corridor...") fires 6 of 6 updates. Proof
entry: only the chosen direction (fails).

**Original write-up:**

**Where:** `reflex.lua`, `Reflex.update`, the shooting part. The axis comes from `bestLane(room, player.Position, tp)`,
and then the loose-aim rule (`S.loose_aim`) only checks that one direction.

**Scenario (K2):** Isaac is in a one-tile-high corridor (rock above and below). A spider sits 200 px to the right,
30 px below his row (they hop about).

**What happens:** `bestLane` judges the row lane from `(Isaac.X, target.Y)`. That's inside the corridor's rock,
so the row counts as "blocked" and it picks the column: shoot **down**. The loose-aim check then asks whether the
target is roughly in line DOWNWARD. It isn't (it's 200 px to the side), so no shot. Measured: **0 shots in 6
updates**. A tear fired right would pass 30 px from the spider, exactly the spray loose_aim was added for.
In an open room this is hidden: walking sideways curves the tear onto the target, so it fires anyway.

**Possible fix:** let the loose-aim rule try the direction the target actually lies in (the 4 directions, the
way the run-and-gun `any_shot` check already does), with the lane taken from Isaac's real position.

Low priority (narrow spots only), but it's the "way too carefully vs spiders" symptom again.

## Observation (not confirmed, no test): a corner held for a full 3 s with six enemies circling the middle

While building test 30 (1.1.47 code): six fast enemies circling the room centre at 110 px. Starting by the
top-left corner, Isaac stayed within 80 px of the corner for all 90 measured updates (about 45 px from it on
average), even with the 1.1.46 fixes. Other starts and layouts were fine. In the fake, the enemies never leave
their circle, so the corner really is safe there. It may just be the fake. Worth a look on the real-room bench if
corner hits continue.

## 3. OPEN (1.1.51): the sandwich cost fires but doesn't make it step out from between two chasers (K3)

**Where:** `mover.lua` `total()`, the `S.m_pincer` / `S.pincer_r` block.

**Scenario (K3):** Isaac is in the middle of an open room. Two Gapers chase him from the left and right along
his row, starting 170/200/230 px away, at speeds 2.0/2.6/3.2 (9 cases). Expected: within ~1.2 s he steps 30+ px
off the line between them.

**Measured (2026-11-25, aggregate of 18 runs per setting, same scenario):**

| m_pincer / pincer_r | avg off-line at 1 s | out from between them by 2.5 s | a run with a touch |
|---|---|---|---|
| 0 / 160 (rule off) | 8.1 px | 11/18 | 1 |
| 200 / 160 (1.1.51) | 9.4 px | 12/18 | 0 |
| 400 / 160 | 10.0 px | 10/18 | 0 |
| 200 / 220 | 10.3 px | 10/18 | 0 |
| 800 / 160 | 10.6 px | 11/18 | 0 |

The K3 test itself (its own chaser type, one warm-up chase): 0 of 9 cases get 30+ px off the line inside the suite,
and 2 of 9 run alone. With `m_pincer = 0` alone it's 1 of 9.

**A clue:** when the chasers were Gapers whose reach the mover had already learned from the fast circling Gapers of
test 30 (a much bigger "could be here" circle), the same scenario went **9 of 9**. So the rule can steer when the
zones are big and close. With the reach of an ordinary slow chaser, it doesn't.

**Why (checked by counting inside the rule):** it does fire. Both chasers' t=20 zones are flagged `mover`, and
in one 2 s run about 1,600 plan ends got the cost. But "opposite sides" (cosine < -0.5, i.e. more than 120° apart)
is still true well off the line. With the enemies 150 px left and right, a plan end 60 px above the line sees
them ~136° apart. So nearly every reachable plan end pays about the same cost, scaled only by closeness, and moving
off the line hardly lowers it. Raising the weight doesn't help either, because the difference between plans
stays small.

**Possible direction (main session's call):** make the cost fall off with the distance from the line between the
two zones, e.g. `m_pincer * closeness * max(0, 1 - perp / pincer_w)`, or use the angle itself (full cost only
near 180°). Then stepping off the line pays and it steers. Re-check the corner test (#30) after any change.