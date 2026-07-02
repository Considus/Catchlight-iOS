//
//  TakeImporter.swift
//  CatchlightCore — import notes as Takes (owner 2026-06-22; multi-Take D-104)
//
//  Pure, testable parsing of a markdown/plain-text file into Takes.
//
//  TWO modes:
//    • `parse` — one file = one Take (the owner's 2026-06-22 rule). Checklist lines
//      ("- [ ]" / "- [x]" / "[x]" / "* [ ]") become check items, so a file with todo
//      lines imports as a Task and plain prose as a Note. This is what a note written
//      ELSEWHERE and dropped in should do.
//    • `parseDocument` — recognises Catchlight's OWN Markdown export and SPLITS it back
//      into the individual Takes (D-104). When the export carries the trailing
//      `<!-- catchlight:data -->` block (enriched exports), every field round-trips
//      losslessly — exact timestamps, Obie, and full reminders. An older export
//      without that block still splits on its `## …` headings, recovering body, type,
//      date, and reminder time from the heading alone. Anything that isn't a
//      Catchlight export falls through to `parse` (one Take), unchanged.
//
//  Markdown is otherwise taken literally (no bold/heading rendering) beyond the
//  checklist syntax; URLs become tappable at display time via `LinkDetector`.
//

import Foundation

public enum TakeImporter {

    // MARK: - Single-file (foreign notes)

    /// Parse one file's text into a Take, or `nil` if it has no content (so the
    /// caller skips empty files). `fileDate` becomes the Take's created/modified
    /// date — pass the file's modification date so imports slot into the timeline
    /// by when they were written.
    public static func parse(_ content: String, fileDate: Date = Date()) -> Take? {
        let blocks = blocks(from: content)
        guard !blocks.isEmpty else { return nil }
        return Take(createdAt: fileDate, modifiedAt: fileDate, blocks: blocks, isNote: true)
    }

    // MARK: - Document (Catchlight export → many Takes)

    /// Parse a whole file into one-or-more Takes. A Catchlight Markdown export is split
    /// back into its individual Takes; anything else imports as a single Take (so the
    /// common "notes written elsewhere" case is unchanged). Returns an empty array only
    /// when there is no content at all.
    public static func parseDocument(_ content: String, fileDate: Date = Date()) -> [Take] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard isCatchlightMarkdownExport(normalized) else {
            return parse(normalized, fileDate: fileDate).map { [$0] } ?? []
        }

        let sections = splitSections(normalized)
        guard !sections.isEmpty else {
            return parse(normalized, fileDate: fileDate).map { [$0] } ?? []
        }

        // Use the enriched metadata only when it lines up 1:1 with the visible
        // sections — if the user hand-edited the file (adding/removing a Take) the
        // indices would desync, so fall back to heading parsing rather than mislabel.
        let metadata = extractMetadata(normalized)
        let useMetadata = metadata?.count == sections.count

