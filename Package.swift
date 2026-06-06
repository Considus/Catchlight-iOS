// swift-tools-version: 5.9
//
// Catchlight — CatchlightCore
//
// The platform-agnostic heart of Catchlight. Pure Swift + Apple CryptoKit only.
// No UIKit, no SwiftUI, no SQLCipher, no third-party crypto inside this package —
// every platform-specific dependency (storage, cloud folder) is injected through
// a protocol (see Storage/ and Sync/). Master-key derivation is HKDF-SHA-256 via
// CryptoKit (see Crypto/MasterKeyDerivation.swift). This is what makes the
// Roadmap §4 cross-platform
// constraint real rather than aspirational: the exact same source compiles for
// iOS, macOS, and (with swift-crypto) Linux, and the file format it produces is
// readable by a future WebCrypto/WASM or Android/Tink client.
//
// It builds and its full test suite runs on macOS with the Command Line Tools
// toolchain (Swift 5.9+). CryptoKit is a system framework on macOS, so HKDF,
// ChaCha20-Poly1305, HMAC-SHA-256 and X25519 are all exercised for real here.
//
import PackageDescription

let package = Package(
    name: "CatchlightCore",
    platforms: [
        .macOS(.v13),   // for local test execution; iOS target is configured in the app project
        .iOS(.v17)
    ],
    products: [
        .library(name: "CatchlightCore", targets: ["CatchlightCore"]),
        .executable(name: "coreverify", targets: ["coreverify"])
    ],
    targets: [
        .target(
            name: "CatchlightCore",
            path: "Sources/CatchlightCore"
        ),
        // XCTest-based suite — the canonical Phase 5 §12 tests. Runs under a full
        // Xcode toolchain / CI (`swift test` or the Xcode test action).
        .testTarget(
            name: "CatchlightCoreTests",
            dependencies: ["CatchlightCore"],
            path: "Tests/CatchlightCoreTests"
        ),
        // A dependency-free executable that re-runs the same scenarios with a tiny
        // assert harness. Exists so the core can be verified GREEN on a
        // Command-Line-Tools-only machine (no Xcode, no XCTest). `swift run coreverify`.
        .executableTarget(
            name: "coreverify",
            dependencies: ["CatchlightCore"],
            path: "Sources/coreverify"
        )
    ]
)
