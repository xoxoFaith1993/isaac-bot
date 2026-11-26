"""Run Ghidra headless on a COPY of isaac-ng.exe: analyse once, then decompile chosen functions.

Why (2026-11-26, RE pilot): enemy AI lives only in the compiled exe. Everything this writes (Ghidra project,
decompiled C, logs) stays in the work folder, outside the repo; we commit only what we learn.

Usage:
    python tools/re/run_ghidra.py --ghidra <ghidra_dir> --work <work_dir> analyse
    python tools/re/run_ghidra.py --ghidra <ghidra_dir> --work <work_dir> apply      (re-apply names/fields)
    python tools/re/run_ghidra.py --ghidra <ghidra_dir> --work <work_dir> decompile <target> [<target> ...]
    python tools/re/run_ghidra.py --ghidra <ghidra_dir> --work <work_dir> probe <command> [<command> ...]

<work_dir> must hold isaac-ng.exe (a copy, never the game folder's file) and sigs.tsv / fields.tsv from
zhl_extract.py. Targets: see ghidra/DecompileFns.java. Temp files go to <work_dir>/tmp, the Ghidra
project to <work_dir>/proj, logs to <work_dir>/logs. Optional --safety-dir points at a folder holding the
PC's safety.py watchdog (pause on low memory or disk); without it the job runs unwatched.
"""
import argparse
import csv
import ctypes
import os
import re
import threading
import time
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ghidra', required=True)
    ap.add_argument('--work', required=True)
    ap.add_argument('--maxmem', default='6G')
    ap.add_argument('--cpus', default='6')
    ap.add_argument('--safety-dir')
    ap.add_argument('mode', choices=['analyse', 'apply', 'decompile', 'probe'])
    ap.add_argument('targets', nargs='*')
    a = ap.parse_args()

    work = Path(a.work)
    for d in ('tmp', 'proj', 'logs', 'scripts', 'out'):
        (work / d).mkdir(parents=True, exist_ok=True)
    # Ghidra's script path can't hold spaces reliably, so copy our scripts next to the project.
    for f in (HERE / 'ghidra').glob('*.java'):
        shutil.copy2(f, work / 'scripts' / f.name)

    env = dict(os.environ, TEMP=str(work / 'tmp'), TMP=str(work / 'tmp'),
               GHIDRA_HEADLESS_MAXMEM=a.maxmem)
    exe = Path(a.ghidra) / 'support' / 'analyzeHeadless.bat'
    common = [str(exe), str(work / 'proj'), 'isaac', '-scriptPath', str(work / 'scripts'),
              '-max-cpu', a.cpus]
    if a.mode == 'analyse':
        cmd = common + ['-import', str(work / 'isaac-ng.exe'), '-overwrite',
                        '-postScript', 'ApplyZhl.java', str(work),
                        '-analysisTimeoutPerFile', '7200',
                        '-log', str(work / 'logs' / 'analyse.log'),
                        '-scriptlog', str(work / 'logs' / 'analyse_script.log')]
    elif a.mode == 'apply':
        # re-apply names and fields to the existing project (after zhl_extract.py changes)
        cmd = common + ['-process', 'isaac-ng.exe', '-noanalysis', '-postScript', 'ApplyZhl.java', str(work),
                        '-log', str(work / 'logs' / 'apply.log'), '-scriptlog', str(work / 'logs' / 'apply_script.log')]
    else:
        script = 'DecompileFns.java' if a.mode == 'decompile' else 'Probe.java'
        cmd = common + ['-process', 'isaac-ng.exe', '-noanalysis',
                        '-postScript', script, str(work / 'out')] + a.targets + [
                        '-log', str(work / 'logs' / (a.mode + '.log')),
                        '-scriptlog', str(work / 'logs' / (a.mode + '_script.log'))]

    lock = work / 'logs' / 'ghidra.lock'
    if lock.exists() and _pid_alive(lock.read_text().strip()):
        print('another Ghidra run is active (one at a time); not starting')
        return 2
    ok, why = _memory_ok()
    if not ok:
        print('pre-flight failed:', why)
        return 3
    lock.write_text(str(os.getpid()))
    try:
        if a.safety_dir:
            sys.path.insert(0, a.safety_dir)
            import safety
            with safety.HeavyJob('isaac-re ghidra ' + a.mode, status_file=str(work / 'logs' / 'status.json')) as job:
                rc = job.run(cmd, env=env)
        else:
            # below-normal CPU priority (2026-11-26): the bot's benchmark runs the game on this PC at the same
            # time, and Ghidra must not slow it (or bias its timing). Child processes (java, decompile.exe)
            # inherit the priority class.
            p = subprocess.Popen(cmd, env=env, creationflags=getattr(subprocess, 'BELOW_NORMAL_PRIORITY_CLASS', 0))
            stop = threading.Event()
            t = threading.Thread(target=_watchdog, args=(p, a.ghidra, work / 'logs' / 'watchdog.log', stop), daemon=True)
            t.start()
            rc = p.wait()
            stop.set()
    finally:
        lock.unlink(missing_ok=True)
    print('exit', rc)
    return rc if isinstance(rc, int) else 0


