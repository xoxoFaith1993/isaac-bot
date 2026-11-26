"""Draft playbook tags for every enemy (2026-11-25): the local AI (Ollama) reads each enemy's wiki text plus its
animations from the game files and picks tags from the playbook's own vocabulary.

Inputs : knowledge\\wiki_bestiary.json (wiki_bestiary.py), knowledge\\bestiary_game.json (bestiary_game.py),
         knowledge\\enemy_playbook.json (vocabulary, scales, hand-checked examples).
Output : knowledge\\playbook_draft.json, one draft per type.variant. Hand-checked playbook entries always win when
         merged; drafts are marked "draft" until someone reviews them.

  python tag_bestiary.py --test 261.0 10.1 23.0   tag a few and print them (no output file)
  python tag_bestiary.py                          tag everything (resumable: answers cached in config "cache_dir")
  python tag_bestiary.py --model gemma4:12b       pick the model (default below)

If config.json "safety_tools" points at a folder with safety.py / progress.py, it runs under them (pauses when memory
or disk gets low, feeds a progress bar); otherwise it runs plainly.
"""
import argparse
import hashlib
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "brain"))
import botconfig  # noqa: E402

K = botconfig.ROOT / "knowledge"
CACHE = Path(botconfig.CFG.get("cache_dir") or (botconfig.ROOT / "runs" / "cache")) / "isaac-wiki-cache" / "tags"
OUT = K / "playbook_draft.json"
OLLAMA = "http://localhost:11434/api/chat"
DEFAULT_MODEL = "gemma4:12b"   # the bot's rescue brain uses it too (one copy in VRAM)
THINK = False                  # thinking: ~5x slower, tags not clearly better in a test (2026-11-25)
EXAMPLES = ("23.0", "261.0", "18.0", "220.0")   # hand-checked playbook entries shown to the model
# optional: a folder with your own safety.py (HeavyJob: pause on low memory/disk) and progress.py (progress bar),
# config.json "safety_tools"; without them the job runs with simple stand-ins
TOOLS = botconfig.CFG.get("safety_tools") or ""


class _Stand:
    """Stand-in for safety.py / progress.py when they aren't there: no pausing, progress printed plainly."""
    class HeavyJob:
        def __init__(self, name):
            self.name = name

        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

        def checkpoint(self):
            pass

    @staticmethod
    def write(title, text, *rest):
        print(f"{title}: {text}", flush=True)


def load():
    wiki = json.loads((K / "wiki_bestiary.json").read_text(encoding="utf-8"))["entries"]
    game = json.loads((K / "bestiary_game.json").read_text(encoding="utf-8"))
    pb = json.loads((K / "enemy_playbook.json").read_text(encoding="utf-8"))
    rows = {}
    for e in game["entities"]:
        rows.setdefault(e["key"], e)
    return wiki, game, rows, pb


def anim_lines(key, game, rows):
    row = rows.get(key)
    if not row:
        return "(no game data)"
    out = []
    for a in game["animations"].get(row.get("anm2"), []):
        ev = a.get("events")
        evs = (" events " + ", ".join(f"{n}@{'/'.join(str(f) for f in fs)}" for n, fs in ev.items())) if ev else ""
        out.append(f"{a['name']} ({a.get('len')}f{', loops' if a.get('loop') else ''}{evs})")
    return "; ".join(out[:40]) or "(no animations)"


def schema(vocab):
    arr = lambda cat: {"type": "array", "items": {"type": "string", "enum": list(vocab[cat])}}  # noqa: E731
    return {"type": "object", "required": ["movement", "attacks", "defense", "danger", "kill_priority", "how",
                                           "tell_anims", "unsure"],
            "properties": {"movement": arr("movement"), "attacks": arr("attacks"), "defense": arr("defense"),
                           "danger": {"type": "integer", "minimum": 1, "maximum": 5},
                           "kill_priority": {"type": "integer", "minimum": 0, "maximum": 3},
                           "how": {"type": "string"}, "tell_anims": {"type": "array", "items": {"type": "string"}},
                           "unsure": {"type": "string"}}}


