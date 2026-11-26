"""Map floor 1-2 enemy types to their AI function and the shared building blocks it calls.

Why (2026-11-26, RE core pass): most enemies are combinations of a few shared helpers (fire modes, the
"can I shoot?" check, pathfinder moves...). Knowing which helpers each enemy's AI calls tells the bot which
known rules apply to it before anyone reads its AI by hand.

Usage (two passes; all inputs are local files from the RE work folder, nothing here is game data):
    python tools/re/floor_map.py --bestiary knowledge/bestiary_game.json --bytes <dispatch_bytes.txt>
        --dispatcher <dispatcher .c> --list            -> prints the AI function addresses to probe
    python tools/re/floor_map.py ... --callees <probe.txt from "callees:" commands>  -> markdown table

dispatch_bytes.txt: output of Probe "bytes:0x6cbe5c:958" (case byte per type 10..967).
"""
import argparse
import json
import re
from collections import Counter, defaultdict

CHAPTER1 = {'Basement', 'Cellar', 'Burning Basement', 'Downpour', 'Dross'}
TABLE_FIRST_TYPE = 10

# Shared helpers (addresses in the 2026-11-26 build; see docs/research/RE_CORE.md)
BLOCKS = {
    '006d2bb0': 'FireProjectiles',
    '006d46a0': 'FireBossProjectiles',
    '006d2730': 'CanShoot',
    '006c6390': 'TargetPos',
    '006c5f90': 'GetPlayerTarget',
    '007ed880': 'RandomAxisWalk',
    '007ebb70': 'PathChase',
    '007ee850': 'WanderBoss',
    '007ef620': 'HasPath',
    '00685f10': 'RandomDir',
    '00686010': 'AxisSnap',
    '00611e90': 'LaserWarning',
    '006ca000': 'ThrowSpider',
    '006df6d0': 'Effect',
}


def chapter1_types(bestiary):
    counts = Counter()
    for f in bestiary['floors']:
        if f['name'] not in CHAPTER1:
            continue
        for room_type in f['by_room_type'].values():
            for key, n in room_type.items():
                t = int(key.split('.')[0])
                if 10 <= t < 1000:
                    counts[key] += n
    return counts


def read_bytes(path):
    vals = []
    for line in open(path, encoding='utf-8'):
        if line.startswith('=='):
            continue
        vals += [int(x, 16) for x in line.split()]
    return vals


def dispatcher_cases(path):
    """case number -> list of called function addresses (in order) inside that case block."""
    text = open(path, encoding='utf-8').read()
    cases = {}
    for m in re.finditer(r'\n    case (0x[0-9a-f]+|\d+):(.*?)(?=\n    case |\n    default:|\n  \}\n)', text, re.S):
        n = int(m.group(1), 0)
        cases[n] = re.findall(r'FUN_([0-9a-f]{8})|(?:Entity_NPC::)?(ai_\w+)', m.group(2))
    return cases


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--bestiary', required=True)
    ap.add_argument('--bytes', required=True)
    ap.add_argument('--dispatcher', required=True)
    ap.add_argument('--callees')
    ap.add_argument('--list', action='store_true')
    a = ap.parse_args()

    best = json.load(open(a.bestiary, encoding='utf-8'))
    names = {e['key']: e.get('name', '') for e in best.get('entities', [])}
    counts = chapter1_types(best)
    table = read_bytes(a.bytes)
    cases = dispatcher_cases(a.dispatcher)

    by_type = defaultdict(list)
    for key in counts:
        by_type[int(key.split('.')[0])].append(key)
    rows, funcs = [], set()
    for t in sorted(by_type):
        if t - TABLE_FIRST_TYPE >= len(table):
            continue
        case = table[t - TABLE_FIRST_TYPE]
        calls = [x[0] or x[1] for x in cases.get(case, [])]
        funcs.update(c for c in calls if re.fullmatch(r'[0-9a-f]{8}', c))
        rows.append((t, case, calls, sorted(by_type[t], key=lambda k: -counts[k])))

    if a.list:
        print(' '.join('callees:0x' + f for f in sorted(funcs)))
        return

    callees = {}
    if a.callees:
        for line in open(a.callees, encoding='utf-8'):
            m = re.match(r'([0-9a-f]{8}) calls(.*)', line.strip())
            if m:
                callees[m.group(1)] = m.group(2).split()

    print('| Type | Enemies (chapter 1 room count) | Case | AI function(s) | Building blocks called |')
    print('|---|---|---|---|---|')
    for t, case, calls, keys in rows:
        ents = ', '.join(f"{names.get(k, k)} {k} ({counts[k]})" for k in keys[:4])
        fn = ', '.join('0x' + c.lstrip('0') if re.fullmatch(r'[0-9a-f]{8}', c) else c for c in calls[:3]) or '(inline)'
        blocks = set()
        for c in calls:
            for k in callees.get(c, []):
                if k in BLOCKS:
                    blocks.add(BLOCKS[k])
        print(f"| {t} | {ents} | 0x{case:x} | {fn} | {', '.join(sorted(blocks)) or '-'} |")


if __name__ == '__main__':
    main()
