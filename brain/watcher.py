"""Live watcher: learns from the bot's own play without someone watching (the author, 2026-11-25: "an active watcher
that looks for loops and damage taken and figures out what needs to be done differently... so it gets smarter as it
plays without constant hand holding").

Runs inside the helper (no extra window). It gets every message from the mod and every snapshot, and:

1. LOOPS: spots them live and nudges the bot.
   - bounce: walking back and forth between the same 2 rooms -> writes that door off for a while ("deadhop").
   - stall: walking (not fighting) but standing in one spot for 20 s -> asks the bot to re-plan.
   - fight stall: a fight where no enemy loses health for 60 s -> recorded (the in-game ladder acts on it).
   - revisits: the same room entered 6+ times on one floor -> recorded.
2. HITS: sorts every hit by CAUSE ("body:261.0" = touched Dingle, "shot:30" = a Boil's shot, creep, bomb, laser)
   and counts encounters per enemy type (rooms where it was present), so each cause has a rate: hits per encounter.
3. LESSONS: when a cause keeps hurting (3+ hits, 0.5+ per encounter), it makes ONE small, capped change for just
   that enemy: more berth from its body (+8 px per step), more margin around its shots (+4 px), and for bosses more
   distance (+20 px). After 4 more encounters it keeps the step only if that cause's rate dropped by a quarter;
   otherwise it undoes it. Lessons live in knowledge/lessons.json and go to the mod at start and when they change.
4. ESCALATION (Level C): what it can't fix with a setting (a repeating loop, a lesson that didn't help, a cause it
   has no setting for) goes into runs/watch/queue.jsonl with the evidence: log lines, the "why" lines, hit frames.
   A Claude session picks those up (tools/queue.py wait / list / done) and fixes them in code. At most 3 new
   problems an hour, and the same problem at most once every 2 hours.

Everything it does is written to runs/watch/REPORT.md (refreshed every minute) and logged as "watch" lines.
"""
import collections
import json
import re
import time
from pathlib import Path

MAX_STEP = 4
STEP = {"body": {"margin": 8}, "shot": {"pad": 4}}
BOSS_DIST_STEP = 20
TRIGGER_HITS, TRIGGER_RATE, TRIGGER_ENC = 3, 0.5, 3
JUDGE_AFTER_ENC = 4
QUEUE_PER_HOUR, QUEUE_SAME_KEY_S = 3, 2 * 3600


def hit_cause(body):
    """'261.0|1|x,y|move 3|via 261.0 d=..|shot 0 d=.. from=30|risk ..' -> ('shot', '30') / ('body', '261.0') ..."""
    parts = body.split("|")
    src = parts[0] if parts else "?"
    m = re.search(r"\|shot \S+ .*?from=(\d+)", body)
    if m and m.group(1) != "0":
        return "shot", m.group(1)
    t = src.split(".")[0]
    if t == "1000":
        return "creep", src
    if t == "4" or (src == "0.0" and len(parts) > 1 and parts[1].startswith("2")):
        return "bomb", src
    if t == "7":
        return "laser", src
    if t == "9":  # a shot we couldn't trace to its shooter
        return "shot", "?"
    return "body", src


