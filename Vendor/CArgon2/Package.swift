// swift-tools-version:5.9
//
//  CArgon2 — LOCAL SPM WRAPPER around the upstream phc-winner-argon2 reference
//  implementation (vendored under Sources/CArgon2, cloned from
//  https://github.com/P-H-C/phc-winner-argon2).
//
//  WHY THIS EXISTS: the upstream repo is a plain C library with no Package.swift, so
//  Swift Package Manager (and therefore Xcode/xcodebuild) cannot resolve it as a
//  remote package — `project.yml` previously pointed at the bare repo and dependency
//  resolution failed before any code compiled. This thin wrapper SPM-ifies the REAL
//  reference sources (the portable `ref.c` path, not the SSE `opt.c`), so `import
//  CArgon2` exposes the genuine `argon2id_hash_raw` and LibArgon2.swift's
//  `#if canImport(CArgon2)` branch compiles and runs.
//
//  BEFORE RELEASE (see README "Before release" + Encryption Architecture §16):
//    • Pin the vendored sources to a reviewed commit and record it.
//    • Run LibArgon2.verifyAgainstKnownAnswerVector() against the official KAT.
//  This wrapper does NOT alter the algorithm — it is the upstream reference code.
//

import PackageDescription

let package = Package(
    name: "CArgon2",
    products: [
        .library(name: "CArgon2", targets: ["CArgon2"]),
    ],
    targets: [
        .target(
            name: "CArgon2",
            path: "Sources/CArgon2",
            // Explicit list: portable reference path only; CLI/bench/genkat mains and
            // the SSE-specific opt.c are intentionally excluded.
            sources: [
                "argon2.c",
                "core.c",
                "encoding.c",
                "ref.c",
                "thread.c",
                "blake2/blake2b.c",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("include"),
                .headerSearchPath("blake2"),
                // ARGON2_NO_THREADS: compute the parallel lanes sequentially in one
                // thread. Output is BYTE-IDENTICAL — `p` still shapes the memory/lane
                // layout; threading only parallelises that computation, it never
                // changes the result. Needed because modern Clang rejects the
                // reference thread.c's POSIX pthread calls as implicit declarations on
                // the iOS toolchain, and correctness/cross-platform reproducibility
                // (Encryption Architecture §16) matters far more than one-time KDF
                // wall-clock at onboarding/unlock.
                .define("ARGON2_NO_THREADS"),
            ]
        ),
    ]
)
