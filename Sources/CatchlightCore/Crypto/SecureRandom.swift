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
    public static func bytes(_ count: Int) -> Data {
        var data = Data(count: count)
        data.withUnsafeMutableBytes { _ = fill($0) }
        return data
    }
}
