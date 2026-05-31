//
//  Take.swift
//  CatchlightCore
//
//  The Take is the fundamental unit of Catchlight. Every item the user creates is
//  a Take. A Take is a *container, not a category* (UX Session Decisions §1): any
//  combination of Note / Task / Reminder / Obie is valid simultaneously, and Note
//  is the floor — it re-asserts if every other type is removed.
//
//  This struct is the plaintext representation. It is what gets encrypted (the
//  whole payload, per Encryption Architecture §10.5) and what the SQLCipher
//  database holds in the clear. The Take's `id` is the ONLY field that is never
//  encrypted: it is the HKDF `info` input for the per-item key and must be known
//  before decryption.
//
//  Forward-compatibility fields (Strategic Roadmap §4) are present now even though
//  unused in v1.0, so that adding the v1.1/Horizon-2 features never requires a
//  breaking data-model migration.
//

import Foundation

public struct Take: Identifiable, Codable, Equatable, Sendable {
    /// Primary key. Used as the HKDF `info` parameter for the per-item key.
    /// Never changes for the life of the Take. Not encrypted.
    public let id: UUID

    public var createdAt: Date
    public var modifiedAt: Date

    // MARK: - Content

    /// The Take's text content.
    public var bodyText: String

    /// `"plain"` in v1.0. `"markdown"` is added when inline formatting ships (v1.1).
    /// Roadmap §4 — present now to gate Markdown cleanly without a migration.
    public var contentType: String

    // MARK: - Activity types (any combination is valid; Note is the floor)

    /// Always `true`. Note re-asserts automatically if all other activity types are
    /// removed (UX Session Decisions §6, "Note is the floor").
    public var isNote: Bool

    public var isTask: Bool

    /// Task completion state. Meaningless (and `false`) when `isTask == false`.
    public var isComplete: Bool

    /// `true` if this Take is the *current* Obie. Exactly one Take across the whole
    /// store may have this set (enforced by the store layer / UX, not the type).
    public var isObie: Bool

    // MARK: - Reminders

    /// Time-based reminder. `nil` in v1.0 if not set.
    public var timeReminder: TimeReminder?

    /// Location-based reminder. **Always `nil` in v1.0.** The field must exist
    /// (Roadmap §4) but must not be wired up before v1.1 (Phase 5 brief §8.4).
    public var locationReminder: LocationTrigger?

    // MARK: - Checklists (v1.0: empty array — Horizon 2 promote-to-Take feature)

    /// Must be present as an empty array in v1.0; do not remove (Roadmap §4).
    public var checklistItems: [ChecklistItem]

    // MARK: - Attachments (v1.0: empty array — v1.1 document scanning / images)

    /// Must be present as an empty array in v1.0; do not remove (Roadmap §4).
    public var attachments: [Attachment]

    // MARK: - Organisation

    /// Sequences this Take belongs to (empty if none). A Take may belong to many.
    public var sequenceIds: [UUID]

    // MARK: - Onboarding

    /// `true` for the five system-authored seed Takes created on first launch
    /// (UX Session Decisions §12). Cleared on first edit or swipe-delete. This is
    /// the only state flag beyond the activity types; it carries no security
    /// meaning and is encrypted with the rest of the payload like any other field.
    public var isSeeded: Bool

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        bodyText: String = "",
        contentType: String = "plain",
        isNote: Bool = true,
        isTask: Bool = false,
        isComplete: Bool = false,
        isObie: Bool = false,
        timeReminder: TimeReminder? = nil,
        locationReminder: LocationTrigger? = nil,
        checklistItems: [ChecklistItem] = [],
        attachments: [Attachment] = [],
        sequenceIds: [UUID] = [],
        isSeeded: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.bodyText = bodyText
        self.contentType = contentType
        self.isNote = isNote
        self.isTask = isTask
        self.isComplete = isComplete
        self.isObie = isObie
        self.timeReminder = timeReminder
        self.locationReminder = locationReminder
        self.checklistItems = checklistItems
        self.attachments = attachments
        self.sequenceIds = sequenceIds
        self.isSeeded = isSeeded
    }

    /// Enforces the "Note is the floor" rule (UX §6). Call after any activity-type
    /// mutation: if no other activity type is active, Note re-asserts.
    public mutating func normaliseActivityFloor() {
        if !isTask && timeReminder == nil && locationReminder == nil && !isObie {
            isNote = true
        }
        // Note is conceptually always true; we never let it become false.
        isNote = true
        if !isTask { isComplete = false }
    }
}