def system_prompt(pb):
    voc = pb["vocabulary"]
    lines = ["You tag enemies of The Binding of Isaac: Repentance+ for a bot whose goal is to never take damage.",
             "Use ONLY tags from these lists; pick every tag that clearly applies, none that are guesses.", ""]
    for cat in ("movement", "attacks", "defense"):
        lines.append(f"{cat.upper()} tags:")
        lines += [f"- {t}: {d}" for t, d in voc[cat].items()]
        lines.append("")
    lines += [f"danger: {pb['scales']['danger']}", f"kill_priority: {pb['scales']['kill_priority']}", "",
              "how: ONE short sentence (max 25 words) telling the bot how to avoid getting hit by it and how to "
              "fight it (distance, lines to avoid, when to shoot). Plain words.",
              "tell_anims: animation names from the game list that come right BEFORE or ARE its attacks "
              "(e.g. one with a Shoot event, or a wind-up); empty if none fit.",
              "unsure: say what you couldn't tell from the text, or empty string.",
              "Repentance+ behaviour wins over older versions. Answer with JSON only.", "",
              "Isaac terms: 'Ipecac' shot = lobbed (explodes where it lands); 'Brimstone' = laser; any dash or charge "
              "or slide toward Isaac = dashes_at_isaac, and charges_on_line when it only happens in a straight row or "
              "column (often 'when aligned' / 'cardinal'); 'creep' = leaves_creep; 'spawns'/'summons' = "
              "spawns_enemies; 'invulnerable'/'can't be damaged' until something = invulnerable_until. "
              "Tag only the NORMAL version: ignore Champion versions, Delirium and Greed Mode text.", "",
              "Examples (hand-checked):"]
    for k in EXAMPLES:
        e = pb["enemies"].get(k)
        if e:
            lines.append(json.dumps({"enemy": e["name"], "movement": e.get("movement", []),
                                     "attacks": e.get("attacks", []), "defense": e.get("defense", []),
                                     "danger": e.get("danger"), "kill_priority": e.get("kill_priority"),
                                     "how": e.get("how")}))
    return "\n".join(lines)


def user_prompt(key, w, game, rows):
    secs = w.get("_sections") or {}
    parts = [f"Enemy {w['name']} (id {key}, {w['kind']}), base HP {w.get('base_hp')}",
             f"Floors: {', '.join(w.get('floors') or []) or 'not listed'}",
             f"Wiki one-line behaviour: {w.get('behavior') or '-'}",
             f"Wiki description: {(w.get('description') or '-')[:1500]}"]
    for name, txt in secs.items():
        parts.append(f"Page section '{name}': {txt[:1800]}")
    parts.append(f"Game animations: {anim_lines(key, game, rows)}")
    return "\n".join(parts)


def ask(model, system, user, sch):
    # keep_alive 45s like the bot's own brain: a 10 min keep_alive held ~13 GB of RAM while the PC hit its memory
    # limit (main session, 2026-11-25)
    body = {"model": model, "stream": False, "format": sch, "keep_alive": "45s", "think": THINK,
            "options": {"temperature": 0.1, "num_ctx": 8192},
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}]}
    req = urllib.request.Request(OLLAMA, data=json.dumps(body).encode("utf-8"),
                                 headers={"Content-Type": "application/json"})
    # Ollama can go away for a while (first full run, 2026-11-25: 180 "connection refused" in a row while the game
    # restarted): wait for it to come back instead of skipping enemies, up to ~10 minutes
    for attempt in range(20):
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                return json.loads(json.loads(r.read().decode("utf-8"))["message"]["content"])
        except (ConnectionError, urllib.error.URLError) as e:
            if attempt == 19:
                raise
            print(f"  Ollama not answering ({str(e)[:80]}); retry in 30 s", flush=True)
            time.sleep(30)


def unload(model):
    """Free the model's RAM/VRAM right away (same as 'ollama stop')."""
    try:
        req = urllib.request.Request("http://localhost:11434/api/generate",
                                     data=json.dumps({"model": model, "keep_alive": 0}).encode("utf-8"),
                                     headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=30).read()
    except Exception as e:
        print(f"  couldn't unload {model}: {e}")


def clean(ans, vocab, anims):
    res = {c: [t for t in ans.get(c, []) if t in vocab[c]] for c in ("movement", "attacks", "defense")}
    res["danger"] = max(1, min(5, int(ans.get("danger") or 3)))
    res["kill_priority"] = max(0, min(3, int(ans.get("kill_priority") or 2)))
    res["how"] = (ans.get("how") or "").strip()[:240]
    res["tell_anims"] = [a for a in ans.get("tell_anims", []) if a in anims]
    res["unsure"] = (ans.get("unsure") or "").strip()[:240]
    return res


