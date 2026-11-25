"""See the game: grab still frames from Steam's background recording (the author's idea, 2026-11-25).

Steam records in 3-second DASH chunks (init-stream0.m4s + chunk-stream0-NNNNN.m4s) under
gamerecordings\\video\\bg_250900_*. The newest finished chunk is at most ~3 s old. This joins the header and the
last N chunks and pulls frames out with ffmpeg. Read-only: nothing in Steam's folder is changed.

Usage: python look.py [SECONDS_BACK=3] [FRAMES=4] [OUT_DIR]
Prints the image paths (newest last).
"""
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "brain"))
import botconfig  # noqa: E402  (Steam userdata folder and ffmpeg come from config.json)

REC = botconfig.recordings()
FFMPEG = botconfig.ffmpeg()


def main():
    back = float(sys.argv[1]) if len(sys.argv) > 1 else 3
    frames = int(sys.argv[2]) if len(sys.argv) > 2 else 4
    out = Path(sys.argv[3]) if len(sys.argv) > 3 else Path(tempfile.gettempdir()) / "isaac-look"
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("look_*.jpg"):
        old.unlink()
    # the live session = the folder whose newest finished chunk is the most recent (folder dates mislead)
    def newest(p):
        cs = list(p.glob("chunk-stream0-*.m4s"))
        return max((c.stat().st_mtime for c in cs), default=0)
    sessions = sorted((p for p in REC.glob("bg_250900_*") if p.is_dir()), key=newest)
    if not sessions:
        sys.exit("no Isaac recording found (is Steam background recording on?)")
    s = sessions[-1]
    init = s / "init-stream0.m4s"
    chunks = sorted(s.glob("chunk-stream0-*.m4s"), key=lambda p: p.name)  # finished chunks only (no .tmp)
    n = max(1, int(round(back / 3)))
    use = chunks[-n:]
    joined = out / "joined.mp4"
    with open(joined, "wb") as f:
        f.write(init.read_bytes())
        for c in use:
            f.write(c.read_bytes())
    dur = 3.0 * len(use)
    fps = frames / dur
    subprocess.run([FFMPEG, "-v", "error", "-y", "-i", str(joined), "-vf", f"fps={fps:.3f},scale=960:-1",
                    "-q:v", "4", str(out / "look_%02d.jpg")], check=True)
    joined.unlink(missing_ok=True)  # the ~1 MB joined video isn't needed once the frames are out
    for p in sorted(out.glob("look_*.jpg")):
        print(p)
    print(f"chunk {use[-1].name}, written {use[-1].stat().st_mtime:.0f}")


if __name__ == "__main__":
    main()
