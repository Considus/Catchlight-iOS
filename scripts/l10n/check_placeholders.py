#!/usr/bin/env python3
"""Check every translation carries the same format placeholders as its English.

A translation that drops, adds or retypes a placeholder crashes or garbles at
run time, and nothing at build time says so. For each key, in every language and
every plural form, the placeholders are compared with the English after positions
are resolved: `%1$@ … %2$lld` in German may reorder `%@ … %lld`, but each position
must keep its type. App Shortcut `${…}` tokens must match as a set.

Usage: scripts/l10n/check_placeholders.py [catalog …]   (defaults to every catalog)
Exit 1 lists each mismatch.
"""
import glob
import json
import re
import sys

SPEC = re.compile(r"%(?:(\d+)\$)?(?:#@\w+@|l{0,2}[@dDuUxXoOfeEgGcCsSp]|%)")
TOKEN = re.compile(r"\$\{\w+\}")


def signature(text):
    """Positional placeholder types, e.g. {1: '@', 2: 'lld'}; '%%' is ignored."""
    sig, auto = {}, 0
    for m in SPEC.finditer(text):
        body = m.group(0)
        if body == "%%":
            continue
        kind = re.sub(r"^%(\d+\$)?", "", body)
        if m.group(1):
            pos = int(m.group(1))
        else:
            auto += 1
            pos = auto
        sig[pos] = kind
    return sig


def values(loc):
    """Every string a localisation entry holds, with a label for the report."""
    if "stringUnit" in loc:
        yield "", loc["stringUnit"]["value"]
    if "stringSet" in loc:
        for i, v in enumerate(loc["stringSet"]["values"]):
            yield f"[{i}]", v
    for axis, forms in loc.get("variations", {}).items():
        for form, sub in forms.items():
            for label, v in values(sub):
                yield f"{axis}.{form}{label}", v


def check(path):
    problems = []
    data = json.load(open(path))
    source = data.get("sourceLanguage", "en")
    for key, entry in data["strings"].items():
        locs = entry.get("localizations", {})
        english = [v for _, v in values(locs[source])] if source in locs else [key]
        want_sig = signature(english[-1])
        want_tokens = set(TOKEN.findall(english[0]))
        for lang, loc in locs.items():
            if lang == source:
                continue
            for label, text in values(loc):
                got = signature(text)
                if got != want_sig:
                    problems.append(f"{path}: {lang} {label} {key!r}\n    want {want_sig}, got {got}: {text!r}")
                if set(TOKEN.findall(text)) != want_tokens:
                    problems.append(f"{path}: {lang} {label} {key!r}\n    tokens {set(TOKEN.findall(text))} != {want_tokens}")
    return problems


def main(paths):
    paths = paths or sorted(glob.glob("**/*.xcstrings", recursive=True))
    problems = [p for path in paths for p in check(path)]
    for p in problems:
        print(p)
    print(f"{len(paths)} catalogs, {len(problems)} placeholder mismatches")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
