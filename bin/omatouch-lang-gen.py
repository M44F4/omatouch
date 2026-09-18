#!/usr/bin/env python3
"""Generate OmaTouch language data from local XKB and Compose data."""
import argparse
import concurrent.futures
import ctypes
import json
import os
import re
import subprocess
import sys
import unicodedata
from pathlib import Path

SCHEMA_VERSION = 2

POSITIONS = {
    "numberRow": ["AE01", "AE02", "AE03", "AE04", "AE05", "AE06", "AE07", "AE08", "AE09", "AE10"],
    "ansiNumberRow": ["TLDE", "AE01", "AE02", "AE03", "AE04", "AE05", "AE06",
                       "AE07", "AE08", "AE09", "AE10", "AE11", "AE12"],
    "qwertyRow": ["AD01", "AD02", "AD03", "AD04", "AD05", "AD06", "AD07", "AD08", "AD09", "AD10"],
    "ansiQwertyRow": ["AD01", "AD02", "AD03", "AD04", "AD05", "AD06", "AD07",
                        "AD08", "AD09", "AD10", "AD11", "AD12", "BKSL"],
    "homeRow": ["AC01", "AC02", "AC03", "AC04", "AC05", "AC06", "AC07", "AC08", "AC09"],
    "ansiHomeRow": ["AC01", "AC02", "AC03", "AC04", "AC05", "AC06", "AC07",
                      "AC08", "AC09", "AC10", "AC11"],
    "shiftRow": ["AB01", "AB02", "AB03", "AB04", "AB05", "AB06", "AB07"],
    "ansiShiftRow": ["AB01", "AB02", "AB03", "AB04", "AB05", "AB06",
                       "AB07", "AB08", "AB09", "AB10"],
}
ALL_POSITIONS = sorted({p for row in POSITIONS.values() for p in row})

LETTER_POSITIONS = [p for p in ALL_POSITIONS if p[:2] in ("AD", "AC", "AB")]

MAX_LEVELS = 4

DEAD_PLACEHOLDER = "◌"

KEY_BLOCK_RE = re.compile(r"key\s*<(\w+)>\s*\{(.*?)\};", re.DOTALL)
SYMBOLS_RE = re.compile(r"\[\s*([^\]]*)\]")

COMPOSE_RE = re.compile(r'^\s*((?:<[A-Za-z0-9_]+>\s*)+):\s*"((?:[^"\\]|\\.)*)"')

COMPOSE_CANDIDATES = [
    "/usr/share/X11/locale/en_US.UTF-8/Compose",
    "/usr/share/X11/locale/C.UTF-8/Compose",
    "/usr/local/share/X11/locale/en_US.UTF-8/Compose",
]

XKB_LIST_CANDIDATES = [
    "/usr/share/X11/xkb/rules/evdev.lst",
    "/usr/local/share/X11/xkb/rules/evdev.lst",
]

ID_RE = re.compile(r"^[A-Za-z0-9._-]{1,64}$")

BUNDLED_FALLBACK_ID = "en-us"


def die(message):
    sys.exit(f"omatouch-lang-gen: {message}")


def state_languages_dir():
    base = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    return Path(base) / "omarchy" / "omatouch" / "languages"


def plugin_languages_dir():
    return Path(__file__).resolve().parent.parent / "languages"


def ensure_dir(path):
    try:
        path.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        die(f"can't create {path}: {exc.strerror}.")


def write_json(path, data):
    """Write atomically, so an interrupted run can't truncate a file that
    the keyboard reads on every launch."""
    tmp = path.with_suffix(path.suffix + ".tmp")
    payload = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    try:
        tmp.write_text(payload, encoding="utf-8")
        os.replace(tmp, path)
    except OSError as exc:
        tmp.unlink(missing_ok=True)
        die(f"can't write {path}: {exc.strerror}.")



def load_xkbcommon():
    try:
        lib = ctypes.CDLL("libxkbcommon.so.0")
    except OSError:
        die("libxkbcommon.so.0 isn't installed. On Arch: sudo pacman -S libxkbcommon")
    lib.xkb_keysym_from_name.restype = ctypes.c_uint32
    lib.xkb_keysym_from_name.argtypes = [ctypes.c_char_p, ctypes.c_int]
    lib.xkb_keysym_to_utf8.restype = ctypes.c_int
    lib.xkb_keysym_to_utf8.argtypes = [ctypes.c_uint32, ctypes.c_char_p, ctypes.c_size_t]
    return lib


