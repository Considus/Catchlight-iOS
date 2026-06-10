//
//  SpotlightIndexer.swift
//  CatchlightCore — Task 6.19
//
//  Spotlight indexing for Takes. Decisions doc §1 is binding:
//
//    INDEX:   the activity type label only ("Note" / "Task" / "Reminder") and
//             the Take UUID for deep-link routing.
//    NEVER:   the encrypted body, the privacy phrase, any key material, or
//             anything derived from them.
//
//  These guarantees are enforced by `SpotlightAttributes.makeItem(for:)` — it
//  is the ONLY path that builds a CSSearchableItem in the app, and it ignores
//  every Take field except `id` and the activity-type computation. The tests
//  cross-check this by asserting the absence of body text in the resulting
//  attribute set.
//
//  Cross-platform: CoreSpotlight is available on iOS 9+ and macOS 10.13+, both
//  within this package's minimum platforms, so the indexer lives in core and
//  is callable from the iOS app target without an extra glue layer.
//

import Foundation
#if canImport(CoreSpotlight)
import CoreSpotlight
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

// MARK: - Constants

public enum SpotlightConstants {
    /// Domain identifier for every Catchlight Spotlight item. Used by
    /// `deleteSearchableItems(withDomainIdentifiers:)` for the deindex-all
    /// path so we never accidentally touch another app's items.
    public static let domainIdentifier = "com.considus.catchlight"

    /// Type string declared in `NSUserActivityTypes` (Info.plist). Deep-link
    /// routing from a Spotlight tap arrives as an `NSUserActivity` of type
    /// `CSSearchableItemActionType` whose userInfo carries the item's
    /// `uniqueIdentifier` (the Take UUID) — see `CatchlightApp.onContinueUserActivity`.
    /// (An earlier comment here claimed this string was set as
    /// `relatedUniqueIdentifier` on the CSSearchableItem; it never was — that
    /// property links an item to a separately-donated NSUserActivity, which
    /// this app does not use.)
    public static let userActivityType = "com.considus.catchlight.viewTake"

    /// Key for the Take UUID inside `NSUserActivity.userInfo`. Deep-link
    /// handlers read this; nothing else is permitted to live in userInfo.
    public static let userInfoTakeIDKey = "takeID"
}

// MARK: - Protocol

/// Indirection point so the app can be unit-tested without touching the real
/// `CSSearchableIndex.default()`. The production wiring uses
/// `CoreSpotlightIndexer`; tests inject `RecordingSpotlightIndexer`.
public protocol SpotlightIndexing: AnyObject, Sendable {
    func index(_ take: Take)
    func deindex(takeID: UUID)
    func deindexAll()
}

// MARK: - Pure attribute construction (testable without CSSearchableIndex)

public enum SpotlightAttributes {

    /// The activity-type label that's safe to expose to the OS index. Mirrors
    /// `TakeExporter.heading(for:)`'s precedence (Reminder > Task > Note) so
    /// the Spotlight surface stays consistent with the export surface.
    public static func title(for take: Take) -> String {
        if take.timeReminder != nil { return "Reminder" }
        if take.isTask { return "Task" }
        return "Note"
    }

    /// The userInfo dictionary attached to the user activity. The Take UUID
    /// is the only thing in here by design — it's the deep-link payload.
    public static func userInfo(for take: Take) -> [String: Any] {
        [SpotlightConstants.userInfoTakeIDKey: take.id.uuidString]
    }

    #if canImport(CoreSpotlight)
    /// Build the CSSearchableItem for a Take. Privacy contract enforced here:
    ///   • `title` is the activity-type label, never the body.
    ///   • No content description, no keywords, no thumbnail.
    ///   • `displayName` is also the activity-type label, since iOS may fall
    ///     back to it when `title` is unset on certain surfaces.
    public static func makeItem(for take: Take) -> CSSearchableItem {
        let attributes: CSSearchableItemAttributeSet
        if #available(iOS 14.0, macOS 11.0, *) {
            attributes = CSSearchableItemAttributeSet(contentType: UTType.item)
        } else {
            attributes = CSSearchableItemAttributeSet(itemContentType: "public.item")
        }
        let label = title(for: take)
        attributes.title = label
        attributes.displayName = label
        // contentDescription is left nil — it's the documented field where the
        // body would belong if we ever indexed it. Leaving it nil is the
        // load-bearing privacy invariant; the corresponding test asserts this.
        attributes.contentDescription = nil

        let item = CSSearchableItem(
            uniqueIdentifier: take.id.uuidString,
            domainIdentifier: SpotlightConstants.domainIdentifier,
            attributeSet: attributes
        )
        // CoreSpotlight items default-expire after ~30 days, after which old
        // Takes silently vanish from Spotlight until re-indexed. A Take should
        // stay findable for as long as it exists — deindexing on delete is the
        // explicit removal path.
        item.expirationDate = .distantFuture
        return item
    }
    #endif
}

// MARK: - CoreSpotlight-backed implementation

#if canImport(CoreSpotlight)
/// Production indexer. Calls go through `CSSearchableIndex.default()` and are
/// fire-and-forget — failures are swallowed because Spotlight is a nice-to-have
/// surface, not a correctness path. The store and the UI never observe its
/// state.
public final class CoreSpotlightIndexer: SpotlightIndexing, @unchecked Sendable {

    private let index: CSSearchableIndex

    public init(index: CSSearchableIndex = .default()) {
        self.index = index
    }

    public func index(_ take: Take) {
        let item = SpotlightAttributes.makeItem(for: take)
        index.indexSearchableItems([item]) { _ in /* fire-and-forget */ }
    }

    public func deindex(takeID: UUID) {
        index.deleteSearchableItems(withIdentifiers: [takeID.uuidString]) { _ in }
    }

    public func deindexAll() {
        index.deleteSearchableItems(withDomainIdentifiers: [SpotlightConstants.domainIdentifier]) { _ in }
    }
}
#endif

// MARK: - No-op for previews / tests / Linux

/// Inert indexer for SwiftUI previews, the `--uitesting` launch path, and any
/// caller that doesn't want Spotlight side effects. Also the only available
/// implementation on platforms without CoreSpotlight.
public final class NoopSpotlightIndexer: SpotlightIndexing, @unchecked Sendable {
    public init() {}
    public func index(_ take: Take) {}
    public func deindex(takeID: UUID) {}
    public func deindexAll() {}
}
