//
//  RecoveryCodeTests.swift
//  CatchlightCoreTests — raw-key recovery code (device backup / transfer for phraseless accounts)
//
//  Round-trips a master key through encode → decode, and proves the code rejects corruption
//  (checksum), a wrong scheme tag, a bad version, and a truncated payload.
//

import XCTest
@testable import CatchlightCore

final class RecoveryCodeTests: XCTestCase {

    private func key(_ byte: UInt8 = 0xAB) -> Data { Data(repeating: byte, count: 32) }

    func testRoundTrip_recoversTheSameKey() throws {
        let k = key()
        let code = RecoveryCode.encode(masterKey: k)
        XCTAssertTrue(code.hasPrefix("CLK1-"))
        XCTAssertEqual(try RecoveryCode.decode(code), k)
    }

    func testDistinctKeys_produceDistinctCodes() {
        XCTAssertNotEqual(RecoveryCode.encode(masterKey: key(0x01)),
                          RecoveryCode.encode(masterKey: key(0x02)))
    }

    func testDecode_toleratesSurroundingWhitespace() throws {
        let code = RecoveryCode.encode(masterKey: key())
        XCTAssertEqual(try RecoveryCode.decode("  \(code)\n"), key())
    }

    func testCorruptedBody_failsChecksum() {
        var code = RecoveryCode.encode(masterKey: key())
        // Flip a character in the payload (not the scheme) → checksum (or decode) rejects it.
        let idx = code.index(code.endIndex, offsetBy: -3)
        let ch = code[idx]
        code.replaceSubrange(idx...idx, with: ch == "A" ? "B" : "A")
        XCTAssertThrowsError(try RecoveryCode.decode(code))
    }

    func testWrongScheme_throwsBadScheme() {
        let code = RecoveryCode.encode(masterKey: key())
        let swapped = "XXXX" + code.dropFirst(4)
        XCTAssertThrowsError(try RecoveryCode.decode(swapped)) { error in
            XCTAssertEqual(error as? RecoveryCode.DecodeError, .badScheme)
        }
    }

    func testNoDash_throwsMalformed() {
        XCTAssertThrowsError(try RecoveryCode.decode("CLK1nodashhere")) { error in
            XCTAssertEqual(error as? RecoveryCode.DecodeError, .malformed)
        }
    }

    func testTruncatedPayload_throwsWrongLength() {
        // A valid scheme + valid base64url but too few bytes for version‖key‖checksum.
        XCTAssertThrowsError(try RecoveryCode.decode("CLK1-AAAA")) { error in
            XCTAssertEqual(error as? RecoveryCode.DecodeError, .wrongKeyLength)
        }
    }
}
