//
//  coreverify — main.swift
//
//  A dependency-free runtime verification of CatchlightCore. It mirrors the
//  XCTest suite (Phase 5 brief §12) so the core can be proven GREEN on a machine
//  with only the Swift Command Line Tools (no Xcode, no XCTest). Run:
//
//      swift run coreverify
//
//  Exits non-zero if any check fails. This is a verification aid, not a substitute
//  for the canonical XCTest suite that runs under full Xcode / CI.
//

import Foundation
import CryptoKit
import CatchlightCore

// MARK: - Tiny harness

var passed = 0
var failed = 0
var currentSection = ""

func section(_ name: String) { currentSection = name; print("\n▸ \(name)") }

func check(_ label: String, _ condition: Bool) {
    if condition { passed += 1; print("  ✓ \(label)") }
    else { failed += 1; print("  ✗ FAIL: \(label)  [\(currentSection)]") }
}

func checkThrows(_ label: String, _ body: () throws -> Void) {
    do { try body(); failed += 1; print("  ✗ FAIL (expected throw): \(label)") }
    catch { passed += 1; print("  ✓ \(label)") }
}

func checkThrows<E: Error & Equatable>(_ label: String, _ expected: E, _ body: () throws -> Void) {
    do { try body(); failed += 1; print("  ✗ FAIL (expected throw): \(label)") }
    catch let e as E where e == expected { passed += 1; print("  ✓ \(label)") }
    catch { failed += 1; print("  ✗ FAIL (wrong error \(error)): \(label)") }
}

func checkNoThrow(_ label: String, _ body: () throws -> Void) {
    do { try body(); passed += 1; print("  ✓ \(label)") }
    catch { failed += 1; print("  ✗ FAIL (threw \(error)): \(label)") }
}

// MARK: - Local fixtures (mirror Tests/.../TestSupport.swift)

func syntheticWordlist() -> BIP39Wordlist { try! BIP39Wordlist(words: (0..<2048).map { "w\($0)" }) }

func richTake(id: UUID = UUID()) -> Take {
    Take(id: id,
         createdAt: ISO8601.date(from: "2026-05-01T09:00:00.000Z")!,
         modifiedAt: ISO8601.date(from: "2026-05-02T10:30:00.000Z")!,
         bodyText: "Buy film for the weekend shoot",
         isTask: true,
         timeReminder: TimeReminder(scheduledDate: ISO8601.date(from: "2026-05-03T15:00:00.000Z")!, notificationIdentifier: id.uuidString),
         checklistItems: [ChecklistItem(text: "Portra 400", isComplete: false)])
}

func mk() -> SymmetricKey { SymmetricKey(size: .bits256) }
func keys() -> KeyHierarchy { KeyHierarchy(masterKey: mk()) }
let salt = Data(repeating: 0x07, count: 16)
func engine(_ store: TakeStore, _ cloud: CloudFolder?, _ k: KeyHierarchy, now: @escaping () -> Date = Date.init) -> SyncEngine {
    SyncEngine(store: store, cloud: cloud, keys: k, argon2Salt: salt, now: now)
}

// MARK: - §12.1 Encryption layer

