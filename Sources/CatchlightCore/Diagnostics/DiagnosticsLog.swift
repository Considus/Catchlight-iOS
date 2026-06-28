//
//  DiagnosticsLog.swift
//  CatchlightCore
//
//  A content-free, append-only, capped diagnostics log (owner 2026-06-28, D-085). Catchlight
//  ships with NO analytics and NO crash reporting by design, so this is the diagnostic
//  channel: it records the same non-blocking notices the user sees (sync / storage / conflict /
//  quarantine) plus a few internal breadcrumbs, so a user can review past notices (Notice
//  History) and export them with a bug report.
//
//  CONTENT-FREE BY CONTRACT. An entry is `timestamp · category · message`, where `message` is
//  ONLY a generic notice string or a count/code — NEVER Take text or anything that maps to
//  content. The file therefore holds no secrets, which is also why it is a PLAIN file (not the
//  encrypted store): it must be writable during a locked-device background sync, when the
//  encryption key is unavailable.
//

import Foundation

/// The kind of notice an entry records. All but `lifecycle` are user-facing (shown in Notice
/// History); `lifecycle` is an internal breadcrumb that only appears in the full export.
public enum DiagnosticCategory: String, Codable, Sendable, CaseIterable {
    case sync, storage, conflict, quarantine, lifecycle

    public var isUserFacing: Bool { self != .lifecycle }

    public var displayName: String {
        switch self {
        case .sync:       return "Sync"
        case .storage:    return "Storage"
        case .conflict:   return "Conflict"
        case .quarantine: return "Quarantine"
        case .lifecycle:  return "App"
        }
    }
}

/// One content-free log entry.
public struct DiagnosticEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let category: DiagnosticCategory
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(),
                category: DiagnosticCategory, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.message = message
    }
}

public final class DiagnosticsLog: @unchecked Sendable {

    /// The log keeps only the newest `maxEntries`; older entries roll off. Sized so the file
    /// stays tiny while holding plenty of history for a bug report.
    public static let maxEntries = 200

    /// The app-wide log, persisted to a content-free file in Application Support. Lazy +
    /// self-configuring, so any layer can record a notice without launch-time wiring. Tests
    /// construct their own instance with a temp `fileURL` instead of using this.
    public static let shared: DiagnosticsLog = {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return DiagnosticsLog(fileURL: base.appendingPathComponent("catchlight-diagnostics.json"))
    }()

    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) { self.fileURL = fileURL }

    // MARK: - Write

    /// Append a CONTENT-FREE entry (generic message / counts / codes only — never Take text),
    /// trimming the file to the newest `maxEntries`. Best-effort: a failed write drops the
    /// entry rather than throwing — diagnostics must never disrupt the app.
    public func record(_ category: DiagnosticCategory, _ message: String) {
        lock.lock(); defer { lock.unlock() }
        var all = loadLocked()
        all.append(DiagnosticEntry(category: category, message: message))
        if all.count > Self.maxEntries { all.removeFirst(all.count - Self.maxEntries) }
        writeLocked(all)
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        writeLocked([])
    }

    // MARK: - Read

    /// All entries, oldest-first (chronological).
    public func entries() -> [DiagnosticEntry] {
        lock.lock(); defer { lock.unlock() }
        return loadLocked()
    }

    /// User-facing entries for the Notice History, NEWEST-first.
    public func userFacingEntries() -> [DiagnosticEntry] {
        entries().filter { $0.category.isUserFacing }.reversed()
    }

    /// A plain-text dump (oldest-first) for the Export / a future bug report.
    public func exportText() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let lines = entries().map {
            "\(formatter.string(from: $0.timestamp))  [\($0.category.rawValue)]  \($0.message)"
        }
        return lines.isEmpty ? "No diagnostics recorded." : lines.joined(separator: "\n")
    }

    // MARK: - File (call only while holding `lock`)

    private func loadLocked() -> [DiagnosticEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([DiagnosticEntry].self, from: data)) ?? []
    }

    private func writeLocked(_ entries: [DiagnosticEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        // Protection-until-first-auth so a locked-device background sync can still append (the
        // file is content-free, so it needs no stronger class). iOS-only option; plain atomic
        // elsewhere (the macOS test host).
        #if os(iOS)
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: fileURL, options: [.atomic])
        #endif
    }
}
