#!/usr/bin/env python3
"""Build a translator review workbook (.xlsx) for one language from the String Catalogs.

Every string in English beside the draft, a yellow column for the translator's
version, per-row English word counts, a glossary and a read-me with the totals.
Each language's notes, glossary and tone live in LANGS below; add one there to
support a new language.

Usage: review_workbook.py <lang> <out.xlsx> [repo root]
Needs openpyxl.
"""
import json
import os
import re
import sys

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side

AREA = {
    "Catchlight/Resources/Localizable.xcstrings": "App",
    "Catchlight/Resources/InfoPlist.xcstrings": "Permission prompt",
    "Catchlight/Resources/AppShortcuts.xcstrings": "Siri phrase",
    "CatchlightWidgets/Localizable.xcstrings": "Widget",
    "CatchlightShare/Localizable.xcstrings": "Share sheet",
}

KEEP = "Take, Obie, Iris, Dailies, Sequence, Angle, Shot List, Storyboard, Catchlight, Considus"

LANGS = {
    "de": {
        "name": "German",
        "tone": 'Informal "du", warm and plain. Catchlight is a private notes app.',
        "plural": 'Rows marked "plural: one" are used when the count is 1; "plural: other" for every other count.',
        "example": 'English "Couldn\'t load your Takes." · draft "Deine Takes konnten nicht geladen werden." · '
                   'your German "Deine Takes ließen sich nicht laden." · your comment "shorter, more natural"',
        "notes": {
            "Privacy phrase": 'Glossary term. Draft "Datenschutz-Phrase": please confirm or propose a better term; it recurs in many strings.',
            "Opens the Focus ring to change what this Take is.": '"Focus ring" drafted as "Fokusring". Avoid confusion with the iOS feature "Fokus".',
            "%@ at %@": 'An email address read aloud by VoiceOver (user "at" domain). Draft keeps "at"; change if German VoiceOver users expect something else.',
            "%lld-day": 'Adjective inside "Start your %@ trial now…" (e.g. "14-tägige Testphase"). Must agree with the noun in that sentence.',
            "Start your %@ trial now, then only %@": 'First %@ is the trial-length adjective (e.g. "14-tägige"), second is the price (e.g. "14,99 €/Jahr").',
            "Not configured": 'Shown in a narrow row; drafted as "Kein Ordner" so it fits.',
            "Snooze for %@": '%@ is a duration such as "1 Stunde".',
        },
        "glossary": [
            ("Take", "Take (der Take, die Takes)", "Product name. Keep in English. Masculine."),
            ("Obie", "Obie (das Obie)", "Product name. Keep in English. Neuter."),
            ("Iris", "Iris (die Iris)", "Product name: the circle beside each Take. Keep."),
            ("Dailies", "Dailies (die Dailies)", "Product name: the main timeline. Keep."),
            ("Sequence", "Sequence (die Sequence)", "Product name: a saved filter. Keep."),
            ("Angle", "Angle (der Angle)", "Product name. Keep."),
            ("Shot List", "Shot List (die Shot List)", "Product name: a Take's checklist view. Keep."),
            ("Storyboard", "Storyboard (das Storyboard)", "Product name: every Take with a task. Keep."),
            ("Privacy phrase", "Datenschutz-Phrase", "The 12 recovery words. Draft term, please confirm."),
            ("Focus ring", "Fokusring", "Draft term, please confirm."),
            ("Note / Task / Reminder", "Notiz / Aufgabe / Erinnerung", "Ordinary words, translated."),
            ("Save", "Sichern", "Follows Apple's German UI."),
            ("Double-tap …", "Doppeltippen …", "VoiceOver hints follow Apple's German VoiceOver wording."),
            ("you", "du / dein", "Informal throughout, lower case."),
        ],
    },
    "fr": {
        "name": "French",
        "tone": 'Formal "vous", warm and plain. Catchlight is a private notes app. French typography: a non-breaking '
                'space before : and a narrow one before ? ! ;, « guillemets », curly apostrophes.',
        "plural": 'Rows marked "plural: one" are used when the count is 0 or 1; "plural: other" for every other count.',
        "example": 'English "Couldn\'t load your Takes." · draft "Impossible de charger vos Takes." · '
                   'your French "Vos Takes n\'ont pas pu être chargés." · your comment "softer"',
        "notes": {
            "Privacy phrase": 'Glossary term. Draft "phrase de confidentialité": please confirm or propose a better term; it recurs in many strings.',
            "Opens the Focus ring to change what this Take is.": '"Focus ring" drafted as "anneau de focus". The iOS feature "Focus" is "mode de concentration" in French and appears separately.',
            "Which Takes Catchlight shows while this Focus is on.": 'Here "Focus" is the iOS feature, which Apple calls "mode de concentration".',
            "%@ at %@": 'An email address read aloud by VoiceOver (user "at" domain). Drafted with "arobase".',
            "%lld-day": 'Trial length inside "Start your %@ trial now…" (e.g. "essai de 14 jours"). French needs a plural here; English does not.',
            "Start your %@ trial now, then only %@": 'First %@ is the trial length (e.g. "14 jours"), second is the price (e.g. "14,99 €/an").',
            "Snooze for %@": '%@ is a duration such as "1 heure".',
            "Settings": 'Drafted as "Réglages", the name Apple uses for Settings in French iOS, for the app\'s own screen as well.',
            "Notice History": '"Notice" (a status message on the main screen) drafted as "alerte" throughout.',
            "Snooze": 'Drafted as "Reporter" rather than Apple\'s alarm wording "Répéter", which here already means Repeat.',
        },
        "glossary": [
            ("Take", "Take (le Take, les Takes)", "Product name. Keep in English. Masculine."),
            ("Obie", "Obie (l'Obie, un Obie)", "Product name. Keep in English. Masculine: \"Nouvel Obie\"."),
            ("Iris", "Iris (l'Iris, un Iris)", "Product name: the circle beside each Take. Keep. Masculine, as the French noun."),
            ("Dailies", "Dailies", "Product name: the main timeline. Keep."),
            ("Sequence", "Sequence", "Product name: a saved filter. Keep."),
            ("Angle", "Angle", "Product name. Keep."),
            ("Shot List", "Shot List (la Shot List)", "Product name: a Take's checklist view. Keep."),
            ("Storyboard", "Storyboard (le Storyboard)", "Product name: every Take with a task. Keep."),
            ("Privacy phrase", "phrase de confidentialité", "The 12 recovery words. Draft term, please confirm."),
            ("Focus ring", "anneau de focus", "Draft term, please confirm."),
            ("Timeline", "chronologie", "Draft term."),
            ("Notice", "alerte", "A status message on the main screen. Draft term."),
            ("Note / Task / Reminder", "note / tâche / rappel", "Ordinary words, translated."),
            ("Settings", "Réglages", "Follows Apple's French UI."),
            ("Save", "Enregistrer", "Follows Apple's French UI."),
            ("Double-tap …", "Touchez deux fois …", "VoiceOver hints follow Apple's French VoiceOver wording."),
            ("you", "vous / votre", "Formal throughout."),
        ],
    },
}