def tag_one(key, w, game, rows, pb, model, system, sch):
    user = user_prompt(key, w, game, rows)
    h = hashlib.sha1((model + str(THINK) + system + user).encode("utf-8")).hexdigest()[:16]
    cf = CACHE / f"{key}.{h}.json"
    if cf.exists():
        return json.loads(cf.read_text(encoding="utf-8"))
    row = rows.get(key)
    anims = {a["name"] for a in game["animations"].get(row.get("anm2"), [])} if row else set()
    t = time.time()
    ans = clean(ask(model, system, user, sch), pb["vocabulary"], anims)
    ans["secs"] = round(time.time() - t, 1)
    cf.write_text(json.dumps(ans, ensure_ascii=False), encoding="utf-8")
    return ans


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--test", nargs="*")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    a = ap.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    wiki_all = json.loads((K / "wiki_bestiary.json").read_text(encoding="utf-8"))
    pages = {p["title"]: p for p in wiki_all["pages"]}
    wiki, game, rows, pb = load()
    for w in wiki.values():  # attach the page's sections (Behavior, Notes, Strategy...) to each variant
        w["_sections"] = (pages.get(w["page"]) or {}).get("sections", {})
    system, sch = system_prompt(pb), schema(pb["vocabulary"])
    if a.test is not None:
        for key in a.test:
            if key not in wiki:
                print(key, "not in the wiki bestiary")
                continue
            r = tag_one(key, wiki[key], game, rows, pb, a.model, system, sch)
            hand = pb["enemies"].get(key)
            print(f"== {key} {wiki[key]['name']} ({r.get('secs')} s)\n draft: {json.dumps(r, ensure_ascii=False)}")
            if hand:
                print(" hand : " + json.dumps({x: hand.get(x) for x in ("movement", "attacks", "defense", "danger",
                                                                       "kill_priority", "how")}))
        return

    try:
        if TOOLS:
            sys.path.insert(0, str(TOOLS))
        import progress  # noqa: E402
        import safety    # noqa: E402
    except ImportError:
        progress, safety = _Stand(), _Stand()
    keys = sorted(wiki, key=lambda k: (int(k.split(".")[0]), int(k.split(".")[1])))
    out, fails, t0 = {}, [], time.time()
    with safety.HeavyJob("isaac-bot playbook tags") as job:
        for i, key in enumerate(keys, 1):
            job.checkpoint()
            w = wiki[key]
            try:
                r = tag_one(key, w, game, rows, pb, a.model, system, sch)
            except Exception as e:  # one bad answer must not stop the batch
                fails.append((key, str(e)[:200]))
                continue
            row = rows.get(key) or {}
            out[key] = dict(r, name=w["name"], kind=w["kind"], floors=w.get("floors") or [],
                            base_hp=w.get("base_hp"), page=w["page"], hand_checked=key in pb["enemies"],
                            radius=(row.get("cfg") or {}).get("radius"),
                            source=f"draft: wiki + game files via {a.model}")
            done = time.time() - t0
            eta = done / i * (len(keys) - i) / 60
            progress.write("Isaac bestiary: tagging enemies", f"{i}/{len(keys)} {w['name']}",
                           round(100 * i / len(keys)), round(eta, 1))
            if i % 25 == 0:
                print(f"{i}/{len(keys)}  {done / 60:.1f} min  eta {eta:.1f} min  fails {len(fails)}", flush=True)
                OUT.write_text(json.dumps({"partial": True, "entries": out}, ensure_ascii=False), encoding="utf-8")
    OUT.write_text(json.dumps({
        "about": "Draft playbook tags for every enemy variant, made by a local AI from the wiki text and the game's "
                 "animation data. Not hand-checked: entries in enemy_playbook.json always win.",
        "made": time.strftime("%Y-%m-%d %H:%M"), "model": a.model, "vocabulary": "see enemy_playbook.json",
        "fails": fails, "entries": out}, indent=1, ensure_ascii=False), encoding="utf-8")
    progress.write("Isaac bestiary: tagging enemies", f"done: {len(out)} tagged, {len(fails)} failed", 100, 0)
    unload(a.model)
    print(f"saved {OUT}: {len(out)} drafts, {len(fails)} failed, {(time.time() - t0) / 60:.1f} min")


if __name__ == "__main__":
    main()