section("§12.1 Encryption layer")
do {
    let m = ["abandon","ability","able","about","above","absent","absorb","abstract","absurd","abuse","access","accident"]
    let k1 = MasterKeyDerivation.deriveRaw(from: m)
    let k2 = MasterKeyDerivation.deriveRaw(from: m)
    check("Master key deterministic for same mnemonic", k1 == k2 && k1.count == 32)
    let kOther = MasterKeyDerivation.deriveRaw(from: ["zone","zoo","zero","zebra","youth","yellow","year","wrong","world","word","wood","wolf"])
    check("Different mnemonics → different master keys", k1 != kOther)
    check("Mnemonic case normalised", MasterKeyDerivation.deriveRaw(from: m.map { $0.uppercased() }) == k1)

    let masterKey = mk()
    let h = KeyHierarchy(masterKey: masterKey)
    check("HKDF deterministic for same key+info",
          h.databaseKey().withUnsafeBytes { Data($0) } == KeyHierarchy(masterKey: masterKey).databaseKey().withUnsafeBytes { Data($0) })
    check("Different UUIDs → different per-item keys",
          h.itemKey(takeUUID: UUID()).withUnsafeBytes { Data($0) } != h.itemKey(takeUUID: UUID()).withUnsafeBytes { Data($0) })
    check("Key separation: db key ≠ manifest hmac key",
          h.databaseKey().withUnsafeBytes { Data($0) } != h.manifestHMACKey().withUnsafeBytes { Data($0) })

    let uuid = UUID()
    let pt = Data("the small light that makes everything feel alive".utf8)
    let c = try encryptTake(pt, masterKey: masterKey, takeUUID: uuid)
    check("encryptTake/decryptTake round-trip", try decryptTake(c, masterKey: masterKey, takeUUID: uuid) == pt)
    let c1 = try encryptTake(pt, masterKey: masterKey, takeUUID: uuid)
    let c2 = try encryptTake(pt, masterKey: masterKey, takeUUID: uuid)
    check("Fresh nonce per encryption → different ciphertext", c1 != c2)
    var tampered = c1; tampered[tampered.count - 1] ^= 0xFF
    checkThrows("Tampered ciphertext throws AEAD auth error", CryptoError.authenticationFailed) {
        _ = try decryptTake(tampered, masterKey: masterKey, takeUUID: uuid)
    }
    checkThrows("Wrong UUID fails to decrypt") { _ = try decryptTake(c1, masterKey: masterKey, takeUUID: UUID()) }

    let crypto = TakeCrypto(keys: KeyHierarchy(masterKey: masterKey))
    let take = richTake()
    check("TakeCrypto whole-Take payload round-trip", try crypto.open(try crypto.seal(take), takeUUID: take.id) == take)
} catch { print("  ✗ EXCEPTION in §12.1: \(error)"); failed += 1 }

// MARK: - §12.2 Data model

section("§12.2 Data model")
do {
    let take = richTake()
    check("Take round-trips through JSON with all fields", try PlatformJSON.decode(Take.self, from: try PlatformJSON.encode(take)) == take)
    // Use a millisecond-aligned date: the canonical wire format is ms-precision,
    // so a raw Date() would not be bit-exact after a round-trip (documented behaviour).
    let nowMs = ISO8601.date(from: ISO8601.string(from: Date()))!
    let empty = Take(createdAt: nowMs, modifiedAt: nowMs, bodyText: "")
    let decodedEmpty = try PlatformJSON.decode(Take.self, from: try PlatformJSON.encode(empty))
    check("Empty Take round-trips; arrays empty; note floor true",
          decodedEmpty == empty && decodedEmpty.checklistItems.isEmpty && decodedEmpty.attachments.isEmpty && decodedEmpty.isNote && decodedEmpty.locationReminder == nil)

    let json = String(data: try PlatformJSON.encode(take), encoding: .utf8)!
    check("ISO-8601 UTC dates in JSON (no Apple reference-date Double)",
          json.contains("2026-05-01T09:00:00.000Z") && json.contains("2026-05-02T10:30:00.000Z") && !json.contains("\"createdAt\":7"))

    let item = ChecklistItem(text: "x", isComplete: true)
    let ijson = String(data: try PlatformJSON.encode(item), encoding: .utf8)!
    check("ChecklistItem has only id/text/isComplete; no reminder/linkedTakeId",
          ijson.contains("\"id\"") && ijson.contains("\"text\"") && ijson.contains("\"isComplete\"") && !ijson.contains("reminder") && !ijson.contains("linkedTake"))

    check("locationReminder nil in v1.0", richTake().locationReminder == nil && Take(bodyText: "x").locationReminder == nil)

    var t = Take(bodyText: "x", isTask: true, isComplete: true); t.isTask = false; t.normaliseActivityFloor()
    check("Note is the floor (re-asserts; completion cleared)", t.isNote && !t.isComplete)

    check("CatchlightSequence round-trips (reserved-name workaround)",
          try PlatformJSON.decode(CatchlightSequence.self, from: try PlatformJSON.encode(CatchlightSequence(name: "Weekend", takeIds: [UUID(), UUID()]))).takeIds.count == 2)

    let canon = ISO8601.date(from: "2026-05-28T07:00:00.000Z")!
    check("Canonical date format + tolerant seconds-only parse",
          ISO8601.string(from: canon) == "2026-05-28T07:00:00.000Z" && ISO8601.date(from: "2026-05-28T07:00:00Z") != nil)
    check("Deterministic key ordering (reproducible bytes)", try PlatformJSON.encode(take) == PlatformJSON.encode(take))
} catch { print("  ✗ EXCEPTION in §12.2: \(error)"); failed += 1 }

