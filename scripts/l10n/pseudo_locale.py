#!/usr/bin/env python3
"""Fill every String Catalog with a throwaway German whose values are the English
wrapped in ⟦ ⟧, so a build run with `-AppleLanguages '(de)'` shows which text goes
through translation. English with no brackets around it escaped.

    python3 scripts/l10n/pseudo_locale.py apply     # backs the catalogs up first
    python3 scripts/l10n/pseudo_locale.py restore   # puts them back exactly

Never commit a catalog while it is applied: `restore` before staging. The backup is
the working copy, not git, so uncommitted catalog edits survive the round trip.
App Shortcut phrases are left alone, because Siri phrases must stay speakable.
"""
import glob, json, os, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BACKUP = os.path.join(ROOT, '.l10n-pseudo-backup')
MARK = 'de'


def catalogs():
    found = glob.glob(os.path.join(ROOT, 'Catchlight*', '**', '*.xcstrings'), recursive=True)
    return sorted(f for f in found if not f.endswith('AppShortcuts.xcstrings'))


def wrap(node):
    if isinstance(node, dict):
        return {k: ({'state': 'translated', 'value': '⟦' + v['value'] + '⟧'} if k == 'stringUnit' else wrap(v))
                for k, v in node.items()}
    return node


def apply():
    if os.path.exists(BACKUP):
        sys.exit('A pseudo locale is already applied. Run `restore` first.')
    count = 0
    for path in catalogs():
        rel = os.path.relpath(path, ROOT)
        os.makedirs(os.path.dirname(os.path.join(BACKUP, rel)), exist_ok=True)
        shutil.copy2(path, os.path.join(BACKUP, rel))
        doc = json.load(open(path))
        for key, entry in doc['strings'].items():
            source = entry.get('localizations', {}).get('en', {'stringUnit': {'state': 'new', 'value': key}})
            entry.setdefault('localizations', {})[MARK] = wrap(source)
            count += 1
        json.dump(doc, open(path, 'w'), ensure_ascii=False, indent=2)
    print(f'pseudo locale applied to {count} strings; build, then launch with -AppleLanguages "({MARK})"')


def restore():
    if not os.path.exists(BACKUP):
        sys.exit('Nothing to restore.')
    for dirpath, _, files in os.walk(BACKUP):
        for name in files:
            saved = os.path.join(dirpath, name)
            shutil.copy2(saved, os.path.join(ROOT, os.path.relpath(saved, BACKUP)))
    shutil.rmtree(BACKUP)
    print('catalogs restored')


if __name__ == '__main__':
    {'apply': apply, 'restore': restore}.get(sys.argv[1] if len(sys.argv) > 1 else '', lambda: sys.exit(__doc__))()
