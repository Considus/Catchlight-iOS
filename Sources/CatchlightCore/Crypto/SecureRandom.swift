//
//  SecureRandom.swift
//  CatchlightCore
//
//  Cryptographically secure randomness. The Encryption Architecture (§3, §5, §6)
//  mandates `SecRandomCopyBytes` as the entropy source for BIP-39 mnemonic
//  generation and for the second-device one-time value (OTV). On Apple platforms
//  that is exactly what is used. On non-Apple platforms (a future Linux test host)
//  it falls back to `SystemRandomNumberGenerator`, which is also a CSPRNG.
//

import Foundation
#if canImport(Security)
import Security
#endif

public enum SecureRandom {
    /// Fill a raw buffer with secure random bytes. Returns 0 on success.
    @discardableResult
    public static func fill(_ buffer: UnsafeMutableRawBufferPointer) -> Int32 {
        guard let base = buffer.baseAddress, buffer.count > 0 else { return 0 }
        #if canImport(Security)
        return SecRandomCopyBytes(kSecRandomDefault, buffer.count, base)
        #else
        var rng = SystemRandomNumberGenerator()
        let bytes = buffer.bindMemory(to: UInt8.self)
        for i in 0..<bytes.count { bytes[i] = UInt8.random(in: 0...255, using: &rng) }
        return 0
        #endif
    }

    /// Return `count` secure random bytes.
    ///
    /// HARD-FAILS (traps) if the CSPRNG reports an error. Previously the status
    /// was discarded and callers received all-zero bytes — for consumers like
    /// BIP-39 entropy generation that failure mode is a deterministic, guessable
    /// mnemonic. `SecRandomCopyBytes` failure is effectively unheard of in
    /// practice; if it ever happens, crashing is strictly safer than silently
    /// generating zero-entropy key material.
    public static func bytes(_ count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { fill($0) }
        precondition(status == 0, "SecureRandom: CSPRNG failure (status \(status)) — refusing to return weak entropy")
        return data
    }
}
