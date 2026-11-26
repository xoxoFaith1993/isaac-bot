"""Isaac Bot helper (Stage 0: the pipe).

Talks to the Isaac Bot mod while the game runs:
  game -> helper : reads the "isaac-bot-out" mod's save file (lines "id|kind|frame|body").
                   (log.txt was the first idea, but the game only writes it to disk late.)
  helper -> game : writes "seq|command|payload" into the "isaac-bot" mod's save-data files

Usage:
  python helper.py            live view: shows what the mod says, pings every 2 s
  python helper.py --test 20  waits for a run, sends 20 pings, reports the round trip
"""
import argparse
import json
import os
import re
import statistics
import sys
import time
from pathlib import Path

from botconfig import GAME, ROOT  # game folder and bot folder come from config.json (see config.example.json)
DATA = GAME / "data" / "isaac-bot"
OUTBOX = GAME / "data" / "isaac-bot-out"
RUNS = ROOT / "runs"
SEND_FILE = RUNS / "send.txt"
import threading
SEND_LOCK = threading.Lock()
LIVE_LOG = RUNS / "live.log"  # everything as it happens; shown scrolling in the "Isaac Bot log" window
GAMEDATA = GAME / "data" / "isaac-bot-data"   # the game-data mod's save file (items, trinkets, cards)
KNOWLEDGE = ROOT / "knowledge"
LINE = re.compile(r"^(\d+)\|(\w+)\|(\d+)\|(.*)$")


class Outbox:
    """Reads the outbox mod's save file and returns only messages not seen yet.

    The file holds the newest ~60 messages. A new game launch starts a new session (first line "S|...")
    with ids from 1 again."""

    def __init__(self):
        self.session = None
        self.last_id = 0
        self.last_mtime = 0.0
        self.first_read = True
        self.state_text = None  # newest "T|" line (JSON snapshot of the room)
        self.grid = None        # newest "G|" line (room tiles)
        self.new_state = False

    def _newest_file(self):
        files = [p for p in OUTBOX.glob("save*.dat") if p.is_file()]
        return max(files, key=lambda p: p.stat().st_mtime) if files else None

    def lines(self):
        path = self._newest_file()
        if not path:
            return []
        mtime = path.stat().st_mtime
        if mtime == self.last_mtime:
            return []
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            return []
        self.last_mtime = mtime
        rows = text.splitlines()
        if not rows or not rows[0].startswith("S|"):
            return []
        session = rows[0][2:]
        if session != self.session:
            self.session, self.last_id = session, 0
        out = []
        for raw in rows[1:]:
            if raw.startswith("T|"):
                if raw[2:] != self.state_text:
                    self.state_text, self.new_state = raw[2:], True
                continue
            if raw.startswith("G|"):
                self.grid = raw[2:]
                continue
            m = LINE.match(raw)
            if not m:
                continue
            mid = int(m.group(1))
            if mid > self.last_id:
                self.last_id = mid
                out.append((m.group(2), int(m.group(3)), m.group(4)))
        if self.first_read:  # whatever was already in the file is old news
            self.first_read = False
            return []
        return out


class Pipe:
    """Inbox file layout: "H|<helper session>", then the last 20 commands "seq|cmd|payload" (oldest first).
    Keeping a queue (not just the newest line) means fast pings never overwrite a real command
    before the mod has read it."""

    KEEP = 20

    def __init__(self):
        DATA.mkdir(parents=True, exist_ok=True)
        self.session = str(int(time.time() * 1000))
        self.seq = 0
        self.queue = []
        self.tail = Outbox()

    def send(self, cmd, payload=""):
        with SEND_LOCK:  # the brain's background thread sends too
            return self._send(cmd, payload)

    def _send(self, cmd, payload=""):
        self.seq += 1
        self.queue.append(f"{self.seq}|{cmd}|{payload}")
        self.queue = self.queue[-self.KEEP:]
        text = "H|" + self.session + "\n" + "\n".join(self.queue)
        # All three slots: the mod reads the file for whichever save slot is loaded (the bot uses slot 2).
        for slot in (1, 2, 3):
            target = DATA / f"save{slot}.dat"
            tmp = target.with_suffix(".tmp")
            for _ in range(20):
                try:
                    tmp.write_bytes(text.encode("utf-8"))  # bytes: no "\r\n" line endings sneaking in
                    os.replace(tmp, target)
                    break
                except PermissionError:
                    time.sleep(0.01)
        return self.seq

    def receive(self):
        return self.tail.lines()


