# Agent notes

For a coding agent working in this repo. `README.md` and `CONTRIBUTING.md` are the human documents and they are not duplicated here; read the non-negotiables in the README first. This file is the part an agent needs and a person already knows.

Every task moves through four beats: isolate on a branch, build, prove with evidence, ship a PR carrying that evidence.

## Isolate

🚨 **`Repos/` is one checkout shared by every concurrent session**, so `HEAD` may be sitting on another session's branch when you arrive. Four incidents so far, one of which published another session's uncommitted work.

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

🚨 **`Sources/CatchlightCore/Crypto/` holds frozen contract bytes.** The domain-separation strings and derivation parameters had specialist sign-off on 2026-06-05, revised to v1.1 on 2026-06-10, and every future client has to agree on them. Changing one is not a refactor, it breaks existing data. Do not propose it.

**The deployment floor is iOS 18.0 and the app builds against the iOS 26 SDK.** The compiler will not catch an API newer than the floor, so anything post-18.0 needs `@available` / `#available` and a wrong version on the guard fails on a real device rather than in CI. Full Xcode 26 or later is required, because the App Intents declare `supportedModes` behind `@available(iOS 26.0, *)` and `IntentModes` is not in the iOS 18 SDK.

**No third-party dependencies without agreeing it first.**

Prefer a shared component or a token over a per-screen implementation. Extract shared logic only when two callers need it; one caller is a layer for nothing.

Product nouns are Capitalised in UI copy only, never in code identifiers. When the subject is what the app holds, the noun is a **Take**.

⚠️ **Leave the vestigial `SessionController` state alone.** It has been reviewed and deliberately kept. Do not re-flag it.

## Prove

Keep build output outside the source tree:

```bash
BUILD_DIR="$HOME/CatchlightBuild"
swift build --scratch-path "$BUILD_DIR/spm"
swift run coreverify          # runtime checks, must pass before any PR
swift test  --scratch-path "$BUILD_DIR/spm"
xcodegen generate
xcodebuild test -scheme Catchlight -derivedDataPath "$BUILD_DIR/DerivedData" \
  -destination '<a simulator from `xcrun simctl list devices available`>'
```

🚨 **Read the test count, never the word "passed".** The `Catchlight` scheme runs both `CatchlightTests` and the UI tests, and a scheme that silently stops running one of them still reports success.

🚨 **Accessibility identifiers are a contract with XCUITest.** Renaming or removing one breaks a test that queries it. An identifier on a container is not exposed on iOS 17. Query type-agnostically rather than through a concrete element type.

🚨 **Keyboard entry and search are device-only.** A test that depends on either cannot be trusted from the simulator. CI disables the simulator hardware keyboard for exactly this reason.

Capture the **before** while you are still reproducing the problem, which is when it is cheapest, and the **after** once the change works. For a visible change that means a simulator screenshot: seed the screen, then `xcrun simctl io <udid> screenshot`. Pin the destination explicitly; a rotted simulator device is a known failure mode here and reads as a code failure.

**Mark uses this app for his real daily notes.** A data-affecting change needs a deliberate extra pass and a real backup, not just a green test run.

**What cannot be checked locally:** push, StoreKit receipts and the subscription path (a sideloaded build has no receipt, and the failure mode there wipes the index), background sync scheduling, Spotlight body text on iOS 17 and later (title only, FB17330079), and anything that needs a physical device.

## Ship

Open the PR with the evidence in the body: what changed, how it was tested, the risks. Run the title and body through the anti-slop pass before posting. No AI attribution footer, ever.

**Greptile costs a credit and the account has 30 a month.** A review runs only on a PR carrying the `greptile` label, set in `.greptile/config.json`. Label anything touching crypto, the Keychain, sync round-tripping, the subscription path or an availability guard. Leave a copy fix, a version bump or a design-note tidy unlabelled. Do not run a loop that re-reviews until it scores 5/5; each pass is another credit.

Present the PR URL and stop. Merging is a separate decision, and the worktree stays until the PR is merged or closed.