class Watcher:
    def __init__(self, root, send, note, local_notes=True):
        self.root = Path(root)
        self.knowledge = self.root / "knowledge"
        self.dir = self.root / "runs" / "watch"
        self.dir.mkdir(parents=True, exist_ok=True)
        self.send, self.note = send, note
        self.local_notes = local_notes  # Level B: the local model writes a first diagnosis of each queued problem
        self.lessons_file = self.knowledge / "lessons.json"
        self.stats_file = self.dir / "stats.json"
        self.lessons = self._load(self.lessons_file, {})
        st = self._load(self.stats_file, {})
        self.hits = collections.Counter(st.get("hits", {}))          # cause -> hits (all time)
        self.enc = collections.Counter(st.get("enc", {}))            # enemy "type.var" and "type" -> encounters
        self.bosses = set(st.get("bosses", []))                      # enemy keys seen as bosses
        self.loops = collections.Counter(st.get("loops", {}))
        self.room_hist = collections.deque(maxlen=40)                # (time, room)
        self.room_now, self.room_seen = None, set()
        self.floor_rooms = collections.Counter()
        self.last_why, self.last_risk = "", ""
        self.recent = collections.deque(maxlen=60)                   # recent log-worthy lines for evidence
        self.still_since, self.still_pos = None, None
        self.fight_hp, self.fight_since = None, None
        self.loop_flags = {}                                          # loop key -> last time reported
        self.queue_times = collections.deque(maxlen=20)
        self.queue_keys = {}
        self.last_report = 0
        self.run_loops = collections.Counter()

    # ------------------------------------------------------------------ files
    @staticmethod
    def _load(fp, default):
        try:
            return json.loads(Path(fp).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return default

    def _save(self):
        self.knowledge.mkdir(exist_ok=True)
        self.lessons_file.write_text(json.dumps(self.lessons, indent=1), encoding="utf-8")
        self.stats_file.write_text(json.dumps({"hits": self.hits, "enc": self.enc, "bosses": sorted(self.bosses),
                                               "loops": self.loops}, indent=1), encoding="utf-8")

    # ------------------------------------------------------------------ to the mod
    def lessons_payload(self):
        """'261.0=12,0,40;30=0,8,0' -> key=body margin px, shot pad px, boss extra distance px"""
        out = []
        for key, ls in self.lessons.items():
            step = ls.get("step", 0)
            if step <= 0:
                continue
            kind, ekey = key.split(":", 1)
            margin = STEP["body"]["margin"] * step if kind == "body" else 0
            pad = STEP["shot"]["pad"] * step if kind == "shot" else 0
            dist = BOSS_DIST_STEP * step if ls.get("boss") else 0
            out.append(f"{ekey}={margin},{pad},{dist}")
        return ";".join(out)

    def send_lessons(self):
        self.send("lessons", self.lessons_payload())

    # ------------------------------------------------------------------ events
    def on_event(self, kind, body):
        now = time.time()
        if kind not in ("ping", "pong", "eyes"):
            self.recent.append(f"{time.strftime('%H:%M:%S')} {kind} {body[:220]}")
        if kind == "why":
            self.last_why = body
        elif kind == "risk":
            self.last_risk = body
        elif kind == "start":
            self.send_lessons()
            if "|reload|" not in body:
                self.run_loops.clear()
        elif kind == "floor":
            self.floor_rooms.clear()
        elif kind == "room":
            self._on_room(body, now)
        elif kind == "hit":
            self._on_hit(body)
        if now - self.last_report > 60:
            self.last_report = now
            self.write_report()

    def on_state(self, state):
        now = time.time()
        try:
            for e in state.get("e", []):
                key = f"{e[0]}.{e[1]}"
                self.room_seen.add(key)
                if len(e) > 8 and e[8]:
                    self.bosses.add(key)
            p = state["p"]
            pos = (p["x"], p["y"])
            bot = state.get("bot") or []
            fighting = bool(len(bot) > 1 and bot[1])
            self._stall(pos, fighting, now)
            self._fight_stall(state, fighting, now)
        except (KeyError, TypeError, IndexError):
            pass

    # ------------------------------------------------------------------ encounters
    def _on_room(self, body, now):
        # close the previous room visit: every enemy type seen there had one more encounter
        for key in self.room_seen:
            self.enc[key] += 1
            self.enc[key.split(".")[0]] += 1
        self.room_seen = set()
        room = body.split("|")[0]
        self.room_now = room
        if room == "-3":  # the bench's test room: it hops -3 <-> start room every round, that's not a bounce
            return
        self.room_hist.append((now, room))
        self.floor_rooms[room] += 1
        self.fight_hp, self.fight_since = None, None
        self._bounce(now)
        if self.floor_rooms[room] == 6:
            self._loop("revisits", f"room {room} entered 6 times on this floor", nudge=None)
        # judge lessons now that encounters moved on
        self._judge_lessons()

    # ------------------------------------------------------------------ loops
    def _loop(self, kind, detail, nudge, key=None):
        key = key or f"{kind}:{detail}"
        now = time.time()
        if now - self.loop_flags.get(key, 0) < 60:
            return
        self.loop_flags[key] = now
        self.loops[kind] += 1
        self.run_loops[key] += 1
        self.note(f"loop: {kind}: {detail}" + (f" -> {nudge[0]}|{nudge[1]}" if nudge else ""))
        if nudge:
            self.send(*nudge)
        with open(self.dir / "loops.jsonl", "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"when": time.strftime("%Y-%m-%d %H:%M:%S"), "kind": kind, "detail": detail,
                                 "nudge": nudge}) + "\n")
        if self.run_loops[key] >= 2 or kind == "fight stall":
            self.escalate("loop", key, f"{kind} again: {detail}", tried=f"nudged with {nudge}" if nudge else "")
        self._save()

    def _bounce(self, now):
        # 4 minutes, not 45 s: the 2026-11-25 bounce (rooms 100/87) took 21 s a trip and slipped under a 45 s window
        recent = [r for t, r in self.room_hist if now - t < 240]
        # exactly TWO rooms (a death restarts in the same start room twice: "bounce 84-84" was a false alarm)
        if len(recent) >= 6 and len(set(recent[-6:])) == 2:
            a, b = recent[-1], recent[-2]  # in a, came from b: write off going BACK to b (one direction only)
            pair = "-".join(sorted((a, b)))
            self._loop("bounce", f"between rooms {pair}", nudge=("deadhop", f"{a}>{b}"), key=f"bounce:{pair}")

    def _stall(self, pos, fighting, now):
        if fighting:
            self.still_since = None
            return
        if self.still_pos and abs(pos[0] - self.still_pos[0]) < 20 and abs(pos[1] - self.still_pos[1]) < 20:
            if self.still_since and now - self.still_since > 20:
                self._loop("stall", f"standing still in room {self.room_now} at {pos}", nudge=("rescue", "replan"),
                           key=f"stall:{self.room_now}")
                self.still_since = now
        else:
            self.still_pos, self.still_since = pos, now

    def _fight_stall(self, state, fighting, now):
        if not fighting:
            self.fight_hp, self.fight_since = None, None
            return
        hp = sum(float(e[6]) for e in state.get("e", []) if len(e) > 6)
        if self.fight_hp is None or hp < self.fight_hp - 0.5:
            self.fight_hp, self.fight_since = hp, now
        elif now - self.fight_since > 60:
            names = sorted({f"{e[0]}.{e[1]}" for e in state.get("e", [])})
            self._loop("fight stall", f"room {self.room_now}: no damage dealt for 60 s vs {', '.join(names)}",
                       nudge=None, key=f"fightstall:{self.room_now}")
            self.fight_since = now

    # ------------------------------------------------------------------ hits and lessons
    def _on_hit(self, body):
        kind, ekey = hit_cause(body)
        cause = f"{kind}:{ekey}"
        self.hits[cause] += 1
        ls = self.lessons.get(cause)
        if ls and ls.get("status") == "trying":
            ls["hits_since"] = ls.get("hits_since", 0) + 1
        self._maybe_lesson(cause, kind, ekey)
        if kind in ("creep", "bomb", "laser") or ekey == "?":
            if self.hits[cause] >= 5 and self.hits[cause] % 5 == 0:
                self.escalate("hits", cause, f"{self.hits[cause]} hits from {cause} (no setting to learn for it)")
        self._save()

    def rate(self, kind, ekey):
        enc = self.enc.get(ekey if kind == "body" else ekey, 0) or self.enc.get(ekey.split(".")[0], 0)
        return self.hits.get(f"{kind}:{ekey}", 0) / max(1, enc), enc

    def _maybe_lesson(self, cause, kind, ekey):
        if kind not in STEP or ekey == "?":
            return
        rate, enc = self.rate(kind, ekey)
        ls = self.lessons.get(cause, {"step": 0, "status": "new", "history": []})
        if ls.get("status") in ("trying", "didn't help", "maxed"):
            return  # being judged, or settings can't fix it: it's in the code-fix queue
        if self.hits[cause] < TRIGGER_HITS or enc < TRIGGER_ENC or rate < TRIGGER_RATE:
            return
        if ls["step"] >= MAX_STEP:
            if ls.get("status") != "maxed":
                ls["status"] = "maxed"
                self.lessons[cause] = ls
                self.escalate("lesson", cause, f"{cause}: max berth reached and still {rate:.2f} hits per encounter")
            return
        ls["step"] += 1
        ls.update(status="trying", boss=ekey in self.bosses, rate_before=round(rate, 3),
                  enc_at=self.enc.get(ekey, 0) or self.enc.get(ekey.split(".")[0], 0), hits_since=0)
        ls["history"].append({"when": time.strftime("%Y-%m-%d %H:%M"), "step": ls["step"], "rate": round(rate, 3)})
        self.lessons[cause] = ls
        self.note(f"lesson: {cause} hurts {rate:.2f} per encounter -> step {ls['step']} "
                  f"({'more berth' if kind == 'body' else 'more shot margin'}{', boss distance' if ls['boss'] else ''})")
        self.send_lessons()

    def _judge_lessons(self):
        changed = False
        for cause, ls in self.lessons.items():
            if ls.get("status") != "trying":
                continue
            kind, ekey = cause.split(":", 1)
            enc_now = self.enc.get(ekey, 0) or self.enc.get(ekey.split(".")[0], 0)
            n = enc_now - ls.get("enc_at", 0)
            if n < JUDGE_AFTER_ENC:
                continue
            new_rate = ls.get("hits_since", 0) / n
            if new_rate < ls.get("rate_before", 1) * 0.75:
                ls["status"] = "kept"
                self.note(f"lesson kept: {cause} {ls['rate_before']:.2f} -> {new_rate:.2f} per encounter at step {ls['step']}")
            else:
                ls["step"] -= 1
                ls["status"] = "didn't help"
                self.note(f"lesson undone: {cause} still {new_rate:.2f} per encounter (was {ls['rate_before']:.2f})")
                self.escalate("lesson", cause, f"{cause}: more berth didn't help ({ls['rate_before']:.2f} -> "
                              f"{new_rate:.2f} hits per encounter)", tried=f"step {ls['step'] + 1}")
            ls["history"].append({"when": time.strftime("%Y-%m-%d %H:%M"), "judged": round(new_rate, 3),
                                  "status": ls["status"]})
            changed = True
        if changed:
            self.send_lessons()
            self._save()

    # ------------------------------------------------------------------ Level C: the queue for code fixes
    def escalate(self, kind, key, summary, tried=""):
        now = time.time()
        if now - self.queue_keys.get(key, 0) < QUEUE_SAME_KEY_S:
            return
        while self.queue_times and now - self.queue_times[0] > 3600:
            self.queue_times.popleft()
        if len(self.queue_times) >= QUEUE_PER_HOUR:
            return
        self.queue_times.append(now)
        self.queue_keys[key] = now
        frames = sorted((self.root / "runs" / "hitframes").glob("*"), key=lambda p: p.name)[-3:]
        entry = {"id": time.strftime("%Y%m%d-%H%M%S"), "when": time.strftime("%Y-%m-%d %H:%M:%S"), "status": "open",
                 "kind": kind, "key": key, "summary": summary, "tried": tried, "room": self.room_now,
                 "why": self.last_why, "risk": self.last_risk, "evidence": list(self.recent)[-40:],
                 "frames": [str(f) for f in frames]}
        with open(self.dir / "queue.jsonl", "a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry) + "\n")
        self.note(f"queued for a code fix: {summary}")
        if self.local_notes:
            self._local_note(entry)

    # ------------------------------------------------------------------ Level B: the local model's first read
    def _local_note(self, entry):
        """In the background (the helper must keep moving): ask the local model for a plain-English diagnosis and save
        it next to the queue entry (runs/watch/notes/<id>.json). The model unloads 45 s after answering."""
        import threading

        def work():
            notes = self.dir / "notes"
            notes.mkdir(exist_ok=True)
            try:
                import rescue_brain
                note = rescue_brain.diagnose(entry)
                note["model"] = rescue_brain.MODEL
            except Exception as exc:  # no Ollama, timeout, bad JSON: the queue entry stands on its own
                note = {"error": f"{exc.__class__.__name__}: {exc}"[:200]}
            (notes / f"{entry['id']}.json").write_text(json.dumps(note, indent=1), encoding="utf-8")
            if "cause" in note:
                self.note(f"local diagnosis for {entry['key']}: {note['cause'][:160]}")

        threading.Thread(target=work, daemon=True).start()

    # ------------------------------------------------------------------ report
    def write_report(self):
        lines = ["# Watcher report", "", f"Updated {time.strftime('%Y-%m-%d %H:%M:%S')}.", "",
                 "## Hit causes (all time)", "", "| Cause | Hits | Encounters | Per encounter | Lesson |",
                 "|---|---|---|---|---|"]
        for cause, n in self.hits.most_common(15):
            kind, ekey = cause.split(":", 1)
            rate, enc = self.rate(kind, ekey)
            ls = self.lessons.get(cause)
            lesson = f"step {ls['step']} ({ls['status']})" if ls else "-"
            lines.append(f"| {cause} | {n} | {enc} | {rate:.2f} | {lesson} |")
        lines += ["", "## Loops (all time)", ""] + [f"- {k}: {v}" for k, v in self.loops.most_common()]
        q = self.dir / "queue.jsonl"
        if q.exists():
            rows = [json.loads(r) for r in q.read_text(encoding="utf-8").splitlines() if r.strip()]
            open_rows = [r for r in rows if r.get("status") == "open"]
            lines += ["", f"## Queue for code fixes ({len(open_rows)} open of {len(rows)})", ""]
            lines += [f"- [{r['id']}] {r['summary']}" for r in open_rows[-10:]]
        (self.dir / "REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
