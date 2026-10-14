# Agent notes

For a coding agent working in this repo. People start with [`README.md`](README.md) (its non-negotiables first) and [`CONTRIBUTING.md`](CONTRIBUTING.md); this file does not repeat them. Text a person sees follows [`LOCALISATION.md`](LOCALISATION.md).

## Build

- **Run `xcodegen generate` after a branch change or a new file:** `Catchlight.xcodeproj` is gitignored and built from `project.yml`.
- **Make a Core change in Catchlight-Core.** It reaches this app as a bump of the `exactVersion` pin in `project.yml`, which `.github/workflows/core-pin.yml` opens weekly. Read the Core compare before merging one: a release can change what is written to disk. `Tests/CatchlightAppTests` holds only tests that need the app module.
- **Make any change to `Catchlight/Database/EncryptedTakeStore.swift`, `Catchlight/Security/Keychain.swift`, `MnemonicKeychain.swift`, `KeychainConfig.swift` or `BIP39Wordlist+English.swift` in Catchlight-AppleStorage too.** The Mac uses that package and this app its own copies, which must not drift. The one intended difference: AppleStorage sets `kSecUseDataProtectionKeychain`, which iOS ignores.
- **Guard any API newer than iOS 18.0 with `@available` / `#available`.** The app builds against the iOS 26 SDK, so the compiler won't catch it, and a wrong guard fails on a device, not in CI.
- **Prefer a shared component or token to a per-screen one;** extract shared logic only at two callers.
- **Capitalise product nouns in UI copy only, never in identifiers.** What the app holds is a **Take**. Name types, tests and PR prose after the glossary, `https://catchlight.app/glossary/`.
- **Change nothing about a Take in the conflict queue until the user chooses.** Every app edit goes through `ConflictHoldingStore`; gate a new edit path on `AppModel.ensureEditable(takeID)` (`ensureNotHeld` if ungated). Never resolve a converted pair on its own id: the next push overwrites the other device's Script. The rules are in `ConflictQueue.swift` and `ConflictHoldingStore.swift`.
- **Write every diagnostics line as a `Notice`,** by the header of `Catchlight/Diagnostics/Notice.swift`.
- **Leave the vestigial `SessionController` state alone:** it was reviewed and kept.

## Test

```bash
BUILD_DIR="$HOME/CatchlightBuild"
xcodegen generate
xcodebuild test -scheme Catchlight -derivedDataPath "$BUILD_DIR/DerivedData" \
  -destination '<a simulator from `xcrun simctl list devices available`>'
```

- **Read the test count, not the word "passed":** the scheme runs the unit and UI tests, and one silently dropped still reports success.
- **Write and prove tests by [`Tests/README.md`](Tests/README.md):** seams, fixtures, simulators and evidence.

**Not checkable locally:** push, StoreKit receipts and the subscription path (a sideloaded build has no receipt, and that failure wipes the index), background sync scheduling, and Spotlight body text on iOS 17 and later (title only, FB17330079).

## Ship

1. Once per clone: `git config core.hooksPath hooks`. `hooks/pre-commit` refuses a commit on `main`; `hooks/commit-msg` refuses a Claude attribution footer.
2. Check nobody is on the work; branch from `origin/main`:

   ```bash
   git fetch origin
   gh pr list -R Considus/Catchlight-iOS
   git checkout -b <type>/<short-name> origin/main
   ```

3. Stage by explicit path, never `git add -A` or `git commit -a`.
4. Fill [`.github/pull_request_template.md`](.github/pull_request_template.md), adding the risks and whether the change can be walked back.
