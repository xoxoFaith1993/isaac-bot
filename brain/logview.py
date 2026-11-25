"""Isaac Bot live log: the scrolling window. Follows runs\\live.log (written by the helper) and prints
every line as it arrives, colour-coded: pings, what the eyes see, and events."""
import os
import sys
import time
from pathlib import Path

from botconfig import ROOT  # noqa: E402

LOG = ROOT / "runs" / "live.log"
RED, YELLOW, GREEN, CYAN, DIM, RESET = ("\x1b[38;2;200;40;60m", "\x1b[33m", "\x1b[32m", "\x1b[36m",
                                        "\x1b[2m", "\x1b[0m")


def colour(line):
    kind = line[9:15].strip() if len(line) > 15 else ""
    if kind == "ping":
        return DIM + line + RESET
    if kind == "eyes":
        return CYAN + line + RESET
    if kind in ("error", "gave"):
        return RED + line + RESET
    if kind in ("start", "room", "spawn"):
        return GREEN + line + RESET
    return YELLOW + line + RESET


def main():
    os.system("")  # ANSI colours in the Windows console
    print(f"{RED}Isaac Bot log{RESET}  {DIM}(following {LOG}){RESET}")
    pos, buf = 0, ""
    while True:
        try:
            size = LOG.stat().st_size if LOG.exists() else 0
            if size < pos:  # helper restarted and started a fresh log
                pos, buf = 0, ""
                print(f"{DIM}--- new session ---{RESET}")
            if size > pos:
                with open(LOG, "r", encoding="utf-8", errors="replace") as f:
                    f.seek(pos)
                    buf += f.read()
                    pos = f.tell()
                *lines, buf = buf.split("\n")
                if lines:
                    sys.stdout.write("\n".join(colour(l) for l in lines) + "\n")
                    sys.stdout.flush()
        except OSError:
            pass
        time.sleep(0.05)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
