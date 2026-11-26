"""Wiki bestiary (2026-11-25): every monster and boss page of the Binding of Isaac wiki, as behaviour text per enemy.

Baseline for the enemy playbook: the wiki says how each enemy moves and attacks; a later step turns that text into
playbook tags. Reads the wiki's own API (MediaWiki), 50 pages per request, one request a second, and caches every
page so a rerun only fetches what's missing.

  python wiki_bestiary.py            fetch (cached) and write knowledge\\wiki_bestiary.json
  python wiki_bestiary.py --refresh  fetch every page again
  python wiki_bestiary.py --parse    only re-parse the cache (no network)

Output: one entry per enemy variant ("type.variant", like the playbook): name, page, HP, floors, the infobox's
one-line behaviour, the variant's own paragraph, and the page's Behavior / Notes / Champion / Strategy sections.
The wiki's text is CC BY-SA, so the output stays local (see .gitignore); only derived tags go in the playbook.
"""
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "brain"))
import botconfig  # noqa: E402

API = "https://bindingofisaacrebirth.wiki.gg/api.php"
PAGE_URL = "https://bindingofisaacrebirth.wiki.gg/wiki/"
UA = "isaac-bot-research/0.1 (personal game-bot project; polite batch reader)"
ROOT_CATS = ["Category:Monsters"]          # includes Bosses and Mini-bosses as subcategories
# cache of fetched pages: config.json "cache_dir" (big, regenerable data), default runs\cache inside the bot folder
CACHE = Path(botconfig.CFG.get("cache_dir") or (botconfig.ROOT / "runs" / "cache")) / "isaac-wiki-cache"
OUT = botconfig.ROOT / "knowledge" / "wiki_bestiary.json"
DELAY = 1.0
KEEP_SECTIONS = ("behavior", "behaviour", "attacks", "notes", "champion", "strategy", "tips", "phase")


def api(params):
    params = dict(params, format="json", formatversion="2")
    req = urllib.request.Request(API + "?" + urllib.parse.urlencode(params), headers={"User-Agent": UA})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                data = json.loads(r.read().decode("utf-8"))
            time.sleep(DELAY)
            return data
        except Exception as e:  # network hiccup or rate limit: back off and retry
            wait = 5 * (attempt + 1)
            print(f"  request failed ({e}); retry in {wait} s")
            time.sleep(wait)
    raise SystemExit("the wiki API keeps failing; stopping (rerun later, the cache keeps finished pages)")


def crawl():
    """All page titles under the root categories, with the category path they were found in."""
    seen_cats, found = set(), {}
    todo = [(c, (c,)) for c in ROOT_CATS]
    while todo:
        cat, path = todo.pop(0)
        if cat in seen_cats or len(path) > 5:
            continue
        seen_cats.add(cat)
        cont = {}
        while True:
            d = api(dict({"action": "query", "list": "categorymembers", "cmtitle": cat, "cmlimit": "500",
                          "cmtype": "page|subcat"}, **cont))
            for m in d["query"]["categorymembers"]:
                if m["ns"] == 14:
                    todo.append((m["title"], path + (m["title"],)))
                elif m["ns"] == 0:
                    found.setdefault(m["title"], set()).update(path)
            if "continue" not in d:
                break
            cont = d["continue"]
        print(f"  {cat}: {len(found)} pages so far, {len(todo)} categories left")
    return {t: sorted(c) for t, c in found.items()}


def safe_name(title):
    return re.sub(r'[<>:"/\\|?*]', "_", title) + ".txt"


def fetch(titles, refresh=False):
    pages = CACHE / "pages"
    pages.mkdir(parents=True, exist_ok=True)
    need = [t for t in titles if refresh or not (pages / safe_name(t)).exists()]
    print(f"fetching {len(need)} of {len(titles)} pages ({len(titles) - len(need)} cached)")
    for i in range(0, len(need), 50):
        batch = need[i:i + 50]
        d = api({"action": "query", "prop": "revisions", "rvprop": "content", "rvslots": "main",
                 "titles": "|".join(batch), "redirects": "1"})
        redirects = {r["to"]: r["from"] for r in d["query"].get("redirects", [])}
        for p in d["query"]["pages"]:
            if p.get("missing") or not p.get("revisions"):
                continue
            title = redirects.get(p["title"], p["title"])
            (pages / safe_name(title)).write_text(p["revisions"][0]["slots"]["main"]["content"], encoding="utf-8")
        print(f"  {min(i + 50, len(need))}/{len(need)}")


# ---------------- wikitext parsing ----------------