        var takes: [Take] = []
        for (index, section) in sections.enumerated() {
            let blocks = blocks(from: section.body)
            guard !blocks.isEmpty else { continue }
            if useMetadata, let meta = metadata?[index] {
                takes.append(makeTake(blocks: blocks, meta: meta))
            } else {
                takes.append(makeTake(blocks: blocks, heading: section.heading, fileDate: fileDate))
            }
        }
        return takes
    }

    /// A Catchlight Markdown export begins with the pinned YAML frontmatter. Plain-text
    /// exports (and foreign files) never match, so they keep the one-file-one-Take path.
    static func isCatchlightMarkdownExport(_ normalized: String) -> Bool {
        normalized.hasPrefix("---\nexported:")
    }

    struct Section { let heading: String; let body: String }

    /// Split the visible body into `(heading, body)` sections on `## ` lines, skipping
    /// the leading `--- … ---` frontmatter and stopping at the trailing data block.
    static func splitSections(_ normalized: String) -> [Section] {
        let lines = normalized.components(separatedBy: "\n")
        var sections: [Section] = []
        var heading: String?
        var body: [String] = []
        var pastFrontmatter = false
        var fenceCount = 0

        func flush() {
            if let heading {
                sections.append(Section(heading: heading,
                                        body: body.joined(separator: "\n")))
            }
            heading = nil
            body.removeAll()
        }

        for line in lines {
            if !pastFrontmatter {
                if line == "---" {
                    fenceCount += 1
                    if fenceCount == 2 { pastFrontmatter = true }
                }
                continue
            }
            if line.hasPrefix(TakeTransfer.dataBlockOpen) { break }  // machine block — stop
            if line.hasPrefix("## ") {
                flush()
                heading = String(line.dropFirst(3))
            } else if heading != nil {
                body.append(line)
            }
        }
        flush()
        return sections
    }

    /// Decode the trailing `<!-- catchlight:data … -->` block, or nil if absent/invalid.
    static func extractMetadata(_ normalized: String) -> [TakeTransferMetadata]? {
        let lines = normalized.components(separatedBy: "\n")
        guard let openIndex = lines.firstIndex(where: { $0.hasPrefix(TakeTransfer.dataBlockOpen) }) else {
            return nil
        }
        guard let closeOffset = lines[(openIndex + 1)...].firstIndex(where: { $0.hasPrefix(TakeTransfer.dataBlockClose) }) else {
            return nil
        }
        let json = lines[(openIndex + 1)..<closeOffset].joined(separator: "\n")
        guard let data = json.data(using: .utf8) else { return nil }
        return try? TakeTransfer.decoder().decode([TakeTransferMetadata].self, from: data)
    }

    // MARK: - Take reconstruction

    /// Rebuild a Take from the visible blocks + the enriched metadata (lossless path).
    private static func makeTake(blocks: [TakeBlock], meta: TakeTransferMetadata) -> Take {
        var take = Take(createdAt: meta.createdAt, modifiedAt: meta.modifiedAt,
                        blocks: blocks, isNote: true, isObie: meta.isObie,
                        locationReminder: meta.locationReminder)
        if var reminder = meta.timeReminder {
            // The imported Take gets a fresh id, so the reminder must point at it and
            // start undelivered (it will be re-armed by the app's scheduling path).
            reminder.notificationIdentifier = take.id.uuidString
            reminder.isDelivered = false
            take.timeReminder = reminder
        }
        take.normaliseActivityFloor()
        return take
    }

    /// Rebuild a Take from the visible blocks + whatever the `## …` heading alone
    /// carries (older exports with no data block): the created DATE and, for a
    /// Reminder heading, the bell time. Obie / location can't be recovered — they were
    /// never in the visible text.
    private static func makeTake(blocks: [TakeBlock], heading: String, fileDate: Date) -> Take {
        let created = headingDate(heading) ?? fileDate
        var take = Take(createdAt: created, modifiedAt: created, blocks: blocks, isNote: true)
        if let bell = headingReminderDate(heading) {
            take.timeReminder = TimeReminder(scheduledDate: bell,
                                             notificationIdentifier: take.id.uuidString)
        }
        take.normaliseActivityFloor()
        return take
    }

    // MARK: - Legacy heading parsing (local time, matching the exporter)

    private static func headingDate(_ heading: String) -> Date? {
        guard let match = firstMatch(#"(\d{4}-\d{2}-\d{2})"#, in: heading) else { return nil }
        return dateFormatter("yyyy-MM-dd").date(from: match)
    }

    private static func headingReminderDate(_ heading: String) -> Date? {
        guard let match = firstMatch(#"🔔\s*(\d{4}-\d{2}-\d{2} \d{2}:\d{2})"#, in: heading, group: 1) else { return nil }
        return dateFormatter("yyyy-MM-dd HH:mm").date(from: match)
    }

    private static func dateFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current   // the exporter rendered Take dates in local time
        f.dateFormat = format
        return f
    }

    private static func firstMatch(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > group else { return nil }
        return ns.substring(with: m.range(at: group))
    }

    // MARK: - Block splitting (shared by both modes)

    /// Split content into blocks: runs of prose collapse into one text block each,
    /// and every checklist line becomes its own check item — preserving order.
    static func blocks(from content: String) -> [TakeBlock] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var result: [TakeBlock] = []
        var prose: [String] = []

        func flushProse() {
            let text = prose.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(.textLine(text)) }
            prose.removeAll()
        }

        for line in normalized.components(separatedBy: "\n") {
            if let item = checklistItem(in: line) {
                flushProse()
                result.append(.checkItem(item.text, isComplete: item.done))
            } else {
                prose.append(line)
            }
        }
        flushProse()
        return result
    }

    // `- [ ]` / `- [x]` / `* [ ]` / `[x]` (case-insensitive x), optional leading bullet,
    // then the item text. Anchored at the start so a mid-line "[x]" or a markdown link
    // "[label](url)" is NOT mistaken for a checkbox.
    private static let checklistRegex = try? NSRegularExpression(
        pattern: #"^\s*(?:[-*]\s+)?\[([ xX])\]\s?(.*)$"#)

    static func checklistItem(in line: String) -> (done: Bool, text: String)? {
        guard let regex = checklistRegex else { return nil }
        let ns = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges == 3 else { return nil }
        let mark = ns.substring(with: m.range(at: 1)).lowercased()
        let text = ns.substring(with: m.range(at: 2))
            .trimmingCharacters(in: .whitespaces)
        return (done: mark == "x", text: text)
    }
}
