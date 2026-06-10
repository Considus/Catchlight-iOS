# Catchlight — App Codebase

Privacy-first iOS productivity app. Zero-knowledge, end-to-end encrypted, offline-first.
This directory began as the **Phase 5** deliverable (project setup, data model,
encryption layer, local storage, sync engine, notifications, search, background tasks)
and now also contains the complete **Phase 6 product UI** (Dailies, Dial, Sequences,
Search, Settings, onboarding, paywall — all 6.x tasks ✅ as of 2026-06-09).

Companion design documents: `../Design & Develop "Catchlight" productivity app/Technical_Architecture_v1.0.md`
and `Encryption_Architecture_v1.0.md` (internal version v1.1, revised 2026-06-10).

## Layout

```
CatchlightApp/
├── Package.swift                 # SwiftPM: CatchlightCore + coreverify
├── project.yml                   # XcodeGen spec for the iOS app (run: xcodegen generate)
├── Sources/
│   ├── CatchlightCore/           # PLATFORM-AGNOSTIC core — pure Swift + CryptoKit
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
└── Catchlight/                   # iOS APP TARGET — platform-specific layers
    ├── App/                      # entry point, composition root, scene lifecycle
    ├── Security/                 # Keychain (SE-wrapped master key), PIN (PBKDF2,
    │                             #   persisted lockout), jailbreak, session
    ├── Database/                 # EncryptedTakeStore — SQLite3, per-item AES-256-GCM
    │                             #   sealed payload columns + NSFileProtection on the
    │                             #   Database/ dir (no plaintext FTS; in-memory search)
    ├── Sync/                     # Files-API cloud folder, BGTaskScheduler
    ├── Notifications/            # UNUserNotificationCenter reminders
    ├── UI/                       # Phase 6 product UI (SwiftUI)
    └── Resources/                # Info.plist, entitlements, wordlist, PrivacyInfo.xcprivacy
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

### Build artifacts — keep them OFF the ProtonDrive-synced tree

This repo lives inside a ProtonDrive-synced folder. Build products must not be
written here (sync churn, path-length and locking issues). All build artifacts go
to local disk at `/Users/stradd3rs/Claude/Catchlight-Build`:

```bash
swift build  --scratch-path /Users/stradd3rs/Claude/Catchlight-Build/spm
swift test   --scratch-path /Users/stradd3rs/Claude/Catchlight-Build/spm
xcodebuild … -derivedDataPath /Users/stradd3rs/Claude/Catchlight-Build/DerivedData
```

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

1. **Confirm database file protection on a real device** — the `Database/` directory
   carries `NSFileProtectionCompleteUntilFirstUserAuthentication` (inherited by the
   db and its -wal/-shm sidecars). `FileProtectionTests` verifies the attribute is
   set, but iOS enforces the protection class only on real hardware (it is observable
   but inert on the simulator). Verified 2026-06-06 on iPhone 17 Pro for the previous
   store; re-confirm after the `EncryptedTakeStore` move.
2. **Verify the Secure-Enclave master-key path on a real device** — on SE hardware
   the master key is ECIES-wrapped under a permanent SE P-256 key (format prefix
   0x02); the simulator exercises only the raw 0x01 path (2026-06-10 redesign in
   `Catchlight/Security/Keychain.swift`).
3. **Set `DEVELOPMENT_TEAM`** in `project.yml` for App Group / Keychain entitlements.

## Non-negotiables enforced here

- Zero knowledge — no backend, no analytics, no off-device transmission anywhere.
- `kSecAttrSynchronizable: false` on every Keychain item (`Keychain.swift`, `PINService.swift`).
- Encryption always on — never optional, never toggleable.
- Offline-first — full functionality with no network; sync is additive (local-only mode).
- Cloud folder holds only platform-agnostic JSON envelopes + one plaintext metadata file.