def now_ms():
    return int(time.perf_counter() * 1000)


# ---------------------------------------------------------------- Enter key for the game's menus
# The title and save screens don't read the mod's fake inputs, so when the mod asks ("need|enter|..."),
# the helper sends a real Enter key to the game window. The mod only asks on those two screens.
# Windows: user32 calls. Linux (Proton): xdotool (X11 / XWayland), see press_enter_linux below.
import ctypes
import shutil
import subprocess

if sys.platform == "win32":
    from ctypes import wintypes
    user32 = ctypes.WinDLL("user32", use_last_error=True)
WM_KEYDOWN, WM_KEYUP, VK_RETURN, SCAN_RETURN = 0x0100, 0x0101, 0x0D, 0x1C
KEYEVENTF_KEYUP = 0x0002


def press_enter_linux(attempt):
    """Linux: find the game's window with xdotool and send it Return (focus it on later attempts)."""
    if not shutil.which("xdotool"):
        return "xdotool not installed (sudo apt install xdotool): press Enter in the game yourself"
    out = subprocess.run(["xdotool", "search", "--name", "Binding of Isaac"], capture_output=True, text=True).stdout
    wins = out.split()
    if not wins:
        return "no game window"
    win = wins[-1]
    if attempt <= 2:
        subprocess.run(["xdotool", "key", "--window", win, "Return"])
        return "sent Return to the game window"
    prev = subprocess.run(["xdotool", "getactivewindow"], capture_output=True, text=True).stdout.strip()
    subprocess.run(["xdotool", "windowactivate", "--sync", win, "key", "Return"])
    if prev and prev != win:
        subprocess.run(["xdotool", "windowactivate", prev])
    return "focused the game and pressed Return"


def game_window():
    """The visible top-level window that belongs to isaac-ng.exe, or None."""
    import subprocess
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq isaac-ng.exe", "/FO", "CSV", "/NH"],
                         capture_output=True, text=True).stdout
    pids = {int(row.split('","')[1]) for row in out.strip().splitlines() if row.startswith('"isaac-ng')}
    found = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def each(hwnd, _):
        pid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value in pids and user32.IsWindowVisible(hwnd):
            found.append(hwnd)
        return True

    user32.EnumWindows(each, 0)
    return found[0] if found else None


def press_enter(attempt):
    """Attempts 1-2: post the key straight to the window (no focus change).
    Later attempts: bring the game to the front for a moment and type Enter, then give focus back."""
    if sys.platform != "win32":
        return press_enter_linux(attempt)
    hwnd = game_window()
    if not hwnd:
        return "no game window"
    if attempt <= 2:
        down = 1 | (SCAN_RETURN << 16)
        up = down | (1 << 30) | (1 << 31)
        user32.PostMessageW(hwnd, WM_KEYDOWN, VK_RETURN, down)
        time.sleep(0.06)
        user32.PostMessageW(hwnd, WM_KEYUP, VK_RETURN, up)
        return "posted Enter to the game window"
    previous = user32.GetForegroundWindow()
    user32.keybd_event(0x12, 0, 0, 0)  # a tap of Alt lets Windows hand focus to another window
    user32.keybd_event(0x12, 0, KEYEVENTF_KEYUP, 0)
    user32.SetForegroundWindow(hwnd)
    time.sleep(0.15)
    user32.keybd_event(VK_RETURN, SCAN_RETURN, 0, 0)
    time.sleep(0.06)
    user32.keybd_event(VK_RETURN, SCAN_RETURN, KEYEVENTF_KEYUP, 0)
    time.sleep(0.1)
    if previous and previous != hwnd:
        user32.SetForegroundWindow(previous)
    return "focused the game and typed Enter"


