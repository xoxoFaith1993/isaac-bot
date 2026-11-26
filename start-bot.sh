#!/usr/bin/env bash
# Linux version of start-bot.cmd / restart-bot.cmd (Steam + Proton).
#   bash start-bot.sh             start Ollama (if installed), the helper and the log viewer, then the game
#   bash start-bot.sh --restart   close a running game first (after mod changes)
# The game must already start WITH REPENTOGON when launched from Steam (see README, "Linux").
# The mod then loads save slot 2 and starts a run as Isaac by itself.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
PY="$(python3 "$ROOT/brain/botconfig.py" --get python 2>/dev/null || echo python3)"
APPID=250900   # The Binding of Isaac: Rebirth (Repentance+ is its DLC)

game_running() { pgrep -f 'isaac-ng.exe' >/dev/null; }

echo "Isaac Bot: starting..."

# 1. one helper and one log viewer, never two
pkill -f "$ROOT/brain/helper.py" 2>/dev/null
pkill -f "$ROOT/brain/logview.py" 2>/dev/null

# 2. --restart: close the game too
if [ "${1:-}" = "--restart" ] && game_running; then
  echo "Closing Isaac..."
  pkill -f 'isaac-ng.exe'
  for _ in $(seq 20); do game_running || break; sleep 0.3; done
  game_running && pkill -9 -f 'isaac-ng.exe'
  sleep 3   # let the game finish writing its files before the next launch
fi

# 3. the brain needs Ollama (optional)
if command -v ollama >/dev/null && ! pgrep -x ollama >/dev/null; then
  nohup ollama serve >/dev/null 2>&1 &
  echo "Started Ollama for the brain."
fi

# 4. helper (dashboard) and log viewer, each in its own terminal window if one is available
open_term() {  # title, command
  for t in x-terminal-emulator gnome-terminal konsole xfce4-terminal kitty alacritty xterm; do
    if command -v "$t" >/dev/null; then
      case "$t" in
        gnome-terminal) setsid gnome-terminal --title="$1" -- bash -c "$2; exec bash" >/dev/null 2>&1 & ;;
        konsole)        setsid konsole -p tabtitle="$1" -e bash -c "$2; exec bash" >/dev/null 2>&1 & ;;
        *)              setsid "$t" -T "$1" -e bash -c "$2; exec bash" >/dev/null 2>&1 & ;;
      esac
      return 0
    fi
  done
  return 1
}
if ! open_term "Isaac Bot helper" "cd '$ROOT' && '$PY' brain/helper.py --auto"; then
  echo "No terminal program found: running the helper in the background (log: runs/helper.out)."
  mkdir -p "$ROOT/runs"
  setsid "$PY" "$ROOT/brain/helper.py" --auto >"$ROOT/runs/helper.out" 2>&1 &
fi
open_term "Isaac Bot log" "cd '$ROOT' && '$PY' brain/logview.py" || true

# 5. the game, through Steam (Proton + REPENTOGON as set up in Steam)
if game_running; then
  echo "Isaac is already running. The bot takes over the menu whenever the game is on it."
  exit 0
fi
if command -v steam >/dev/null; then
  setsid steam -applaunch "$APPID" >/dev/null 2>&1 &
else
  xdg-open "steam://rungameid/$APPID" >/dev/null 2>&1 &
fi
echo "Asked Steam to start Isaac, waiting for the game..."
for _ in $(seq 180); do game_running && { echo "Game is up."; exit 0; }; sleep 1; done
echo "The game didn't start within 3 minutes. Start it from Steam; the bot connects by itself."
