"""Live terminal dashboard for the Isaac Bot helper (Stage 1: what the bot sees).

Redraws in place (no scrolling) using ANSI codes, which Windows Terminal understands.
Map letters: @ you, E enemy, B boss, o enemy shot, * bomb, $ pickup, F fire, D door,
# rock, ~ pit, ^ spikes, p poop, T tnt, W wall.
"""
import math
import os
import time

RED = "\x1b[38;2;200;40;60m"
DIM = "\x1b[2m"
BOLD = "\x1b[1m"
RESET = "\x1b[0m"
YELLOW = "\x1b[33m"
GREEN = "\x1b[32m"
CYAN = "\x1b[36m"

ROOM_TYPES = {1: "normal", 2: "shop", 3: "error", 4: "treasure", 5: "boss", 6: "miniboss", 7: "secret",
              8: "super secret", 9: "arcade", 10: "curse", 11: "challenge", 12: "library", 13: "sacrifice",
              14: "devil", 15: "angel", 16: "dungeon", 17: "boss rush", 18: "isaac's", 19: "barren",
              20: "chest", 21: "dice", 22: "black market", 23: "greed exit", 24: "planetarium",
              25: "teleporter", 26: "teleporter exit", 27: "secret exit", 28: "blue", 29: "ultra secret"}
FLOORS = {1: "Basement I", 2: "Basement II", 3: "Caves I", 4: "Caves II", 5: "Depths I", 6: "Depths II",
          7: "Womb I", 8: "Womb II", 9: "Blue Womb", 10: "Sheol/Cathedral", 11: "Dark Room/Chest",
          12: "The Void", 13: "Home"}
DOOR_SIDES = {0: "W", 1: "N", 2: "E", 3: "S", 4: "W2", 5: "N2", 6: "E2", 7: "S2"}
TILE_COLOUR = {"#": DIM, "W": DIM, "~": CYAN, "^": YELLOW, "D": GREEN}


def enable_ansi():
    os.system("")  # makes the Windows console process ANSI escape codes
    print("\x1b[?25l\x1b[2J", end="")  # hide cursor, clear once