// MARK: - BIP-39 algorithm

section("BIP-39 algorithm")
do {
    let bip = BIP39(wordlist: syntheticWordlist())
    check("generateMnemonic → 12 words", try bip.generateMnemonic().count == 12)
    let entropy = Data((0..<16).map { UInt8($0) })
    let m = try bip.mnemonic(fromEntropy: entropy)
    check("mnemonic ⇄ entropy round-trip + checksum valid", try bip.validate(mnemonic: m) == entropy)
    // Deterministic corruption: the last word's low 4 bits are the BIP-39 checksum
    // and its high 7 bits are entropy. Flip one checksum bit while keeping the
    // entropy prefix identical → guaranteed checksum mismatch (synthetic wordlist
    // is "w<index>", so the index is parseable).
    let lastIdx = Int(m.last!.dropFirst())!
    let corruptedIdx = (lastIdx & ~0xF) | ((lastIdx & 0xF) ^ 0x1)
    var bad = m; bad[bad.count - 1] = "w\(corruptedIdx)"
    checkThrows("invalid checksum rejected") { _ = try bip.validate(mnemonic: bad) }
    checkThrows("word not in wordlist rejected") { _ = try bip.validate(mnemonic: Array(repeating: "w0", count: 11) + ["nope"]) }
    checkThrows("wordlist must be 2048 unique") { _ = try BIP39Wordlist(words: ["a", "b"]) }
    var allValid = true
    for _ in 0..<25 { if (try? bip.validate(mnemonic: bip.generateMnemonic())) == nil { allValid = false } }
    check("25 random mnemonics all validate", allValid)
} catch { print("  ✗ EXCEPTION in BIP-39: \(error)"); failed += 1 }

// MARK: - §12.5 Second-device handshake

section("§12.5 Second-device handshake")
do {
    let masterKey = mk()
    let mkBytes = masterKey.withUnsafeBytes { Data($0) }
    let (req, newPriv) = DeviceHandshake.makeRequest(deviceIdentifier: "iPhone-15")
    let resp = try DeviceHandshake.makeResponse(to: req, masterKey: masterKey)
    check("Wrap + unwrap recovers master key", try DeviceHandshake.unwrapMasterKey(response: resp, ephemeralPrivate: newPriv) == mkBytes)

    let issued = Date()
    let (req2, priv2) = DeviceHandshake.makeRequest(deviceIdentifier: "iPad", now: issued)
    let resp2 = try DeviceHandshake.makeResponse(to: req2, masterKey: masterKey, now: issued)
    checkThrows(">15min request rejected", SyncError.handshakeExpired) {
        _ = try DeviceHandshake.unwrapMasterKey(response: resp2, ephemeralPrivate: priv2, now: issued.addingTimeInterval(16*60))
    }
    checkNoThrow("within expiry accepted") {
        _ = try DeviceHandshake.unwrapMasterKey(response: resp2, ephemeralPrivate: priv2, now: issued.addingTimeInterval(14*60))
    }
    checkThrows("attacker's private key cannot unwrap (OTV alone useless)", CryptoError.authenticationFailed) {
        _ = try DeviceHandshake.unwrapMasterKey(response: resp, ephemeralPrivate: Curve25519.KeyAgreement.PrivateKey())
    }
    let folder = InMemoryCloudFolder()
    let name = "catchlight-device-request-\(UUID().uuidString).json"
    try folder.write(Data(repeating: 0x41, count: 256), to: name)
    try folder.secureDelete(name)
    check("Handshake file overwritten then deleted", (try folder.read(name)) == nil && folder.secureDeleteOverwroteBytes[name] == 256)
} catch { print("  ✗ EXCEPTION in §12.5: \(error)"); failed += 1 }

// MARK: - §12.4 Sync engine

