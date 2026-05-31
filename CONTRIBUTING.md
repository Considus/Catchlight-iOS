# Contributing to Catchlight

Thank you for your interest in contributing.

## Before you contribute

- Read the non-negotiables in `README.md` — particularly the zero-knowledge and
  encryption-always-on constraints. Any contribution that weakens these will not
  be accepted regardless of other merits.
- The encryption architecture is under specialist review. Do not propose changes
  to `Sources/CatchlightCore/Crypto/` until that review is published.

## Development setup

```bash
# Requires full Xcode (not just Command Line Tools) for the iOS app target.
swift build            # builds CatchlightCore
swift run coreverify   # 52 runtime checks — must pass before any PR
swift test             # full XCTest suite — must be all green

brew install xcodegen
xcodegen generate      # produces Catchlight.xcodeproj
```

## Pull requests

- All PRs must pass `swift test` with no regressions.
- No analytics, no telemetry, no off-device data transmission — ever.
- `kSecAttrSynchronizable: false` on every Keychain item — this is not negotiable.
- Follow the existing code style. No third-party dependencies without discussion.

## Security issues

Please do not open public issues for security vulnerabilities.
Contact the maintainer privately before disclosure.