def collect(root, lang):
    rows = []
    for rel in sorted(AREA):
        d = json.load(open(os.path.join(root, rel)))
        for k, e in d["strings"].items():
            loc = e.get("localizations", {})
            tr, en = loc.get(lang), loc.get("en")
            if not tr:
                continue
            comment = e.get("comment", "")
            en_unit = en["stringUnit"]["value"] if en and "stringUnit" in en else k
            if "stringSet" in tr:
                for i, (ev, tv) in enumerate(zip(en["stringSet"]["values"], tr["stringSet"]["values"])):
                    rows.append((AREA[rel], k, f"phrase {i + 1}", ev, tv,
                                 comment or "Something a person says to Siri. Must contain ${applicationName}."))
            elif "variations" in tr:
                ep = en["variations"]["plural"] if en and "variations" in en else None
                for form, sub in tr["variations"]["plural"].items():
                    ev = ep[form]["stringUnit"]["value"] if ep and form in ep else en_unit
                    rows.append((AREA[rel], k, f"plural: {form}", ev, sub["stringUnit"]["value"], comment))
            else:
                if k.startswith("CFBundle") or not re.search(r"[A-Za-z]", re.sub(r"%(\d\$)?(lld|@)", "", en_unit)):
                    continue
                rows.append((AREA[rel], k, "", en_unit, tr["stringUnit"]["value"], comment))
    return rows


def words(s):
    s = re.sub(r"%(\d\$)?(lld|ld|d|@)|\$\{\w+\}|\*\*", " ", s)
    return len([w for w in s.split() if re.search(r"[A-Za-zÀ-ÿ]", w)])