def keysym_to_char(lib, name, allow_combining=False):
    """The printable character a keysym produces, or None. Dead keys return
    None on purpose -- they are not characters, and the caller records them
    by name instead so composition can resolve them later.

    A combining mark on its own (Unicode category Mn/Mc/Me) renders as an
    accent floating on nothing when it's the OUTPUT of a compose sequence
    or the trigger half of one (build_compose_rules' call, below) --
    str.isprintable() doesn't catch these (they ARE printable, just not
    alone), so that call site keeps the default and gets None. But when a
    layout maps a key DIRECTLY to a combining keysym (allow_combining=True,
    parse_positions' call), it's not a floating accent -- it's a script
    that legitimately types marks standalone (Thai's vowel signs, several
    of Vietnamese's diacritics), and text shaping renders those correctly
    attached to whatever precedes them, same as any real Thai/Vietnamese
    keyboard. Filtering those out isn't caution, it's silently breaking
    the layout: several of Thai's own required keys resolved to nothing
    and the whole language failed to generate before this was threaded
    through.
    """
    name = (name or "").strip()
    if not name or name == "NoSymbol":
        return None
    ks = lib.xkb_keysym_from_name(name.encode("utf-8"), 0)
    if ks == 0:
        return None
    buf = ctypes.create_string_buffer(16)
    n = lib.xkb_keysym_to_utf8(ks, buf, 16)
    if n <= 0:
        return None
    try:
        ch = buf.raw[: n - 1].decode("utf-8")
    except UnicodeDecodeError:
        return None
    if not allow_combining and len(ch) == 1 and unicodedata.combining(ch) != 0:
        return None
    if not ch or not ch.isprintable():
        return None
    return ch


def compile_keymap(layout, variant):
    args = ["xkbcli", "compile-keymap", "--layout", layout]
    if variant:
        args += ["--variant", variant]
    try:
        result = subprocess.run(args, capture_output=True, text=True)
    except FileNotFoundError:
        die("the `xkbcli` command isn't installed. On Arch: sudo pacman -S libxkbcommon-tools")
    if result.returncode != 0 or not result.stdout.strip():
        detail = result.stderr.strip()
        die(
            f"xkbcli couldn't compile layout '{layout}'"
            + (f" variant '{variant}'" if variant else "")
            + (f":\n{detail}" if detail else ".")
            + "\nRun with --list to see the layout codes this system knows."
        )
    return result.stdout



def find_compose_file():
    for path in COMPOSE_CANDIDATES:
        if Path(path).is_file():
            return Path(path)
    return None


def unescape_compose(value):
    out, i = [], 0
    while i < len(value):
        ch = value[i]
        if ch == "\\" and i + 1 < len(value):
            nxt = value[i + 1]
            out.append({"n": "\n", "t": "\t", "r": "\r"}.get(nxt, nxt))
            i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def build_compose_rules(lib, compose_path):
    """{dead_keysym: {trigger: output}} for two-key sequences starting with
    a dead key. `trigger` is the character the user taps, except when the
    second key is itself a dead key, where the keysym name is kept so
    pressing the same accent twice can resolve to its spacing form.

    Longer sequences (<Multi_key> <a> <b>, three-key accents) are skipped:
    this keyboard arms one dead key at a time.
    """
    rules = {}
    skipped_long = 0
    for raw in compose_path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = COMPOSE_RE.match(line)
        if not match:
            continue
        names = re.findall(r"<([A-Za-z0-9_]+)>", match.group(1))
        if not names or not names[0].startswith("dead_"):
            continue
        if len(names) != 2:
            skipped_long += 1
            continue
        dead, second = names
        output = unescape_compose(match.group(2))
        if not output:
            continue
        if len(output) == 1 and unicodedata.combining(output) != 0:
            continue
        trigger = second if second.startswith("dead_") else keysym_to_char(lib, second)
        if not trigger:
            continue
        rules.setdefault(dead, {})[trigger] = output
    return rules, skipped_long


def dead_display_glyph(rules, dead):
    """The spacing mark shown on a dead key, taken from the Compose table
    itself: pressing the accent twice is defined to produce it, and the
    space form is the documented escape."""
    entry = rules.get(dead) or {}
    return entry.get(dead) or entry.get(" ") or DEAD_PLACEHOLDER


