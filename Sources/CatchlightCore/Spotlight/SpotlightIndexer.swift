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

// MARK: - Exposure level (user setting — Settings › Security, D-110)

/// How much of a Take iOS may index for system search. Escalating:
///   `.none`      — nothing is indexed (default).
///   `.type`      — the activity-type label only ("Note" / "Task" / "Reminder").
///   `.firstLine` — the type PLUS the first line of the Take's text.
///   `.all`       — the type PLUS the Take's full text.
/// Anything beyond `.type` copies DECRYPTED Take text into the on-device OS index,
/// where iOS search and Siri can read it. It never leaves the device or reaches
/// Considus (end-to-end encryption is untouched), but it does leave Catchlight's
/// encrypted store. The default is `.none` — the privacy-preserving choice.
public enum SpotlightExposure: String, CaseIterable, Identifiable, Sendable {
    case none, type, firstLine, all
    public var id: String { rawValue }
}

// MARK: - Protocol

/// Indirection point so the app can be unit-tested without touching the real
/// `CSSearchableIndex.default()`. The production wiring uses
/// `CoreSpotlightIndexer`; tests inject `RecordingSpotlightIndexer`.
public protocol SpotlightIndexing: AnyObject, Sendable {
    /// The current exposure level. Set from the user's Settings choice; every
    /// subsequent `index(_:)` honours it, so callers never pass it per-Take.
    var exposure: SpotlightExposure { get set }
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

    /// The first non-empty line of the Take's text — used by the `.firstLine` level.
    public static func firstLine(for take: Take) -> String {
        take.plainText
            .split(whereSeparator: \.isNewline)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            .map(String.init) ?? ""
    }

    /// The text placed in `contentDescription` for a given exposure. `nil` at
    /// `.none`/`.type` — the privacy-preserving levels index NO body content.
    public static func contentDescription(for take: Take, exposure: SpotlightExposure) -> String? {
        switch exposure {
        case .none, .type:
            return nil
        case .firstLine:
            let line = firstLine(for: take)
            return line.isEmpty ? nil : line
        case .all:
            let text = take.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }

    #if canImport(CoreSpotlight)
    /// Build the CSSearchableItem for a Take at the given exposure. Returns `nil`
    /// for `.none` (nothing to index). Privacy contract enforced here:
    ///   • `title`/`displayName` are ALWAYS the activity-type label, never the body.
    ///   • `contentDescription` carries body text ONLY at `.firstLine`/`.all`, per
    ///     the explicit user setting; it stays nil at `.none`/`.type`.
    public static func makeItem(for take: Take, exposure: SpotlightExposure) -> CSSearchableItem? {
        guard exposure != .none else { return nil }
        let attributes: CSSearchableItemAttributeSet
        if #available(iOS 14.0, macOS 11.0, *) {
            attributes = CSSearchableItemAttributeSet(contentType: UTType.item)
        } else {
            attributes = CSSearchableItemAttributeSet(itemContentType: "public.item")
        }
        let label = title(for: take)
        attributes.title = label
        attributes.displayName = label
        // Body content is indexed ONLY when the user opts past `.type`; it stays
        // nil at the private levels (`contentDescription(for:exposure:)`).
        attributes.contentDescription = contentDescription(for: take, exposure: exposure)

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

    /// Privacy-first default: index nothing until the user opts in via Settings.
    public var exposure: SpotlightExposure = .none

    public init(index: CSSearchableIndex = .default()) {
        self.index = index
    }

    public func index(_ take: Take) {
        // At `.none` there's nothing to add; the setting-change path deindexes
        // any items left over from a higher level, so this is a clean no-op.
        guard let item = SpotlightAttributes.makeItem(for: take, exposure: exposure) else { return }
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
    public var exposure: SpotlightExposure = .none
    public init() {}
    public func index(_ take: Take) {}
    public func deindex(takeID: UUID) {}
    public func deindexAll() {}
}
