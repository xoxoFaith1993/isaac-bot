"""The watcher's queue of problems that need a CODE fix (Level C). brain\\watcher.py files them with evidence; a Claude
session (or a person) works them the usual way: diagnose from the evidence, fix the category, add an offline test,
reload with tools\\reload.ps1, check, then mark it done.

    python tools/queue.py list              open problems (newest last)
    python tools/queue.py show <id>         one problem with all its evidence
    python tools/queue.py wait [seconds]    block until a NEW open problem appears, print it, exit (default 6 h)
    python tools/queue.py done <id> "what was changed"

`wait` is how a Claude session gets woken up: it runs it in the background and is notified when it exits.
"""
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "brain"))
import botconfig  # noqa: E402

QUEUE = botconfig.ROOT / "runs" / "watch" / "queue.jsonl"


def rows():
    if not QUEUE.exists():
        return []
    out = []
    for line in QUEUE.read_text(encoding="utf-8").splitlines():
        try:
            out.append(json.loads(line))
        except ValueError:
            pass
    return out


def show(r, full=False):
    print(f"[{r['id']}] {r['status']}  {r['kind']}  {r['summary']}")
    if full:
        print(f"  room {r.get('room')}  tried: {r.get('tried') or '-'}")
        print(f"  last why: {r.get('why')}")
        print(f"  risk: {r.get('risk')}")
        for f in r.get("frames", []):
            print(f"  frames: {f}")
        note = QUEUE.parent / "notes" / f"{r['id']}.json"  # Level B: the local model's first read, if it answered
        if note.exists():
            try:
                n = json.loads(note.read_text(encoding="utf-8"))
                if "cause" in n:
                    print(f"  local model ({n.get('model')}, {n.get('confidence')} confidence):")
                    print(f"    cause: {n['cause']}\n    category: {n['category']}\n    change: {n['change']}")
                else:
                    print(f"  local model: no answer ({n.get('error')})")
            except ValueError:
                pass
        print("  evidence (newest last):")
        for e in r.get("evidence", []):
            print("    " + e)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    if cmd == "list":
        open_rows = [r for r in rows() if r.get("status") == "open"]
        for r in open_rows:
            show(r)
        print(f"{len(open_rows)} open")
    elif cmd == "show":
        for r in rows():
            if r["id"] == sys.argv[2]:
                show(r, full=True)
    elif cmd == "wait":
        limit = float(sys.argv[2]) if len(sys.argv) > 2 else 6 * 3600
        seen = {r["id"] for r in rows()}
        end = time.time() + limit
        while time.time() < end:
            new = [r for r in rows() if r["id"] not in seen and r.get("status") == "open"]
            if new:
                for r in new:
                    show(r, full=True)
                return 0
            time.sleep(5)
        print("no new problems")
    elif cmd == "done":
        rid, note = sys.argv[2], " ".join(sys.argv[3:])
        all_rows = rows()
        for r in all_rows:
            if r["id"] == rid:
                r["status"], r["fixed"] = "done", note
        QUEUE.write_text("".join(json.dumps(r) + "\n" for r in all_rows), encoding="utf-8")
        print(f"{rid} marked done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
