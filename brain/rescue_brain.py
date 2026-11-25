"""Ask the local LLM what to do when the bot's watchdog has run out of ideas (Stage 4, first piece).

Input: the stuck report from the mod, the latest snapshot, the room map. Output: one action from a fixed menu,
which the helper sends back to the mod as "rescue|action|arg". Runs in a background thread.
"""
import json
import re
import urllib.request
from pathlib import Path

import dashboard
from botconfig import ROOT

OLLAMA = "http://127.0.0.1:11434/api/chat"
MODEL = "gemma4:12b"  # exam 2026-11-25: 28/28 (gemma3:12b 25.5, gpt-oss:20b 24, gemma4:26b 27 but 3x slower)
THINK = False          # thinking off: ~1.3 s per answer and still careful; turn on for big Stage 4 decisions
RULES = ROOT / "knowledge" / "RULES.md"
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")

MENU = """Pick ONE action:
- "replan": give up the current goal and pick another one
- "bomb": bomb the nearest breakable rock or poop (only if bombs > 0). Only "p" on the map is poop; "#" is rock.
- "replan": in a fight this means "switch to a different enemy"
- "door": walk through a door; arg = its slot number from the door list
- "goto": walk to a map square; arg = "col,row" (0-based, counted on the map below). In a FIGHT, pick a "·"
  floor square in the same row or column as an enemy with NO # between them (tears can't pass rocks, they fly
  over pits ~), not right next to an enemy: the bot will walk there and shoot along that line.
- "shake": shoot in all directions for a few seconds (breaks poop/fires, reveals things)
- "wait": do nothing for now
Bombs are scarce: CONSERVE them. In a fight, prefer "goto" to a firing square or "replan" (switch enemy).
Only choose "bomb" if every enemy is completely enclosed by # rock AND bombs >= 3. Never bomb poop (p): shoot it.
Answer with JSON only: {"action": "...", "arg": "...", "reason": "one short sentence"}"""


def plain_map(state, grid):
    rows = dashboard.build_map(state, grid)
    out = []
    for r in rows:
        cells = ANSI.sub("", r).strip().split(" ")
        out.append("".join(cells))
    header = "    " + "".join(str(i % 10) for i in range(len(out[0]) if out else 0))
    return "\n".join([header] + [f"{i:>2}  {line}" for i, line in enumerate(out)])


def describe(report, state, grid):
    parts = report.split("|")
    floor, room_idx, room_type, mode, goal = (parts + [""] * 5)[:5]
    p = state.get("p", {}) if state else {}
    doors = []
    for d in (state or {}).get("doors", []):
        slot, rtype, is_open, locked = d[0], d[1], d[2], d[3]
        doors.append(f"slot {slot}: to a {dashboard.ROOM_TYPES.get(rtype, rtype)} room"
                     f"{'' if is_open else ', shut'}{', LOCKED (needs a key)' if locked else ''}")
    return f"""You are helping a bot that plays The Binding of Isaac. It is STUCK: no progress for a while, and its
automatic fixes (replan, shoot around, bomb, leave) didn't work.

Situation: floor {floor}, room type {dashboard.ROOM_TYPES.get(int(room_type) if room_type.isdigit() else room_type, room_type)},
{'in a fight' if mode == 'fight' else 'room is clear, walking'}. Its goal was: "{goal}".
Isaac: hearts {p.get('red')}/{p.get('max')} (+{p.get('soul', 0)} soul), bombs {p.get('bombs')}, keys {p.get('keys')}, coins {p.get('coins')}.
Enemies visible: {len((state or {}).get('e', []))}. Pickups visible: {len((state or {}).get('k', []))}.
Doors:
{chr(10).join('  ' + d for d in doors) or '  none'}

Room map (one character per square). @ Isaac, E enemy, B boss, o enemy shot, $ pickup, F fire, D door,
# rock/block, ~ pit, ^ spikes, p poop, T tnt, W wall, · floor:
{plain_map(state, grid) if grid else '(no map)'}

{MENU}"""


def choose(facts, options, goal="", timeout=90):
    """The multiple-choice brain: the mod's code lists real options (geometry already worked out), the model
    only picks one. Returns (id, reason). Exam 2026-11-25: gemma4:12b 28/28 when asked this way."""
    rules = RULES.read_text(encoding="utf-8") if RULES.exists() else ""
    menu = "\n".join(f"{o['id']}: {o['text']}" for o in options)
    ids = [o["id"] for o in options]
    body = {
        "model": MODEL, "stream": False, "format": "json", "think": THINK,
        "options": {"temperature": 0.1, "num_ctx": 8192},
        "messages": [
            {"role": "system", "content": "You are an expert Binding of Isaac player advising a bot. Rules you follow:\n" + rules},
            {"role": "user", "content": (
                "The bot is STUCK (no progress for a while; its automatic fixes didn't help).\n"
                f"Facts: {facts.replace(' / ', chr(10))}\n"
                f"What it was trying to do: {goal or '-'}\n\nOptions:\n{menu}\n\n"
                "Pick the option most likely to make progress safely. Conserve bombs and health.\n"
                'Answer with JSON only: {"choice": "<letter>", "reason": "one short sentence"}')},
        ],
    }
    req = urllib.request.Request(OLLAMA, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        reply = json.loads(r.read().decode())["message"]["content"]
    ans = json.loads(reply)
    choice = str(ans.get("choice", "")).strip().upper()[:1]
    if choice not in ids:
        choice = ids[-1]  # unusable answer: the last option is always the harmless "wait / keep going"
    return choice, str(ans.get("reason", ""))[:200]


def ask(report, state, grid, timeout=90):
    rules = RULES.read_text(encoding="utf-8") if RULES.exists() else ""
    body = {
        "model": MODEL, "stream": False, "format": "json", "think": THINK,
        "options": {"temperature": 0.2, "num_ctx": 8192},
        "messages": [
            {"role": "system", "content": "You are an expert Binding of Isaac player. Follow these rules:\n" + rules},
            {"role": "user", "content": describe(report, state, grid)},
        ],
    }
    req = urllib.request.Request(OLLAMA, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        reply = json.loads(r.read().decode())["message"]["content"]
    ans = json.loads(reply)
    action = str(ans.get("action", "wait")).lower()
    if action not in ("replan", "bomb", "door", "goto", "shake", "wait", "leave"):
        action = "replan"
    return action, str(ans.get("arg", "")), str(ans.get("reason", ""))[:200]
