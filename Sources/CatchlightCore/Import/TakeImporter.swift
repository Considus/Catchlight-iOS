//
//  TakeImporter.swift
//  CatchlightCore — import notes as Takes (owner 2026-06-22)
//
//  Pure, testable parsing of a markdown/plain-text file into a Take. The owner's
//  rule (2026-06-22): one file = one Take. Checklist lines ("- [ ]" / "- [x]" /
//  "[x]" / "* [ ]") become check items — so a file with todo lines imports as a
//  Task, plain prose as a Note (Task-ness derives from the blocks).
//
//  v1 deliberately does NOT round-trip Catchlight's OWN multi-Take export back into
//  many Takes (that re-splits headings + reconstructs reminders/dates — a separate
//  feature). A dropped export file therefore imports as a single Take; the common
//  case — notes written elsewhere — is what this serves. Markdown is taken
//  literally (no bold/heading rendering) beyond the checklist syntax; URLs become
//  tappable at display time via `LinkDetector`.
//

import Foundation

public enum TakeImporter {

    /// Parse one file's text into a Take, or `nil` if it has no content (so the
    /// caller skips empty files). `fileDate` becomes the Take's created/modified
    /// date — pass the file's modification date so imports slot into the timeline
    /// by when they were written.
    public static func parse(_ content: String, fileDate: Date = Date()) -> Take? {
        let blocks = blocks(from: content)
        guard !blocks.isEmpty else { return nil }
        return Take(createdAt: fileDate, modifiedAt: fileDate, blocks: blocks, isNote: true)
    }

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
