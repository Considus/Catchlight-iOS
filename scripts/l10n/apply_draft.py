#!/usr/bin/env python3
"""Write one language's translations into every String Catalog.

The draft is a JSON file:

    {"unit":      {"<key>": "<text>", ...},
     "plural":    {"<key>": ["<one>", "<other>"], ...},
     "shortcuts": {"<key>": ["<phrase>", ...], ...}}

Every key a catalog already translates into another language gets the new
language in the matching shape: a Siri phrase set from "shortcuts", plural forms
from "plural" (also allowed where English has none, e.g. a trial length), plain
text from "unit". The existing order of a key's languages is kept and the new one
goes last, so the diff shows only additions. A catalog key the draft does not
cover is listed and the script exits 1 without writing anything.

Usage: scripts/l10n/apply_draft.py <lang> <draft.json>
Then run check_placeholders.py, and xcodebuild -exportLocalizations to sync.
"""
import glob
import json
import re
import sys


def dump(data):
    """Xcode's own layout: 2-space indent, ' : ', an empty object opened and closed."""
    s = json.dumps(data, ensure_ascii=False, indent=2, separators=(",", " : "))
    return re.sub(r"^( *)(.*)\{\}", lambda m: f"{m.group(1)}{m.group(2)}{{\n\n{m.group(1)}}}", s, flags=re.M)


def unit(text):
    return {"stringUnit": {"state": "translated", "value": text}}


def main(lang, draft_path):
    draft = json.load(open(draft_path, encoding="utf-8"))
    units, plurals, sets = draft.get("unit", {}), draft.get("plural", {}), draft.get("shortcuts", {})
    catalogs, missing = {}, []
    for path in sorted(glob.glob("**/*.xcstrings", recursive=True)):
        data = json.load(open(path, encoding="utf-8"))
        for key, entry in data["strings"].items():
            locs = entry.get("localizations", {})
            others = [l for l in locs if l not in ("en", lang)]
            if not others:
                continue
            shape = locs[others[0]]
            if "stringSet" in shape:
                if key not in sets:
                    missing.append((path, key)); continue
                new = {"stringSet": {"state": "translated", "values": sets[key]}}
            elif key in plurals:
                one, other = plurals[key]
                new = {"variations": {"plural": {"one": unit(one), "other": unit(other)}}}
            elif key in units:
                new = unit(units[key])
            else:
                missing.append((path, key)); continue
            locs[lang] = new
        catalogs[path] = data
    if missing:
        for path, key in missing:
            print(f"missing: {path}: {key!r}")
        return 1
    for path, data in catalogs.items():
        open(path, "w", encoding="utf-8").write(dump(data))
    print(f"{lang}: written to {len(catalogs)} catalogs")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
