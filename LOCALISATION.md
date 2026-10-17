# Localisation

Every string a person sees or hears goes through a String Catalog: `Localizable.xcstrings` in the app, widgets and share extension, `InfoPlist.xcstrings` for the permission prompts, `AppShortcuts.xcstrings` for Siri phrases. English is the source language. The compiler fills the catalogs and `xcodebuild -exportLocalizations` (or a build in Xcode) syncs them, so never hand-add a key the code does not use.

## Writing a string

- **A literal passed straight to SwiftUI is already localised** (`Text("…")`, `Button("…")`, `.accessibilityLabel("…")`). A helper or component that takes UI copy takes it as `LocalizedStringKey`, never `String`: a `String` parameter silently drops the literal out of the catalog. `SettingsRow`, `SelectorRow`, `MenuFieldRow`, `DockPill`, `SwipeAction` and `TakeLabelLane` follow this.
- **Text built anywhere else is `String(localized: "…")` with the literal inside the call:** view-model errors, notification text, VoiceOver sentences, computed labels. `String(localized: String.LocalizationValue(someVar))` compiles and is never extracted.
- **One whole sentence per key.** Never glue fragments (`"Double-tap to " + verb`) or build plurals (`"Take\(n == 1 ? "" : "s")"`). A count goes in as an `Int` interpolation and the catalog carries the plural forms; English has its own `one`/`other` variations for every such key.
- **A raw value is an identifier, not a label.** An enum persisted or compared by raw value gets a separate `label` with a literal per case.
- **The reminder sheet's week start is per language,** in `ReminderPickerSheet.firstWeekday` (`Catchlight/UI/Components/FocusRingFanView.swift`), which lists each. A new language adds its own case.
- **Dates come from formatters and templates** (`setLocalizedDateFormatFromTemplate`, `DateComponentsFormatter`), never a fixed `dateFormat` for anything shown. Machine formats keep `en_US_POSIX`.
- **Core values the app shows are worded in `Catchlight/UI/CoreLabels.swift`.** Core's own `label`s stay English and carry no translations.

**What stays English on purpose:** the product nouns (Take, Obie, Iris, Dailies, Sequence, Angle, Shot List, Storyboard), still routed through the catalog so a translator sees them in context and keeps them; the 12 recovery-phrase words, which are the BIP-39 English wordlist and part of the key; developer-only diagnostics (the `lifecycle` category and scheduling failures, which never show in Notice History); and the `Import` folder name in the cloud folder. Notice History lines are recorded in the device language, like the notices themselves.

## Testing in another language

The test scheme runs in English whatever the machine is set to (`language: en` in `project.yml`), because many tests assert the English copy. To run another language, say so: `xcodebuild test -testLanguage de -testRegion DE`. English-copy assertions are expected to fail there.

## Checks and tools

Each script in `scripts/l10n/` documents its own usage at the top of the file.

| When | Script | What it does |
|---|---|---|
| After touching UI copy | `find_unlocalised.py` | Lists English sentences in the source that no catalog holds. Export first: it is what syncs the catalogs |
| After touching UI copy | `pseudo_locale.py apply`, then `restore` | Fills every catalog with a throwaway German wrapping each string in ⟦ ⟧; build, launch with `-AppleLanguages '(de)'`, and any English without brackets escaped. `restore` before staging anything |
| After adding or changing a translation | `check_placeholders.py` | Compares every translation's placeholders with the English, in every plural form and Siri phrase. A dropped or retyped placeholder garbles or crashes at run time, with nothing at build time to say so |
| After adding or changing a translation | `check_mixups.py` | Flags a language whose text is copied from another: a translation pasted from the wrong language passes the placeholder check |
| Adding a language | `apply_draft.py` | Writes a JSON draft into every catalog in one step; writes nothing while a catalog key is missing from the draft |
| For a translator | `review_workbook.py` | A review workbook (English beside the draft, a column for theirs, word counts, a glossary), or with `--texts` plain-text files, line N translating line N of the English. Each language's notes and glossary live in the script. `--store` adds the App Store text, which lives outside the repo |
| A translation comes back as text | `apply_texts.py` | Writes it back into the catalogs against each key's English; writes nothing if a translation loses or invents a placeholder |
| With `apply_texts.py` | `test_round_trip.py` | Exports every language to text and writes it back; must report 0 changed |
