"""Turn REPENTOGON's libzhl/functions/*.zhl files into two plain tables for Ghidra.

Why (2026-11-26, RE pilot): the game's enemy AI is compiled into isaac-ng.exe with no names. REPENTOGON
keeps byte signatures and names for about 1,700 functions and the field offsets of the game's structs.
Applying those to a Ghidra project turns `*(int *)(param_1 + 0xb64)` into `this->State`, which makes the
decompiled AI readable. This script only reads the .zhl files; it copies no game code.

Usage:
    python tools/re/zhl_extract.py <REPENTOGON>/libzhl/functions <out_dir>

Writes:
    <out_dir>/sigs.tsv    signature<TAB>Class::Name<TAB>source file   (one per function signature)
    <out_dir>/fields.tsv  struct<TAB>offset<TAB>type<TAB>field         (fields with a fixed offset)
"""
import re
import sys
from pathlib import Path

SIG_RE = re.compile(r'^\s*"([0-9A-Fa-f?()]*)"\s*:')
FIELD_RE = re.compile(r'^\s*([A-Za-z_][\w:<>, ]*?[\w>*&\s])\s*\b([A-Za-z_]\w*)\s*:\s*(0x[0-9A-Fa-f]+)\s*;')
STRUCT_RE = re.compile(r'^\s*struct\s+([A-Za-z_]\w*)')
MULTI_RE = re.compile(r'^\s*((?:unsigned |signed |const )*[A-Za-z_][\w:<>]*\s*\**)\s+[A-Za-z_]\w*\s*:\s*0x[0-9A-Fa-f]+\s*,')
PAIR_RE = re.compile(r'([A-Za-z_]\w*)\s*:\s*(0x[0-9A-Fa-f]+)')
NAME_RE =re.compile(r'([A-Za-z_]\w*(?:::[A-Za-z_~]\w*)+|[A-Za-z_~]\w*)\s*\(')


def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)


def parse(path):
    sigs, fields = [], []
    lines = strip_comments(path.read_text(encoding='utf-8', errors='replace')).splitlines()
    struct = None          # struct we are inside (for vtable entries and fields)
    pending = None         # signature waiting for its declaration
    decl = ''
    for line in lines:
        m = STRUCT_RE.match(line)
        if m and '(' not in line.split('struct', 1)[1].split('depends')[0]:
            struct = m.group(1)
        if re.match(r'^\s*}\s*:\s*0x[0-9A-Fa-f]+\s*;', line):
            struct = None
        m = SIG_RE.match(line)
        if m:
            pending, decl = m.group(1), ''
            continue
        if pending is not None:
            s = line.strip()
            if not s or s in ('override',):
                continue
            decl += ' ' + s
            if ';' not in decl:
                continue
            nm = NAME_RE.search(decl)
            sig = pending
            pending = None
            if not nm or not sig or 'reference' in decl.split('(')[0]:
                continue
            name = nm.group(1)
            if '::' not in name and struct:
                name = struct + '::' + name
            sigs.append((sig.lower(), name, path.name))
            continue
        if struct and ',' in line and MULTI_RE.match(line):
            # one type, several fields: "float A : 0x4, B : 0x8, C : 0xc;"
            # (fixed 2026-11-26: the single-field regex kept only the last name of such a line)
            typ = MULTI_RE.match(line).group(1)
            for name, off in PAIR_RE.findall(line):
                fields.append((struct, off.lower(), ' '.join(typ.split()), name))
            continue
        m = FIELD_RE.match(line)
        if m and struct:
            fields.append((struct, m.group(3).lower(), ' '.join(m.group(1).split()), m.group(2)))
    return sigs, fields


def main():
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    all_sigs, all_fields = [], []
    for p in sorted(src.glob('*.zhl')):
        s, f = parse(p)
        all_sigs += s
        all_fields += f
    (out / 'sigs.tsv').write_text(''.join('\t'.join(r) + '\n' for r in all_sigs), encoding='utf-8')
    (out / 'fields.tsv').write_text(''.join('\t'.join(r) + '\n' for r in all_fields), encoding='utf-8')
    print(f'{len(all_sigs)} signatures, {len(all_fields)} fields -> {out}')


if __name__ == '__main__':
    main()