def templates(text, start_pat):
    """Top-level {{...}} blocks whose name matches start_pat, with their span."""
    out = []
    for m in re.finditer(r"\{\{\s*" + start_pat, text, re.I):
        depth, i = 0, m.start()
        while i < len(text) - 1:
            two = text[i:i + 2]
            if two == "{{":
                depth += 1
                i += 2
                continue
            if two == "}}":
                depth -= 1
                i += 2
                if depth == 0:
                    break
                continue
            i += 1
        out.append((m.start(), i, text[m.start():i]))
    return out


def params(block):
    """Top-level |key = value pairs of a template block."""
    inner = block[2:-2]
    parts, depth, cur, i = [], 0, "", 0
    while i < len(inner):
        two = inner[i:i + 2]
        if two in ("{{", "[["):
            depth += 1
            cur += two
            i += 2
            continue
        if two in ("}}", "]]"):
            depth -= 1
            cur += two
            i += 2
            continue
        if inner[i] == "|" and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += inner[i]
        i += 1
    parts.append(cur)
    res = {}
    for p in parts[1:]:
        if "=" in p:
            k, v = p.split("=", 1)
            res[k.strip().lower()] = v.strip()
    return res


DLC = {"nr": "[not Repentance]", "r": "[Repentance]", "r+": "[Repentance+]", "a": "[Afterbirth]",
       "a+": "[Afterbirth+]", "na": "[not Afterbirth]", "nr+": "[not Repentance+]"}


def clean(text):
    """Wikitext to plain text (keeps version markers like [Repentance])."""
    t = text
    t = re.sub(r"<!--.*?-->", "", t, flags=re.S)
    t = re.sub(r"<ref[^>]*/>|<ref.*?</ref>", "", t, flags=re.S)
    t = re.sub(r"<gallery.*?</gallery>", "", t, flags=re.S | re.I)
    t = re.sub(r"<br\s*/?>", "; ", t, flags=re.I)
    t = re.sub(r"\{\{\s*dlc\+?\s*\|\s*([a-z+]+)[^}]*\}\}", lambda m: DLC.get(m.group(1).lower(), ""), t, flags=re.I)
    t = re.sub(r"\{\{\s*dlc-\s*\}\}", "", t, flags=re.I)
    for _ in range(4):  # innermost templates first: {{e|Name}} / {{floor|X}} / {{i|Item|..}} -> their first argument
        t = re.sub(r"\{\{\s*(?:bc|unlockable|clear|toc)[^{}]*\}\}", "", t, flags=re.I)
        t = re.sub(r"\{\{\s*[^{}|]+\|\s*([^{}|]*)(?:\|[^{}]*)?\}\}", r"\1", t)
        t = re.sub(r"\{\{[^{}]*\}\}", "", t)
    t = re.sub(r"\[\[(?:File|Image):[^\]]*\]\]", "", t, flags=re.I)
    t = re.sub(r"\[\[[^\]|]*\|([^\]]*)\]\]", r"\1", t)
    t = re.sub(r"\[\[([^\]]*)\]\]", r"\1", t)
    t = re.sub(r"'{2,}", "", t)
    t = re.sub(r"<[^>]+>", "", t)
    t = re.sub(r"__[A-Z]+__", "", t)
    t = re.sub(r"[ \t]+", " ", t)
    t = re.sub(r"\n{3,}", "\n\n", t)
    return t.strip()


def floors(env):
    """Floors from an infobox environment: (normal floors, pre-Repentance-only floors, {other role: floors}).
    Boss pages group floors under underlined headers: Boss / Double Trouble / Degraded Boss; only the first
    (or Boss / Mini-Boss) counts as where it normally appears."""
    cur, sect, out, old, other = None, "main", [], [], {}
    pat = r"<u>(.*?)</u>|\{\{\s*(dlc\+?|floor|room)\s*\|\s*([^}|]+)"
    for tok in re.finditer(pat, env or "", re.I):
        if tok.group(1) is not None:
            head = clean(tok.group(1)).strip()
            sect = "main" if head.lower().replace("-", "").replace(" ", "") in ("boss", "miniboss") else head
            cur = None
            continue
        kind, val = tok.group(2).lower(), tok.group(3).strip()
        if kind.startswith("dlc"):
            cur = val.lower()
        elif kind == "floor":
            if sect != "main":
                if cur not in ("nr", "na"):
                    other.setdefault(sect, []).append(val)
            else:
                (old if cur in ("nr", "na") else out).append(val)
    return sorted(set(out)), sorted(set(old) - set(out)), {k: sorted(set(v)) for k, v in other.items()}