def wait_for_game(pipe, timeout_s):
    print(f"Waiting for the mod (start a run on save slot 2)... up to {timeout_s} s")
    end = time.time() + timeout_s
    while time.time() < end:
        for kind, frame, body in pipe.receive():
            if kind in ("alive", "start", "loaded", "pong", "hello"):
                print(f"  mod is talking ({kind}, frame {frame})")
                return True
        if pipe.tail.new_state:
            pipe.tail.new_state = False
            if time.time() > end - timeout_s + 1:  # ignore the snapshot already in the file at start
                print("  mod is sending snapshots")
                return True
        time.sleep(0.05)
    return False


def ping_once(pipe, timeout_s=3.0):
    t0 = now_ms()
    seq = pipe.send("ping", str(t0))
    end = time.time() + timeout_s
    while time.time() < end:
        for kind, _frame, body in pipe.receive():
            if kind == "pong" and body.split("|", 1)[0] == str(seq):
                return now_ms() - t0
        time.sleep(0.005)
    return None


def run_test(count):
    pipe = Pipe()
    if not wait_for_game(pipe, 180):
        print("FAIL: no message from the mod. Is the game running with the Isaac Bot mod on, inside a run?")
        return 1
    pipe.send("hello")
    time.sleep(0.5)
    pipe.receive()
    times, lost = [], 0
    for i in range(count):
        ms = ping_once(pipe)
        if ms is None:
            lost += 1
            print(f"  ping {i + 1}: lost")
        else:
            times.append(ms)
            print(f"  ping {i + 1}: {ms} ms")
        time.sleep(0.1)
    result = {"when": time.strftime("%Y-%m-%d %H:%M:%S"), "sent": count, "lost": lost}
    if times:
        result.update(min_ms=min(times), median_ms=int(statistics.median(times)), max_ms=max(times))
    RUNS.mkdir(exist_ok=True)
    (RUNS / "pipe_test.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    ok = times and lost <= count // 10 and result["median_ms"] < 500
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


PING_EVERY_S = 0.1  # the author's pick (2 s, then 0.5 s, felt too slow)

FLOOR_NAMES = {1: "Basement I", 2: "Basement II", 3: "Caves I", 4: "Caves II", 5: "Depths I", 6: "Depths II",
               7: "Womb I", 8: "Womb II", 9: "Blue Womb", 10: "Sheol/Cathedral", 11: "Dark Room/Chest",
               12: "The Void", 13: "Home"}


PLAYBOOK_TAGS = {"charges_on_line", "dashes_at_isaac", "knocked_back_by_tears", "burrows", "flies", "jumps",
                 "invulnerable_until", "invulnerable", "spawns_enemies", "explodes_on_death", "explodes_on_contact",
                 "leaves_creep", "shoots_single", "shoots_spread", "shoots_ring", "shoots_burst", "lobbed", "laser",
                 "stomp", "hops", "erratic", "splits", "heavy", "tethered",
                 # movement kinds the movement core reads (chasers home in; stationary turrets fire along lines)
                 "chases", "wanders", "stationary", "orbits"}


def send_playbook(pipe):
    """Enemy baseline (the author, 2026-11-25: give it each enemy's behaviour instead of learning it by getting hit).
    Compact: "type.variant=tag,tag,...,k<kill_priority>,d<danger>;..." with only the tags the bot uses."""
    fp = KNOWLEDGE / "enemy_playbook.json"
    if not fp.exists():
        return
    try:
        en = json.loads(fp.read_text(encoding="utf-8")).get("enemies", {})
        parts = []
        for key, e in en.items():
            # only hand-written and reviewed entries; the local-AI drafts (source "draft", 2026-11-25) wait until
            # someone checks them: a wrong tag (say "chases") changes how the bot fights that enemy
            if e.get("source") == "draft":
                continue
            tags = [t for f in ("movement", "attacks", "defense") for t in (e.get(f) or []) if t in PLAYBOOK_TAGS]
            tags.append(f"k{e.get('kill_priority', 0)}")
            tags.append(f"d{e.get('danger', 0)}")
            parts.append(key + "=" + ",".join(tags))
        pipe.send("playbook", ";".join(parts))
    except (ValueError, OSError):
        pass


def send_item_ratings(pipe):
    """Level 3 (run strategy): each item's rating for this bot, carry and tags (knowledge\\item_ratings.json).
    Compact: "id=rating,carry,tag,tag;..." """
    fp = KNOWLEDGE / "item_ratings.json"
    if not fp.exists():
        return
    try:
        items = json.loads(fp.read_text(encoding="utf-8")).get("items", {})
        parts = []
        for key, it in items.items():
            tags = [t for t in (it.get("tag_codes") or []) if re.fullmatch(r"[a-z_]+", t)]
            parts.append(f"{key}={it.get('rating', 2)},{it.get('carry', 0)}" + ("," + ",".join(tags) if tags else ""))
        pipe.send("itemratings", ";".join(parts))
    except (ValueError, OSError):
        pass


def send_boss_tactics(pipe):
    """How good players beat each boss (knowledge\\boss_tactics.json, from wiki pages, guides and videos).
    Compact: "type.variant=pref_dist,flags,adds,tell|tell;..."  flags: d diagonal, r avoid row, c avoid column,
    k avoid corners; tells = animations right before an attack you dodge sideways (aimed at Isaac)."""
    fp = KNOWLEDGE / "boss_tactics.json"
    if not fp.exists():
        return
    try:
        bosses = json.loads(fp.read_text(encoding="utf-8")).get("bosses", {})
        parts = []
        for key, b in bosses.items():
            if not re.fullmatch(r"\d+\.\d+", key):
                continue
            flags = ("d" if b.get("stay_diagonal") else "") + \
                    ("r" if b.get("avoid_row_col") or b.get("avoid_row") else "") + \
                    ("c" if b.get("avoid_row_col") or b.get("avoid_col") else "") + \
                    ("k" if b.get("avoid_corners") else "") + \
                    ("g" if b.get("room_zone") == "edges" or b.get("style") == "ring" else "")  # ring-kite
            adds = b.get("adds") if b.get("adds") in ("ignore", "kill_close", "kill_first") else ""
            tells = set()
            for d in b.get("dodge") or []:
                if isinstance(d, dict) and str(d.get("how", "")).startswith("sideways"):
                    for a in d.get("tell_anim") or []:
                        if re.fullmatch(r"[A-Za-z0-9_ ]+", str(a)):
                            tells.add(str(a))
            # attack windows: animations during which it's safe to pour damage in (not "always"/free text)
            windows = sorted(str(a) for a in (b.get("attack_windows") or [])
                             if re.fullmatch(r"[A-Za-z0-9_]+", str(a)) and str(a) != "always")
            pd = b.get("pref_dist")
            parts.append(f"{key}={int(pd) if isinstance(pd, (int, float)) else ''},{flags},{adds},"
                         + "|".join(sorted(tells)) + "," + "|".join(windows))
        pipe.send("bosstactics", ";".join(parts))
    except (ValueError, OSError, TypeError):
        pass


def send_consumables(pipe):
    """Level 3: when to use each card and pill effect (knowledge\\consumable_ratings.json).
    Compact: "c<id>=<use>,<rating>;p<effect>=<use>,<rating>,<bad 0/1>;..." """
    fp = KNOWLEDGE / "consumable_ratings.json"
    if not fp.exists():
        return
    try:
        data = json.loads(fp.read_text(encoding="utf-8"))
        parts = []
        for key, prefix in (("cards", "c"), ("pills", "p")):
            rows = data.get(key) or []
            rows = rows.values() if isinstance(rows, dict) else rows
            for r in rows:
                if not isinstance(r, dict) or r.get("id") is None:
                    continue
                use = str(r.get("use", "never")).lower()
                use = use if use in ("now", "fight", "boss", "hurt", "clear", "never", "manual") else "never"
                rating = max(0, min(4, int(r.get("rating", 0) or 0)))
                part = f"{prefix}{int(r['id'])}={use},{rating}"
                if prefix == "p":
                    part += ",1" if (r.get("bad") or r.get("bad_for_bot")) else ",0"
                parts.append(part)
        if parts:
            pipe.send("consumables", ";".join(parts))
    except (ValueError, OSError, TypeError):
        pass


HITFRAMES = RUNS / "hitframes"
HITFRAMES_KEEP = 15  # newest hits kept (3 small JPGs each, ~4 MB in all); older ones are deleted
_last_capture = [0.0]


def capture_hit_frames(body):
    """the author's idea (2026-11-25): look at the game, not just the log. ~4 s after a hit (Steam finishes the 3 s
    chunk), save 3 frames of the moments before it from Steam's background recording (tools\\look.py)."""
    if time.time() - _last_capture[0] < 5:  # hits in quick succession share one capture
        return
    _last_capture[0] = time.time()
    stamp = time.strftime("%H%M%S")
    cause = re.sub(r"[^0-9A-Za-z.]", "", body.split("|")[0])

    def work():
        time.sleep(4)
        out = HITFRAMES / f"{stamp}_{cause}"
        try:
            import subprocess
            subprocess.run([sys.executable, str(Path(__file__).resolve().parent.parent / "tools" / "look.py"),
                            "6", "3", str(out)], capture_output=True, timeout=30)
            folders = sorted((p for p in HITFRAMES.iterdir() if p.is_dir()), key=lambda p: p.name)
            for old in folders[:-HITFRAMES_KEEP]:
                for f in old.iterdir():
                    f.unlink()
                old.rmdir()
        except Exception as exc:  # never let a capture problem disturb the helper
            with open(RUNS / "hitframes_errors.txt", "a", encoding="utf-8") as fh:
                fh.write(f"{time.strftime('%H:%M:%S')} {exc}\n")

    threading.Thread(target=work, daemon=True).start()


def record_run(body, test=False):
    """One line per finished bot run in runs\\runs.jsonl: how it ended, how far, how long."""
    try:
        result, stage, stage_type, seconds, slot = body.split("|")[:5]
        if slot != "2":
            return  # only the bot's own runs
        row = {"when": time.strftime("%Y-%m-%d %H:%M:%S"), "result": result, "floor": int(stage),
               "floor_name": FLOOR_NAMES.get(int(stage), stage), "seconds": int(seconds)}
        if test:
            row["test"] = True
        RUNS.mkdir(exist_ok=True)
        with open(RUNS / "runs.jsonl", "a", encoding="utf-8") as f:
            f.write(json.dumps(row) + "\n")
    except ValueError:
        pass


def run_live(auto):
    import collections
    import dashboard

    pipe = Pipe()
    dashboard.enable_ansi()
    info = {"events": [], "ping": None, "rate": 0.0, "version": "?",
            "mode": "Auto-start ON: the bot will load save slot 2 and start a run." if auto else "Auto-start off."}
    state, last_draw = None, 0.0
    last_send, last_in_run = 0.0, 0.0
    asks_per_screen = {}
    pings = collections.deque(maxlen=10)
    state_times = collections.deque(maxlen=20)

    RUNS.mkdir(exist_ok=True)
    # keep the previous session's log (rooms.py collects problem rooms from all of them; a wiped log lost rooms),
    # newest 30 kept in runs\logs\
    if LIVE_LOG.exists() and LIVE_LOG.stat().st_size > 0:
        logs = RUNS / "logs"
        logs.mkdir(exist_ok=True)
        try:
            LIVE_LOG.replace(logs / time.strftime("live-%Y%m%d-%H%M%S.log", time.localtime(LIVE_LOG.stat().st_mtime)))
            for old in sorted(logs.glob("live-*.log"))[:-30]:
                old.unlink()
        except OSError:
            pass
    live = open(LIVE_LOG, "w", encoding="utf-8", buffering=1)  # fresh log each session, one line at a time

    def log(kind, text):
        live.write(f"{time.strftime('%H:%M:%S')} {kind:6} {text}\n")

    def event(text):
        info["events"].append(f"{time.strftime('%H:%M:%S')}  {text}")
        info["events"] = info["events"][-30:]
        kind, _, rest = text.partition(":")
        log(kind.split()[0][:6] if kind else "event", rest.strip() or text)

    # the live watcher: loops, hit causes, lessons, the code-fix queue (brain\watcher.py)
    import watcher as watcher_mod
    watcher = watcher_mod.Watcher(ROOT, send=lambda c, b: pipe.send(c, b), note=lambda t: event(f"watch: {t}"))

    def ask_brain(report, snap, grid):
        # in the background: the model can take a few seconds and the dashboard must keep moving
        import threading
        import rescue_brain

        def work():
            t0 = time.time()
            try:
                action, arg, reason = rescue_brain.ask(report, snap, grid)
                pipe.send("rescue", f"{action}|{arg}")
                event(f"brain: {action} {arg} - {reason} ({time.time() - t0:.1f} s)")
                row = {"when": time.strftime("%Y-%m-%d %H:%M:%S"), "report": report, "action": action, "arg": arg,
                       "reason": reason, "seconds": round(time.time() - t0, 1)}
            except Exception as exc:  # brain offline or a bad answer: the watchdog carries on by itself
                event(f"brain: no answer ({exc.__class__.__name__}: {exc})"[:150])
                row = {"when": time.strftime("%Y-%m-%d %H:%M:%S"), "report": report, "error": str(exc)[:200]}
            with open(RUNS / "brain.jsonl", "a", encoding="utf-8") as fh:
                fh.write(json.dumps(row) + "\n")

        threading.Thread(target=work, daemon=True).start()
        event("brain: thinking about the stuck report...")

    pending_menu = {}

    def ask_choice(menu):
        import threading
        import rescue_brain
        opts = list(menu.get("options", []))
        facts, goal = menu.get("facts", ""), menu.get("goal", "")
        for o in opts:
            log("option", f"{o['id']}: {o['text']}")

        def work():
            t0 = time.time()
            try:
                choice, reason = rescue_brain.choose(facts, opts, goal)
                pipe.send("do", choice)
                text = next((o["text"] for o in opts if o["id"] == choice), "?")
                event(f"brain: {choice} = {text[:70]} - {reason} ({time.time() - t0:.1f} s)")
                row = {"when": time.strftime("%Y-%m-%d %H:%M:%S"), "facts": facts, "options": opts, "choice": choice,
                       "reason": reason, "seconds": round(time.time() - t0, 1), "mode": "choice"}
            except Exception as exc:
                event(f"brain: no answer ({exc.__class__.__name__}: {exc})"[:150])
                row = {"when": time.strftime("%Y-%m-%d %H:%M:%S"), "facts": facts, "options": opts, "error": str(exc)[:200]}
            with open(RUNS / "brain.jsonl", "a", encoding="utf-8") as fh:
                fh.write(json.dumps(row) + "\n")

        threading.Thread(target=work, daemon=True).start()
        event(f"brain: choosing between {len(opts)} options...")

    def save_gamedata():
        src = sorted(GAMEDATA.glob("save*.dat"), key=lambda p: p.stat().st_mtime)
        if not src:
            return
        try:
            data = json.loads(src[-1].read_text(encoding="utf-8"))
            KNOWLEDGE.mkdir(exist_ok=True)
            (KNOWLEDGE / "gamedata.json").write_text(json.dumps(data, indent=1, ensure_ascii=False), encoding="utf-8")
            event(f"game data saved: {len(data.get('items', []))} items, {len(data.get('trinkets', []))} trinkets, "
                  f"{len(data.get('cards', []))} cards")
        except (OSError, ValueError) as exc:
            event(f"game data: couldn't save ({exc})")

    event("helper started" + (" (auto-start on)" if auto else ""))
    while True:
        for kind, frame, body in pipe.receive():
            try:
                watcher.on_event(kind, body)
            except Exception as exc:  # the watcher must never stop the helper
                log("error", f"watcher: {exc.__class__.__name__}: {exc}"[:200])
            if kind == "need" and auto and body.startswith("enter|"):
                screen = body.split("|")[1].split(" ")[0]  # "title", "saves" or "gameover"
                asks_per_screen[screen] = asks_per_screen.get(screen, 0) + 1
                event(f"Enter on {screen}: {press_enter(asks_per_screen[screen])}")
                continue
            if kind == "menu":
                asks_per_screen.clear()
            if kind == "pong":
                last_in_run = time.time()
                seq, sent = (body.split("|", 1) + [""])[:2]
                if sent.isdigit():
                    pings.append(now_ms() - int(sent))
                    info["ping"] = sum(pings) / len(pings)
                    log("ping", f"#{seq} {pings[-1]} ms")
                continue
            if kind in ("start", "loaded", "hello"):
                info["version"] = body.split("|")[0]
            if kind == "gauntl" and body.startswith("died"):
                info["test_death"] = time.time()
            if kind == "runend":
                # a death in a gauntlet/A-B round is a test, not a real run: tag it so stats can leave it out
                record_run(body, test=time.time() - info.get("test_death", 0) < 15)
            if kind == "stuck":  # the watchdog hit the top of its ladder: keep it for batch fixing + ask the brain
                snap = json.loads(pipe.tail.state_text) if pipe.tail.state_text else None
                with open(RUNS / "stuck.jsonl", "a", encoding="utf-8") as fh:
                    fh.write(json.dumps({"when": time.strftime("%Y-%m-%d %H:%M:%S"), "report": body,
                                         "state": snap, "grid": pipe.tail.grid}) + "\n")
                if not pending_menu.get("fresh"):
                    ask_brain(body, snap, pipe.tail.grid)  # old way: only when no option menu came with it
                pending_menu["fresh"] = False
            if kind == "ask":  # the multiple-choice menu (sent just before "stuck")
                try:
                    pending_menu.update(json.loads(body), fresh=True)
                    ask_choice(pending_menu)
                except ValueError as exc:
                    event(f"brain: bad option menu ({exc})")
            if kind == "hit":
                with open(RUNS / "hits.jsonl", "a", encoding="utf-8") as fh:
                    fh.write(json.dumps({"when": time.strftime("%Y-%m-%d %H:%M:%S"), "hit": body,
                                         "room": state["room"] if state else None}) + "\n")
                capture_hit_frames(body)
            if kind == "data" and body.startswith("ready"):
                save_gamedata()
            if kind in ("tellsraw", "respectraw", "motionraw"):  # learning that should survive restarts
                KNOWLEDGE.mkdir(exist_ok=True)
                (KNOWLEDGE / (kind.replace("raw", "") + ".dat")).write_text(body, encoding="utf-8")
                continue
            if kind == "start":  # a run (or the game) started: hand back what was learned before
                send_playbook(pipe)  # each enemy's known behaviour (knowledge\enemy_playbook.json)
                send_item_ratings(pipe)  # each item's rating for this bot (knowledge\item_ratings.json)
                send_consumables(pipe)  # when to use cards and pills (knowledge\consumable_ratings.json)
                send_boss_tactics(pipe)  # how players beat each boss (knowledge\boss_tactics.json)
                for name, cmd in (("tells.dat", "tellsload"), ("respect.dat", "respectload"), ("motion.dat", "motionload")):
                    fp = KNOWLEDGE / name
                    if fp.exists() and fp.read_text(encoding="utf-8").strip():
                        pipe.send(cmd, fp.read_text(encoding="utf-8").strip())
                tuned = KNOWLEDGE / "tuned.json"  # numbers the auto-tuner found better
                if tuned.exists():
                    try:
                        for k, v in json.loads(tuned.read_text(encoding="utf-8")).items():
                            pipe.send("set", f"{k}={v}")
                    except ValueError:
                        pass
            if kind == "tells":  # what the bot has learned about enemy wind-ups (animation -> shot)
                KNOWLEDGE.mkdir(exist_ok=True)
                (KNOWLEDGE / "telegraphs.txt").write_text(
                    time.strftime("%Y-%m-%d %H:%M:%S") + "\n" + body.replace("; ", "\n") + "\n", encoding="utf-8")
            if kind == "start":
                last_in_run = time.time()
            event(f"{kind}: {body}")
        if pipe.tail.new_state:  # a fresh snapshot only exists while a run is going
            pipe.tail.new_state = False
            try:
                state = json.loads(pipe.tail.state_text)
                last_in_run = time.time()
                try:
                    watcher.on_state(state)
                except Exception as exc:
                    log("error", f"watcher: {exc.__class__.__name__}: {exc}"[:200])
                p = state["p"]
                log("eyes", f"frame {state['f']:>6}  @{p['x']},{p['y']}  hp {p['red']}/{p['max']}"
                            f"{'+' + str(p['soul']) if p['soul'] else ''}  enemies {len(state['e'])}"
                            f"  shots {len(state['t'])}  pickups {len(state['k'])}  room {state['room'][0]}"
                            + (f"  bot move {state['bot'][2]} shoot {state['bot'][3] or '-'}  {state['bot'][6] if len(state['bot']) > 6 else ''}"
                               if state.get("bot") and state["bot"][1]
                               else (f"  walking: {state['bot'][6]}" if state.get("bot") and len(state["bot"]) > 6 else "")))
                state_times.append(time.time())
                if len(state_times) > 1:
                    span = state_times[-1] - state_times[0]
                    info["rate"] = (len(state_times) - 1) / span if span > 0 else 0.0
            except ValueError:
                pass
        # Developer test channel: lines "command|payload" dropped into runs\send.txt get forwarded once.
        if SEND_FILE.exists():
            try:
                for row in SEND_FILE.read_text(encoding="utf-8-sig").splitlines():  # -sig: ignore a BOM
                    if row.strip():
                        cmd, _, payload = row.strip().partition("|")
                        pipe.send(cmd, payload)
                        event(f"sent {cmd} {payload}")
                SEND_FILE.unlink()
            except OSError:
                pass
        in_run = time.time() - last_in_run < 3
        if not in_run:
            state, info["rate"], info["ping"] = None, 0.0, None
        if auto and not in_run and time.time() - last_send > 1.5:
            pipe.send("autostart")
            last_send = time.time()
        elif in_run and time.time() - last_send > PING_EVERY_S:
            pipe.send("ping", str(now_ms()))
            last_send = time.time()
        if time.time() - last_draw > 0.1:  # redraw 10x a second, in place
            print(dashboard.render(state, pipe.tail.grid if state else None, info), end="", flush=True)
            last_draw = time.time()
        time.sleep(0.02)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--test", type=int, metavar="N", help="send N pings and report the round trip")
    ap.add_argument("--auto", action="store_true", help="from the main menu, load save slot 2 and start a run")
    args = ap.parse_args()
    try:
        sys.exit(run_test(args.test) if args.test else run_live(args.auto))
    except KeyboardInterrupt:
        pass
