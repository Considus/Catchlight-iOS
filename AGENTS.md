# Agent notes

For a coding agent working in this repo. `README.md` and `CONTRIBUTING.md` are the human documents and they are not duplicated here; read the non-negotiables in the README first. This file is the part an agent needs and a person already knows.

Every task moves through four beats: isolate on a branch, build, prove with evidence, ship a PR carrying that evidence.

## Isolate

🚨 **`Repos/` is one checkout shared by every concurrent session**, so `HEAD` may be sitting on another session's branch when you arrive. Six incidents so far, one of which published another session's uncommitted work.

Take your own checkout rather than branching in the shared tree:

```bash
python3 ../Catchlight-Ops/session_worktree.py --name <session>
```

A plain `git worktree add` is not the fix and was measured: it breaks `_paths.py` completely, because `site_root()` and `ios_root()` derive siblings under `Repos/` and `workplan()` walks two levels up. The script builds the mirrored-symlink layout that works.

If you are in the shared tree anyway, branch from the named ref and check first:

```bash
git fetch origin
gh pr list -R Considus/catchlight-ios
git checkout -b <type>/<short-name> origin/main
```

Stage by explicit path. **Never `git add -A` and never `git commit -a`.** Run `git --no-optional-locks status --porcelain` immediately before committing and read every line: an unexpected path is another session's work in progress, not noise. Check `git branch --show-current` and `git log --oneline -1` before you push.

Regenerate the project after any branch change or file addition, because `Catchlight.xcodeproj` is gitignored and built from `project.yml`:

```bash
xcodegen generate
```

## Build

**The non-negotiables in `README.md` are constraints, not house style.** A change that weakens one is rejected however good the rest is: zero knowledge with nothing transmitted off the device, `kSecAttrSynchronizable: false` on every Keychain item, encryption always on and never toggleable, offline-first with local-only as a real way to run it, and nothing in the cloud folder but platform-agnostic JSON envelopes and one plaintext metadata file.

**`CatchlightCore` is not in this repo.** It lives in `Considus/Catchlight-Core` and arrives as a remote Swift package pinned with `exactVersion` in `project.yml`. A Core change is made, tested and tagged there, then reaches the app as a bump of that pin in its own PR. `.github/workflows/core-pin.yml` opens that PR every Monday when Core has a newer tag (or on demand from the Actions tab) and dispatches CI on it; the Claude review skips a PR a bot opened, so review its diff yourself, and read the Core compare before merging, because a release can change what is written to disk. On a PR a person opened, add the `re-review` label after a push to get a fresh Claude review of the latest commit (remove it first if it is on); closing and reopening also works but re-runs Greptile, which spends a credit. `Tests/CatchlightAppTests` holds only tests that need the app module; Core's suite and `coreverify` run in the Core repo.

🚨 **The encrypted store and the Keychain code exist twice until iOS switches over.** `Catchlight/Database/EncryptedTakeStore.swift`, `Catchlight/Security/Keychain.swift`, `MnemonicKeychain.swift`, `KeychainConfig.swift` and `BIP39Wordlist+English.swift` were moved, with their history, into `Considus/Catchlight-AppleStorage`, which the Mac app uses ([[D-351]]). This app still builds its own copies until a PR moves it onto that package. Until then, a change to any of those files here has to be made in Catchlight-AppleStorage too, or the iPhone's and the Mac's databases and Keychain handling drift apart. The one intended difference: AppleStorage sets `kSecUseDataProtectionKeychain` on every Keychain query, which iOS ignores.

🚨 **Core's `Sources/CatchlightCore/Crypto/` holds frozen contract bytes.** The domain-separation strings and derivation parameters had specialist sign-off on 2026-06-05, revised to v1.1 on 2026-06-10, and every future client has to agree on them. Changing one is not a refactor, it breaks existing data. Do not propose it, here or through a Core version bump.

**The deployment floor is iOS 18.0 and the app builds against the iOS 26 SDK.** The compiler will not catch an API newer than the floor, so anything post-18.0 needs `@available` / `#available` and a wrong version on the guard fails on a real device rather than in CI. Full Xcode 26 or later is required, because the App Intents declare `supportedModes` behind `@available(iOS 26.0, *)` and `IntentModes` is not in the iOS 18 SDK.

