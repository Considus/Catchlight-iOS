#!/usr/bin/env python3
"""Flag a language whose catalog text is copied from another language.

A translation file pasted into the wrong column passes every placeholder check,
because the other language's text has the same placeholders. This compares every
pair of languages and counts values that are identical, ignoring short ones and
ones equal to the English (product names, numbers). Neighbouring languages share
some text honestly (Danish/Norwegian/Swedish, Spanish/Portuguese, the two
Portugueses, the two Chinese scripts), so a related pair is allowed more.

Usage: scripts/l10n/check_mixups.py [catalog …]   (exit 1 lists each suspect pair)
"""
import glob
import itertools
import json
import re
import sys

# Share of a language's values found word for word in the other. Unrelated pairs share
# almost nothing (at most 1.5% measured, German and Norwegian); a pasted file shows up
# as 20% or more (the Finnish file that was a quarter Dutch: 23%). The two
# Portugueses share 43%: the Portugal translation uses the formal "você", much of
# which reads the same as Brazilian.
LIMIT = 0.03
RELATED = [({"da", "nb", "sv"}, 0.30), ({"es", "pt-BR", "pt-PT", "it"}, 0.30),
           ({"pt-BR", "pt-PT"}, 0.50), ({"zh-Hans", "zh-Hant"}, 0.50)]


def values(loc):
    if "stringUnit" in loc:
        return [loc["stringUnit"]["value"]]
    if "stringSet" in loc:
        return loc["stringSet"]["values"]
    return [s["stringUnit"]["value"] for s in loc.get("variations", {}).get("plural", {}).values()]


def main(paths):
    paths = paths or sorted(glob.glob("**/*.xcstrings", recursive=True))
    text = {}
    for path in paths:
        for key, entry in json.load(open(path, encoding="utf-8"))["strings"].items():
            locs = entry.get("localizations", {})
            english = set(values(locs["en"])) if "en" in locs else {key}
            for lang, loc in locs.items():
                for i, v in enumerate(values(loc)):
                    if lang != "en" and v not in english and len(re.sub(r"[\W\d_]", "", v)) >= 6:
                        text.setdefault(lang, {})[(path, key, i)] = v
    problems = []
    for a, b in itertools.combinations(sorted(text), 2):
        shared = [k for k in text[a] if text[b].get(k) == text[a][k]]
        share = len(shared) / max(1, min(len(text[a]), len(text[b])))
        limit = max([lim for group, lim in RELATED if {a, b} <= group], default=LIMIT)
        if share > limit:
            problems.append(f"{a} and {b} share {len(shared)} values ({share:.0%}), e.g. {text[a][shared[0]]!r}")
    for p in problems:
        print(p)
    print(f"{len(text)} languages, {len(problems)} suspect pairs")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
