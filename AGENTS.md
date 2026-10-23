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
- **Give a change that affects stored or synced data a deliberate extra pass and a real backup, not only a green test run:** people keep their real notes in this app. That covers `Catchlight/Database`, `Security`, `Sync`, `Import`, `Subscription` and a package pin in `project.yml`.

**Not checkable locally:** push, StoreKit receipts and the subscription path (a sideloaded build has no receipt, and that failure wipes the index), background sync scheduling, and Spotlight body text on iOS 17 and later (title only, FB17330079).

## Ship

1. Install the committed hooks once per clone, copied from `origin/main` into git's own hooks folder. `hooks/pre-commit` refuses a commit on `main`, and `hooks/commit-msg` refuses a Claude attribution footer or an em or en dash.

   ```bash
   git fetch origin
   git config --unset core.hooksPath || true
   d="$(git rev-parse --git-common-dir)/hooks"; mkdir -p "$d"
   for h in pre-commit commit-msg; do git show "origin/main:hooks/$h" > "$d/$h.tmp" && chmod 755 "$d/$h.tmp" && mv "$d/$h.tmp" "$d/$h" || { rm -f "$d/$h.tmp"; echo "not copied: $h"; }; done
   ```

   Never set `core.hooksPath` to `hooks`. Git would then run the hook files of whichever branch is checked out, so checking out an outsider's PR would run their code on your machine. The unset line removes that setting from a clone that followed the old instruction. While it is set, git ignores its own hooks folder. If `git config --show-origin --get core.hooksPath` still prints a value afterwards, it was set globally: remove it with `git config --global --unset core.hooksPath`. Each hook goes to a temporary file first, so a failed copy keeps the old hook instead of leaving an empty one that lets every commit through. Copy again after a reviewed change to `hooks/` lands on `main`.
2. Check nobody is on the work; branch from `origin/main`:

   ```bash
   git fetch origin
   gh pr list -R Considus/Catchlight-iOS
   git checkout -b <type>/<short-name> origin/main
   ```

3. Stage by explicit path, never `git add -A` or `git commit -a`.
4. Fill [`.github/pull_request_template.md`](.github/pull_request_template.md), adding the risks and whether the change can be walked back.
