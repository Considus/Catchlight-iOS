#!/usr/bin/env python3
"""Print the diagnostics reference-code table, in Markdown, from `NoticeCode` in
Catchlight/Diagnostics/Notice.swift: one row per code, with the English summary from
the comment on its line.

    python3 scripts/diagnostics/notice_codes.py > Diagnostic_Reference_Codes.md

Fails if a case has no summary comment, so the table can't silently miss a code.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SOURCE = os.path.join(ROOT, 'Catchlight', 'Diagnostics', 'Notice.swift')
GROUPS = [(100, 'Sync'), (200, 'Storage'), (300, 'Conflicts'), (400, 'Verification'), (900, 'Developer-only (export only, English)')]

text = open(SOURCE).read()
body = text[text.index('enum NoticeCode'):text.index('enum Notice:')]
rows, missing = [], []
for line in body.splitlines():
    m = re.match(r'\s*case (\w+) = (\d+)\s*(?://\s*(.+))?$', line)
    if not m:
        continue
    name, code, summary = m.group(1), int(m.group(2)), (m.group(3) or '').strip()
    if not summary:
        missing.append(name)
    rows.append((code, name, summary))
if missing:
    sys.exit('NoticeCode cases with no summary comment: ' + ', '.join(missing))

print('# Catchlight diagnostic reference codes\n')
print('Every line in a Catchlight diagnostics export starts with a reference such as `[CCIOS-202]`. '
      '`CC` is Considus Catchlight, the next letters are the platform that wrote it (`IOS` iPhone, `MOS` Mac), '
      'and the number is the notice. A number means the same notice on every platform and is never reused. '
      'The message after it is in the user\'s language for user-facing notices, English for developer-only lines. '
      '950–999 is reserved for lines Catchlight-Core writes itself (not yet coded). '
      'Lines recorded before codes existed carry no reference.\n')
print(f'Generated from `Catchlight/Diagnostics/Notice.swift` by `scripts/diagnostics/notice_codes.py`. Do not edit by hand.\n')
for start, title in GROUPS:
    group = [r for r in rows if start <= r[0] < start + 100]
    if not group:
        continue
    print(f'## {start // 100}xx {title}\n')
    print('| Code | Meaning | Name in code |')
    print('|---|---|---|')
    for code, name, summary in group:
        print(f'| {code} | {summary} | `{name}` |')
    print()