**No third-party dependencies without agreeing it first.**

Prefer a shared component or a token over a per-screen implementation. Extract shared logic only when two callers need it; one caller is a layer for nothing.

Product nouns are Capitalised in UI copy only, never in code identifiers. When the subject is what the app holds, the noun is a **Take**. The product lexicon is `https://catchlight.app/glossary/`: name new types, tests and PR prose after its concepts rather than inventing synonyms.

🚨 **A Take waiting in the conflict queue is held until the user chooses** (owner 2026-10-07: "the file shouldn't update or edit until the conflict is resolved"). Every app edit goes through `ConflictHoldingStore`, which refuses writes to a held Take; a new edit path gates on `AppModel.ensureEditable(takeID)` (or `ensureNotHeld` for an ungated action) so the user is told why. Sync is handed the held ids on every pass (`BackgroundSyncCoordinator.pass`). Only `ConflictQueue.resolve` and the unverified-copy choices write through `DailiesViewModel.conflictChoiceStore`, the raw store. The queue is kept on disk, sealed, in `Database/Conflicts` inside the library, so "Skip for now" hides a conflict until the next launch and never releases the hold.

⚠️ **Leave the vestigial `SessionController` state alone.** It has been reviewed and deliberately kept. Do not re-flag it.

### Diagnostics log

**Every line the app writes to the diagnostics log is a `Notice`** (`Catchlight/Diagnostics/Notice.swift`), recorded with `DiagnosticsLog.shared.record(.someNotice)`. The log stores `[CCIOS-NNN] message`: the code identifies the notice whatever language the message is in, and Notice History strips it, so only the export shows it. **Which group a notice goes in is decided by one rule (owner, 2026-10-04): a warning that can appear on the main screen goes in Notice History (1xx–4xx, in the device language); anything that can never appear there is 9xx, export only, English.** A lasting banner is recorded once per onset through `NoticeOnset`, not on every launch. A new log line is a new `NoticeCode` case with the next free number in its hundred and a one-line English summary comment. Never reuse or renumber a code. `NoticeCodeTests` fails on the free-text form `record(.storage, "…")`. After adding a code, regenerate the support table: `python3 scripts/diagnostics/notice_codes.py > ~/Claude/Considus/Products/Catchlight/03_Engineering/Diagnostic_Reference_Codes.md`.

### Localisation

Every string a person sees or hears goes through a String Catalog: `Localizable.xcstrings` in the app, widgets and share extension, `InfoPlist.xcstrings` for the permission prompts, `AppShortcuts.xcstrings` for Siri phrases. English is the source language. The compiler fills the catalogs; `xcodebuild -exportLocalizations` (or a build in Xcode) syncs them, so never hand-add a key the code does not use.

- **A literal passed straight to SwiftUI is already localised** (`Text("…")`, `Button("…")`, `.accessibilityLabel("…")`). A helper or component that takes UI copy takes it as `LocalizedStringKey`, never `String`: a `String` parameter silently drops the literal out of the catalog. `SettingsRow`, `SelectorRow`, `MenuFieldRow`, `DockPill`, `SwipeAction` and `TakeLabelLane` follow this.
- **Text built anywhere else is `String(localized: "…")` at the literal**: view-model errors, notification text, VoiceOver sentences, computed labels. The literal must sit inside the call. `String(localized: String.LocalizationValue(someVar))` compiles and is never extracted.
- **One whole sentence per key.** Never glue fragments (`"Double-tap to " + verb`), never build plurals (`"Take\(n == 1 ? "" : "s")"`). A count goes in as an `Int` interpolation and the catalog carries the plural forms; English has its own `one`/`other` variations for every such key.
- **A raw value is an identifier, not a label.** Enums persisted or compared by raw value get a separate `label` with a literal per case.
- **The reminder sheet's week start is per language**, in `ReminderPickerSheet.firstWeekday`: Sunday in English and Brazilian Portuguese, Monday in German, Spanish, Italian, Dutch, European Portuguese, Polish, Swedish, Danish, Norwegian, Finnish, Turkish and French, except French in Canada (Sunday). A new language adds its own case.
- **Dates come from formatters and templates** (`setLocalizedDateFormatFromTemplate`, `DateComponentsFormatter`), never a fixed `dateFormat` for anything shown. Machine formats keep `en_US_POSIX`.
- **What stays English on purpose:** the product nouns (Take, Obie, Iris, Dailies, Sequence, Angle, Shot List, Storyboard), which are still routed through the catalog so a translator sees them in context and keeps them; the 12 recovery-phrase words, which are the BIP-39 English wordlist and part of the key; developer-only diagnostics (the `lifecycle` category and scheduling failures, which never show in Notice History); the `Import` folder name in the cloud folder. Notice History lines are recorded in the device language, like the notices themselves.
- **Core values the app shows are worded here**, in `Catchlight/UI/CoreLabels.swift`. Core's own `label`s stay English and carry no translations.

