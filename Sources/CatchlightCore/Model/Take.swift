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
    ///
    /// Designating a Take Obie AUTO-flags it Important and importance is STICKY —
    /// removing the Obie designation leaves `isImportant` set (owner 2026-06-18). The
    /// `didSet` enforces "Obie ⟹ Important" on every runtime mutation (the store's
    /// `setObie`, the inline Focus-ring path, etc.); it does NOT fire during `init` /
    /// decode, so persisted values are respected (and the init + decode below apply the
    /// same rule for constructed / freshly-decoded Obie Takes).
    public var isObie: Bool {
        didSet { if isObie { isImportant = true } }
    }

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

    /// `true` when this Take is flagged Important — a tier BELOW Obie (important,
    /// plural, unordered; owner 2026-06-17). For now the ONLY way a Take becomes
    /// Important is by being designated Obie (auto-flag, see `isObie`); it stays set
    /// after the Obie designation is removed ("sticky"). A manual mark is deferred
    /// (owner 2026-06-18). Additive field: `decodeIfPresent` default false keeps older
    /// payloads decoding, and it rides the encrypted payload like any other field.
    public var isImportant: Bool

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
        isSeeded: Bool = false,
        isImportant: Bool = false
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
        // didSet doesn't fire during init — apply the Obie ⟹ Important rule explicitly
        // so an Obie constructed directly is also Important.
        self.isImportant = isImportant || isObie
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

    /// `(done, total)` for the card's "0 of 1 / 3 of 5 completed" progress marker —
    /// shown for ANY Task with 1+ check items (owner 2026-06-19: a single-item Task
    /// should still read "0 of 1 completed"; previously one-item Tasks were silent).
    /// A pure note (no check items) returns nil.
    public var checklistProgress: (done: Int, total: Int)? {
        let items = checkItems
        guard !items.isEmpty else { return nil }
        return (items.filter(\.isComplete).count, items.count)
    }

    // MARK: - Block editing (the block-stack editor, D-035)
    //
    // These reshape `blocks` for the editor and the Focus-ring Task Mark. They
    // are pure value mutations so they're unit-tested directly; the editor's
    // focus/cursor management lives in the view layer.

    /// Make this Take a Task (`on == true`, the Focus ring's "Task" Mark turned
    /// on) or a plain note (`on == false`). A thin wrapper over the structural
    /// conversions used when there is no cursor context (the timeline petal fan).
    public mutating func setTask(_ on: Bool) {
        guard on != isTask else { return }
        if on { _ = convertToChecklist() } else { convertToProse() }
    }

    /// Begin a Task WITHOUT consuming existing prose (owner 2026-06-17). Picking
    /// the Task Mark no longer turns the lines you already wrote into checkboxes:
    /// any existing content is left exactly as prose, and ONE empty check item is
    /// added so the next line you type becomes the first task entry. An empty Take
    /// becomes a one-item checklist immediately (so the first entry has a checkbox).
    /// Returns the new item's id so the editor can drop focus straight into it.
    @discardableResult
    public mutating func convertToChecklist() -> UUID? {
        let item = ChecklistItem(text: "")
        blocks.append(.check(item))   // append works for both empty and content-ful Takes
        return item.id
    }

    /// Turn the Take back into prose: each maximal run of consecutive check
    /// items collapses into a single text block (their labels newline-joined),
    /// so a checklist demotes back to the lines it came from. Existing text
    /// blocks are left in place, preserving any interleaving.
    public mutating func convertToProse() {
        var rebuilt: [TakeBlock] = []
        var runTexts: [String] = []
        var runFirstID: UUID?

        func flushRun() {
            guard !runTexts.isEmpty else { return }
            let id = runFirstID ?? UUID()
            rebuilt.append(.text(TextBlock(id: id, text: runTexts.joined(separator: "\n"))))
            runTexts.removeAll()
            runFirstID = nil
        }

        for block in blocks {
            switch block {
            case .check(let item):
                if runFirstID == nil { runFirstID = item.id }
                runTexts.append(item.text)
            case .text:
                flushRun()
                rebuilt.append(block)
            }
        }
        flushRun()
        blocks = rebuilt
    }

    /// Set the text of the block with `blockID` (no-op if it's gone).
    public mutating func updateText(_ text: String, blockID: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        switch blocks[index] {
        case .text(var textBlock):
            textBlock.text = text
            blocks[index] = .text(textBlock)
        case .check(var item):
            item.text = text
            blocks[index] = .check(item)
        }
    }

    /// Toggle the completion of the check block with `blockID` (no-op otherwise).
    public mutating func toggleItemComplete(blockID: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }),
              case .check(var item) = blocks[index] else { return }
        item.isComplete.toggle()
        blocks[index] = .check(item)
    }

    /// Insert a new empty check item immediately after `blockID` (Return inside a
    /// non-empty check item continues the list). Returns the new item's id, or
    /// nil if `blockID` isn't present.
    @discardableResult
    public mutating func insertCheckItem(after blockID: UUID) -> UUID? {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return nil }
        let item = ChecklistItem(text: "")
        blocks.insert(.check(item), at: index + 1)
        return item.id
    }

    /// Convert the check block with `blockID` into a text block, preserving id and
    /// text (Return in an EMPTY check item exits the list back to prose).
    public mutating func convertCheckToText(blockID: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }),
              case .check(let item) = blocks[index] else { return }
        blocks[index] = .text(TextBlock(id: item.id, text: item.text))
    }

    /// The id of the block immediately before `blockID`, or nil if it's first /
    /// absent (used to move focus on backspace-merge).
    public func blockID(before blockID: UUID) -> UUID? {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }), index > 0 else { return nil }
        return blocks[index - 1].id
    }

    /// Remove the block with `blockID` (backspace-merge into the previous block,
    /// or swipe-to-delete).
    public mutating func removeBlock(blockID: UUID) {
        blocks.removeAll { $0.id == blockID }
    }

    /// Move the block `id` so it sits immediately before `targetID` (drag
    /// reorder). No-op if they're the same or either is missing.
    public mutating func moveBlock(id: UUID, before targetID: UUID) {
        guard id != targetID, let from = blocks.firstIndex(where: { $0.id == id }) else { return }
        let block = blocks.remove(at: from)
        if let to = blocks.firstIndex(where: { $0.id == targetID }) {
            blocks.insert(block, at: to)
        } else {
            blocks.append(block)
        }
    }

    /// Drop empty text blocks — called when the editor commits, so a stray empty
    /// prose line (e.g. the seeded blank row, or a return-exited line left
    /// untyped) doesn't linger in the saved content / preview / export. Empty
    /// check items are kept (an unfilled to-do is intentional).
    public mutating func removeEmptyTextBlocks() {
        blocks.removeAll { block in
            if case .text(let textBlock) = block { return textBlock.text.isEmpty }
            return false
        }
    }

    /// Tick (or untick) every check item. The timeline row's "mark complete"
    /// affordance (the editor toggles items individually); no-op for a non-Task.
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

    /// Whether the Take reads as "done" — drives the card's grey border + grey text
    /// (D-044, [[catchlight-take-colour-system]]) and the long-press "Mark as done"
    /// toggle. A Take is done when every actionable marker it carries is settled: a
    /// Task with all items ticked AND/OR a reminder marked `isDone`. Only meaningful
    /// for a Take that IS a Task or has a reminder (a plain Note is never "done").
    public var isMarkedDone: Bool {
        guard isTask || timeReminder != nil else { return false }
        let taskDone = !isTask || isComplete
        let reminderDone = timeReminder?.isDone ?? true
        return taskDone && reminderDone
    }

    /// Mark the WHOLE Take done / not-done in one move (owner 2026-06-18): ticks or
    /// unticks every check item and flips any reminder's `isDone`, so a single
    /// "Mark as done" settles a Take that is both a Task and a reminder.
    public mutating func setMarkedDone(_ done: Bool) {
        if isTask { setAllItemsComplete(done) }
        if timeReminder != nil { timeReminder?.isDone = done }
    }

    // MARK: - Codable (explicit so future fields can carry decoding defaults)

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, createdAt, modifiedAt, blocks, contentType
        case isNote, isObie
        case timeReminder, locationReminder, attachments
        case isSeeded, isImportant
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
        // Obie ⟹ Important, including for OLD payloads written before this field
        // existed (a pre-existing Obie decodes as Important). didSet doesn't fire in
        // init, so apply the rule explicitly here.
        self.isImportant = (try c.decodeIfPresent(Bool.self, forKey: .isImportant) ?? false) || self.isObie
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
        try c.encode(isImportant, forKey: .isImportant)
    }

    /// Enforces the "Note is the floor" rule (UX §6). Call after any activity-type
    /// mutation. Note is the FLOOR, not a constant (owner 2026-06-17): it re-asserts
    /// only when the Take has no OTHER activity type. A Take that is a Task and/or a
    /// Reminder may carry Note explicitly removed (so the Iris drops the Note mark);
    /// a Take that is neither always reads as a Note. Obie is not an activity type in
    /// this sense — an Obie that is neither Task nor Reminder is still a Note.
    /// (Completion no longer needs clearing here: it is derived from the check
    /// blocks, so a Take with no checks is never "complete".)
    public mutating func normaliseActivityFloor() {
        if !isTask && timeReminder == nil { isNote = true }
    }
}
