//
//  Take.swift
//  CatchlightCore
//
//  The Take is the fundamental unit of Catchlight. Every item the user creates is
//  a Take. A Take is a *container, not a category* (UX Session Decisions §1): any
//  combination of Note / Task / Reminder / Obie is valid simultaneously, and Note
//  is the floor — it re-asserts if every other type is removed.
//
//  CONTENT IS BLOCKS (D-035). A Take's body is an ordered `[TakeBlock]`: prose
//  lines (`.text`) and checkbox lines (`.check`) interleave in any order, the way
//  Apple Notes / Word behave. This replaced the old `bodyText: String` plus the
//  separate `checklistItems: [ChecklistItem]` (which could only render
//  text-then-checkboxes, never interleaved). `isTask` / `isComplete` are now
//  DERIVED from the blocks (a Take is a Task iff it has ≥1 check block; complete
//  iff it has checks and all are ticked), so they can never drift.
//
//  This struct is the plaintext representation. It is what gets sealed with the
//  per-item AES-256-GCM key (the whole payload, per Encryption Architecture
//  §10.5) — both in the cloud blob and in the local database's payload column.
//  The Take's `id` is never encrypted: it is the HKDF `info` input for the
//  per-item key and must be known before decryption. The timestamps and the
//  Obie flag are additionally mirrored as plaintext columns locally because the
//  store needs them for ordering, sync watermarks, and the single-Obie index.
//  `isTask` was never a plaintext column, so deriving it has no store impact.
//
//  Forward-compatibility fields (Strategic Roadmap §4) are present now even though
//  unused in v1.0, so that adding the v1.1/Horizon-2 features never requires a
//  breaking data-model migration.
//

import Foundation

public struct Take: Identifiable, Codable, Equatable, Sendable {
    /// Version of the encrypted payload schema. v2 (2026-06-13) is the block
    /// content model (D-035); v1 carried `bodyText` + `checklistItems`. Old
    /// payloads without the field decode as version 1 and are upgraded to blocks
    /// in `init(from:)`. Synthesised Codable offers no decoding defaults, so
    /// future fields MUST be added with `decodeIfPresent` + a default below.
    public static let currentSchemaVersion = 2
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

    // MARK: - Content (D-035)

    /// Ordered content: prose lines and checkbox lines interleaved. The single
    /// source of truth for the Take's body, its Task-ness, and its completion.
    public var blocks: [TakeBlock]

    /// Structured content marker. `"blocks/v2"` since D-035 — the old
    /// `"plain"` vs `"markdown"` gate is moot now the content is structured.
    public var contentType: String

    // MARK: - Activity types

    /// Always `true`. Note re-asserts automatically if all other activity types are
    /// removed (UX Session Decisions §6, "Note is the floor").
    public var isNote: Bool

    /// Derived: a Take is a **Task** iff it contains at least one check block
    /// (D-034). Never stored — computed from `blocks` so it can never drift.
    public var isTask: Bool {
        blocks.contains { $0.isCheck }
    }

    /// Derived: a Task is **complete** when it has check items and every one of
    /// them is ticked (a one-item Task is done when its item is ticked). `false`
    /// for a Take with no check blocks. Never stored.
    public var isComplete: Bool {
        let items = checkItems
        return !items.isEmpty && items.allSatisfy { $0.isComplete }
    }

    /// `true` if this Take is the *current* Obie. Exactly one Take across the whole
    /// store may have this set (enforced by the store layer / UX, not the type).
    public var isObie: Bool

    // MARK: - Reminders

    /// Time-based reminder. `nil` in v1.0 if not set.
    public var timeReminder: TimeReminder?

