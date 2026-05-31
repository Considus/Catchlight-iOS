//
//  TestSupport.swift
//  CatchlightCoreTests
//
//  Test-only doubles. NONE of these are production code.
//

import Foundation
import CryptoKit
@testable import CatchlightCore

/// A DETERMINISTIC, INSECURE stand-in for Argon2id, used ONLY to exercise the
/// consumers of the KDF (key hierarchy, recovery flow) in unit tests without the
/// real libargon2 C dependency. It satisfies the `Argon2idDeriving` contract — same
/// (password, salt, params) → same output, different salt → different output,
/// correct output length — which is all the downstream code relies on. It is NOT
/// Argon2 and MUST NEVER be used in the app. Real Argon2id correctness is verified
/// against the official KAT in the iOS target (LibArgon2 + Encryption Architecture
/// §16 "libargon2 version audit").
struct InsecureMockArgon2idKDF: Argon2idDeriving {
    func deriveKey(passwordBytes: [UInt8], saltBytes: [UInt8], parameters: Argon2Parameters) throws -> Data {
        // HKDF over (password) with salt+params folded into info. Deterministic,
        // salt-sensitive, parameter-sensitive, fixed length. Explicitly not Argon2.
        let ikm = SymmetricKey(data: Data(passwordBytes))
        var info = Data("MOCK-ARGON2-NOT-REAL".utf8)
        info.append(contentsOf: saltBytes)
        info.append(contentsOf: withUnsafeBytes(of: parameters.memoryKiB.littleEndian) { Data($0) })
        info.append(contentsOf: withUnsafeBytes(of: parameters.iterations.littleEndian) { Data($0) })
        info.append(contentsOf: withUnsafeBytes(of: parameters.parallelism.littleEndian) { Data($0) })
        let salt = Data(saltBytes)
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: salt,
            info: info,
            outputByteCount: parameters.outputLength
        )
        return key.withUnsafeBytes { Data($0) }
    }
}

enum TestFixtures {
    /// A deterministic synthetic 2048-word "wordlist" to exercise the BIP-39
    /// ALGORITHM (entropy ⇄ checksum ⇄ indices). NOT the official English wordlist;
    /// it only needs 2048 unique tokens.
    static func syntheticWordlist() -> BIP39Wordlist {
        let words = (0..<2048).map { "w\($0)" }
        return try! BIP39Wordlist(words: words)
    }

    /// A representative Take exercising every populated v1.0 field.
    static func richTake(id: UUID = UUID()) -> Take {
        Take(
            id: id,
            createdAt: ISO8601.date(from: "2026-05-01T09:00:00.000Z")!,
            modifiedAt: ISO8601.date(from: "2026-05-02T10:30:00.000Z")!,
            bodyText: "Buy film for the weekend shoot / café at 3",
            contentType: "plain",
            isNote: true,
            isTask: true,
            isComplete: false,
            isObie: false,
            timeReminder: TimeReminder(
                scheduledDate: ISO8601.date(from: "2026-05-03T15:00:00.000Z")!,
                isDelivered: false,
                notificationIdentifier: id.uuidString
            ),
            locationReminder: nil,
            checklistItems: [
                ChecklistItem(text: "Kodak Portra 400", isComplete: false),
                ChecklistItem(text: "Lens cloth", isComplete: true)
            ],
            attachments: [],
            sequenceIds: [],
            isSeeded: false
        )
    }
}