section("§12.4 Sync engine")
do {
    // Outbound writes envelopes + signed manifest + plaintext metadata.
    do {
        let k = keys(); let store = InMemoryTakeStore(); let cloud = InMemoryCloudFolder()
        let take = richTake(); try store.upsert(take)
        try engine(store, cloud, k).pushOutbound()
        let blobData = try cloud.read("\(take.id.uuidString).clk")
        let manifestData = try cloud.read(Manifest.fileName)
        let metaData = try cloud.read("catchlight-account-metadata.json")
        let blob = try CloudBlob.parse(blobData!)
        check("Outbound writes .clk envelope (JSON, v1, has ciphertext)", blob.uuid == take.id && blob.version == 1 && blob.ciphertext != nil)
        check("Outbound writes manifest + plaintext metadata", manifestData != nil && metaData != nil)
    }
    // Blob tampering quarantined.
    do {
        let k = keys(); let store = InMemoryTakeStore(); let cloud = InMemoryCloudFolder()
        let take = richTake(); try store.upsert(take)
        try engine(store, cloud, k).pushOutbound()
        var blob = try cloud.read("\(take.id.uuidString).clk")!; blob[blob.count-1] ^= 0xFF
        try cloud.write(blob, to: "\(take.id.uuidString).clk")
        let store2 = InMemoryTakeStore()
        let report = try engine(store2, cloud, k).pullInbound()
        let stored = try store2.take(id: take.id)
        check("Tampered blob quarantined, not applied, not stored",
              report.quarantined == [take.id] && report.applied.isEmpty && stored == nil)
    }
    // Manifest signature failure leaves local untouched.
    do {
        let k = keys(); let store = InMemoryTakeStore(); let cloud = InMemoryCloudFolder()
        try store.upsert(richTake()); try engine(store, cloud, k).pushOutbound()
        var manifest = try Manifest.parse(try cloud.read(Manifest.fileName)!)
        manifest.updated = "1999-01-01T00:00:00.000Z"
        try cloud.write(try manifest.serialise(), to: Manifest.fileName)
        let store2 = InMemoryTakeStore(); let existing = richTake(id: UUID()); try store2.upsert(existing)
        checkThrows("Manifest signature failure throws", SyncError.manifestSignatureInvalid) {
            _ = try engine(store2, cloud, k).pullInbound()
        }
        check("Local DB untouched on manifest failure", try store2.allTakes().map(\.id) == [existing.id])
    }
    // Wrong master key → manifest fails.
    do {
        let store = InMemoryTakeStore(); let cloud = InMemoryCloudFolder()
        try store.upsert(richTake()); try engine(store, cloud, keys()).pushOutbound()
        checkThrows("Wrong master key → manifest invalid", SyncError.manifestSignatureInvalid) {
            _ = try engine(InMemoryTakeStore(), cloud, keys()).pullInbound()
        }
    }
    // New take from another device.
    do {
        let k = keys(); let cloud = InMemoryCloudFolder()
        let storeA = InMemoryTakeStore(); let take = richTake(); try storeA.upsert(take)
        try engine(storeA, cloud, k).pushOutbound()
        let storeB = InMemoryTakeStore()
        let report = try engine(storeB, cloud, k).pullInbound()
        let got = try storeB.take(id: take.id)
        check("Inbound new Take from another device applied", report.applied == [take.id] && got == take)
    }
    // Deletion from another device.
    do {
        let k = keys(); let cloud = InMemoryCloudFolder()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let storeA = InMemoryTakeStore(); var take = richTake(); take.modifiedAt = t0; try storeA.upsert(take)
        try engine(storeA, cloud, k, now: { t0.addingTimeInterval(1) }).pushOutbound()
        let storeB = InMemoryTakeStore()
        try engine(storeB, cloud, k, now: { t0.addingTimeInterval(2) }).pullInbound()
        storeB.setLastSyncDate(t0.addingTimeInterval(5))
        try storeA.delete(id: take.id)
        try engine(storeA, cloud, k, now: { t0.addingTimeInterval(10) }).pushOutbound()
        let report = try engine(storeB, cloud, k, now: { t0.addingTimeInterval(11) }).pullInbound()
        let afterDelete = try storeB.take(id: take.id)
        check("Inbound deletion from another device applied locally", report.deletedLocally == [take.id] && afterDelete == nil)
    }
    // Conflict detection + surfaced end-to-end without overwrite.
    do {
        let lastSync = Date(timeIntervalSince1970: 1_700_000_000)
        var base = richTake(); base.modifiedAt = lastSync
        var l = base; l.bodyText = "local"; l.modifiedAt = lastSync.addingTimeInterval(100)
        var r = base; r.bodyText = "remote"; r.modifiedAt = lastSync.addingTimeInterval(200)
        if case .conflict = ConflictResolver.decide(local: l, remote: r, lastSync: lastSync) { check("Two offline edits detected as conflict", true) }
        else { check("Two offline edits detected as conflict", false) }

        let k = keys(); let cloud = InMemoryCloudFolder(); let t0 = lastSync
        let remoteStore = InMemoryTakeStore(); var remote = richTake(); remote.bodyText = "remote version"; remote.modifiedAt = t0.addingTimeInterval(300)
        try remoteStore.upsert(remote); try engine(remoteStore, cloud, k, now: { t0.addingTimeInterval(301) }).pushOutbound()
        let local = InMemoryTakeStore(); var le = richTake(id: remote.id); le.bodyText = "local version"; le.modifiedAt = t0.addingTimeInterval(250)
        try local.upsert(le); local.setLastSyncDate(t0)
        let report = try engine(local, cloud, k, now: { t0.addingTimeInterval(400) }).pullInbound()
        let localBody = try local.take(id: remote.id)?.bodyText
        check("Conflict surfaced, local NOT overwritten", report.conflicts.count == 1 && localBody == "local version")
    }
    // Local-only mode.
    do {
        let store = InMemoryTakeStore(); let e = engine(store, nil, keys())
        try store.upsert(richTake())
        check("Local-only mode flagged", e.isLocalOnly)
        checkThrows("Local-only push throws noCloudFolderConfigured", SyncError.noCloudFolderConfigured) { _ = try e.pushOutbound() }
        checkThrows("Local-only pull throws noCloudFolderConfigured", SyncError.noCloudFolderConfigured) { _ = try e.pullInbound() }
    }
    // Enable sync later → uploads all.
    do {
        let k = keys(); let store = InMemoryTakeStore()
        for _ in 0..<3 { try store.upsert(richTake(id: UUID())) }
        let cloud = InMemoryCloudFolder()
        let report = try engine(store, cloud, k).pushOutbound()
        let clkCount = try cloud.clkFiles().count
        check("Enable sync later uploads all existing Takes", report.uploaded.count == 3 && clkCount == 3)
    }
    // Idempotency.
    do {
        let k = keys(); let store = InMemoryTakeStore(); try store.upsert(richTake())
        let cloud = InMemoryCloudFolder(); let e = engine(store, cloud, k)
        try e.pushOutbound(); try e.pushOutbound()
        let signer = ManifestSigner(keys: k)
        let verifies = try signer.verify(Manifest.parse(try cloud.read(Manifest.fileName)!))
        let blobCount = try cloud.clkFiles().count
        check("Outbound idempotent (manifest still verifies; 1 blob)", verifies && blobCount == 1)
    }
} catch { print("  ✗ EXCEPTION in §12.4: \(error)"); failed += 1 }

// MARK: - Seed Takes (UX §12)

section("Seed Takes (UX §12)")
do {
    let seeds = SeedTakes.make()
    check("Five seed Takes created", seeds.count == 5)
    check("All flagged isSeeded", seeds.allSatisfy { $0.isSeeded })
    check("Quadrants: Note, Task, Reminder, Obie present",
          seeds[0].isNote && seeds[1].isTask && seeds[2].timeReminder != nil && seeds[3].isObie)
    check("Exactly one Obie among seeds", seeds.filter { $0.isObie }.count == 1)
    check("Seeds chronological (createdAt ascending)", zip(seeds, seeds.dropFirst()).allSatisfy { $0.createdAt <= $1.createdAt })
    // Seed Takes round-trip like any other Take (they are standard Takes).
    let rt = try seeds.allSatisfy { try PlatformJSON.decode(Take.self, from: PlatformJSON.encode($0)) == $0 }
    check("Seed Takes round-trip through JSON", rt)
}

// MARK: - Summary

print("\n────────────────────────────────────────")
print("coreverify: \(passed) passed, \(failed) failed")
print("────────────────────────────────────────")
if failed > 0 { exit(1) }
