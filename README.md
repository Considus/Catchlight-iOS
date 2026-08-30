# Catchlight, the app codebase

A zero-knowledge notes and reminders app for iPhone. Everything is encrypted on the device, there is no backend, and the whole thing works with the network switched off.

This started as the Phase 5 work, so the project setup, data model, encryption layer, local storage, sync engine, notifications, search and background tasks. It now carries the complete Phase 6 product UI as well, Dailies, Dial, Sequences, Search, Settings, onboarding and the paywall, all of it done as of 2026-06-09.

The detailed design and encryption-architecture documents are kept separately by Considus. There is a public overview of the security model in [`SECURITY.md`](SECURITY.md).

## Layout

```
CatchlightApp/
├── Package.swift                 # SwiftPM: CatchlightCore + coreverify
├── project.yml                   # XcodeGen spec for the iOS app (run: xcodegen generate)
├── Sources/
│   ├── CatchlightCore/           # PLATFORM-AGNOSTIC core, pure Swift + CryptoKit
│   │   ├── Model/                # Take, Sequence, reminders, attachments, seed Takes
│   │   ├── Serialization/        # ISO-8601 + platform-agnostic JSON codec
│   │   ├── Crypto/               # HKDF master key + key hierarchy, Take crypto
│   │   │                         #   (AES-256-GCM), manifest HMAC, X25519 handshake
│   │   │                         #   + SAS code, BIP-39, hard-failing RNG
│   │   ├── Sync/                 # cloud blob, manifest v2 (tombstones), sync engine,
│   │   │                         #   conflicts, lock, folder protocol
│   │   └── Storage/              # TakeStore protocol + in-memory impl
│   └── coreverify/               # dependency-free runtime verifier (runs under CLT)
├── Tests/                        # XCTest suites (Core + iOS + UI)
└── Catchlight/                   # iOS APP TARGET, platform-specific layers
    ├── App/                      # entry point, composition root, scene lifecycle
    ├── Security/                 # Keychain (SE-wrapped master key), PIN (PBKDF2,
    │                             #   persisted lockout), jailbreak, session
    ├── Database/                 # EncryptedTakeStore, SQLite3, per-item AES-256-GCM
    │                             #   sealed payload columns + NSFileProtection on the
    │                             #   Database/ dir (no plaintext FTS; in-memory search)
    ├── Sync/                     # Files-API cloud folder, BGTaskScheduler
    ├── Notifications/            # UNUserNotificationCenter reminders
    ├── UI/                       # Phase 6 product UI (SwiftUI)
    └── Resources/                # Info.plist, entitlements, wordlist, PrivacyInfo.xcprivacy
```

### The core and the app, and why they are split

`CatchlightCore` holds everything that has to behave identically on every platform Catchlight ever reaches (Roadmap §4), so the data model, the platform-agnostic JSON file format, and the whole crypto chain (CryptoKit HKDF plus AES-256-GCM). Every platform-specific dependency, and that means Keychain, NSFileProtection, SQLite3, `UNUserNotificationCenter`, `BGTaskScheduler` and the Files API, is injected through a protocol and implemented over in the `Catchlight/` app target.

That split is what makes "platform-agnostic from day one" a structural fact rather than a promise. The iOS app depends on the core and never the other way round, so the future Web, Android and Mac clients re-implement the thin app layer and nothing else.

## Building and testing

### Keep build output out of the source tree

Write build products to a local directory outside the repo. If your checkout lives on a cloud-synced folder this saves you the sync churn, and the path-length and locking trouble that comes with it.

```bash
BUILD_DIR="$HOME/CatchlightBuild"
swift build  --scratch-path "$BUILD_DIR/spm"
swift test   --scratch-path "$BUILD_DIR/spm"
xcodebuild … -derivedDataPath "$BUILD_DIR/DerivedData"
```

### The core, which builds with Command Line Tools alone

```bash
swift build            # builds CatchlightCore (pure Swift + CryptoKit)
swift run coreverify   # runs the runtime verification harness
```

`coreverify` exists because XCTest is not bundled with the Command Line Tools. It re-runs the same scenarios as the XCTest suite against a tiny assert harness, so the core can be proven green without a full Xcode. All the checks pass.

The harness prints its own count when it finishes, and this page does not repeat it, because a number written down here goes stale the day somebody adds a check. Which is exactly what happened.

### The full XCTest suite and the iOS app, which need full Xcode

You need **Xcode 26 or later**, and that has been true since 2026-08-15. The App Intents declare `supportedModes` behind `@available(iOS 26.0, *)` (D-202), and `IntentModes` is not in the iOS 18 SDK at all, so Xcode 16 cannot compile the app. Note what this does not change. The deployment floor is still iOS 18.0 (D-039), so the app still runs on iOS 18 and only builds against the iOS 26 SDK.

```bash
swift test                 # the canonical Tests/ suite, under a full Xcode toolchain
brew install xcodegen
xcodegen generate          # produces Catchlight.xcodeproj from project.yml
open Catchlight.xcodeproj  # set DEVELOPMENT_TEAM, then build/run on a device
```

## What still has to happen on real hardware before release

1. **Confirm database file protection on a real device.** The `Database/` directory carries `NSFileProtectionCompleteUntilFirstUserAuthentication`, and the db and its -wal and -shm sidecars inherit it. `FileProtectionTests` checks the attribute is set, but iOS only enforces the protection class on real hardware, so on the simulator it is observable and completely inert. This was verified on 2026-06-06 on an iPhone 17 Pro for the previous store, so it wants confirming again after the `EncryptedTakeStore` move.
2. **Verify the Secure-Enclave master-key path on a real device.** On SE hardware the master key is ECIES-wrapped under a permanent SE P-256 key, which is the 0x02 format prefix. The simulator only ever exercises the raw 0x01 path (2026-06-10 redesign in `Catchlight/Security/Keychain.swift`).
3. **Set `DEVELOPMENT_TEAM`** in `project.yml`, for the App Group and Keychain entitlements.

## The non-negotiables

- Zero knowledge, so no backend, no analytics, and nothing transmitted off the device anywhere.
- `kSecAttrSynchronizable: false` on every Keychain item (`Keychain.swift`, `PINService.swift`).
- Encryption is always on. Never optional, never toggleable.
- Offline-first, so everything works with no network at all. Sync is additive, and local-only is a real way to run it.
- The cloud folder holds platform-agnostic JSON envelopes and one plaintext metadata file, nothing else.
