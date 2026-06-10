//
//  Take.swift
//  CatchlightCore
//
//  The Take is the fundamental unit of Catchlight. Every item the user creates is
//  a Take. A Take is a *container, not a category* (UX Session Decisions §1): any
//  combination of Note / Task / Reminder / Obie is valid simultaneously, and Note
//  is the floor — it re-asserts if every other type is removed.
//
//  This struct is the plaintext representation. It is what gets sealed with the
//  per-item AES-256-GCM key (the whole payload, per Encryption Architecture
//  §10.5) — both in the cloud blob and in the local database's payload column.
//  The Take's `id` is never encrypted: it is the HKDF `info` input for the
//  per-item key and must be known before decryption. The timestamps and the
//  Obie flag are additionally mirrored as plaintext columns locally because the
//  store needs them for ordering, sync watermarks, and the single-Obie index.
//
//  Forward-compatibility fields (Strategic Roadmap §4) are present now even though
//  unused in v1.0, so that adding the v1.1/Horizon-2 features never requires a
//  breaking data-model migration.
//

import Foundation

public struct Take: Identifiable, Codable, Equatable, Sendable {
    /// Version of the encrypted payload schema (2026-06-10). Synthesised Codable
    /// offers no decoding defaults, so the FIRST field ever added in a future
    /// version would have broken decoding of every existing payload — and with
    /// no version stamp, a migrator could not even tell what it was reading.
    /// Old payloads without the field decode as version 1. Future fields MUST be
    /// added with `decodeIfPresent` + a default in `init(from:)` below.
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int

    /// Primary key. Used as the HKDF `info` parameter for the per-item key.
    /// Never changes for the life of the Take. Not encrypted.
    public let id: UUID

    /// Timestamps are normalised to MILLISECOND precision (the wire format's
    /// resolution) at init and on mutation, so a Take compares equal to itself
    /// after a serialisation round trip. See `ISO8601.truncateToMilliseconds`.
    public var createdAt: Date {
        didSet { createdAt = ISO8601.truncateToMilliseconds(createdAt) }
    }
    public var modifiedAt: Date {
        didSet { modifiedAt = ISO8601.truncateToMilliseconds(modifiedAt) }
    }

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
        isSeeded: Bool = false
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.createdAt = ISO8601.truncateToMilliseconds(createdAt)
        self.modifiedAt = ISO8601.truncateToMilliseconds(modifiedAt)
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
        self.isSeeded = isSeeded
    }

    // MARK: - Codable (explicit so future fields can carry decoding defaults)

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, createdAt, modifiedAt, bodyText, contentType
        case isNote, isTask, isComplete, isObie
        case timeReminder, locationReminder, checklistItems, attachments
        case isSeeded
        // `sequenceIds` REMOVED 2026-06-10 (filter-based Sequences): membership
        // is computed from the Sequence's saved filter, never stored on the
        // Take. Old payloads carrying the key decode fine (unknown keys are
        // ignored).
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Payloads written before 2026-06-10 carry no version field — they are v1.
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.id = try c.decode(UUID.self, forKey: .id)
        self.createdAt = ISO8601.truncateToMilliseconds(try c.decode(Date.self, forKey: .createdAt))
        self.modifiedAt = ISO8601.truncateToMilliseconds(try c.decode(Date.self, forKey: .modifiedAt))
        self.bodyText = try c.decode(String.self, forKey: .bodyText)
        self.contentType = try c.decode(String.self, forKey: .contentType)
        self.isNote = try c.decode(Bool.self, forKey: .isNote)
        self.isTask = try c.decode(Bool.self, forKey: .isTask)
        self.isComplete = try c.decode(Bool.self, forKey: .isComplete)
        self.isObie = try c.decode(Bool.self, forKey: .isObie)
        self.timeReminder = try c.decodeIfPresent(TimeReminder.self, forKey: .timeReminder)
        self.locationReminder = try c.decodeIfPresent(LocationTrigger.self, forKey: .locationReminder)
        self.checklistItems = try c.decodeIfPresent([ChecklistItem].self, forKey: .checklistItems) ?? []
        self.attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        self.isSeeded = try c.decodeIfPresent(Bool.self, forKey: .isSeeded) ?? false
        // NOTE for future versions: new fields added here MUST use
        // `decodeIfPresent` with a default so older payloads keep decoding.
    }

    /// Enforces the "Note is the floor" rule (UX §6). Call after any activity-type
    /// mutation. Note is conceptually always true — it is never allowed to become
    /// false — and completion state is meaningless for non-Tasks.
    public mutating func normaliseActivityFloor() {
        isNote = true
        if !isTask { isComplete = false }
    }
}