The test scheme runs in English whatever the machine is set to (`language: en` in `project.yml`), because many tests assert the English copy. To run them in another language, say so: `xcodebuild test -testLanguage de -testRegion DE`; English-copy assertions are expected to fail there.

Three checks. Run the first two after touching UI copy. The static one lists English sentences in the source that no catalog holds (export first, it is what syncs the catalogs):

```bash
python3 scripts/l10n/find_unlocalised.py
```

The visual one fills every catalog with a throwaway German that wraps each string in ⟦ ⟧. Build, launch with `-AppleLanguages '(de)'`, and any English on screen without brackets escaped. `restore` before staging anything:

```bash
python3 scripts/l10n/pseudo_locale.py apply
python3 scripts/l10n/pseudo_locale.py restore
```

The third runs after adding or changing a translation. It compares every translation's placeholders with the English, in every plural form and Siri phrase, and lists each mismatch, because a dropped or retyped placeholder garbles or crashes at run time with nothing at build time to say so:

```bash
python3 scripts/l10n/check_placeholders.py
```

A translation pasted from the wrong language passes the placeholder check, because the other language has the same placeholders. The mix-up check compares every pair of languages and flags one whose text is copied from another (neighbouring languages are allowed the overlap they honestly share):

```bash
python3 scripts/l10n/check_mixups.py
```

A new language's draft goes into every catalog in one step, from a JSON file of plain strings, plural forms and Siri phrases; it refuses to write anything while a catalog key is missing from the draft:

```bash
python3 scripts/l10n/apply_draft.py es draft-es.json
```

A translator gets a review workbook built from the catalogs: English beside the draft, a column for their version, English word counts and a glossary. Each language's notes and glossary live in the script (needs `openpyxl`). `--store` adds the App Store listing and screenshot text, which live outside the repo:

```bash
python3 scripts/l10n/review_workbook.py fr Catchlight_iOS_French_Translation_Review.xlsx --store store-src.json store-fr.json
```

For a translator who wants plain text, `--texts` writes one English file and one file per language, line N of each translating line N of the English. Placeholders read as `{1}`, `{2}` (numbered by position, so a translation may reorder them) and `{app}`, a line break as ` / `; lines with nothing to translate are left out and each English line appears once. The script refuses to write anything if a language is missing a line or translates two keys that share an English line differently.:

```bash
python3 scripts/l10n/review_workbook.py --texts OUT_DIR --store-src store-src.json --store-dir DRAFTS_DIR
```

A translated text file goes back into the catalogs with `apply_texts.py`. It finds each key by its English line and rebuilds the value against that key's English: `{1}` becomes the key's specifier (numbered when the key has more than one), `{app}` becomes `${applicationName}`, ` / ` becomes a line break where the English has one, and the one capitalised run is wrapped in `**` where the English is bold. It refuses to write anything if a translation loses or invents a placeholder. A product name or bare number has no line; a new language takes the English for it. `test_round_trip.py` exports every language to text and writes it back, and must report 0 changed:

```bash
python3 scripts/l10n/apply_texts.py pl Catchlight_iOS_Translation_EN.txt Catchlight_iOS_Translation_PL.txt
python3 scripts/l10n/test_round_trip.py
```

