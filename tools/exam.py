"""Isaac brain exam: runs local models on knowledge\\exam.json (multiple choice with facts) and scores them.

Usage: python exam.py gemma3:12b gemma4:26b gpt-oss:20b gemma4:12b
Writes runs\\exam_results.json and prints a table: score, average seconds, and which questions each got wrong.
"""
import json
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "brain"))
import botconfig  # noqa: E402  (bot folder: config.json "bot_dir", default this repo)

ROOT = botconfig.ROOT
EXAM = ROOT / "knowledge" / "exam.json"
RULES = ROOT / "knowledge" / "RULES.md"
OLLAMA = "http://127.0.0.1:11434/api/chat"


def ask(model, rules, q):
    opts = "\n".join(f"{k}: {v}" for k, v in q["options"].items())
    body = {
        "model": model, "stream": False, "format": "json",
        "options": {"temperature": 0.1, "num_ctx": 8192},
        "messages": [
            {"role": "system", "content": "You are an expert Binding of Isaac player advising a bot. Rules you follow:\n" + rules},
            {"role": "user", "content": f"Situation: {q['situation']}\n\nOptions:\n{opts}\n\n"
                                        'Pick the best option. Answer with JSON only: {"choice": "A/B/C/D", "reason": "one short sentence"}'},
        ],
    }
    req = urllib.request.Request(OLLAMA, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=300) as r:
        reply = json.loads(r.read().decode())["message"]["content"]
    secs = time.time() - t0
    try:
        ans = json.loads(reply)
        choice = str(ans.get("choice", "?")).strip().upper()[:1]
        reason = str(ans.get("reason", ""))
    except ValueError:
        choice, reason = "?", reply[:120]
    return choice, reason, secs


def unload(model):
    body = json.dumps({"model": model, "keep_alive": 0}).encode()
    try:
        urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:11434/api/generate", data=body,
                                                      headers={"Content-Type": "application/json"}), timeout=60).read()
    except Exception:
        pass


def main():
    models = sys.argv[1:] or ["gemma3:12b"]
    exam = json.loads(EXAM.read_text(encoding="utf-8"))["questions"]
    rules = RULES.read_text(encoding="utf-8")
    results = {}
    for m in models:
        print(f"\n=== {m}", flush=True)
        score, times, wrong = 0.0, [], []
        ask(m, rules, exam[0])  # warm-up: loads the model, not counted
        for q in exam:
            try:
                choice, reason, secs = ask(m, rules, q)
            except Exception as exc:
                choice, reason, secs = "!", f"error: {exc}", 0
            times.append(secs)
            if choice == q["answer"]:
                score += 1
                mark = "right"
            elif choice in q.get("ok", []):
                score += 0.5
                mark = "half"
            else:
                mark = "WRONG"
                wrong.append(q["id"])
            print(f"  {q['id']:<28} {choice} ({mark:5}) {secs:5.1f}s  {reason[:90]}", flush=True)
        results[m] = {"score": score, "of": len(exam), "avg_s": round(sum(times) / len(times), 1), "wrong": wrong}
        unload(m)  # one model in memory at a time (PC stability rules)
    print("\nRESULTS")
    for m, r in sorted(results.items(), key=lambda kv: -kv[1]["score"]):
        print(f"  {m:<20} {r['score']:>4}/{r['of']}   {r['avg_s']:>5}s per question   wrong: {', '.join(r['wrong']) or '-'}")
    out = ROOT / "runs" / "exam_results.json"
    prev = json.loads(out.read_text(encoding="utf-8")) if out.exists() else {}
    prev[time.strftime("%Y-%m-%d %H:%M")] = results
    out.write_text(json.dumps(prev, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
