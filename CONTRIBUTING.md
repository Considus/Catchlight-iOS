# Contributing to Catchlight

Thanks for taking a look. Catchlight holds people's private notes, and it holds them under a key the user controls and nobody else has, so the constraints below aren't house style. They are the reason the app is worth having.

## Before you write anything

Read the non-negotiables in `README.md`, the zero-knowledge and encryption-always-on ones in particular. A contribution that weakens either of them won't be accepted, however good the rest of it is.

The encryption architecture had specialist sign-off on 2026-06-05 and was revised to v1.1 on 2026-06-10. The domain-separation strings and derivation parameters in `Sources/CatchlightCore/Crypto/` are frozen cross-platform contract bytes, so please don't propose changes to them. They are the bytes every future client has to agree on.

## Development setup

The iOS app target needs full Xcode, not just the Command Line Tools, and it needs **Xcode 26 or later** as of 2026-08-15. The App Intents declare `supportedModes` behind `@available(iOS 26.0, *)` (D-202), and `IntentModes` is not in the iOS 18 SDK, so Xcode 16 cannot compile the app. Note what this does not change. The deployment floor is still iOS 18.0 (D-039), so the app runs on iOS 18 and only builds against the iOS 26 SDK.

Keep build output outside the source tree, as described under "Keep build output out of the source tree" in `README.md`.

```bash
BUILD_DIR="$HOME/CatchlightBuild"
swift build  --scratch-path "$BUILD_DIR/spm"
swift run coreverify   # the runtime checks, and they must pass before any PR
swift test   --scratch-path "$BUILD_DIR/spm"

brew install xcodegen
xcodegen generate      # produces Catchlight.xcodeproj
# Build with: xcodebuild … -derivedDataPath "$BUILD_DIR/DerivedData"
```

## Pull requests

- Every PR has to pass `swift test` with no regressions.
- No analytics, no telemetry, nothing transmitted off the device. Ever.
- `kSecAttrSynchronizable: false` on every Keychain item, and that one is not up for discussion.
- Follow the code style that is already there.
- No third-party dependencies without talking about it first.

## Security issues

Please don't open a public issue for a security vulnerability. [`SECURITY.md`](SECURITY.md) says how to report one privately.
