"""Local settings for the Isaac Bot: where the game, Steam, ffmpeg and Python live on this PC.

Copy config.example.json (repo root) to config.json and fill it in. config.json is never committed.
Every key is optional; anything missing or empty falls back to the default below.
"""
import json
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CONFIG_FILE = REPO / "config.json"

DEFAULTS = {
    "game_dir": r"C:\Program Files (x86)\Steam\steamapps\common\The Binding of Isaac Rebirth",
    "steam_userdata": "",       # e.g. <Steam>\userdata\<your id>; empty = search <Steam>\userdata for recordings
    "ffmpeg": "ffmpeg",          # full path, or a name on PATH
    "python": "",                # used by helper.cmd / logview.cmd; empty = "python" on PATH
    "repentogon_launcher": "",   # used by tools\start_bot.ps1
    "repentogon_ini": "",        # used by tools\start_bot.ps1; empty = Documents\My Games\repentogon_launcher.ini
    "bot_dir": "",               # empty = this repo (the folder holding brain\, tools\, knowledge\)
}


def load():
    cfg = dict(DEFAULTS)
    if CONFIG_FILE.exists():
        try:
            for k, v in json.loads(CONFIG_FILE.read_text(encoding="utf-8-sig")).items():
                if not k.startswith("_") and v not in (None, ""):
                    cfg[k] = v
        except ValueError as exc:
            sys.exit(f"config.json is not valid JSON: {exc}")
    return cfg


CFG = load()
ROOT = Path(CFG["bot_dir"]) if CFG["bot_dir"] else REPO
GAME = Path(CFG["game_dir"])


def ffmpeg():
    return shutil.which(CFG["ffmpeg"]) or CFG["ffmpeg"]


def recordings():
    """Steam's background-recording folder (userdata\\<id>\\gamerecordings\\video)."""
    if CFG["steam_userdata"]:
        return Path(CFG["steam_userdata"]) / "gamerecordings" / "video"
    # game_dir = <Steam>\steamapps\common\<game>, so Steam's root is three levels up
    steam = GAME.parents[2] if len(GAME.parents) > 2 else GAME
    found = sorted((steam / "userdata").glob("*/gamerecordings/video"), key=lambda p: p.stat().st_mtime)
    return found[-1] if found else steam / "userdata" / "gamerecordings" / "video"