# ---- PC safety watchdog (2026-11-26) ----------------------------------------------------------------------
# Ghidra's native decompile.exe once reached 13.3 GB and pushed RAM to 99%; the JVM -Xmx doesn't cap it.
# Rules (from the PC stability rules): kill decompile.exe above 4 GB; stop the whole job when free RAM or
# commit headroom falls below 6 GB; log everything it does. Uses only the standard library.
DECOMPILER_MAX_MB = 4096
MIN_FREE_GB = 6.0


class _MemStatus(ctypes.Structure):
    _fields_ = [('dwLength', ctypes.c_ulong), ('dwMemoryLoad', ctypes.c_ulong),
                ('ullTotalPhys', ctypes.c_ulonglong), ('ullAvailPhys', ctypes.c_ulonglong),
                ('ullTotalPageFile', ctypes.c_ulonglong), ('ullAvailPageFile', ctypes.c_ulonglong),
                ('ullTotalVirtual', ctypes.c_ulonglong), ('ullAvailVirtual', ctypes.c_ulonglong),
                ('ullAvailExtendedVirtual', ctypes.c_ulonglong)]


def _memory():
    m = _MemStatus()
    m.dwLength = ctypes.sizeof(_MemStatus)
    ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m))
    return m.ullAvailPhys / 2**30, m.ullAvailPageFile / 2**30   # free RAM, commit headroom (GB)


def _memory_ok():
    free, commit = _memory()
    if free < MIN_FREE_GB or commit < MIN_FREE_GB:
        return False, f'free RAM {free:.1f} GB, commit headroom {commit:.1f} GB (need {MIN_FREE_GB} each)'
    return True, ''


def _pid_alive(pid):
    try:
        out = subprocess.run(['tasklist', '/FI', f'PID eq {int(pid)}', '/FO', 'CSV', '/NH'],
                             capture_output=True, text=True).stdout
        return str(int(pid)) in out
    except (ValueError, OSError):
        return False


def _decompilers():
    """(pid, MB) of every decompile.exe (Ghidra's native decompiler)."""
    out = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq decompile.exe', '/FO', 'CSV', '/NH'],
                         capture_output=True, text=True).stdout
    procs = []
    for row in csv.reader(out.splitlines()):
        if len(row) >= 5 and row[0].lower() == 'decompile.exe':
            procs.append((int(row[1]), int(re.sub(r'[^\d]', '', row[4]) or 0) // 1024))
    return procs


def _watchdog(proc, ghidra_dir, log_path, stop):
    def log(msg):
        with open(log_path, 'a', encoding='utf-8') as f:
            f.write(time.strftime('%Y-%m-%d %H:%M:%S ') + msg + '\n')
    while not stop.wait(2.0):
        for pid, mb in _decompilers():
            if mb > DECOMPILER_MAX_MB:
                subprocess.run(['taskkill', '/F', '/PID', str(pid)], capture_output=True)
                log(f'killed decompile.exe pid {pid} at {mb} MB (cap {DECOMPILER_MAX_MB} MB)')
        free, commit = _memory()
        if free < MIN_FREE_GB or commit < MIN_FREE_GB:
            log(f'stopping the job: free RAM {free:.1f} GB, commit headroom {commit:.1f} GB')
            subprocess.run(['taskkill', '/F', '/T', '/PID', str(proc.pid)], capture_output=True)
            for pid, _ in _decompilers():
                subprocess.run(['taskkill', '/F', '/PID', str(pid)], capture_output=True)
            return


if __name__ == '__main__':
    sys.exit(main())
