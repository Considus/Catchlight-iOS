#!/usr/bin/env python3
"""List English sentence-like string literals in the app's Swift source that are not
keys in any String Catalog: the static half of the escape check, which reaches the
screens the pseudo locale cannot (onboarding, errors, VoiceOver text).

    xcodebuild -exportLocalizations -project Catchlight.xcodeproj \\
        -localizationPath "$BUILD_DIR/l10n" -exportLanguage en -sdk iphonesimulator
    python3 scripts/l10n/find_unlocalised.py

Run the export first: it is what syncs the catalogs with the source. The output is
candidates, not verdicts. SQL, log lines, identifiers and comments are skipped, and
what remains still includes text that stays English on purpose (diagnostics logs,
version strings, the brand). Single words are not reported; the pseudo locale
catches those on screen.
"""
import glob, json, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SKIP = re.compile(r'Logger|logger\.|print\(|os_log|accessibilityIdentifier|forKey|defaultsKey|'
                  r'UserDefaults|DiagnosticsLog|fatalError|assert|precondition|systemName:|'
                  r'systemImage:|Image\("|named:|URL\(string|identifier:|NSError|rawValue|'
                  r'case \w+ = |comment:|PRAGMA|SELECT |INSERT |DELETE |CREATE |DROP ')
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
INTERPOLATION = re.compile(r'\\\((?:[^()]|\([^()]*\))*\)')
SPECIFIER = re.compile(r'%(?:\d\$)?(?:lld|ld|d|@|lf|f)')


def catalog_keys():
    keys = set()
    for path in glob.glob(os.path.join(ROOT, 'Catchlight*', '**', '*.xcstrings'), recursive=True):
        keys |= {SPECIFIER.sub('%@', k) for k in json.load(open(path))['strings']}
    return keys


def main():
    keys = catalog_keys()
    for path in sorted(glob.glob(os.path.join(ROOT, 'Catchlight*', '**', '*.swift'), recursive=True)):
        in_preview = False
        for number, line in enumerate(open(path), 1):
            in_preview = in_preview or '#Preview' in line
            stripped = line.strip()
            if in_preview or stripped.startswith('//') or SKIP.search(line):
                continue
            for match in LITERAL.finditer(line):
                text = match.group(1)
                if ' ' not in text or not re.match(r'^[A-Z\\]', text):
                    continue
                if SPECIFIER.sub('%@', INTERPOLATION.sub('%@', text)) in keys:
                    continue
                print(f'{os.path.relpath(path, ROOT)}:{number}: "{text[:90]}"')


if __name__ == '__main__':
    main()