def build(lang, out, root):
    cfg = LANGS[lang]
    name = cfg["name"]
    rows = collect(root, lang)

    wb = Workbook()
    F = "Arial"
    hdr_font = Font(name=F, bold=True, color="FFFFFF")
    hdr_fill = PatternFill("solid", fgColor="5B4A2F")
    body = Font(name=F, size=10)
    wrap = Alignment(wrap_text=True, vertical="top")
    fill_in = PatternFill("solid", fgColor="FFF2B3")
    thin = Border(bottom=Side(style="thin", color="DDDDDD"))

    ws = wb.active
    ws.title = "Strings"
    heads = ["ID", "Where", "Form", "English (source)", f"{name} (draft)", "Context", "Notes for the translator",
             f"Your {name} (only if different)", "Your comment", "English words"]
    widths = [6, 14, 12, 48, 48, 30, 36, 44, 30, 9]
    for c, (h, w) in enumerate(zip(heads, widths), 1):
        cell = ws.cell(row=1, column=c, value=h)
        cell.font, cell.fill, cell.alignment = hdr_font, hdr_fill, wrap
        ws.column_dimensions[cell.column_letter].width = w
    total = 0
    for i, (area, key, form, ev, tv, comment) in enumerate(rows, 2):
        n = words(ev)
        total += n
        for c, v in enumerate([i - 1, area, form, ev, tv, comment, cfg["notes"].get(key, ""), None, None, n], 1):
            cell = ws.cell(row=i, column=c, value=v)
            cell.font, cell.alignment, cell.border = body, wrap, thin
        ws.cell(row=i, column=8).fill = fill_in
        ws.cell(row=i, column=9).fill = fill_in
    last = len(rows) + 1
    ws.freeze_panes = "D2"
    ws.auto_filter.ref = f"A1:J{last}"

    g = wb.create_sheet("Glossary")
    gl = [("Term (English)", name, "Rule")] + cfg["glossary"] + [("Catchlight, Considus", "unchanged", "Brand names. Keep.")]
    for r, row in enumerate(gl, 1):
        for c, v in enumerate(row, 1):
            cell = g.cell(row=r, column=c, value=v)
            cell.alignment = wrap
            cell.font = hdr_font if r == 1 else body
            if r == 1:
                cell.fill = hdr_fill
    for col, w in zip("ABC", (24, 32, 60)):
        g.column_dimensions[col].width = w

    rm = wb.create_sheet("Read me", 0)
    lines = [
        (f"Catchlight for iOS: {name} translation review", None),
        ("", None),
        ("What this is", "Every piece of text in the Catchlight iPhone app (screens, VoiceOver, notifications, widgets, "
                         f"share sheet, Siri phrases, permission prompts) in English, with a {name} draft beside it."),
        ("What we need", f"Read each {name} draft. If it is right, leave it. If not, write your {name} in the yellow "
                         f'column "Your {name} (only if different)" on the Strings tab, and add a comment if useful.'),
        ("Total English words", f"=SUM(Strings!J2:J{last})"),
        ("Strings to review", f"=COUNTA(Strings!A2:A{last})"),
        ("Tone", cfg["tone"]),
        ("Keep in English", f"Product names: {KEEP}. Their genders are on the Glossary tab."),
        ("Placeholders", "Keep every %@, %lld, %1$@, ${text}, ${scope} and ${applicationName} exactly as written. "
                         "The app replaces them with names, numbers or dates. Numbered ones (%1$@, %2$@) may move "
                         "within the sentence."),
        ("Plurals", cfg["plural"]),
        ("Siri phrases", 'Rows marked "phrase N" are alternative things a person can say to Siri. Each must contain '
                         "${applicationName}."),
        ("Length", f"Short labels sit in narrow rows on an iPhone screen. Where the {name} runs much longer than the "
                   "English, a shorter wording is welcome."),
        ("Word count", "English words per row are in the last column of the Strings tab: words containing letters, "
                       "placeholders not counted. Each plural form and each Siri phrase counts as its own row."),
    ]
    for r, (a, b) in enumerate(lines, 1):
        ca, cb = rm.cell(row=r, column=1, value=a), rm.cell(row=r, column=2, value=b)
        ca.font = Font(name=F, bold=True, size=14 if r == 1 else 10)
        cb.font = body
        ca.alignment = cb.alignment = wrap
    for ref in ("B5", "B6"):
        rm[ref].font = Font(name=F, bold=True, size=12)
        rm[ref].alignment = Alignment(horizontal="left")
    rm.column_dimensions["A"].width = 22
    rm.column_dimensions["B"].width = 100
    leg = rm.cell(row=len(lines) + 2, column=1, value="Yellow cells")
    leg.font, leg.fill = Font(name=F, bold=True, size=10), fill_in
    rm.cell(row=len(lines) + 2, column=2, value="The only cells to fill in (Strings tab, columns H and I).").font = body
    ex = len(lines) + 3
    rm.cell(row=ex, column=1, value="Example").font = Font(name=F, bold=True, size=10)
    c = rm.cell(row=ex, column=2, value=cfg["example"])
    c.font, c.alignment = body, wrap
    wb.save(out)
    print(f"{out}\nrows={len(rows)} words={total}")


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in LANGS:
        sys.exit(__doc__)
    build(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else ".")
