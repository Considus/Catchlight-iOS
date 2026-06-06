# Catchlight — Phase 5 Technical Architecture (code)

Privacy-first iOS productivity app. Zero-knowledge, end-to-end encrypted, offline-first.
This directory is the **Phase 5** deliverable: project setup, data model, encryption
layer, local storage, sync engine, notifications, search, and background tasks.
**No product UI** — that is Phase 6 (see `Phase5_Claude_Code_Brief.md` §14).

The companion design document is `../Technical_Architecture_v1.0.md`.

## Layout

```
CatchlightApp/
├── Package.swift                 # SwiftPM: CatchlightCore + coreverify
├── project.yml                   # XcodeGen spec for the iOS app (run: xcodegen generate)
├── Sources/
│   ├── CatchlightCore/           # PLATFORM-AGNOSTIC core — pure Swift + CryptoKit
│   │   ├── Model/                # Take, Sequence, reminders, attachments, seed Takes
│   │   ├── Serialization/        # ISO-8601 + platform-agnostic JSON codec
│   │   ├── Crypto/               # Argon2id protocol, key hierarchy, Take crypto,
│   │   │                         #   manifest HMAC, X25519 handshake, BIP-39, RNG
│   │   ├── Sync/                 # cloud blob, manifest, sync engine, conflicts, folder
│   │   └── Storage/              # TakeStore protocol + in-memory impl
│   └── coreverify/               # dependency-free runtime verifier (runs under CLT)
├── Tests/CatchlightCoreTests/    # canonical XCTest suite (Phase 5 brief §12)
└── Catchlight/                   # iOS APP TARGET — platform-specific layers
    ├── App/                      # entry point, composition root, scene lifecycle
    ├── Security/                 # Keychain, PIN (PBKDF2), jailbreak, session
    ├── Database/                 # SQLite3 + NSFileProtection TakeStore (FTS5)
    ├── Sync/                     # Files-API cloud folder, BGTaskScheduler
    ├── Notifications/            # UNUserNotificationCenter reminders
    └── Resources/                # Info.plist, entitlements, wordlist resource
```

### The core / app split (and why)

`CatchlightCore` contains everything that must run identically on every future
platform (Roadmap §4): the data model, the platform-agnostic JSON file format, and
the full crypto chain (CryptoKit HKDF + AES-256-GCM). Every platform-specific
dependency — Keychain, NSFileProtection, SQLite3, `UNUserNotificationCenter`,
`BGTaskScheduler`, the Files API — is injected through a protocol and implemented in
the `Catchlight/` app target. This is what makes "platform-agnostic from day one" a
structural fact rather than a promise: the iOS app depends on the core, never the
reverse, and the future Web/Android/Mac clients re-implement only the thin app layer.

## Building & testing

### Core (works on this machine — Command Line Tools only)

```bash
swift build            # builds CatchlightCore (pure Swift + CryptoKit)
swift run coreverify   # runs the runtime verification harness — 52 checks
```

`coreverify` exists because XCTest is not bundled with the Command Line Tools. It
re-runs the same scenarios as the XCTest suite with a tiny assert harness so the
core can be proven green without full Xcode. **Current status: 52/52 passing.**

### Full XCTest suite + iOS app (requires full Xcode)

```bash
swift test                 # the canonical Tests/ suite, under a full Xcode toolchain
brew install xcodegen
xcodegen generate          # produces Catchlight.xcodeproj from project.yml
open Catchlight.xcodeproj  # set DEVELOPMENT_TEAM, then build/run on a device
```

## Before release — required external steps

1. **Confirm database file protection on a real device** — the database file is
   tagged with `NSFileProtectionCompleteUntilFirstUserAuthentication`. `FileProtectionTests`
   verifies the attribute is set, but iOS enforces the protection class only on real
   hardware (it is observable but inert on the simulator). Before release, run the
   app on a passcode-protected device, lock it once after first unlock, and confirm
   that the database file remains accessible to `BGAppRefreshTask` while remaining
   inaccessible across reboots until the user enters their passcode.
2. **Set `DEVELOPMENT_TEAM`** in `project.yml` for App Group / Keychain entitlements.

## Non-negotiables enforced here

- Zero knowledge — no backend, no analytics, no off-device transmission anywhere.
- `kSecAttrSynchronizable: false` on every Keychain item (`Keychain.swift`, `PINService.swift`).
- Encryption always on — never optional, never toggleable.
- Offline-first — full functionality with no network; sync is additive (local-only mode).
- Cloud folder holds only platform-agnostic JSON envelopes + one plaintext metadata file.
