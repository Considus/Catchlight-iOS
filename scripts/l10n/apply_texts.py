#!/usr/bin/env python3
"""Write a translated plain-text file back into every String Catalog.

The reverse of `review_workbook.py --texts`: the English file lists each English
line once, and line N of a language file translates line N of the English. Each
catalog key (and plural form, and Siri phrase) is found by reading its English the
way the text file shows it, then the translation is turned back into a catalog
value against that key's English:

  {1}, {2}…        -> the key's format specifiers by position (%@, %lld; numbered
                      %1$@ when the key has more than one)
  {app} {text} {filter} -> ${applicationName} ${text} ${scope}
  " / "             -> a line break, when the English has one
  bold              -> the one all-capitals word wrapped in **, when the English
                      has a **WORD**

A count with no English plural (the trial length "%lld-day") reads as two lines,
"{1} day" / "{1} days", and is written as plural forms. A key the text file does
not cover (a product name or bare number) keeps its current value, or takes the
English when the language has none; a catalog key whose line is missing, or a
translation that loses a placeholder, stops the run before anything is written.

Usage: apply_texts.py <lang> <EN.txt> <LANG.txt> [--root DIR]
Then run check_placeholders.py, and xcodebuild -exportLocalizations to sync.
"""
import argparse
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apply_draft import dump  # noqa: E402  (Xcode's own JSON layout)
from review_workbook import TOKENS, english_line, readable  # noqa: E402

SPEC = re.compile(r"%(?:(\d+)\$)?(l{0,2}[@dDuUxXoOfeEgGcCsSp])")
TRIAL = re.compile(r"%lld-(\w+)")


def specs(english):
    """The English's specifiers in positional order, as type strings: ['@', 'lld']."""
    found, auto = {}, 0
    for m in SPEC.finditer(english):
        if m.group(1):
            pos = int(m.group(1))
        else:
            auto += 1
            pos = auto
        found[pos] = m.group(2)
    return [found[k] for k in sorted(found)]


def to_value(text, english):
    """A translated line back into a catalog value, against its English."""
    types = specs(english)
    positional = len(types) > 1

    def spec(m):
        k = int(m.group(1))
        if not 1 <= k <= len(types):
            raise ValueError(f"{{{k}}} has no placeholder in the English")
        return f"%{k}${types[k - 1]}" if positional else f"%{types[k - 1]}"

    value = re.sub(r"\{(\d+)\}", spec, text)
    for raw, shown in TOKENS.items():
        value = value.replace(shown, raw)
    if "\n" in english:
        value = value.replace(" / ", "\n")
    if "**" in english and "**" not in value:
        # The emphasis is the one run of capitalised words ("ONLY", "DEN ENESTE").
        runs = [m for m in re.finditer(r"\b[^\W\d_a-z]{2,}(?:\s+[^\W\d_a-z]{2,})*\b", value)
                if m.group(0).isupper() and m.group(0) not in ("ID", "iOS")]
        if len(runs) == 1:
            m = runs[0]
            value = f"{value[:m.start()]}**{m.group(0)}**{value[m.end():]}"
        else:
            print(f"note: no single capitalised run to embolden in {value[:60]!r}", file=sys.stderr)
    if specs(value) != types or sorted(re.findall(r"\$\{\w+\}", value)) != sorted(re.findall(r"\$\{\w+\}", english)):
        raise ValueError(f"placeholders differ from the English: {value!r}")
    return value


def entries(path, data):
    """Every (key, form, English) the text file can carry, from one catalog."""
    for key, entry in data["strings"].items():
        locs = entry.get("localizations", {})
        if not any(l != "en" for l in locs):
            continue
        en = locs.get("en", {})
        if "stringSet" in en:
            for i, v in enumerate(en["stringSet"]["values"]):
                yield key, f"phrase {i + 1}", v
        elif "variations" in en:
            for form, sub in en["variations"]["plural"].items():
                yield key, f"plural: {form}", sub["stringUnit"]["value"]
        elif TRIAL.fullmatch(key):
            for form in ("one", "other"):
                yield key, f"plural: {form}", key
        else:
            yield key, "", en.get("stringUnit", {}).get("value", key)


def main(lang, en_path, tr_path, root):
    en_lines = open(en_path, encoding="utf-8").read().rstrip("\n").split("\n")
    tr_lines = open(tr_path, encoding="utf-8-sig").read().rstrip("\n").split("\n")
    if len(en_lines) != len(tr_lines):
        sys.exit(f"{tr_path}: {len(tr_lines)} lines, the English has {len(en_lines)}")
    line_of = {line: i for i, line in enumerate(en_lines)}

    catalogs, problems = {}, []
    for path in sorted(glob.glob(os.path.join(root, "**/*.xcstrings"), recursive=True)):
        data = json.load(open(path, encoding="utf-8"))
        new = {}
        for key, form, english in entries(path, data):
            shown = english_line(("", key, form, english, "", ""))
            if shown not in line_of:
                # A product name or bare number: no line. A language that has no value
                # yet takes the English, which is the same in every language.
                if form == "" and lang not in data["strings"][key].get("localizations", {}):
                    new.setdefault(key, {})[""] = english
                continue
            try:
                new.setdefault(key, {})[form] = to_value(tr_lines[line_of[shown]], english)
            except ValueError as e:
                problems.append(f"{path}: {key!r} {form}: {e}")
        for key, forms in new.items():
            locs = data["strings"][key].setdefault("localizations", {})
            if any(f.startswith("phrase") for f in forms):
                vals = [forms[f] for f in sorted(forms, key=lambda f: int(f.split()[1]))]
                locs[lang] = {"stringSet": {"state": "translated", "values": vals}}
            elif any(f.startswith("plural") for f in forms):
                plural = {f.split(": ")[1]: {"stringUnit": {"state": "translated", "value": v}}
                          for f, v in forms.items()}
                locs[lang] = {"variations": {"plural": plural}}
            else:
                locs[lang] = {"stringUnit": {"state": "translated", "value": forms[""]}}
        catalogs[path] = data
    if problems:
        sys.exit("nothing written:\n  " + "\n  ".join(problems))
    for path, data in catalogs.items():
        open(path, "w", encoding="utf-8").write(dump(data))
    print(f"{lang}: written to {len(catalogs)} catalogs")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(usage=__doc__)
    ap.add_argument("lang")
    ap.add_argument("en")
    ap.add_argument("translation")
    ap.add_argument("--root", default=".")
    a = ap.parse_args()
    main(a.lang, a.en, a.translation, a.root)