    /// Location-based reminder. **Always `nil` in v1.0.** The field must exist
    /// (Roadmap §4) but must not be wired up before v1.1 (Phase 5 brief §8.4).
    public var locationReminder: LocationTrigger?

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
        blocks: [TakeBlock] = [],
        contentType: String = "blocks/v2",
        isNote: Bool = true,
        isObie: Bool = false,
        timeReminder: TimeReminder? = nil,
        locationReminder: LocationTrigger? = nil,
        attachments: [Attachment] = [],
        isSeeded: Bool = false
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.createdAt = ISO8601.truncateToMilliseconds(createdAt)
        self.modifiedAt = ISO8601.truncateToMilliseconds(modifiedAt)
        self.blocks = blocks
        self.contentType = contentType
        self.isNote = isNote
        self.isObie = isObie
        self.timeReminder = timeReminder
        self.locationReminder = locationReminder
        self.attachments = attachments
        self.isSeeded = isSeeded
    }

    // MARK: - Derived content accessors

    /// The Take's check items, in block order. Empty for a non-Task.
    public var checkItems: [ChecklistItem] {
        blocks.compactMap { block in
            if case .check(let item) = block { return item }
            return nil
        }
    }

    /// Flattened text (prose lines + item labels, in order, newline-joined) for
    /// timeline preview, in-app search, and export-adjacent surfaces. The single
    /// source of truth for "what does this Take say" outside the block editor.
    public var plainText: String {
        blocks.map { $0.text }.joined(separator: "\n")
    }

    /// Phase-1 editor bridge: the text of the FIRST prose block (or `""` if the
    /// Take has none). Setting it writes into that block, prepending a new text
    /// block when the Take has no prose yet. This lets the minimal Phase-1 editor
    /// "edit the Take's text" without a block editor; Phase 2's block-stack editor
    /// replaces it with per-block editing.
    public var primaryText: String {
        get {
            for block in blocks {
                if case .text(let textBlock) = block { return textBlock.text }
            }
            return ""
        }
        set {
            if let index = blocks.firstIndex(where: { if case .text = $0 { return true } else { return false } }) {
                if case .text(var textBlock) = blocks[index] {
                    textBlock.text = newValue
                    blocks[index] = .text(textBlock)
                }
            } else {
                blocks.insert(.text(TextBlock(text: newValue)), at: 0)
            }
        }
    }

    // MARK: - Content mutation helpers (Phase-1 bridges for the petal fan)

    /// Make this Take a Task (`on == true`) or a plain note (`on == false`) by
    /// reshaping `blocks`. This is the coarse Phase-1 affordance the petal fan
    /// uses; Phase 2's editor does fine-grained per-line make-task at the cursor.
    ///
    /// - Promote: every prose line becomes a check item (preserving id + text);
    ///   a Take with no blocks gains one empty check item.
    /// - Demote: every check item becomes a prose line (preserving id + text).
    public mutating func setTask(_ on: Bool) {
        guard on != isTask else { return }
        if on {
            if blocks.isEmpty {
                blocks = [.check(ChecklistItem(text: ""))]
            } else {
                blocks = blocks.map { block in
                    if case .text(let textBlock) = block {
                        return .check(ChecklistItem(id: textBlock.id, text: textBlock.text))
                    }
                    return block
                }
            }
        } else {
            blocks = blocks.map { block in
                if case .check(let item) = block {
                    return .text(TextBlock(id: item.id, text: item.text))
                }
                return block
            }
        }
    }

    /// Tick (or untick) every check item. The Phase-1 row/quadrant "mark complete"
    /// affordance; no-op for a non-Task.
    public mutating func setAllItemsComplete(_ complete: Bool) {
        guard isTask else { return }
        blocks = blocks.map { block in
            if case .check(var item) = block {
                item.isComplete = complete
                return .check(item)
            }
            return block
        }
    }

    // MARK: - Codable (explicit so future fields can carry decoding defaults)

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, createdAt, modifiedAt, blocks, contentType
        case isNote, isObie
        case timeReminder, locationReminder, attachments
        case isSeeded
        // DROPPED in v2 (D-035): `bodyText`, `checklistItems` (now `blocks`), and
        // the formerly-stored `isTask` / `isComplete` (now derived). Old payloads
        // carrying those keys are upgraded in `init(from:)`; unknown keys on
        // decode are ignored. `sequenceIds` was removed 2026-06-10 (filter-based
        // Sequences).
    }

    /// Keys present only in v1 payloads, read solely to upgrade them to blocks.
    private enum LegacyV1Keys: String, CodingKey {
        case bodyText, checklistItems
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Payloads written before 2026-06-13 carry no version field — they are v1.
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.id = try c.decode(UUID.self, forKey: .id)
        self.createdAt = ISO8601.truncateToMilliseconds(try c.decode(Date.self, forKey: .createdAt))
        self.modifiedAt = ISO8601.truncateToMilliseconds(try c.decode(Date.self, forKey: .modifiedAt))

        // v2: blocks present. v1: upgrade `bodyText` (+ any `checklistItems`) to
        // a single prose block followed by check blocks, so nothing throws. No v1
        // data exists in the wild pre-launch, but the path is exercised by tests.
        if let blocks = try c.decodeIfPresent([TakeBlock].self, forKey: .blocks) {
            self.blocks = blocks
        } else {
            let legacy = try decoder.container(keyedBy: LegacyV1Keys.self)
            var upgraded: [TakeBlock] = []
            if let body = try legacy.decodeIfPresent(String.self, forKey: .bodyText) {
                upgraded.append(.text(TextBlock(text: body)))
            }
            let legacyItems = try legacy.decodeIfPresent([ChecklistItem].self, forKey: .checklistItems) ?? []
            upgraded.append(contentsOf: legacyItems.map { TakeBlock.check($0) })
            self.blocks = upgraded
            // The in-memory content is now the v2 block shape; re-stamp so a
            // subsequent save never persists v2 content under a v1 version.
            self.schemaVersion = Self.currentSchemaVersion
        }

        self.contentType = try c.decodeIfPresent(String.self, forKey: .contentType) ?? "blocks/v2"
        self.isNote = try c.decode(Bool.self, forKey: .isNote)
        self.isObie = try c.decode(Bool.self, forKey: .isObie)
        self.timeReminder = try c.decodeIfPresent(TimeReminder.self, forKey: .timeReminder)
        self.locationReminder = try c.decodeIfPresent(LocationTrigger.self, forKey: .locationReminder)
        self.attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        self.isSeeded = try c.decodeIfPresent(Bool.self, forKey: .isSeeded) ?? false
        // NOTE for future versions: new fields added here MUST use
        // `decodeIfPresent` with a default so older payloads keep decoding.
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(contentType, forKey: .contentType)
        try c.encode(isNote, forKey: .isNote)
        try c.encode(isObie, forKey: .isObie)
        try c.encodeIfPresent(timeReminder, forKey: .timeReminder)
        try c.encodeIfPresent(locationReminder, forKey: .locationReminder)
        try c.encode(attachments, forKey: .attachments)
        try c.encode(isSeeded, forKey: .isSeeded)
    }

    /// Enforces the "Note is the floor" rule (UX §6). Call after any activity-type
    /// mutation. Note is conceptually always true — it is never allowed to become
    /// false. (Completion no longer needs clearing here: it is derived from the
    /// check blocks, so a Take with no checks is never "complete".)
    public mutating func normaliseActivityFloor() {
        isNote = true
    }
}
