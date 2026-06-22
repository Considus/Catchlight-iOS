//
//  ImportCoordinator.swift
//  Catchlight (iOS app target) — import notes as Takes (owner 2026-06-22)
//
//  iOS glue between `CatchlightCore.TakeImporter` (pure) and the filesystem. Reads
//  `.md` / `.txt` files from a folder and parses each into a Take (one file = one
//  Take); the caller inserts them via `DailiesViewModel.importTakes`.
//
//  The source is a fixed `Import/` subfolder inside the configured sync folder
//  (owner's design 2026-06-22: drop files there from any device that shares the
//  folder, then tap Import on the phone). Import requires a configured sync folder —
//  there is no separate picker path.
//
//  Logging is intentionally absent — note content is sensitive and must never reach
//  the system log (mirrors ExportCoordinator).
//

import Foundation
import UIKit
import CatchlightCore

@MainActor
enum ImportCoordinator {

    /// The fixed subfolder, inside the sync folder, the user drops files into.
    static let importFolderName = "Import"

    // `.rtf` (TextEdit's default) is read as PLAIN TEXT — its formatting is stripped
    // via NSAttributedString so only the words come through (owner 2026-06-22).
    private static let importableExtensions: Set<String> = ["md", "markdown", "txt", "text", "rtf"]

    struct Outcome {
        /// Parsed Takes, ready for `DailiesViewModel.importTakes`.
        let takes: [Take]
        /// Importable files seen (before parsing).
        let filesScanned: Int
        /// Files that were empty or unreadable.
        let skipped: Int
    }

    enum ImportError: Error { case folderUnreadable }

    /// The `Import/` folder inside the configured sync folder, created if missing.
    /// Returns nil when no sync folder is configured. The returned `stopAccess` must
    /// be called once the caller has finished reading (it releases the security scope).
    static func syncImportFolder() -> (url: URL, stopAccess: () -> Void)? {
        guard let resolved = try? Wiring.resolveCloudFolderURL() else { return nil }
        let base = resolved.url
        let accessing = base.startAccessingSecurityScopedResource()
        let folder = base.appendingPathComponent(importFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (folder, { if accessing { base.stopAccessingSecurityScopedResource() } })
    }

    /// Parse every importable file in `folder` into a Take. Does NOT touch the store.
    /// The folder is the sync `Import/` subfolder, whose security scope is already
    /// held by the caller (via `syncImportFolder`'s base access).
    static func parseFolder(_ folder: URL) throws -> Outcome {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else {
            throw ImportError.folderUnreadable
        }

        let files = items
            .filter { importableExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        var takes: [Take] = []
        var skipped = 0
        for url in files {
            guard let content = plainText(of: url) else {
                skipped += 1
                continue
            }
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date()
            if let take = TakeImporter.parse(content, fileDate: modDate) {
                takes.append(take)
            } else {
                skipped += 1   // empty / no content
            }
        }
        return Outcome(takes: takes, filesScanned: files.count, skipped: skipped)
    }

    /// Read a file as plain text. `.rtf` is decoded through NSAttributedString so the
    /// RTF control words never reach the Take (just the words); everything else is read
    /// as UTF-8. Returns nil for unreadable / non-decodable content (the caller skips it).
    private static func plainText(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if url.pathExtension.lowercased() == "rtf" {
            let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil)
            return attributed?.string
        }
        return String(data: data, encoding: .utf8)
    }
}
