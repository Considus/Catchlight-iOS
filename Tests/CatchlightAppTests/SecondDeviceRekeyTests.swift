//
//  SecondDeviceRekeyTests.swift
//  CatchlightAppTests — R8: the Second-device re-key never leaves this device holding a
//  Privacy phrase and a master key from different accounts.
//
//  The two Keychain writes are injected (`AppModel.AccountSecrets`), so each can be made to
//  fail without the real Keychain. Only the failure paths run here: success wipes the
//  library files and the cloud-folder bookmark in the App Group container.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight
@testable import CatchlightCore

@MainActor
final class SecondDeviceRekeyTests: XCTestCase {

    /// The Keychain as the re-key sees it: one phrase and one master key, each write able to fail.
    private final class FakeSecrets {
        var phrase: [String]
        var key: Data
        var failPhrase = false
        var failKey = false
        /// The key the unlocked session holds in memory, which a failed Keychain write leaves alone.
        let sessionKey: Data
        init(phrase: [String], key: Data) { self.phrase = phrase; self.key = key; self.sessionKey = key }

        var accountSecrets: AppModel.AccountSecrets {
            AppModel.AccountSecrets(
                currentMasterKey: { [unowned self] in sessionKey },
                storePhrase: { [unowned self] in
                    if failPhrase { throw KeychainError.storeFailed(errSecInteractionNotAllowed) }
                    phrase = $0
                },
                storeMasterKey: { [unowned self] in
                    if failKey { throw KeychainError.storeFailed(errSecInteractionNotAllowed) }
                    key = $0
                })
        }
    }

    private let oldPhrase = Array(repeating: "zoo", count: 11) + ["wrong"]
    private let oldKey = Data(repeating: 7, count: 32)
    // The BIP-39 test phrase: valid, so validation passes and the writes are reached.
    private let newWords = Array(repeating: "abandon", count: 11) + ["about"]

    private func makeUnlocked(holding take: Take) throws -> AppModel {
        let store = InMemoryTakeStore()
        try store.upsert(take)
        return AppModel(needsOnboarding: false,
                        initialStore: store,
                        session: SessionController(),
                        makeStoreFromKeys: { _ in InMemoryTakeStore() },
                        unlockKeys: { KeyHierarchy(masterKeyBytes: Data(repeating: 7, count: 32)) },
                        lockState: .unlocked,
                        subscription: SubscriptionManager())
    }

    func testKeyWriteFails_phraseAndKeyStayThisAccounts_andNothingIsWiped() throws {
        let take = Take(blocks: [.textLine("Still here")])
        let app = try makeUnlocked(holding: take)
        let secrets = FakeSecrets(phrase: oldPhrase, key: oldKey)
        secrets.failKey = true
        app.accountSecrets = secrets.accountSecrets

        XCTAssertNotNil(app.replaceAccountForSecondDevice(newWords))

        XCTAssertEqual(secrets.phrase, oldPhrase, "the phrase no longer matches this device's key")
        XCTAssertEqual(secrets.key, oldKey)
        XCTAssertEqual(try app.dailiesVM.store.allTakes().map(\.id), [take.id])
        XCTAssertEqual(app.lockState, .unlocked)
    }

    func testPhraseWriteFails_phraseAndKeyStayThisAccounts_andNothingIsWiped() throws {
        let take = Take(blocks: [.textLine("Still here")])
        let app = try makeUnlocked(holding: take)
        let secrets = FakeSecrets(phrase: oldPhrase, key: oldKey)
        secrets.failPhrase = true
        app.accountSecrets = secrets.accountSecrets

        XCTAssertNotNil(app.replaceAccountForSecondDevice(newWords))

        XCTAssertEqual(secrets.phrase, oldPhrase)
        XCTAssertEqual(secrets.key, oldKey, "the key no longer matches this device's phrase")
        XCTAssertEqual(try app.dailiesVM.store.allTakes().map(\.id), [take.id])
        XCTAssertEqual(app.lockState, .unlocked)
    }

    /// The phrase write and the rollback both fail: the stored key is the new account's while
    /// the library is under the old one. The app stays unlocked on the old session key, so a
    /// second attempt reaches both writes again with the old key still in hand.
    func testPhraseAndRollbackFail_appStaysUsable_andATryAgainWritesBoth() throws {
        let take = Take(blocks: [.textLine("Still here")])
        let app = try makeUnlocked(holding: take)
        let secrets = FakeSecrets(phrase: oldPhrase, key: oldKey)
        var keyWrites: [Data] = []
        secrets.failPhrase = true
        let base = secrets.accountSecrets
        app.accountSecrets = AppModel.AccountSecrets(
            currentMasterKey: base.currentMasterKey,
            storePhrase: base.storePhrase,
            storeMasterKey: { data in
                keyWrites.append(data)
                if keyWrites.count == 2 { throw KeychainError.storeFailed(errSecInteractionNotAllowed) }
                try base.storeMasterKey(data)
            })

        XCTAssertNotNil(app.replaceAccountForSecondDevice(newWords))
        XCTAssertNotEqual(secrets.key, oldKey, "the rollback failed, so the new key is what's stored")
        XCTAssertEqual(try app.dailiesVM.store.allTakes().map(\.id), [take.id], "the timeline still reads")
        XCTAssertEqual(app.lockState, .unlocked)

        // Try again, with the phrase write still failing so the test stops before the wipe:
        // the attempt reaches the writes and puts the old session key back this time.
        XCTAssertNotNil(app.replaceAccountForSecondDevice(newWords))
        XCTAssertEqual(keyWrites.count, 4)
        XCTAssertEqual(secrets.key, oldKey)
    }
}
#endif