def generate_compose(target_dir, lib):
    compose_path = find_compose_file()
    if not compose_path:
        die(
            "no X11 Compose table found (looked in "
            + ", ".join(COMPOSE_CANDIDATES)
            + "). On Arch it ships with xorg-xkb-utils / libx11."
        )
    rules, skipped_long = build_compose_rules(lib, compose_path)
    if not rules:
        die(f"{compose_path} contained no usable dead-key sequences.")
    glyphs = {dead: dead_display_glyph(rules, dead) for dead in rules}
    ensure_dir(target_dir)
    out_path = target_dir / "compose.json"
    write_json(out_path, {
        "schemaVersion": SCHEMA_VERSION,
        "source": str(compose_path),
        "glyphs": glyphs,
        "rules": rules,
    })
    pairs = sum(len(v) for v in rules.values())
    print(f"Wrote {out_path}")
    print(f"{pairs} compose sequences across {len(rules)} dead keys "
          f"(skipped {skipped_long} multi-key sequences).")



def list_layouts():
    path = next((Path(p) for p in XKB_LIST_CANDIDATES if Path(p).is_file()), None)
    if not path:
        die("xkb's layout list (evdev.lst) isn't installed. On Arch: sudo pacman -S xkeyboard-config")
    section = None
    layouts, variants = [], []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.rstrip()
        if line.startswith("!"):
            section = line[1:].strip().split()[0] if len(line) > 1 else None
            continue
        if not line.strip() or section not in ("layout", "variant"):
            continue
        parts = line.strip().split(None, 1)
        if len(parts) != 2:
            continue
        code, description = parts[0], parts[1].strip()
        if section == "layout":
            layouts.append({"layout": code, "variant": "", "description": description})
        else:
            head, _, tail = description.partition(":")
            if not tail:
                continue
            variants.append({"layout": head.strip(), "variant": code,
                             "description": tail.strip()})
    return layouts + variants


