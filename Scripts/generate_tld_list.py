#!/usr/bin/env python3
"""
Regenerate `Sources/CatchlightCore/Text/TLDList.swift` from IANA's authoritative
list of top-level domains.

    python3 Scripts/generate_tld_list.py

WHY THIS IS GENERATED AND COMMITTED, rather than fetched at run time.
Catchlight makes almost no network requests, and every one it does make is
named in a published white paper. A notes app that phoned IANA to decide
whether text is a link would add a request that leaks WHEN the user is typing,
and would break the papers' closed-set claim about what crosses the boundary.
So the list is baked into the binary at build time and this script is the only
thing that ever talks to IANA. Run it deliberately; never from CI, and never
from the app.

WHY A LIST AT ALL. `NSDataDetector` runs first in `LinkDetector` and handles
country codes well, but its own table has not kept up: measured 2026-09-12 it
caught 44/47 country codes and only 5/33 of the gTLDs created from 2013 onward,
missing `.app`, `.dev` and `.ai` among them. Bare domains on modern TLDs
therefore link only because this list says they may.
"""

import re
import sys
import urllib.parse
import urllib.request

SOURCE = "https://data.iana.org/TLD/tlds-alpha-by-domain.txt"
OUT = "Sources/CatchlightCore/Text/TLDList.swift"

# 🚨 `urllib` honours `file://` and `ftp://` as happily as `https://`, so a URL that
# ever becomes dynamic could be pointed at the local disk and this script would
# cheerfully "download" a local file into the generated Swift. `SOURCE` is a constant
# today and nothing user-supplied reaches it, so this guard changes no behaviour —
# it exists so that the day someone parameterises the source, the failure is a loud
# refusal here rather than a silent local read.
#
# Raised by a Semgrep `dynamic-urllib-use-detected` finding, 2026-09-12. The finding
# was a false positive in substance and a fair point in principle, which is the kind
# worth fixing rather than arguing with.
ALLOWED_SCHEMES = ("https",)

# 🚨 Never auto-linked, however live the TLD. Each of these is overwhelmingly a
# FILE EXTENSION in a notes app and vanishingly rare as a domain someone types
# into a Take, so linking them turns ordinary filenames into links (owner
# decision 2026-09-12).
#
# Deliberately NOT excluded, and the reasoning matters if this set is ever
# revisited: `.app`, `.ai` and `.sh` are also file extensions but are real,
# widely-used domains — the owner's own reference list contains `squoosh.app`,
# `consensus.app` and `carbon.now.sh`. `.py`, `.pl` and `.rs` are Paraguay,
# Poland and Serbia. Excluding any of those would break working links to fix
# a rarer nuisance.
EXCLUDED = {"md", "zip", "mov", "java"}

HEADER = '''//
//  TLDList.swift
//  CatchlightCore
//
//  🚨 GENERATED FILE — DO NOT EDIT BY HAND.
//  Regenerate with:  python3 Scripts/generate_tld_list.py
//
//  Source: {source}
//  IANA list version: {version}
//  {count} top-level domains, {excluded_count} deliberately excluded.
//
//  Excluded, because each is far more often a FILE EXTENSION than a domain
//  someone types into a Take ({excluded}). `.app`, `.ai` and `.sh` are NOT
//  excluded despite also being extensions: they are real domains in daily use.
//  The exclusion list lives in the generator, not here.
//

import Foundation

enum TLDList {{
    /// IANA's own version stamp for the list below, `YYYYMMDDNN`. Exposed so a
    /// drift check can compare it against the live file without parsing this
    /// source — see `Scripts/generate_tld_list.py`. A stale stamp is not a
    /// defect: new TLDs are added rarely, and a list some months behind costs
    /// only that a very new domain does not auto-link.
    static let ianaVersion = "{version}"

    /// Every live top-level domain IANA publishes, minus the excluded set.
    /// Lowercase; `LinkDetector` lowercases before it looks anything up.
    static let all: Set<String> = [
{body}    ]
}}
'''


def main() -> int:
    scheme = urllib.parse.urlparse(SOURCE).scheme.lower()
    if scheme not in ALLOWED_SCHEMES:
        print(f"refusing to fetch over {scheme!r}: only {ALLOWED_SCHEMES} are allowed",
              file=sys.stderr)
        return 1

    try:
        with urllib.request.urlopen(SOURCE, timeout=30) as response:
            text = response.read().decode("utf-8")
    except Exception as error:                      # noqa: BLE001
        print(f"could not fetch {SOURCE}: {error}", file=sys.stderr)
        return 1

    version = "unknown"
    tlds = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith("#"):
            found = re.search(r"Version (\d+)", line)
            if found:
                version = found.group(1)
            continue
        tlds.append(line.lower())

    # Punycode entries (`xn--…`) are the internationalised TLDs. They are kept:
    # the detector's regex only matches ASCII labels so they cannot currently be
    # reached, but excluding them here would hide that limitation in the wrong file.
    kept = sorted(t for t in tlds if t not in EXCLUDED)

    if len(kept) < 1000:
        print(f"refusing to write: only {len(kept)} TLDs parsed, expected >1000",
              file=sys.stderr)
        return 1

    lines, row = [], []
    for tld in kept:
        row.append(f'"{tld}",')
        if len(row) == 8:
            lines.append("        " + " ".join(row))
            row = []
    if row:
        lines.append("        " + " ".join(row))

    swift = HEADER.format(
        source=SOURCE,
        version=version,
        count=len(kept),
        excluded_count=len(EXCLUDED),
        excluded=", ".join("." + e for e in sorted(EXCLUDED)),
        body="\n".join(lines) + "\n",
    )

    with open(OUT, "w", encoding="utf-8") as handle:
        handle.write(swift)

    print(f"wrote {OUT}: {len(kept)} TLDs (IANA version {version}), "
          f"excluded {', '.join(sorted(EXCLUDED))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
