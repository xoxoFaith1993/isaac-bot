"""Privacy guard: stops a commit that would publish personal details.

Runs from the git pre-commit hook (see tools/install_hooks.py) or by hand:
    python tools/privacy_check.py           # check what is staged for the next commit
    python tools/privacy_check.py --all     # check every tracked file

Two kinds of patterns:
  * generic ones below (home folders, private IP addresses, e-mail addresses, Steam user ids)
  * your own words in privacy_words.txt next to this repo's root (one per line, never committed:
    it is in .gitignore), e.g. your name, your Windows user name, your Steam id.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

GENERIC = [
    (r"[A-Za-z]:\\Users\\(?!<|you\b|USER\b|%)[A-Za-z0-9_.-]+", "a Windows home folder"),
    (r"/home/(?!<|you\b|user\b|\$)[a-z0-9_.-]+", "a Linux home folder"),
    (r"\b192\.168\.\d+\.\d+\b|\b10\.\d+\.\d+\.\d+\b", "a private IP address"),
    (r"steam\\?/?userdata[\\/]\d{5,}", "a Steam user id"),
    (r"[\w.+-]+@(?!users\.noreply\.github\.com|example\.com|anthropic\.com)[\w-]+\.[\w.]+", "an e-mail address"),
    (r"G:" r"\\My Drive|One" r"Drive\\", "a cloud-drive folder"),  # split so this line doesn't match itself
    # any other drive-letter folder (2026-11-26: a doc named the author's local dev-copy folder - nothing personal, but
    # meaningless to readers). The standard install folders (Windows, Program Files) are fine.
    # (not after a backslash or a letter: "\d\d:\d\d" in a regex isn't a drive; "path\to" placeholders are fine)
    (r"(?<![\\\w])[A-Za-z]:\\\\?(?!Windows\\|Program Files|path\\\\?to\\)[A-Za-z0-9_][^\s\"'`|<>)]*",
     "a local folder path"),
]

SKIP_SUFFIX = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".mp4", ".zip", ".dll", ".exe"}


def own_words():
    f = ROOT / "privacy_words.txt"
    if not f.exists():
        return []
    words = []
    for line in f.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            words.append((r"(?<![A-Za-z])" + re.escape(line) + r"(?![A-Za-z])", "a private word"))
    return words


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, check=True).stdout


def files(all_files):
    if all_files:
        out = git("ls-files")
    else:
        out = git("diff", "--cached", "--name-only", "--diff-filter=ACMR")
    return [p for p in out.decode("utf-8", "replace").splitlines() if p]


def content(path, all_files):
    if all_files:
        return (ROOT / path).read_bytes()
    return git("show", ":" + path)


def main():
    all_files = "--all" in sys.argv
    patterns = [(re.compile(p, re.IGNORECASE), why) for p, why in GENERIC + own_words()]
    problems = []
    for path in files(all_files):
        if Path(path).suffix.lower() in SKIP_SUFFIX:
            continue
        text = content(path, all_files).decode("utf-8", "replace")
        for n, line in enumerate(text.splitlines(), 1):
            for rx, why in patterns:
                m = rx.search(line)
                if m:
                    problems.append(f"{path}:{n}: {why}: {m.group(0)[:40]}")
    if problems:
        print("Privacy check FAILED. These lines would publish personal details:")
        for p in problems[:50]:
            print("  " + p)
        if len(problems) > 50:
            print(f"  ... and {len(problems) - 50} more")
        print("Fix them (or, if one is a false alarm, reword it) and commit again.")
        return 1
    print(f"Privacy check OK ({'all tracked' if all_files else 'staged'} files).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