def compile_and_parse(lib, layout, variant):
    """(keys, deads) for a layout/variant, or None if it can't even be
    compiled/parsed -- used for probing, so failure is data, not a die()."""
    try:
        result = subprocess.run(
            ["xkbcli", "compile-keymap", "--layout", layout]
            + (["--variant", variant] if variant else []),
            capture_output=True, text=True, timeout=5,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0 or not result.stdout.strip():
        return None
    try:
        keys, deads, _ = parse_positions(result.stdout, lib)
    except SystemExit:
        return None
    return keys, deads


def probe_native_script(lib, layout, variant, us_keys):
    """Return false for layouts that cannot be parsed or match US exactly.

    Exact comparison identifies layouts that require an IME without keeping
    a hand-maintained list of layout codes.
    """
    result = compile_and_parse(lib, layout, variant)
    if result is None:
        return False
    keys, _deads = result
    return keys != us_keys


def _self_discloses_latin(description):
    """Whether xkb's OWN description text already says this is English or
    spells out its own Latin-ness -- read from evdev.lst's own words
    (the same field this whole list is built from), not a hand-typed
    "these languages are Latin" table. Being identical to plain "us" is
    correct, not a bug, for a layout that IS English (regional English
    variants) or that already tells you it's "(Latin)" (Indonesian,
    Kazakh) -- unlike Chinese/Korean, nothing here was promised and not
    delivered.
    """
    return description.startswith("English") or "(Latin)" in description


def annotate_script_support(entries):
    lib = load_xkbcommon()
    us = compile_and_parse(lib, "us", "")
    us_keys = us[0] if us else {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        results = pool.map(
            lambda e: probe_native_script(lib, e["layout"], e["variant"], us_keys), entries
        )
        for entry, native in zip(entries, results):
            if entry["layout"] == "us" and not entry["variant"]:
                entry["nativeScript"] = True
            elif _self_discloses_latin(entry["description"]):
                entry["nativeScript"] = True
            else:
                entry["nativeScript"] = native
    return entries


def get_annotated_layouts():
    """Return layout annotations cached by the XKB layout-list mtime."""
    path = next((Path(p) for p in XKB_LIST_CANDIDATES if Path(p).is_file()), None)
    src_mtime = path.stat().st_mtime if path else None
    cache_path = state_languages_dir().parent / "layout-list-cache.json"
    if cache_path.is_file():
        try:
            cached = json.loads(cache_path.read_text(encoding="utf-8"))
            if cached.get("sourceMtime") == src_mtime and isinstance(cached.get("entries"), list):
                return cached["entries"]
        except (OSError, ValueError):
            pass
    entries = annotate_script_support(list_layouts())
    try:
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(
            json.dumps({"sourceMtime": src_mtime, "entries": entries}, ensure_ascii=False),
            encoding="utf-8",
        )
    except OSError:
        pass  # best-effort -- a failed cache write just means next time re-scans too
    return entries



def parse_positions(keymap_text, lib):
    """Every level of every position OmaTouch renders.

    xkb gives up to four symbols per key; only the first two were ever read
    before, which is why AltGr characters (French `@` on AC01, `€` on AD03)
    were unreachable -- the data was there and thrown away.
    """
    keys, deads, keysyms = {}, {}, {}
    for block_match in KEY_BLOCK_RE.finditer(keymap_text):
        name = block_match.group(1)
        if name not in ALL_POSITIONS:
            continue
        sym_matches = SYMBOLS_RE.findall(block_match.group(2))
        if not sym_matches:
            continue
        symbols = [s.strip() for s in sym_matches[-1].split(",")][:MAX_LEVELS]

        chars, dead_names, sym_names = [], [], []
        for sym in symbols:
            is_dead = sym.startswith("dead_")
            dead_names.append(sym if is_dead else "")
            sym_names.append(sym if sym and sym != "NoSymbol" else "")
            chars.append(None if is_dead else keysym_to_char(lib, sym, allow_combining=True))

        if len(chars) < 2 or (not chars[1] and not dead_names[1]):
            base = chars[0] or ""
            implied = base.upper() if base.isalpha() else base
            if len(chars) < 2:
                chars.append(implied)
                dead_names.append("")
                sym_names.append("")
            else:
                chars[1] = implied

        while len(chars) > 2 and not chars[-1] and not dead_names[-1]:
            chars.pop()
            dead_names.pop()
            sym_names.pop()

        keys[name] = [c or "" for c in chars]
        if any(dead_names):
            deads[name] = dead_names
        if any(sym_names):
            keysyms[name] = sym_names

    missing = [p for p in ALL_POSITIONS if p not in keys]
    if missing:
        die(
            "this layout doesn't define every key OmaTouch needs "
            f"(missing: {', '.join(missing)}). Not writing a partial language file."
        )
    return keys, deads, keysyms


def script_direction(keys):
    """Derived from the characters themselves via Unicode's own bidi
    classes -- recorded now so right-to-left support later is a rendering
    change rather than a data migration."""
    rtl = ltr = 0
    for pos in LETTER_POSITIONS:
        level1 = (keys.get(pos) or [""])[0]
        if not level1:
            continue
        bidi = unicodedata.bidirectional(level1[0])
        if bidi in ("R", "AL"):
            rtl += 1
        elif bidi == "L":
            ltr += 1
    return "rtl" if rtl > ltr else "ltr"


def fill_dead_glyphs(keys, deads, compose):
    """A dead key has no character of its own, so show the spacing mark the
    Compose table says it produces."""
    glyphs = (compose or {}).get("glyphs") or {}
    rules = (compose or {}).get("rules") or {}
    for pos, levels in deads.items():
        for idx, dead in enumerate(levels):
            if not dead or idx >= len(keys.get(pos, [])):
                continue
            if keys[pos][idx]:
                continue
            entry = rules.get(dead) or {}
            keys[pos][idx] = glyphs.get(dead) or entry.get(dead) or entry.get(" ") or DEAD_PLACEHOLDER


def load_compose_for_generation(bundle_dir, state_dir):
    for directory in (state_dir, bundle_dir):
        path = directory / "compose.json"
        if path.is_file():
            try:
                return json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
    return None



def read_manifest(languages_dir):
    """A corrupt manifest must never silently discard the user's language
    list, so rebuild it from what is actually on disk instead."""
    manifest_path = languages_dir / "index.json"
    try:
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
        if isinstance(data, dict) and isinstance(data.get("languages"), list):
            return data
        raise json.JSONDecodeError("not a language manifest", "", 0)
    except FileNotFoundError:
        return {"languages": []}
    except (json.JSONDecodeError, OSError):
        backup = manifest_path.with_suffix(".json.bak")
        try:
            os.replace(manifest_path, backup)
            print(f"warning: {manifest_path.name} was unreadable; kept a copy at {backup.name}",
                  file=sys.stderr)
        except OSError:
            pass
        rebuilt = rebuild_manifest_from_disk(languages_dir)
        print(f"warning: rebuilt the language list from the {len(rebuilt)} file(s) present.",
              file=sys.stderr)
        return {"languages": rebuilt}


def rebuild_manifest_from_disk(languages_dir):
    entries = []
    for path in sorted(languages_dir.glob("*.json")):
        if path.name in ("index.json", "compose.json"):
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        lang_id = data.get("id") or path.stem
        entries.append({"id": lang_id, "name": data.get("name") or lang_id.upper()})
    return entries


def write_manifest(languages_dir, manifest):
    write_json(languages_dir / "index.json", manifest)


def remove_language(languages_dir, lang_id):
    if lang_id == BUNDLED_FALLBACK_ID:
        die(f"{BUNDLED_FALLBACK_ID} is the built-in fallback and can't be removed -- "
            "OmaTouch always needs a working default.")
    lang_path = languages_dir / f"{lang_id}.json"
    existed = lang_path.is_file()
    try:
        lang_path.unlink(missing_ok=True)
    except OSError as exc:
        die(f"can't remove {lang_path}: {exc.strerror}.")
    manifest = read_manifest(languages_dir)
    before = len(manifest.get("languages", []))
    manifest["languages"] = [e for e in manifest.get("languages", []) if e.get("id") != lang_id]
    write_manifest(languages_dir, manifest)
    if len(manifest["languages"]) == before and not existed:
        print(f"'{lang_id}' wasn't installed -- nothing to remove.")
    else:
        print(f"Removed '{lang_id}'.")



def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--layout", help="xkb layout code, e.g. fr, de, es")
    parser.add_argument("--variant", default="", help="xkb variant, e.g. oss (default: none)")
    parser.add_argument("--id", default=None, help="short id for this language (default: layout[-variant])")
    parser.add_argument("--name", default=None, help="display name shown on the keyboard (default: uppercased id)")
    parser.add_argument("--remove", metavar="ID", help="remove an installed language by its id")
    parser.add_argument("--list", action="store_true", help="list every layout and variant xkb knows")
    parser.add_argument("--json", action="store_true", help="machine-readable output for --list")
    parser.add_argument("--compose", action="store_true",
                        help="regenerate the shared dead-key compose table")
    parser.add_argument("--bundle", action="store_true",
                        help="write into the plugin directory instead of your state directory "
                             "(for cutting a release, not for normal use)")
    args = parser.parse_args()

    bundle_dir = plugin_languages_dir()
    state_dir = state_languages_dir()
    target_dir = bundle_dir if args.bundle else state_dir

    if args.list:
        entries = get_annotated_layouts()
        if args.json:
            print(json.dumps(entries, ensure_ascii=False))
        else:
            for entry in entries:
                code = entry["layout"] + (f" {entry['variant']}" if entry["variant"] else "")
                tag = " [no native script, keys only]" if entry.get("nativeScript") is False else ""
                print(f"{code:<24} {entry['description']}{tag}")
        return

    if args.compose:
        generate_compose(target_dir, load_xkbcommon())
        return

    if args.remove:
        if not ID_RE.match(args.remove):
            die(f"'{args.remove}' isn't a valid language id.")
        ensure_dir(target_dir)
        remove_language(target_dir, args.remove)
        return

    if not args.layout:
        parser.error("--layout is required unless --remove, --list or --compose is given")

    lang_id = args.id or (f"{args.layout}-{args.variant}" if args.variant else args.layout)
    if not ID_RE.match(lang_id):
        die(f"'{lang_id}' isn't a valid language id (letters, digits, dot, dash, underscore).")
    display_name = args.name or lang_id.upper()

    lib = load_xkbcommon()
    keymap_text = compile_keymap(args.layout, args.variant)
    keys, deads, keysyms = parse_positions(keymap_text, lib)

    compose = load_compose_for_generation(bundle_dir, state_dir)
    if compose:
        fill_dead_glyphs(keys, deads, compose)
    elif deads:
        print("warning: no compose table found, so dead keys will show a placeholder. "
              "Run with --compose first.", file=sys.stderr)

    data = {
        "schemaVersion": SCHEMA_VERSION,
        "id": lang_id,
        "name": display_name,
        "xkbLayout": args.layout,
        "xkbVariant": args.variant,
        "direction": script_direction(keys),
        "keys": keys,
    }
    if deads:
        data["dead"] = deads
    if keysyms:
        data["keysyms"] = keysyms

    ensure_dir(target_dir)
    lang_path = target_dir / f"{lang_id}.json"
    write_json(lang_path, data)

    manifest = read_manifest(target_dir)
    manifest["languages"] = [e for e in manifest.get("languages", []) if e.get("id") != lang_id]
    manifest["languages"].append({"id": lang_id, "name": display_name})
    write_manifest(target_dir, manifest)

    levels = max(len(v) for v in keys.values())
    print(f"Wrote {lang_path}")
    print(f"'{display_name}' ({lang_id}) is ready -- {len(keys)} keys, {levels} levels"
          + (f", {len(deads)} dead-key positions" if deads else "") + ".")


if __name__ == "__main__":
    main()
