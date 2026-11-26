"""Install the git pre-commit hook that runs tools/privacy_check.py before every commit.
Run once after cloning:  python tools/install_hooks.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
hook = ROOT / ".git" / "hooks" / "pre-commit"
py = Path(sys.executable).as_posix()
hook.write_text(f'#!/bin/sh\nexec "{py}" tools/privacy_check.py\n', encoding="utf-8", newline="\n")
try:
    hook.chmod(0o755)
except OSError:
    pass
print("Installed", hook)
