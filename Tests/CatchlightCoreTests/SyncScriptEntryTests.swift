//
//  SyncScriptEntryTests.swift
//  CatchlightCoreTests
//
//  D-315: the manifest marks each entry as a Take or a Script, and the phone holds Takes
//  only. Scripts are written on the desktop and iPad (D-265); the phone must never fetch
//  one, never drop one from the manifest, and never change an entry's kind. When another
//  device turns a Take the phone holds into a Script, the phone lets it go WITHOUT a
//  tombstone, because nothing was deleted (D-313, and owner 2026-10-01: no conversion on
//  the phone itself).
//
//  Tests cross the public seams only: ManifestEntry's encoding, and SyncEngine's
//  pullInbound / pushOutbound against an in-memory store and folder.
//

import XCTest
import CryptoKit
@testable import CatchlightCore

final class SyncScriptEntryTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeKeys() -> KeyHierarchy { KeyHierarchy(masterKey: SymmetricKey(size: .bits256)) }

    private func engine(_ store: TakeStore, _ cloud: CloudFolder, _ keys: KeyHierarchy,
                        at: Date, device: UUID = UUID()) -> SyncEngine {
        TestFixtures.engine(store: store, cloud: cloud, keys: keys, deviceId: device, now: { at })
    }

    /// Put `take` in the folder as another device would, then re-mark its entry with `kind`
    /// and the given `modified` stamp — the shape a desktop conversion leaves behind.
    private func plant(_ take: Take, kind: String?, modified: Date? = nil,
                       in cloud: CloudFolder, keys: KeyHierarchy, at: Date) throws {
        let elsewhere = InMemoryTakeStore()
        try elsewhere.upsert(take)
        try engine(elsewhere, cloud, keys, at: at).pushOutbound()
        try remark(take.id, kind: kind, modified: modified, in: cloud, keys: keys)
    }

    private func remark(_ id: UUID, kind: String?, modified: Date? = nil,
                        in cloud: CloudFolder, keys: KeyHierarchy) throws {
        var manifest = try Manifest.readEncrypted(from: cloud, keys: keys)
        manifest.takes = manifest.takes.map { e in
            guard e.uuid == id else { return e }
            return ManifestEntry(uuid: e.uuid,
                                 modified: modified.map(ISO8601.string(from:)) ?? e.modified,
                                 hmac: e.hmac, kind: kind)
        }
        try Manifest.writeEncrypted(manifest, to: cloud, keys: keys)
    }

    private func entry(_ id: UUID, in cloud: CloudFolder, keys: KeyHierarchy) throws -> ManifestEntry? {
        try Manifest.readEncrypted(from: cloud, keys: keys).takes.first { $0.uuid == id }
    }

    // MARK: - Encoding

    /// A Take entry encodes exactly as it did before `kind` existed: no `kind` key at all.
    /// That is what keeps every existing folder's entries, and so their signed bytes, unchanged.
    func testTakeEntry_encodesWithoutKindKey() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let bytes = try PlatformJSON.encode(ManifestEntry(uuid: id, modified: "2026-05-28T07:00:00.000Z", hmac: "ab"))
        XCTAssertEqual(String(data: bytes, encoding: .utf8),
                       #"{"hmac":"ab","modified":"2026-05-28T07:00:00.000Z","uuid":"00000000-0000-0000-0000-000000000001"}"#)
    }

    /// "take" is not a second spelling of a Take: it normalises to the absence of a kind.
    func testExplicitTakeKind_normalisesToNoKind() throws {
        let e = ManifestEntry(uuid: UUID(), modified: "2026-05-28T07:00:00.000Z", hmac: "ab", kind: "take")
        XCTAssertNil(e.kind)
        XCTAssertTrue(e.isTake)
    }

    func testScriptEntry_roundTripsItsKind() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let bytes = try PlatformJSON.encode(ManifestEntry(uuid: id, modified: "2026-05-28T07:00:00.000Z",
                                                          hmac: "ab", kind: ManifestEntry.Kind.script))
        XCTAssertEqual(String(data: bytes, encoding: .utf8),
                       #"{"hmac":"ab","kind":"script","modified":"2026-05-28T07:00:00.000Z","uuid":"00000000-0000-0000-0000-000000000002"}"#)
        let back = try PlatformJSON.decode(ManifestEntry.self, from: bytes)
        XCTAssertEqual(back.kind, "script")
        XCTAssertFalse(back.isTake)
    }

    /// A kind from a newer client is neither rejected nor shown: it is kept verbatim.
    func testUnknownKind_isNotATake_andSurvivesReEncoding() throws {
        let json = #"{"hmac":"ab","kind":"storyboard","modified":"2026-05-28T07:00:00.000Z","uuid":"00000000-0000-0000-0000-000000000003"}"#
        let e = try PlatformJSON.decode(ManifestEntry.self, from: Data(json.utf8))
        XCTAssertFalse(e.isTake)
        XCTAssertEqual(String(data: try PlatformJSON.encode(e), encoding: .utf8), json)
    }

    // MARK: - The phone never fetches a Script

    /// The planted blob is garbage. Had the phone read it, it would land in `quarantined` or
    /// `unverified`; landing in neither proves it was never fetched.
    func testPull_scriptEntry_isNeverFetchedOrApplied() throws {
        let k = makeKeys(), cloud = InMemoryCloudFolder(), phone = InMemoryTakeStore()
        let script = TestFixtures.richTake()
        try plant(script, kind: ManifestEntry.Kind.script, in: cloud, keys: k, at: t0)
        try cloud.write(Data("not a blob".utf8), to: "\(script.id.uuidString).clk")

        let report = try engine(phone, cloud, k, at: t0.addingTimeInterval(10)).pullInbound()

        XCTAssertNil(try phone.take(id: script.id))
        XCTAssertEqual(report.applied, [])
        XCTAssertEqual(report.quarantined, [])
        XCTAssertEqual(report.unverified.map(\.id), [])
        XCTAssertEqual(report.skipped, [])
        XCTAssertEqual(report.conflicts.count, 0)
    }

    // MARK: - ...and never drops or rewrites one

    func testPush_carriesScriptEntryForwardUntouched() throws {
        let k = makeKeys(), cloud = InMemoryCloudFolder(), phone = InMemoryTakeStore()
        let script = TestFixtures.richTake()
        try plant(script, kind: ManifestEntry.Kind.script, in: cloud, keys: k, at: t0)
        let before = try XCTUnwrap(entry(script.id, in: cloud, keys: k))
        let blobBefore = try cloud.read("\(script.id.uuidString).clk")

        var mine = TestFixtures.richTake()
        mine.modifiedAt = t0.addingTimeInterval(5)
        try phone.upsert(mine)
        try engine(phone, cloud, k, at: t0.addingTimeInterval(10)).sync()

        XCTAssertEqual(try entry(script.id, in: cloud, keys: k), before)
        XCTAssertEqual(try cloud.read("\(script.id.uuidString).clk"), blobBefore)
        XCTAssertNotNil(try entry(mine.id, in: cloud, keys: k), "the phone's own Take still syncs")
    }

    /// A tombstone for a Script the phone never held changes nothing here.
    func testPull_tombstoneForAScriptNeverHeld_isANoOp() throws {
        let k = makeKeys(), cloud = InMemoryCloudFolder(), phone = InMemoryTakeStore()
        var mine = TestFixtures.richTake()
        mine.modifiedAt = t0
        try phone.upsert(mine)
        let gone = UUID()
        try Manifest.writeEncrypted(
            Manifest(updated: ISO8601.string(from: t0), takes: [],
                     tombstones: [ManifestTombstone(uuid: gone, deletedAt: ISO8601.string(from: t0))]),
            to: cloud, keys: k)

        let report = try engine(phone, cloud, k, at: t0.addingTimeInterval(10)).pullInbound()

        XCTAssertEqual(report.deletedLocally, [])
        XCTAssertEqual(try phone.allTakes().map(\.id), [mine.id])
        XCTAssertEqual(try phone.tombstones().map(\.id), [])
    }

    // MARK: - A Take turned into a Script elsewhere leaves the phone

    func testPull_takeTurnedIntoScript_leavesThePhoneWithoutATombstone() throws {
        let k = makeKeys(), cloud = InMemoryCloudFolder(), phone = InMemoryTakeStore()
        var take = TestFixtures.richTake()
        take.modifiedAt = t0
        try phone.upsert(take)
        try engine(phone, cloud, k, at: t0.addingTimeInterval(1)).sync()       // phone and folder agree
        try remark(take.id, kind: ManifestEntry.Kind.script, modified: t0.addingTimeInterval(50),
                   in: cloud, keys: k)                                           // the Mac converts it

        let report = try engine(phone, cloud, k, at: t0.addingTimeInterval(100)).sync()

        XCTAssertNil(try phone.take(id: take.id), "a Script is not held on the phone")
        XCTAssertEqual(report.deletedLocally, [take.id], "reported so its reminders are cancelled")
        XCTAssertEqual(try phone.tombstones().map(\.id), [], "nothing was deleted")
        let manifest = try Manifest.readEncrypted(from: cloud, keys: k)
        XCTAssertEqual(manifest.tombstones.map(\.uuid), [], "no deletion may reach the other devices")
        XCTAssertEqual(try entry(take.id, in: cloud, keys: k)?.kind, ManifestEntry.Kind.script)
        XCTAssertNotNil(try cloud.read("\(take.id.uuidString).clk"), "the Script's content stays in the folder")
    }

    /// The phone edited the Take after its last sync, before it learnt of the conversion. The
    /// edit must not be thrown away: it is kept, uploaded AS A SCRIPT, and only then let go.
    func testPull_takeTurnedIntoScript_withAnUnsyncedPhoneEdit_keepsTheEditAndSendsItAsAScript() throws {
        let k = makeKeys(), cloud = InMemoryCloudFolder(), phone = InMemoryTakeStore()
        var take = TestFixtures.richTake()
        take.primaryText = "before"
        take.modifiedAt = t0
        try phone.upsert(take)
        try engine(phone, cloud, k, at: t0.addingTimeInterval(1)).sync()
        try remark(take.id, kind: ManifestEntry.Kind.script, in: cloud, keys: k)   // converted, content as it was

        var edited = take
        edited.primaryText = "after"
        edited.modifiedAt = t0.addingTimeInterval(20)
        try phone.upsert(edited)

        let first = try engine(phone, cloud, k, at: t0.addingTimeInterval(30)).sync()
        XCTAssertEqual(first.deletedLocally, [])
        XCTAssertEqual(try phone.take(id: take.id)?.primaryText, "after", "the unsynced edit survives the pull")
        let sent = try XCTUnwrap(try entry(take.id, in: cloud, keys: k))
        XCTAssertEqual(sent.kind, ManifestEntry.Kind.script, "the phone never turns it back into a Take")
        XCTAssertEqual(sent.modified, ISO8601.string(from: edited.modifiedAt))
        let blob = try CloudBlob.parse(try XCTUnwrap(try cloud.read("\(take.id.uuidString).clk")))
        XCTAssertEqual(try TakeCrypto(keys: k).open(blob.ciphertext!, takeUUID: take.id).primaryText, "after")

        let second = try engine(phone, cloud, k, at: t0.addingTimeInterval(40)).sync()
        XCTAssertEqual(second.deletedLocally, [take.id])
        XCTAssertNil(try phone.take(id: take.id))
        XCTAssertEqual(try Manifest.readEncrypted(from: cloud, keys: k).tombstones, [])
    }

    // MARK: - A Script turned back into a Take arrives on the phone

    func testPull_scriptTurnedBackIntoATake_arrivesOnThePhone() throws {
        let k = makeKeys(), cloud = InMemoryCloudFolder(), phone = InMemoryTakeStore()
        var script = TestFixtures.richTake()
        script.modifiedAt = t0
        try plant(script, kind: ManifestEntry.Kind.script, in: cloud, keys: k, at: t0)
        _ = try engine(phone, cloud, k, at: t0.addingTimeInterval(1)).sync()
        XCTAssertNil(try phone.take(id: script.id))

        try remark(script.id, kind: nil, modified: t0.addingTimeInterval(50), in: cloud, keys: k)
        let report = try engine(phone, cloud, k, at: t0.addingTimeInterval(100)).pullInbound()

        XCTAssertEqual(report.applied, [script.id])
        XCTAssertEqual(try phone.take(id: script.id)?.primaryText, script.primaryText)
    }

    // MARK: - An edit landing mid-pull is never lost

    /// The user's edit commits after the pull has decided the Take is unchanged but before it is
    /// let go — the window a separate read-then-delete leaves open. The store's single
    /// check-and-remove sees the edit, so the Take stays and is sent as the Script.
    func testPull_editLandingJustBeforeTheRelease_isKept() throws {
        let k = makeKeys(), cloud = InMemoryCloudFolder(), inner = InMemoryTakeStore()
        var take = TestFixtures.richTake()
        take.modifiedAt = t0
        try inner.upsert(take)
        try engine(inner, cloud, k, at: t0.addingTimeInterval(1)).sync()
        try remark(take.id, kind: ManifestEntry.Kind.script, in: cloud, keys: k)

        var edited = take
        edited.primaryText = "typed mid-pull"
        edited.modifiedAt = t0.addingTimeInterval(20)
        let phone = EditBeforeReleaseStore(wrapping: inner, edit: edited)
        let report = try engine(phone, cloud, k, at: t0.addingTimeInterval(30)).pullInbound()

        XCTAssertTrue(phone.editFired)
        XCTAssertEqual(report.deletedLocally, [])
        XCTAssertEqual(try inner.take(id: take.id)?.primaryText, "typed mid-pull")
        XCTAssertEqual(try inner.tombstones().map(\.id), [])
    }
}

