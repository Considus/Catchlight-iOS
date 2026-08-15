# Contributing to Catchlight

Thank you for your interest in contributing.

## Before you contribute

- Read the non-negotiables in `README.md` — particularly the zero-knowledge and
  encryption-always-on constraints. Any contribution that weakens these will not
  be accepted regardless of other merits.
- The encryption architecture received specialist sign-off (2026-06-05) and was
  revised to v1.1 on 2026-06-10. The domain-separation strings and derivation
  parameters in `Sources/CatchlightCore/Crypto/` are frozen cross-platform
  contract bytes — do not propose changes to them.

## Development setup

```bash
# Requires full Xcode (not just Command Line Tools) for the iOS app target.
# XCODE 26 OR LATER (2026-08-15). The App Intents declare `supportedModes` behind
# `@available(iOS 26.0, *)` (D-202), and `IntentModes` is absent from the iOS 18
# SDK, so Xcode 16 cannot compile the app. Note what this does NOT change: the
# deployment floor is still iOS 18.0 (D-039). The app RUNS on iOS 18 and BUILDS
# only against the iOS 26 SDK.
# Keep build artifacts OUTSIDE the source tree (see README "Build artifacts"):
BUILD_DIR="$HOME/CatchlightBuild"
swift build  --scratch-path "$BUILD_DIR/spm"
swift run coreverify   # the runtime checks — must pass before any PR (all green)
swift test   --scratch-path "$BUILD_DIR/spm"

brew install xcodegen
xcodegen generate      # produces Catchlight.xcodeproj
# Build with: xcodebuild … -derivedDataPath "$BUILD_DIR/DerivedData"
```

## Pull requests

- All PRs must pass `swift test` with no regressions.
- No analytics, no telemetry, no off-device data transmission — ever.
- `kSecAttrSynchronizable: false` on every Keychain item — this is not negotiable.
- Follow the existing code style. No third-party dependencies without discussion.

## Security issues

Please do not open public issues for security vulnerabilities.
See [`SECURITY.md`](SECURITY.md) for how to report privately.
