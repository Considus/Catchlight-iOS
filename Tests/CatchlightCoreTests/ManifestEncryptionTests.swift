//
//  ManifestEncryptionTests.swift
//  CatchlightCoreTests — manifest v3 / blob v2 (owner 2026-08-11, D-196)
//
//  The point of the change is NEGATIVE — certain things must no longer appear in the cloud
//  folder — so most of these assert absence in the written bytes. A round-trip test alone
//  would pass just as happily with the metadata still sitting there in the clear.
//

import XCTest
import CryptoKit
@testable import CatchlightCore

final class ManifestEncryptionTests: XCTestCase {

    private let keys = KeyHierarchy(masterKey: SymmetricKey(size: .bits256))
    private var signer: ManifestSigner { ManifestSigner(keys: keys) }
    private var key: SymmetricKey { keys.manifestEncryptionKey() }

    private let takeID = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
    private let deletedID = UUID(uuidString: "660E8400-E29B-41D4-A716-446655440111")!

    private func sampleManifest() -> Manifest {
        Manifest(
            updated: "2026-08-11T07:00:00.000Z",
            schemaVersion: 1,
            takes: [ManifestEntry(uuid: takeID,
                                  modified: "2026-08-11T06:59:00.000Z",
                                  hmac: "abc123")],
            tombstones: [ManifestTombstone(uuid: deletedID,
                                           deletedAt: "2026-08-10T12:00:00.000Z")]
        )
    }

    // MARK: - What must no longer be readable

    func testWrittenManifest_leaksNoTakeUUIDs() throws {
        let bytes = try signer.sign(try sampleManifest().sealed(with: key)).serialise()
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(text.contains(takeID.uuidString),
                       "a Take uuid must not be readable in the cloud folder")
        XCTAssertFalse(text.localizedCaseInsensitiveContains(takeID.uuidString),
                       "nor in any case variant")
    }

    func testWrittenManifest_leaksNoModificationTimes() throws {
        let bytes = try signer.sign(try sampleManifest().sealed(with: key)).serialise()
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(text.contains("2026-08-11T06:59:00.000Z"),
                       "per-Take modification times were the main leak — they must be sealed")
    }

    /// The deletion log is the most revealing part: what the user threw away, and when.
    func testWrittenManifest_leaksNoDeletionRecord() throws {
        let bytes = try signer.sign(try sampleManifest().sealed(with: key)).serialise()
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(text.contains(deletedID.uuidString))
        XCTAssertFalse(text.contains("2026-08-10T12:00:00.000Z"))
        XCTAssertFalse(text.contains("tombstone"))
    }

    func testWrittenBlob_leaksNoUUIDOrTimestamp() throws {
        let take = Take(id: takeID, blocks: [.textLine("private")])
        let blob = CloudBlob(take: take, sealed: Data([1, 2, 3, 4]))
        let text = String(decoding: try blob.serialise(), as: UTF8.self)
        XCTAssertFalse(text.contains(takeID.uuidString),
                       "the uuid is already the filename — repeating it inside adds nothing")
        XCTAssertFalse(text.contains("modified"),
                       "the envelope's modification time had no readers and must not be written")
    }

    /// Guards the deliberate belt-and-braces in `CloudBlob.encode`: the v2 shape is written
    /// even when the in-memory value still carries a uuid, so correctness never depends on a
    /// caller remembering to nil it out.
    func testWrittenBlob_omitsUUIDEvenWhenSetInMemory() throws {
        let blob = CloudBlob(uuid: takeID, modified: "2026-08-11T00:00:00.000Z",
                             encryptedPayload: "AAAA")
        let text = String(decoding: try blob.serialise(), as: UTF8.self)
        XCTAssertFalse(text.contains(takeID.uuidString))
        XCTAssertFalse(text.contains("2026-08-11T00:00:00.000Z"))
    }

    // MARK: - What must still work

    func testManifest_roundTripsThroughTheEnvelope() throws {
        let original = sampleManifest()
        let envelope = try signer.sign(try original.sealed(with: key))
        let parsed = try ManifestEnvelope.parse(try envelope.serialise())
        XCTAssertTrue(try signer.verify(parsed))

        let reopened = try Manifest.opening(parsed, with: key)
        XCTAssertEqual(reopened.takes, original.takes)
        XCTAssertEqual(reopened.tombstones, original.tombstones)
        XCTAssertEqual(reopened.updated, original.updated)
        XCTAssertEqual(reopened.schemaVersion, original.schemaVersion)
        XCTAssertEqual(reopened.version, Manifest.currentVersion)
    }

    /// The version MUST be readable without the key, or the fail-closed version gate can
    /// never run on an encrypted manifest.
    func testVersion_isReadableWithoutTheKey() throws {
        let bytes = try signer.sign(try sampleManifest().sealed(with: key)).serialise()
        XCTAssertEqual(ManifestEnvelope.peekVersion(bytes), 3)
    }

    func testTamperedEnvelope_failsVerification() throws {
        var envelope = try signer.sign(try sampleManifest().sealed(with: key))
        envelope.encryptedBody = String(envelope.encryptedBody.dropLast()) + "A"
        XCTAssertFalse(try signer.verify(envelope))
    }

    func testWrongKey_failsToOpen() throws {
        let envelope = try signer.sign(try sampleManifest().sealed(with: key))
        let otherKey = KeyHierarchy(masterKey: SymmetricKey(size: .bits256)).manifestEncryptionKey()
        XCTAssertThrowsError(try Manifest.opening(envelope, with: otherKey)) { error in
            // Lands on the pull path's existing fail-closed branch, not a raw crypto error.
            XCTAssertEqual(error as? SyncError, .manifestSignatureInvalid)
        }
    }

    /// The encryption key must not be the HMAC key — separate HKDF info strings.
    func testManifestEncryptionKey_differsFromHMACKey() {
        let encryption = keys.manifestEncryptionKey().withUnsafeBytes { Data($0) }
        let hmac = keys.manifestHMACKey().withUnsafeBytes { Data($0) }
        XCTAssertNotEqual(encryption, hmac)
    }

    // MARK: - Backward compatibility

    /// A folder written by an earlier build must keep syncing rather than becoming
    /// unreadable; the next push rewrites it as v3.
    func testLegacyPlaintextManifest_stillParsesAndVerifies() throws {
        var legacy = sampleManifest()
        legacy.version = 2
        let signed = try signer.sign(legacy)
        let bytes = try signed.serialise()

        XCTAssertEqual(ManifestEnvelope.peekVersion(bytes), 2)
        let parsed = try Manifest.parse(bytes)
        XCTAssertTrue(try signer.verify(parsed))
        XCTAssertEqual(parsed.takes, legacy.takes)
    }

    func testLegacyV1Blob_stillParses() throws {
        let json = """
        {"version":1,"uuid":"\(takeID.uuidString)","modified":"2026-08-01T00:00:00.000Z","encryptedPayload":"AAAA"}
        """
        let blob = try CloudBlob.parse(Data(json.utf8))
        XCTAssertEqual(blob.version, 1)
        XCTAssertEqual(blob.uuid, takeID)
        XCTAssertEqual(blob.encryptedPayload, "AAAA")
    }

    func testFutureVersions_areStillRefused() {
        XCTAssertFalse(Manifest.supportedVersions.contains(4))
        XCTAssertFalse(CloudBlob.supportedVersions.contains(3))
    }
}
