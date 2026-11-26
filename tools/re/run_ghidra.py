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
import os
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

    if a.safety_dir:
        sys.path.insert(0, a.safety_dir)
        import safety
        with safety.HeavyJob('isaac-re ghidra ' + a.mode, status_file=str(work / 'logs' / 'status.json')) as job:
            rc = job.run(cmd, env=env)
    else:
        rc = subprocess.call(cmd, env=env)
    print('exit', rc)
    return rc if isinstance(rc, int) else 0


if __name__ == '__main__':
    sys.exit(main())
