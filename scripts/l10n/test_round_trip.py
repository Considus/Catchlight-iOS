#!/usr/bin/env python3
"""Round trip: catalogs -> plain-text files -> catalogs leaves every translation as it was.

Copies the catalogs to a scratch folder, writes the text files with
review_workbook.py --texts, writes every language back with apply_texts.py, and
compares each value (numbered placeholders in their own order count as the plain
form, which reads the same). A unit translation written back as plural forms (the trial
length, "%lld-day") passes when every form equals the original unit.

Usage: scripts/l10n/test_round_trip.py   (exit 1 lists each difference)
"""
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from review_workbook import LANGS, write_texts  # noqa: E402


def values(loc):
    if "stringUnit" in loc:
        return {"": loc["stringUnit"]["value"]}
    if "stringSet" in loc:
        return {f"phrase {i + 1}": v for i, v in enumerate(loc["stringSet"]["values"])}
    return {f: sub["stringUnit"]["value"] for f, sub in loc["variations"]["plural"].items()}


def plain(value):
    """%1$@ … %2$lld in their own order reads the same as %@ … %lld."""
    nums = [int(n) for n in re.findall(r"%(\d+)\$", value)]
    return re.sub(r"%\d+\$", "%", value) if nums == sorted(nums) else value


def same(old, new):
    old = {k: plain(v) for k, v in old.items()}
    new = {k: plain(v) for k, v in new.items()}
    if old == new:
        return True
    return list(old) == [""] and set(new.values()) == {old[""]}


def main():
    root = os.getcwd()
    tmp = tempfile.mkdtemp()
    try:
        for path in glob.glob("**/*.xcstrings", recursive=True):
            os.makedirs(os.path.join(tmp, os.path.dirname(path)), exist_ok=True)
            shutil.copy(path, os.path.join(tmp, path))
        before = {p: json.load(open(os.path.join(tmp, p))) for p in glob.glob("**/*.xcstrings", root_dir=tmp, recursive=True)}
        out = os.path.join(tmp, "texts")
        write_texts(out, tmp, None, None)
        en = os.path.join(out, "Catchlight_iOS_Translation_EN.txt")
        for lang in LANGS:
            subprocess.run([sys.executable, os.path.join(HERE, "apply_texts.py"), lang, en,
                            os.path.join(out, f"Catchlight_iOS_Translation_{lang.upper()}.txt"), "--root", tmp],
                           check=True, capture_output=True)
        diffs = []
        for p, data in before.items():
            after = json.load(open(os.path.join(tmp, p)))
            for key, entry in data["strings"].items():
                for lang, loc in entry.get("localizations", {}).items():
                    if lang == "en":
                        continue
                    new = after["strings"][key]["localizations"].get(lang)
                    if new is None or not same(values(loc), values(new)):
                        diffs.append(f"{p}: {lang} {key!r}: {values(loc)} -> {new and values(new)}")
        for d in diffs:
            print(d)
        checked = sum(len(e.get("localizations", {})) - ("en" in e.get("localizations", {}))
                      for d in before.values() for e in d["strings"].values())
        print(f"{checked} translations round-tripped, {len(diffs)} changed")
        return 1 if diffs else 0
    finally:
        shutil.rmtree(tmp)


if __name__ == "__main__":
    sys.exit(main())
