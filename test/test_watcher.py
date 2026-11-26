"""Offline tests for brain/watcher.py (no game): python test/test_watcher.py"""
import json
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "brain"))
import watcher  # noqa: E402

results = []


def check(name, ok, detail=""):
    results.append(("PASS " if ok else "FAIL ") + name + (f"  ({detail})" if detail else ""))


def make():
    root = Path(tempfile.mkdtemp())
    sent, notes = [], []
    w = watcher.Watcher(root, send=lambda c, b: sent.append((c, b)), note=notes.append, local_notes=False)
    return w, sent, notes, root


def room_with(w, idx, enemies):
    w.on_event("room", f"{idx}|1|100|11|test")
    w.on_state({"e": [[t, v, 100, 100, 0, 0, 20, 20, 1 if boss else 0, 13] for t, v, boss in enemies],
                "p": {"x": 300, "y": 300}, "bot": ["full", 1, 0, ""]})


# 1. hit causes
cases = {
    "261.0|1|410,157|move 8|via 261.0 d=16 size=13|risk 0.35 deal": ("body", "261.0"),
    "9.0|1|188,281|move 5|via 9.0 d=15 size=5|shot 0 d=15 size=5 scale=1.00 height=-16 speed=10.0 from=30": ("shot", "30"),
    "1000.22|1|1,1|move 0": ("creep", "1000.22"),
    "0.0|2|419,355|move 9|risk 0.65": ("bomb", "0.0"),
}
ok = all(watcher.hit_cause(b) == want for b, want in cases.items())
check("hit causes are sorted (body, shot by shooter, creep, bomb)", ok,
      ", ".join(f"{watcher.hit_cause(b)}" for b in cases))

# 2. a boss that keeps touching us -> a lesson (more berth + distance), sent to the mod
w, sent, notes, root = make()
for i in range(3):
    room_with(w, 10 + i, [(261, 0, True)])
    w.on_event("hit", "261.0|1|1,1|move 3|via 261.0 d=16 size=13")
w.on_event("room", "99|1|1|11|next")  # closes the 3rd encounter
w.on_event("hit", "261.0|1|1,1|move 3|via 261.0 d=16 size=13")
lesson = w.lessons.get("body:261.0", {})
payload = w.lessons_payload()
check("repeated body hits from a boss -> step 1 lesson sent", lesson.get("step") == 1 and "261.0=8,0,20" in payload
      and any(c == "lessons" for c, _ in sent), f"lesson {lesson.get('step')} {lesson.get('status')}, payload '{payload}'")

# 3. it helped (no hits in the next 4 encounters) -> kept
for i in range(5):
    room_with(w, 20 + i, [(261, 0, True)])
w.on_event("room", "98|1|1|11|next")
check("a lesson that helps is kept", w.lessons["body:261.0"]["status"] == "kept", w.lessons["body:261.0"]["status"])

# 4. a lesson that doesn't help is undone and queued for a code fix
w, sent, notes, root = make()
for i in range(3):
    room_with(w, 10 + i, [(30, 0, False)])
    w.on_event("hit", "9.0|1|1,1|move 5|via 9.0 d=15 size=5|shot 0 d=15 size=5 from=30")
w.on_event("room", "99|1|1|11|next")
w.on_event("hit", "9.0|1|1,1|move 5|via 9.0 d=15 size=5|shot 0 d=15 size=5 from=30")
for rnd in range(2):  # (a borderline first trial gets a second one since 2026-11-26)
    for i in range(5):
        room_with(w, 30 + 10 * rnd + i, [(30, 0, False)])
        w.on_event("hit", "9.0|1|1,1|move 5|via 9.0 d=15 size=5|shot 0 d=15 size=5 from=30")
    w.on_event("room", f"9{7 - rnd}|1|1|11|next")
ls = w.lessons.get("shot:30", {})
q = root / "runs" / "watch" / "queue.jsonl"
queued = q.exists() and any("shot:30" in json.loads(r)["key"] for r in q.read_text().splitlines())
check("a lesson that doesn't help is undone and queued", ls.get("status") == "didn't help" and ls.get("step") == 0
      and queued, f"status {ls.get('status')}, step {ls.get('step')}, queued {queued}")

# 5. bouncing between two rooms -> that door gets written off
w, sent, notes, root = make()
for i in range(7):
    w.on_event("room", f"{84 if i % 2 == 0 else 85}|1|1|11|x")
check("a two-room bounce is caught and the door written off", any(c == "deadhop" for c, _ in sent),
      str([s for s in sent if s[0] == "deadhop"]))