def hearts(p):
    red, mx, soul = p["red"], p["max"], p["soul"]
    full, half = divmod(red, 2)
    empty = max(0, (mx - red) // 2)
    s = RED + "♥" * full + ("♡" if half else "") + RESET + DIM + "♡" * empty + RESET
    if soul:
        s += " " + CYAN + "♦" * (soul // 2) + ("◊" if soul % 2 else "") + RESET
    return s


def build_map(state, grid):
    """Room tiles with everything the bot sees drawn on top, one character per grid square."""
    if not grid:
        return []
    try:
        idx, w, h, x0, y0, tiles = grid.split("|", 5)
        w, h, x0, y0 = int(w), int(h), int(x0), int(y0)
    except ValueError:
        return []
    cells = [list(tiles[r * w:(r + 1) * w]) for r in range(h)]

    def put(x, y, ch):
        c, r = round((x - x0) / 40), round((y - y0) / 40)
        if 0 <= r < h and 0 <= c < w:
            cells[r][c] = ch

    if state:
        for k in state.get("k", []):
            put(k[2], k[3], "$")
        for fp in state.get("fp", []):
            put(fp[1], fp[2], "F")
        for e in state.get("e", []):
            put(e[2], e[3], "B" if e[8] else "E")
        for b in state.get("b", []):
            put(b[0], b[1], "*")
        for t in state.get("t", []):
            put(t[0], t[1], "o")
        p = state.get("p")
        if p:
            put(p["x"], p["y"], "@")

    out = []
    for row in cells:
        drawn = []
        for ch in row:
            if ch == "@":
                drawn.append(BOLD + GREEN + "@" + RESET)
            elif ch in "EB":
                drawn.append(BOLD + RED + ch + RESET)
            elif ch == "o":
                drawn.append(YELLOW + "o" + RESET)
            elif ch == "$":
                drawn.append(GREEN + "$" + RESET)
            elif ch == ".":
                drawn.append(DIM + "·" + RESET)
            else:
                drawn.append(TILE_COLOUR.get(ch, "") + ch + RESET)
        out.append(" " + " ".join(drawn))  # a space between squares keeps the room's real shape
    return out


def threats(state):
    """The shots most likely to hit, with time until impact (simple straight-line guess)."""
    p = state.get("p")
    if not p:
        return []
    px, py, pr = p["x"], p["y"], p["size"] + 8
    found = []
    for t in state.get("t", []):
        x, y, vx, vy = t[0], t[1], t[2], t[3]
        dx, dy = px - x, py - y
        dist = math.hypot(dx, dy)
        speed2 = vx * vx + vy * vy
        if speed2 < 0.01:
            found.append((dist, f"shot standing still {dist:4.0f} px away"))
            continue
        tclosest = max(0.0, (dx * vx + dy * vy) / speed2)  # in game updates (30 per second)
        cx, cy = x + vx * tclosest, y + vy * tclosest
        miss = math.hypot(px - cx, py - cy)
        if miss < pr + 10 and tclosest < 45:
            found.append((tclosest, f"shot {dist:4.0f} px away, {'WILL HIT' if miss < pr else 'close call'} in {tclosest / 30:.2f} s"))
    for e in state.get("e", []):
        d = math.hypot(px - e[2], py - e[3])
        if d < 90:
            found.append((d / 10, f"enemy {e[0]}.{e[1]} only {d:3.0f} px away"))
    found.sort()
    return [f for _, f in found[:4]]


def render(state, grid, info):
    lines = []
    ping = f"{info['ping']:.0f} ms" if info.get("ping") is not None else "--"
    rate = f"{info.get('rate', 0):4.1f}/s"
    head = f"{RED}{BOLD}ISAAC BOT{RESET}  {DIM}mod {info.get('version', '?')}{RESET}   ping {ping}   eyes {rate}   {time.strftime('%H:%M:%S')}"
    lines.append(head)
    if not state:
        lines.append(f"{DIM}Not in a run. {info.get('mode', '')}{RESET}")
    else:
        p = state["p"]
        room = state["room"]
        floor = FLOORS.get(state["floor"][0], f"floor {state['floor'][0]}")
        rtype = ROOM_TYPES.get(room[1], str(room[1]))
        lines.append(f"{floor}   room {room[0]} ({rtype}{', cleared' if room[3] else ''})   "
                     f"{len(state['e'])} enemies   {len(state['t'])} shots   {len(state['k'])} pickups")
        lines.append(f"{hearts(p)}   dmg {p['dmg']:.2f}  delay {p['delay']:.1f}  range {p['range']}  "
                     f"speed {p['speed']:.2f}  shot {p['shot']:.2f}  luck {p['luck']:g}   "
                     f"{YELLOW}¢{p['coins']}{RESET} bombs {p['bombs']} keys {p['keys']}  items {p['items']}")
        bot = state.get("bot")
        if bot:
            mode, active, move, shoot, cost, incoming = bot[:6]
            goal = bot[6] if len(bot) > 6 else ""
            arrow = "stand" if move == 0 else ("→↘↓↙←↖↑↗"[round(((move - 1) % 16) / 2) % 8] if move > 0 else "-")
            if move > 16:
                arrow += " (slow step)"
            if active:
                doing = f"{GREEN}FIGHTING{RESET}  move {arrow}  shoot {shoot or '-'}  risk {cost}  incoming {incoming}"
            elif mode == "full":
                doing = f"{CYAN}WALKING{RESET}  goal: {goal or '-'}"
            else:
                doing = f"{DIM}room clear - your controls{RESET}"
            lines.append(f"{BOLD}bot{RESET} {mode}  " + doing)
        doors = "  ".join(f"{DOOR_SIDES.get(d[0], d[0])}:{ROOM_TYPES.get(d[1], d[1])}{'' if d[2] else ' (shut)'}"
                          f"{' LOCKED' if d[3] else ''}" for d in state.get("doors", []))
        lines.append(f"{DIM}doors{RESET} {doors}")
    lines.append("")
    lines += build_map(state, grid)
    lines.append("")
    if state:
        th = threats(state)
        lines.append(f"{BOLD}Threats{RESET} " + (f"{GREEN}none{RESET}" if not th else ""))
        lines += ["  " + t for t in th]
    lines.append(f"{BOLD}Events{RESET}")
    lines += ["  " + e for e in info.get("events", [])[-6:]]
    # draw in place: go home, rewrite each line, clear the rest
    return "\x1b[H" + "\n".join(l + "\x1b[K" for l in lines) + "\n\x1b[J"