## Prove

Keep build output outside the source tree:

```bash
BUILD_DIR="$HOME/CatchlightBuild"
xcodegen generate
xcodebuild test -scheme Catchlight -derivedDataPath "$BUILD_DIR/DerivedData" \
  -destination '<a simulator from `xcrun simctl list devices available`>'
```

**Agree the seams before writing tests.** Name the public interface each new test will cross, and confirm it before writing the test. Tests live at seams, never against internals: not private methods, not the database behind a store's back, not a mocked internal collaborator. A test that breaks on a refactor that did not change behaviour was testing the implementation.

**An expected value comes from outside the code under test**: a known-good literal, a worked example, the spec, or a fixture captured from a real run. An assertion that recomputes the answer the way the code does passes by construction and can never disagree with it.

**One slice at a time.** One test, the least code that passes it, then the next. Writing every test first tests an imagined shape. Watch each new test fail before making it pass.

🚨 **Read the test count, never the word "passed".** The `Catchlight` scheme runs both `CatchlightTests` and the UI tests, and a scheme that silently stops running one of them still reports success.

🚨 **Accessibility identifiers are a contract with XCUITest.** Renaming or removing one breaks a test that queries it. An identifier on a container is not exposed on iOS 17. Query type-agnostically rather than through a concrete element type.

🚨 **Keyboard entry and search are device-only.** A test that depends on either cannot be trusted from the simulator. CI disables the simulator hardware keyboard for exactly this reason.

Capture the **before** while you are still reproducing the problem, which is when it is cheapest, and the **after** once the change works. For a visible change that means a simulator screenshot: seed the screen, then `xcrun simctl io <udid> screenshot`. Pin the destination explicitly; a rotted simulator device is a known failure mode here and reads as a code failure.

**The `--uitesting` fixture is not how Mark runs the app.** It starts at the default text size, with the "Created on" stamp off, no notice strips, and two short Takes. Before trusting a layout result, mirror the conditions the change is about: `-UIPreferredContentSizeCategoryName <category>` for text size, `-catchlight.creationStamp editor|always` for the stamp, `--uitesting-notice` for a strip above the page, `--uitesting-unverified` for the cloud-copy review sheet. A brand-new simulator also shows iOS's one-time "slide to type" introduction over the first keyboard; `dismissKeyboardIntroductionIfPresent` in `UITestSupport` handles it, so route keyboard-raising taps through `tapUntil` or `typeWhenReady`.

**Run a UI test you add or change on both CI simulators before pushing**: iPhone 16 on the iOS 18 runtime and on the latest one. Their screens and keyboards differ, and a layout fix proven on one phone has failed on the other.

**Mark uses this app for his real daily notes.** A data-affecting change needs a deliberate extra pass and a real backup, not just a green test run.

**What cannot be checked locally:** push, StoreKit receipts and the subscription path (a sideloaded build has no receipt, and the failure mode there wipes the index), background sync scheduling, Spotlight body text on iOS 17 and later (title only, FB17330079), and anything that needs a physical device.

## Ship

Open the PR with the evidence in the body: what changed, how it was tested, the risks, and whether the change can be walked back. The `pr` skill carries the shape. A PR body is technical writing and takes no voice or anti-slop pass. No AI attribution footer, ever.

**Greptile costs a credit and the account has 50 a month across the org (the Greptile free plan).** A review runs only on a PR carrying the `greptile` label, and that needs TWO settings to agree ([[D-287]]): `labels: ["greptile"]` in `.greptile/config.json`, which decides which PRs qualify, and the dashboard's auto-review trigger, which decides whether anything starts at all. A filter with the trigger off reviews nothing; the trigger on with no filter reviews everything, which is how this repo spent credits on unlabelled PRs until 2026-09-18. Label anything touching crypto, the Keychain, sync round-tripping, the subscription path or an availability guard. Leave a copy fix, a version bump or a design-note tidy unlabelled. Do not run a loop that re-reviews until it scores 5/5; each pass is another credit.

Present the PR URL. Once Mark has approved the work and CI is green, merge it. The worktree stays until the PR is merged or closed.