# 6. standing still while walking -> re-plan
w, sent, notes, root = make()
w.on_event("room", "84|1|1|11|x")
w.on_state({"e": [], "p": {"x": 300, "y": 300}, "bot": ["full", 0, 0, ""]})
w.still_since = time.time() - 25
w.on_state({"e": [], "p": {"x": 302, "y": 301}, "bot": ["full", 0, 0, ""]})
check("standing still while walking -> asks the bot to re-plan", ("rescue", "replan") in sent, str(sent))

# 7. a benchmark is running (runs/watch/PAUSED): no lessons, no nudges, so A vs B starts from the same state
w, sent, notes, root = make()
(root / "runs" / "watch").mkdir(parents=True, exist_ok=True)
(root / "runs" / "watch" / "PAUSED").write_text("bench")
for i in range(7):
    w.on_event("room", f"{84 if i % 2 == 0 else 85}|1|1|11|x")
for i in range(4):
    room_with(w, 10 + i, [(261, 0, True)])
    w.on_event("hit", "261.0|1|1,1|move 3|via 261.0 d=16 size=13")
check("paused during a benchmark: no deadhop, no lessons", not any(c in ("deadhop", "lessons") for c, _ in sent)
      and not w.lessons, str(sent))

# 8. ...but it still WRITES what it noticed (the author: "fills out some sort of document"): hits by cause, stalls, and a
# summary when the benchmark ends - without nudging, queueing or touching the lesson stats
w.on_state({"e": [], "p": {"x": 300, "y": 300}, "bot": ["combat", 0, 0, ""]})
w.still_since = time.time() - 25
w.on_state({"e": [], "p": {"x": 301, "y": 300}, "bot": ["combat", 0, 0, ""]})
(root / "runs" / "watch" / "PAUSED").unlink()
w.on_event("ping", "")  # the switch back closes the section with a summary
notes = (root / "runs" / "watch" / "BENCH_NOTES.md").read_text(encoding="utf-8")
q = root / "runs" / "watch" / "queue.jsonl"
check("benchmark notes written, nothing acted on", "hit in" in notes and "stall" in notes and "Summary" in notes
      and "body:261.0" in notes and not any(c == "rescue" for c, _ in sent) and not q.exists()
      and w.hits.get("body:261.0", 0) == 0, f"notes {len(notes)} chars, sent {sent}")

# 9. a lesson that helped a little (1.00 -> 0.75, exactly the bar) isn't thrown out: it gets a second trial
w, sent, notes, root = make()
w.lessons["body:24.0"] = {"step": 1, "status": "trying", "rate_before": 1.0, "enc_at": 0, "hits_since": 3,
                          "history": []}
w.enc["24.0"] = 4
w._judge_lessons()
ls = w.lessons["body:24.0"]
q = root / "runs" / "watch" / "queue.jsonl"
check("a borderline lesson gets a second trial, not the queue", ls["status"] == "trying" and ls.get("extended")
      and ls["step"] == 1 and not q.exists(), str(ls))

# 10. the decompile-queue failsafe (2026-11-26): open batches + nothing new for an hour -> one queue entry; a fresh
# change, or no open batch, -> nothing
import os  # noqa: E402


def re_setup(open_batch, age_s):
    w, sent, notes, root = make()
    d = root / "docs" / "research"
    d.mkdir(parents=True)
    rows = ["| Batch | Item | Status |", "|---|---|---|", "| E3 | Gluttony | [x] abc |"]
    if open_batch:
        rows.append("| E3b | Famine, Death | [ ] |")
    qf = d / "RE_QUEUE.md"
    qf.write_text("\n".join(rows) + "\n", encoding="utf-8")
    t = time.time() - age_s
    os.utime(qf, (t, t))
    w.check_re_queue(time.time())
    q = root / "runs" / "watch" / "queue.jsonl"
    return [json.loads(x) for x in q.read_text(encoding="utf-8").splitlines()] if q.exists() else []


stalled = re_setup(True, 2 * 3600)
fresh = re_setup(True, 600)
done = re_setup(False, 2 * 3600)
check("decompile failsafe: a stalled queue is filed, a busy or finished one isn't",
      len(stalled) == 1 and stalled[0]["kind"] == "re" and "E3b Famine, Death" in stalled[0]["summary"]
      and not fresh and not done,
      f"stalled {len(stalled)} ({stalled[0]['summary'][:70] if stalled else '-'}), fresh {len(fresh)}, done {len(done)}")

print("\n".join(results))
fails = sum(r.startswith("FAIL") for r in results)
print(f"\n{len(results) - fails} passed, {fails} failed")
sys.exit(1 if fails else 0)
