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

    /// The log keeps only the newest `maxEntries` USER-FACING entries; older ones roll off.
    ///
    /// Budgets are kept SEPARATE per class (see `maxLifecycleEntries`) and trimmed independently.
    /// A single shared pool cannot work once breadcrumbs are chatty: `lifecycle` entries are
    /// frequent and notices are rare, so the breadcrumbs would evict every sync/storage/conflict/
    /// quarantine notice within minutes and Notice History (D-085) would simply read empty.
    public static let maxEntries = 200

    /// Breadcrumbs get their own budget so they can never starve the notices above. Bigger, because
    /// they're the diagnostic history behind a crash report, and cheap (short, content-free lines).
    public static let maxLifecycleEntries = 400

    /// Hard byte ceiling for the whole file. `maxEntries` bounds the COUNT, not the SIZE — one
    /// chatty breadcrumb or an interpolated string and the file grows unbounded. The export leaves
    /// by email/share, so it must stay small; oldest entries are dropped until it fits.
    public static let maxBytes = 256 * 1024

    /// Retention ceiling, regardless of count (owner 2026-07-16). Nothing older than this survives
    /// — a light user's 200 entries could otherwise span MONTHS, which is exposure with no upside.
    /// Mirrors the app's own Auto-delete reasoning: "trimming finished data you no longer need
    /// limits your exposure."
    public static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    /// The effective retention: the SHORTER of `maxAge` and the user's Auto-delete window (owner
    /// 2026-07-16 — reuse the retention intent they've already expressed rather than add a setting
    /// for a log they never see).
    ///
    /// It cannot be driven by Auto-delete ALONE: that defaults to `Never`, which would leave the
    /// log unbounded in time for the default user. And `Never` means "keep my writing forever" —
    /// not a wish to hoard technical logs. So `Never`/`Monthly`/`Annually` all fall back to
    /// `maxAge`, while `Daily`/`Weekly` tighten it.
    ///
    /// - Parameter autoDeleteWindow: the user's Auto-delete age threshold; `nil` for `Never`.
    public static func effectiveMaxAge(autoDeleteWindow: TimeInterval?) -> TimeInterval {
        guard let window = autoDeleteWindow else { return maxAge }
        return min(maxAge, window)
    }

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
        writeLocked(Self.trim(all))
    }

    /// Enforce every bound, oldest-first: per-class COUNT budgets, then AGE, then the byte ceiling.
    /// Order matters — age/bytes must run last so they can still evict entries a budget would keep.
    /// Chronological order is preserved throughout (the file is oldest-first).
    ///
    /// - Parameter maxAge: retention ceiling; defaults to `Self.maxAge`. The app passes
    ///   `effectiveMaxAge(autoDeleteWindow:)` so a tighter Auto-delete window also tightens the log.
    static func trim(_ entries: [DiagnosticEntry],
                     maxAge: TimeInterval = DiagnosticsLog.maxAge,
                     now: Date = Date()) -> [DiagnosticEntry] {
        // 1. COUNT, per class — separate budgets so chatty breadcrumbs can never evict a notice.
        let keep = Set(newestIDs(entries.filter { $0.category.isUserFacing }, max: maxEntries)
            + newestIDs(entries.filter { !$0.category.isUserFacing }, max: maxLifecycleEntries))
        var kept = entries.filter { keep.contains($0.id) }

        // 2. AGE — nothing older than the ceiling survives, however few entries there are.
        let cutoff = now.addingTimeInterval(-maxAge)
        kept.removeAll { $0.timestamp < cutoff }

        // 3. BYTES — drop oldest until the encoded file fits. Bounds SIZE, which a count cannot.
        while kept.count > 1, (try? JSONEncoder().encode(kept).count) ?? 0 > maxBytes {
            kept.removeFirst()
        }
        return kept
    }

    private static func newestIDs(_ entries: [DiagnosticEntry], max: Int) -> [UUID] {
        entries.suffix(max).map(\.id)
    }

    // MARK: - Unexpected-termination detection (owner 2026-07-16)

    /// Whether the app is currently "running" as far as the log is concerned. Set on launch,
    /// cleared on an orderly background/terminate. If it's STILL set at the next launch, the last
    /// run died without an orderly exit — a crash, a watchdog kill, or a jetsam.
    private static let runningFlagKey = "catchlight.diagnostics.running"

    /// Call once at launch, BEFORE `markRunning()`. If the previous run never exited cleanly,
    /// records a content-free `lifecycle` entry so the export shows it.
    ///
    /// This exists because the log is IN-PROCESS: a native crash kills it before it can write
    /// anything, so it can never witness its own death — only its absence at the next launch.
    /// On 2026-07-16 the app crashed 8 times in one session and recorded NOTHING; five of those
    /// were silent (a crash right after saving a lock-screen capture is indistinguishable from
    /// "returned to the lock screen") and were reported as working. Every cause had to come from
    /// OS crash logs pulled off the device — which a TestFlight tester cannot give us.
    ///
    /// NOT user-visible (owner): `lifecycle` never reaches Notice History, only the export.
    ///
    /// - Parameters:
    ///   - defaults: injected for tests.
    ///   - build: app version + git SHA, e.g. "1.0 (a1b2c3d)".
    ///   - systemVersion: OS version, e.g. "26.3.1".
    ///   - deviceModel: hardware identifier, e.g. "iPhone17,1".
    /// - Returns: `true` if the previous run ended unexpectedly.
    @discardableResult
    public func recordLaunch(defaults: UserDefaults = .standard,
                             build: String, systemVersion: String, deviceModel: String) -> Bool {
        let crashed = defaults.bool(forKey: Self.runningFlagKey)
        if crashed {
            // Everything technical, nothing personal (owner: capture as much as we can, right up
            // to the line where user info would be gleaned). Build/OS/device only — the preceding
            // breadcrumbs supply the "what was it doing", and they're already in the file.
            record(.lifecycle, "Previous run ended unexpectedly (no clean shutdown) — \(build), iOS \(systemVersion), \(deviceModel)")
        }
        defaults.set(true, forKey: Self.runningFlagKey)
        record(.lifecycle, "Launch — \(build), iOS \(systemVersion), \(deviceModel)")
        return crashed
    }

    /// Call on an orderly exit (background / terminate). Clears the flag, so the next launch knows
    /// this run ended properly.
    public func markCleanExit(defaults: UserDefaults = .standard) {
        record(.lifecycle, "Backgrounded (clean exit)")
        defaults.set(false, forKey: Self.runningFlagKey)
    }

    /// Enforce retention now — call on the Auto-delete sweep so a tighter window also tightens the
    /// log (owner 2026-07-16). Age-only work; the count/byte bounds already run on every `record`.
    public func enforceRetention(autoDeleteWindow: TimeInterval?) {
        lock.lock(); defer { lock.unlock() }
        writeLocked(Self.trim(loadLocked(),
                              maxAge: Self.effectiveMaxAge(autoDeleteWindow: autoDeleteWindow)))
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        writeLocked([])
    }

    /// Remove only the USER-FACING notices (the Notice History rows), keeping the
    /// lifecycle breadcrumbs (2026-07-01). Notice History's Clear previously wiped
    /// the whole file — a user tidying stale banners unknowingly destroyed the
    /// "Export diagnostics" content they'd attach to a bug report (the D-085
    /// one-backbone design cuts both ways).
    public func clearUserFacing() {
        lock.lock(); defer { lock.unlock() }
        writeLocked(loadLocked().filter { !$0.category.isUserFacing })
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
