//
//  LibArgon2.swift
//  Catchlight (iOS app target)
//
//  The production Argon2id binding. Conforms to `CatchlightCore.Argon2idDeriving`
//  by calling the unmodified upstream `libargon2` reference implementation
//  (`argon2id_hash_raw`). This is the single most important cross-platform
//  primitive: the Web (argon2-browser / WASM), Android (Tink / argon2 via JNI), and
//  macOS clients must all be able to re-derive the identical master key from the
//  same mnemonic + salt + parameters. Using the reference library — not a CryptoKit
//  substitute and not a hand-rolled re-implementation — is what guarantees that.
//
//  INTEGRATION (see README and project.yml):
//    The C library is added as a dependency exposing the `argon2.h` API. Either:
//      • SPM: a vendored `CArgon2` system/clang target wrapping the pinned upstream
//        source (commit recorded in README), or
//      • CocoaPods: pod 'Argon2' pinned to a reviewed version.
//    Once linked, `import CArgon2` (or the module name configured) makes
//    `argon2id_hash_raw` available. The `#if canImport(CArgon2)` guard lets the rest
//    of the app build while the dependency is being wired, and forces a clear
//    fatalError rather than a silent wrong-KDF if it is ever missing in a release.
//
//  VERIFICATION (Encryption Architecture §16 "libargon2 version audit confirmation"):
//    `verifyAgainstKnownAnswerVector()` MUST be run on a networked build machine
//    against the official Argon2id KAT before release, to confirm the binding
//    produces standard-compliant output byte-for-byte. This is the one correctness
//    check that cannot be performed in an offline environment.
//

import Foundation
import CatchlightCore

#if canImport(CArgon2)
import CArgon2
#endif

public struct LibArgon2: Argon2idDeriving {

    public init() {}

    public func deriveKey(passwordBytes: [UInt8], saltBytes: [UInt8], parameters: Argon2Parameters) throws -> Data {
        #if canImport(CArgon2)
        var output = [UInt8](repeating: 0, count: parameters.outputLength)
        let result = passwordBytes.withUnsafeBufferPointer { pwd in
            saltBytes.withUnsafeBufferPointer { salt in
                argon2id_hash_raw(
                    parameters.iterations,          // t_cost
                    parameters.memoryKiB,           // m_cost (KiB)
                    parameters.parallelism,         // parallelism
                    pwd.baseAddress, pwd.count,
                    salt.baseAddress, salt.count,
                    &output, output.count
                )
            }
        }
        guard result == ARGON2_OK.rawValue else {
            throw CryptoError.kdfFailed("argon2id_hash_raw returned \(result)")
        }
        let data = Data(output)
        // Zero the intermediate buffer immediately (Encryption Architecture §12.1).
        output.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) }
        return data
        #else
        // The C library is not linked. NEVER substitute a different KDF — that would
        // silently break cross-platform key derivation. Fail loudly instead.
        throw CryptoError.kdfFailed("libargon2 (CArgon2 module) is not linked — see LibArgon2.swift integration notes")
        #endif
    }

    /// Official Argon2id known-answer test. Run before release to confirm
    /// byte-for-byte standard compliance of the linked library. Paste the canonical
    /// vector from RFC 9106 / the reference repo's `kat-argon2id.log` here on a
    /// networked machine and assert equality. Left as an explicit, must-complete
    /// step rather than a fabricated value (the official bytes are not reproducible
    /// offline).
    public func verifyAgainstKnownAnswerVector() -> Bool {
        // TODO(pre-release, Encryption Architecture §16): populate with the official
        // Argon2id v0x13 KAT and assert `deriveKey(...) == expected`.
        return false
    }
}