/// Commits a user edit at the start of `release`, i.e. after the pull has already read the
/// Take as unchanged. Everything else forwards to the wrapped store.
private final class EditBeforeReleaseStore: TakeStore {
    private let wrapped: InMemoryTakeStore
    private let edit: Take
    private(set) var editFired = false

    init(wrapping wrapped: InMemoryTakeStore, edit: Take) {
        self.wrapped = wrapped
        self.edit = edit
    }

    func release(id: UUID, ifNotModifiedAfter cutoff: Date) throws -> Bool {
        if id == edit.id, !editFired {
            editFired = true
            try wrapped.upsert(edit)   // the user's edit lands here
        }
        return try wrapped.release(id: id, ifNotModifiedAfter: cutoff)
    }

    func upsert(_ take: Take) throws { try wrapped.upsert(take) }
    func delete(id: UUID) throws { try wrapped.delete(id: id) }
    func take(id: UUID) throws -> Take? { try wrapped.take(id: id) }
    func allTakes() throws -> [Take] { try wrapped.allTakes() }
    func takesModified(since date: Date?) throws -> [Take] { try wrapped.takesModified(since: date) }
    func search(_ query: String) throws -> [Take] { try wrapped.search(query) }
    func upsert(_ sequence: CatchlightSequence) throws { try wrapped.upsert(sequence) }
    func sequence(id: UUID) throws -> CatchlightSequence? { try wrapped.sequence(id: id) }
    func allSequences() throws -> [CatchlightSequence] { try wrapped.allSequences() }
    func deleteSequence(id: UUID) throws { try wrapped.deleteSequence(id: id) }
    func currentObie() throws -> Take? { try wrapped.currentObie() }
    func setObie(id: UUID, replaceExisting: Bool) throws { try wrapped.setObie(id: id, replaceExisting: replaceExisting) }
    func lastSyncDate() -> Date? { wrapped.lastSyncDate() }
    func setLastSyncDate(_ date: Date) { wrapped.setLastSyncDate(date) }
    func tombstones() throws -> [Tombstone] { try wrapped.tombstones() }
    func purgeTombstones(ids: [UUID]) throws { try wrapped.purgeTombstones(ids: ids) }
    func applyRemote(_ take: Take) throws -> Bool { try wrapped.applyRemote(take) }

}
