//
//  FileCloudFolder.swift
//  Catchlight (iOS app target)
//
//  The production `CloudFolder` over the iOS Files API (Phase 5 brief §7.1). The
//  user picks a folder once via `UIDocumentPickerViewController`; we persist a
//  security-scoped bookmark and re-resolve it for ongoing `FileManager` access. The
//  app is cloud-AGNOSTIC — any provider that exposes a folder through Files works
//  (iCloud Drive is the primary v1.0 case; see Cloud_Provider_Sync_Compatibility.md).
//
//  Conforms to `CatchlightCore.CloudFolder`, so the entire cloud-agnostic SyncEngine
//  drives it unchanged. File coordination (`NSFileCoordinator`) is used so reads and
//  writes cooperate with the provider's background up/download.
//

import Foundation
import CatchlightCore

public final class FileCloudFolder: CloudFolder {

    private let folderURL: URL
    private let coordinator = NSFileCoordinator()

    /// Resolve a previously stored security-scoped bookmark to the chosen folder.
    public init(bookmark: Data) throws {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        self.folderURL = url
        _ = url.startAccessingSecurityScopedResource()
    }

    /// Direct-URL initialiser (e.g. an app-owned iCloud container).
    public init(folderURL: URL) {
        self.folderURL = folderURL
    }

    deinit { folderURL.stopAccessingSecurityScopedResource() }

    /// Persist a bookmark for the picked folder so access survives relaunches.
    public static func makeBookmark(for pickedURL: URL) throws -> Data {
        _ = pickedURL.startAccessingSecurityScopedResource()
        defer { pickedURL.stopAccessingSecurityScopedResource() }
        return try pickedURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public func listFiles() throws -> [String] {
        var result: [String] = []
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: folderURL, options: [], error: &coordError) { url in
            let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            result = items.map { $0.lastPathComponent }
        }
        if let coordError { throw coordError }
        return result
    }

    public func read(_ name: String) throws -> Data? {
        let fileURL = folderURL.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        var data: Data?
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordError) { url in
            data = try? Data(contentsOf: url)
        }
        if let coordError { throw coordError }
        return data
    }

    public func write(_ data: Data, to name: String) throws {
        let fileURL = folderURL.appendingPathComponent(name)
        var coordError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: fileURL, options: [.forReplacing], error: &coordError) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let coordError { throw coordError }
        if let writeError { throw writeError }
    }

    public func writeAtomically(_ data: Data, to name: String) throws {
        // `Data.write(.atomic)` already performs temp-write + rename; this satisfies
        // the "no partial manifest on crash" requirement (Phase 5 brief §7.4 step 5).
        try write(data, to: name)
    }

    public func delete(_ name: String) throws {
        let fileURL = folderURL.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        var coordError: NSError?
        var rmError: Error?
        coordinator.coordinate(writingItemAt: fileURL, options: [.forDeleting], error: &coordError) { url in
            do { try FileManager.default.removeItem(at: url) } catch { rmError = error }
        }
        if let coordError { throw coordError }
        if let rmError { throw rmError }
    }

    public func secureDelete(_ name: String) throws {
        // Overwrite with equal-length random bytes, then delete (Encryption
        // Architecture §6 step 13). NOTE (accepted residual risk, threat model):
        // cloud providers may retain prior versions in version history — the
        // ephemeral ECDH binding is what actually protects the handshake files, so
        // overwrite-then-delete is defence in depth, not the primary control.
        if let existing = try read(name) {
            try write(SecureRandom.bytes(existing.count), to: name)
        }
        try delete(name)
    }
}