def sections(text):
    """{heading: cleaned text} for the sections worth keeping."""
    res = {}
    parts = re.split(r"^(={2,4})\s*(.*?)\s*\1\s*$", text, flags=re.M)
    for i in range(1, len(parts) - 2, 3):
        head = clean(parts[i + 1]).strip().lower()
        body = parts[i + 2]
        if any(k in head for k in KEEP_SECTIONS):
            txt = clean(body)
            if txt:
                res[head] = txt[:4000]
    return res


INFOBOX = r"infobox\s+(monster|boss|mini-?boss|enemy)"


def parse_page(title, text, cats):
    boxes = templates(text, INFOBOX)
    if not boxes:
        return None, []
    kind_cats = " ".join(cats).lower()
    page = {"title": title, "url": PAGE_URL + urllib.parse.quote(title.replace(" ", "_")),
            "categories": cats, "sections": sections(text)}
    entries, page_id = [], None
    for n, (s, e, block) in enumerate(boxes):
        p = params(block)
        box_kind = re.match(r"\{\{\s*" + INFOBOX, block, re.I).group(1).lower()
        if p.get("id"):
            page_id = p["id"]
        tid = re.match(r"\d+", clean(p.get("id") or page_id or ""))
        if not tid:
            continue
        var = re.match(r"\d+", clean(p.get("variant") or "0")) or re.match(r"\d+", "0")
        nxt = boxes[n + 1][0] if n + 1 < len(boxes) else len(text)
        own = text[e:nxt]
        own = re.split(r"^={2,4}[^=\n]+={2,4}\s*$", own, maxsplit=1, flags=re.M)[0]
        fl, old, other = floors(p.get("environment"))
        if "mini" in box_kind or "category:mini-bosses" in kind_cats:
            kind = "miniboss"
        elif box_kind == "boss":
            kind = "boss"
        else:
            kind = "monster"
        entries.append({
            "key": f"{tid.group(0)}.{var.group(0)}", "name": clean(p.get("name") or title), "page": title,
            "kind": kind, "base_hp": clean(p.get("base hp") or p.get("hp") or "") or None,
            "floors": fl, "floors_pre_repentance_only": old, "floors_other": other or None,
            "environment": clean(p.get("environment") or "")[:600] or None,
            "behavior": clean(p.get("behavior") or p.get("behaviour") or "") or None,
            "description": clean(own)[:2000] or None,
            "dlc": p.get("dlc"),
        })
    return page, entries


def parse(index):
    pages_dir = CACHE / "pages"
    pages, entries, skipped = [], {}, []
    for title, cats in sorted(index.items()):
        f = pages_dir / safe_name(title)
        if not f.exists():
            skipped.append((title, "not fetched"))
            continue
        page, ents = parse_page(title, f.read_text(encoding="utf-8"), cats)
        if not page:
            skipped.append((title, "no monster/boss infobox"))
            continue
        pages.append(page)
        for e in ents:
            if e["key"] in entries:
                entries[e["key"]].setdefault("also_on", []).append(e["page"] + ": " + e["name"])
            else:
                entries[e["key"]] = e
    return pages, entries, skipped


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    idx_file = CACHE / "index.json"
    if "--parse" in sys.argv and idx_file.exists():
        index = json.loads(idx_file.read_text(encoding="utf-8"))
    else:
        print("listing categories...")
        index = crawl()
        idx_file.write_text(json.dumps(index, indent=1), encoding="utf-8")
        fetch(sorted(index), refresh="--refresh" in sys.argv)
    pages, entries, skipped = parse(index)
    out = {"about": "Behaviour text for every monster/boss variant on the Binding of Isaac wiki (wiki.gg), keyed "
                    "type.variant like enemy_playbook.json. Baseline input for playbook tags. Local only (CC BY-SA "
                    "text).", "source": PAGE_URL, "made": time.strftime("%Y-%m-%d %H:%M"),
           "pages_listed": len(index), "pages_parsed": len(pages), "entries_n": len(entries),
           "skipped": skipped, "pages": pages, "entries": entries}
    OUT.write_text(json.dumps(out, indent=1, ensure_ascii=False), encoding="utf-8")
    kinds = {}
    for e in entries.values():
        kinds[e["kind"]] = kinds.get(e["kind"], 0) + 1
    print(f"saved {OUT} ({OUT.stat().st_size // 1024} KB): {len(pages)} pages, {len(entries)} enemy variants "
          f"{kinds}; {len(skipped)} pages skipped")


if __name__ == "__main__":
    main()
